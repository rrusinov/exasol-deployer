#!/usr/bin/env python3
"""
Emergency Response System for E2E Testing

Provides timeout monitoring, emergency cleanup, and resource leak prevention
for E2E test deployments. Creates execution plans that can be inspected
and tested without actual cloud resource destruction.
"""

import json
import time
import threading
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Optional, Callable
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
import logging


@dataclass
class ResourceInfo:
    """Information about a cloud resource."""
    resource_id: str
    resource_type: str
    provider: str
    deployment_id: str
    creation_time: datetime
    status: str = "unknown"
    estimated_cost: Optional[float] = None


@dataclass
class EmergencyCleanupResult:
    """Result of emergency cleanup operation."""
    deployment_id: str
    success: bool
    resources_found: int
    resources_cleaned: int
    resources_failed: int
    cleanup_time: float
    error_message: Optional[str] = None
    dry_run: bool = False


class ResourceTracker:
    """Tracks cloud resources created during E2E testing."""
    
    def __init__(self, deployment_dir: Path, dry_run: bool = True):
        self.deployment_dir = Path(deployment_dir)
        self.dry_run = dry_run
        self.logger = logging.getLogger(__name__)
        
        # Resource registry
        self.resources: Dict[str, ResourceInfo] = {}
        
        # Load existing resources if any
        self._load_existing_resources()
    
    def _load_existing_resources(self):
        """Load existing resource information from deployment directory."""
        resources_file = self.deployment_dir / 'resources.json'
        
        if not resources_file.exists():
            # Create mock resources for testing
            self._create_mock_resources()
            return
        
        try:
            with open(resources_file, 'r') as f:
                data = json.load(f)
                
            for resource_data in data.get('resources', []):
                resource = ResourceInfo(
                    resource_id=resource_data['resource_id'],
                    resource_type=resource_data['resource_type'],
                    provider=resource_data['provider'],
                    deployment_id=resource_data['deployment_id'],
                    creation_time=datetime.fromisoformat(resource_data['creation_time']),
                    status=resource_data.get('status', 'unknown'),
                    estimated_cost=resource_data.get('estimated_cost')
                )
                self.resources[resource.resource_id] = resource
                
        except Exception as e:
            self.logger.warning(f"Failed to load existing resources: {e}")
            self._create_mock_resources()
    
    def _create_mock_resources(self):
        """Create mock resources for testing."""
        deployment_id = self.deployment_dir.name
        
        mock_resources = [
            ResourceInfo(
                resource_id="i-1234567890abcdef0",
                resource_type="EC2 Instance",
                provider="aws",
                deployment_id=deployment_id,
                creation_time=datetime.now() - timedelta(hours=1),
                status="running",
                estimated_cost=0.05
            ),
            ResourceInfo(
                resource_id="vol-1234567890abcdef0",
                resource_type="EBS Volume",
                provider="aws",
                deployment_id=deployment_id,
                creation_time=datetime.now() - timedelta(hours=1),
                status="in-use",
                estimated_cost=0.01
            ),
            ResourceInfo(
                resource_id="sg-1234567890abcdef0",
                resource_type="Security Group",
                provider="aws",
                deployment_id=deployment_id,
                creation_time=datetime.now() - timedelta(hours=1),
                status="in-use",
                estimated_cost=0.0
            )
        ]
        
        for resource in mock_resources:
            self.resources[resource.resource_id] = resource
    
    def register_resource(self, resource_info: ResourceInfo):
        """Register a new resource."""
        self.resources[resource_info.resource_id] = resource_info
        self._save_resources()
    
    def get_resources_by_deployment(self, deployment_id: str) -> List[ResourceInfo]:
        """Get all resources for a specific deployment."""
        return [r for r in self.resources.values() if r.deployment_id == deployment_id]
    
    def get_resources_by_type(self, resource_type: str) -> List[ResourceInfo]:
        """Get all resources of a specific type."""
        return [r for r in self.resources.values() if r.resource_type == resource_type]
    
    def estimate_total_cost(self, deployment_id: Optional[str] = None) -> float:
        """Estimate total cost for resources."""
        resources = self.get_resources_by_deployment(deployment_id) if deployment_id else list(self.resources.values())
        return sum(r.estimated_cost or 0 for r in resources)
    
    def _save_resources(self):
        """Save resource information to file."""
        if self.dry_run:
            return
            
        resources_file = self.deployment_dir / 'resources.json'
        
        data = {
            'deployment_id': self.deployment_dir.name,
            'last_updated': datetime.now().isoformat(),
            'resources': [asdict(r) for r in self.resources.values()]
        }
        
        # Convert datetime objects to strings
        for resource in data['resources']:
            resource['creation_time'] = resource['creation_time'].isoformat()
        
        with open(resources_file, 'w') as f:
            json.dump(data, f, indent=2)


class EmergencyHandler:
    """Handles emergency cleanup and timeout monitoring for E2E tests."""
    
    def __init__(self, deployment_dir: Path, timeout_minutes: int = 30, dry_run: bool = True):
        self.deployment_dir = Path(deployment_dir)
        self.timeout_minutes = timeout_minutes
        self.dry_run = dry_run
        self.logger = logging.getLogger(__name__)
        
        # Resource tracker
        self.resource_tracker = ResourceTracker(deployment_dir, dry_run)
        
        # Timeout monitoring
        self.timeout_thread = None
        self.timeout_triggered = False
        self.cleanup_callbacks: List[Callable] = []
        
        # Cleanup results
        self.cleanup_results: List[EmergencyCleanupResult] = []
    
    def start_timeout_monitoring(self, deployment_id: str):
        """Start timeout monitoring for a deployment."""
        self.timeout_triggered = False
        
        def timeout_monitor():
            """Monitor deployment timeout."""
            end_time = datetime.now() + timedelta(minutes=self.timeout_minutes)
            
            while datetime.now() < end_time and not self.timeout_triggered:
                time.sleep(60)  # Check every minute
            
            if datetime.now() >= end_time and not self.timeout_triggered:
                self.logger.warning(f"Deployment {deployment_id} timed out after {self.timeout_minutes} minutes")
                self.timeout_triggered = True
                self._trigger_emergency_cleanup(deployment_id)
        
        self.timeout_thread = threading.Thread(target=timeout_monitor, daemon=True)
        self.timeout_thread.start()
        
        self.logger.info(f"Started timeout monitoring for {deployment_id} ({self.timeout_minutes} minutes)")
    
    def stop_timeout_monitoring(self):
        """Stop timeout monitoring."""
        self.timeout_triggered = True
        if self.timeout_thread and self.timeout_thread.is_alive():
            self.timeout_thread.join(timeout=5)
        
        self.logger.info("Stopped timeout monitoring")
    
    def add_cleanup_callback(self, callback: Callable[[str], None]):
        """Add a callback to be called during emergency cleanup."""
        self.cleanup_callbacks.append(callback)
    
    def _trigger_emergency_cleanup(self, deployment_id: str):
        """Trigger emergency cleanup for a deployment."""
        self.logger.error(f"TRIGGERING EMERGENCY CLEANUP FOR: {deployment_id}")
        
        # Call all cleanup callbacks
        for callback in self.cleanup_callbacks:
            try:
                callback(deployment_id)
            except Exception as e:
                self.logger.error(f"Cleanup callback failed: {e}")
        
        # Perform emergency cleanup
        result = self.emergency_cleanup(deployment_id)
        self.cleanup_results.append(result)
    
    def emergency_cleanup(self, deployment_id: str) -> EmergencyCleanupResult:
        """Perform emergency cleanup of all resources."""
        start_time = time.time()
        
        # Get all resources for deployment
        resources = self.resource_tracker.get_resources_by_deployment(deployment_id)
        
        result = EmergencyCleanupResult(
            deployment_id=deployment_id,
            success=True,
            resources_found=len(resources),
            resources_cleaned=0,
            resources_failed=0,
            cleanup_time=0,
            dry_run=self.dry_run
        )
        
        if self.dry_run:
            # Simulate cleanup for dry run
            for resource in resources:
                self.logger.info(f"DRY_RUN: Would clean up {resource.resource_type} {resource.resource_id}")
                result.resources_cleaned += 1
            
            result.cleanup_time = time.time() - start_time
            result.success = True
            
            self.logger.info(f"DRY_RUN: Emergency cleanup completed for {deployment_id}")
            return result
        
        # Perform actual cleanup
        for resource in resources:
            try:
                cleanup_success = self._cleanup_resource(resource)
                if cleanup_success:
                    result.resources_cleaned += 1
                else:
                    result.resources_failed += 1
                    result.success = False
            except Exception as e:
                self.logger.error(f"Failed to cleanup resource {resource.resource_id}: {e}")
                result.resources_failed += 1
                result.success = False
        
        result.cleanup_time = time.time() - start_time
        
        # Verify cleanup
        if not self._verify_cleanup(deployment_id):
            result.success = False
            result.error_message = "Cleanup verification failed - some resources may remain"
        
        self.logger.info(f"Emergency cleanup completed for {deployment_id}: "
                        f"{result.resources_cleaned}/{result.resources_found} resources cleaned")
        
        return result
    
    def _cleanup_resource(self, resource: ResourceInfo) -> bool:
        """Clean up a single resource."""
        if resource.provider == "aws":
            return self._cleanup_aws_resource(resource)
        elif resource.provider == "azure":
            return self._cleanup_azure_resource(resource)
        elif resource.provider == "gcp":
            return self._cleanup_gcp_resource(resource)
        else:
            self.logger.warning(f"Unknown provider: {resource.provider}")
            return False
    
    def _cleanup_aws_resource(self, resource: ResourceInfo) -> bool:
        """Clean up AWS resource."""
        if resource.resource_type == "EC2 Instance":
            cmd = ["aws", "ec2", "terminate-instances", "--instance-ids", resource.resource_id]
        elif resource.resource_type == "EBS Volume":
            cmd = ["aws", "ec2", "delete-volume", "--volume-id", resource.resource_id]
        elif resource.resource_type == "Security Group":
            cmd = ["aws", "ec2", "delete-security-group", "--group-id", resource.resource_id]
        else:
            self.logger.warning(f"Unknown AWS resource type: {resource.resource_type}")
            return False
        
        try:
            process = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            return process.returncode == 0
        except subprocess.TimeoutExpired:
            self.logger.error(f"Cleanup command timed out for {resource.resource_id}")
            return False
        except Exception as e:
            self.logger.error(f"Cleanup command failed for {resource.resource_id}: {e}")
            return False
    
    def _cleanup_azure_resource(self, resource: ResourceInfo) -> bool:
        """Clean up Azure resource."""
        # Placeholder for Azure cleanup
        self.logger.info(f"Would clean up Azure resource: {resource.resource_id}")
        return True
    
    def _cleanup_gcp_resource(self, resource: ResourceInfo) -> bool:
        """Clean up GCP resource."""
        # Placeholder for GCP cleanup
        self.logger.info(f"Would clean up GCP resource: {resource.resource_id}")
        return True
    
    def _verify_cleanup(self, deployment_id: str) -> bool:
        """Verify that all resources have been cleaned up."""
        remaining_resources = self.resource_tracker.get_resources_by_deployment(deployment_id)
        
        if self.dry_run:
            return True  # Assume success in dry run
        
        # Check if any resources remain
        for resource in remaining_resources:
            if self._check_resource_exists(resource):
                self.logger.warning(f"Resource still exists after cleanup: {resource.resource_id}")
                return False
        
        return True
    
    def _check_resource_exists(self, resource: ResourceInfo) -> bool:
        """Check if a resource still exists."""
        if resource.provider == "aws":
            return self._check_aws_resource_exists(resource)
        else:
            return True  # Assume exists for unknown providers
    
    def _check_aws_resource_exists(self, resource: ResourceInfo) -> bool:
        """Check if AWS resource still exists."""
        if resource.resource_type == "EC2 Instance":
            cmd = ["aws", "ec2", "describe-instances", "--instance-ids", resource.resource_id]
        elif resource.resource_type == "EBS Volume":
            cmd = ["aws", "ec2", "describe-volumes", "--volume-ids", resource.resource_id]
        else:
            return True  # Assume exists for unknown types
        
        try:
            process = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            return process.returncode == 0
        except Exception:
            return True  # Assume exists if check fails
    
    def check_resource_leaks(self, deployment_id: Optional[str] = None) -> Dict[str, Any]:
        """Check for resource leaks."""
        resources = self.resource_tracker.get_resources_by_deployment(deployment_id) if deployment_id else list(self.resource_tracker.resources.values())
        
        leak_report = {
            'total_resources': len(resources),
            'leaked_resources': [],
            'estimated_cost': self.resource_tracker.estimate_total_cost(deployment_id),
            'deployment_id': deployment_id,
            'check_time': datetime.now().isoformat()
        }
        
        # Check for resources that should have been cleaned up
        for resource in resources:
            if self._check_resource_exists(resource):
                leak_report['leaked_resources'].append({
                    'resource_id': resource.resource_id,
                    'resource_type': resource.resource_type,
                    'provider': resource.provider,
                    'estimated_cost': resource.estimated_cost
                })
        
        leak_report['leak_count'] = len(leak_report['leaked_resources'])
        leak_report['leak_cost'] = sum(r['estimated_cost'] or 0 for r in leak_report['leaked_resources'])
        
        return leak_report
    
    def get_emergency_plan(self, deployment_id: str) -> Dict[str, Any]:
        """Get emergency cleanup plan without executing."""
        resources = self.resource_tracker.get_resources_by_deployment(deployment_id)
        
        plan = {
            'deployment_id': deployment_id,
            'timeout_minutes': self.timeout_minutes,
            'resources_to_cleanup': [],
            'cleanup_commands': [],
            'estimated_cleanup_time': len(resources) * 30,  # 30 seconds per resource
            'dry_run': self.dry_run
        }
        
        for resource in resources:
            resource_info = {
                'resource_id': resource.resource_id,
                'resource_type': resource.resource_type,
                'provider': resource.provider,
                'estimated_cost': resource.estimated_cost
            }
            plan['resources_to_cleanup'].append(resource_info)
            
            # Add cleanup command
            if resource.provider == "aws":
                if resource.resource_type == "EC2 Instance":
                    cmd = f"aws ec2 terminate-instances --instance-ids {resource.resource_id}"
                elif resource.resource_type == "EBS Volume":
                    cmd = f"aws ec2 delete-volume --volume-id {resource.resource_id}"
                elif resource.resource_type == "Security Group":
                    cmd = f"aws ec2 delete-security-group --group-id {resource.resource_id}"
                else:
                    cmd = f"# Unknown AWS resource type: {resource.resource_type}"
                
                plan['cleanup_commands'].append({
                    'resource_id': resource.resource_id,
                    'command': cmd,
                    'description': f"Clean up {resource.resource_type}"
                })
        
        return plan
    
    def save_emergency_plan(self, deployment_id: str, output_file: Path):
        """Save emergency cleanup plan to file."""
        plan = self.get_emergency_plan(deployment_id)
        
        with open(output_file, 'w') as f:
            json.dump(plan, f, indent=2)
        
        self.logger.info(f"Emergency plan saved to {output_file}")
    
    def get_cleanup_summary(self) -> Dict[str, Any]:
        """Get summary of all cleanup operations."""
        total_cleanups = len(self.cleanup_results)
        successful_cleanups = sum(1 for r in self.cleanup_results if r.success)
        
        return {
            'total_cleanups': total_cleanups,
            'successful_cleanups': successful_cleanups,
            'failed_cleanups': total_cleanups - successful_cleanups,
            'success_rate': successful_cleanups / total_cleanups if total_cleanups > 0 else 0,
            'dry_run': self.dry_run,
            'cleanup_results': [asdict(r) for r in self.cleanup_results]
        }