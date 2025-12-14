#!/usr/bin/env python3
"""
Configuration Schema and Validation

Defines supported values for workflow steps, validation checks, and cloud providers.
Used for validating configuration files and documentation consistency.
"""

from typing import Dict, List, Set
from dataclasses import dataclass


@dataclass
class WorkflowStepSchema:
    """Schema for a workflow step type"""
    name: str
    description: str
    required_fields: List[str]
    optional_fields: List[str]
    supported_providers: Set[str]  # Empty set means all providers


# Supported cloud providers
SUPPORTED_PROVIDERS = {
    'aws', 'azure', 'gcp', 'digitalocean', 'hetzner', 'libvirt'
}

# Workflow step types with their requirements
WORKFLOW_STEPS = {
    'init': WorkflowStepSchema(
        name='init',
        description='Initialize deployment directory',
        required_fields=['step'],
        optional_fields=['description'],
        supported_providers=set()  # All providers
    ),
    'deploy': WorkflowStepSchema(
        name='deploy',
        description='Deploy the cluster',
        required_fields=['step'],
        optional_fields=['description'],
        supported_providers=set()  # All providers
    ),
    'validate': WorkflowStepSchema(
        name='validate',
        description='Perform validation checks',
        required_fields=['step', 'checks'],
        optional_fields=['description', 'allow_failures', 'retry'],
        supported_providers=set()  # All providers
    ),
    'stop_cluster': WorkflowStepSchema(
        name='stop_cluster',
        description='Stop entire cluster',
        required_fields=['step'],
        optional_fields=['description'],
        supported_providers=set()  # All providers
    ),
    'start_cluster': WorkflowStepSchema(
        name='start_cluster',
        description='Start entire cluster',
        required_fields=['step'],
        optional_fields=['description'],
        supported_providers=set()  # All providers
    ),
    'restart_node': WorkflowStepSchema(
        name='restart_node',
        description='Restart specific node',
        required_fields=['step', 'target_node'],
        optional_fields=['description', 'method'],
        supported_providers=set()  # All providers support method='ssh'
    ),
    'custom_command': WorkflowStepSchema(
        name='custom_command',
        description='Execute a custom shell command with variable substitution',
        required_fields=['step'],
        optional_fields=['description', 'command', 'script'],
        supported_providers=set()  # All providers
    ),
    'destroy': WorkflowStepSchema(
        name='destroy',
        description='Destroy cluster',
        required_fields=['step'],
        optional_fields=['description'],
        supported_providers=set()  # All providers
    ),
}

# Validation check components for health_status checks
HEALTH_CHECK_COMPONENTS = {
    'ssh': 'SSH connectivity to nodes',
    'adminui': 'Admin UI port 8443 connectivity',
    'database': 'Database port 8563 connectivity',
    'cos_ssh': 'COS SSH connectivity',
}

# Validation check patterns
VALIDATION_CHECK_PATTERNS = {
    'cluster_status': 'cluster_status==<value> or cluster_status!=<value>',
    'health_status': 'health_status[<nodes>].<component>==<value> or !=<value>',
}

# Valid cluster status values (from exasol status)
VALID_CLUSTER_STATUSES = {
    'initialized',
    'database_ready',
    'stopped',
    'starting',
    'stopping',
    'error',
    'degraded',
    'deploy_failed',
    'stop_failed',
    'start_failed',
    'destroyed',
}

# Valid health check values
VALID_HEALTH_VALUES = {
    'ok': 'true',
    'failed': 'false',
    'true': 'true',
    'false': 'false',
}

# SUT configuration parameters
SUT_PARAMETERS = {
    # Common parameters (all providers)
    'cluster_size': {
        'type': 'int',
        'cli_flag': '--cluster-size',
        'providers': 'all',
        'description': 'Number of nodes in the cluster'
    },
    'data_volumes_per_node': {
        'type': 'int',
        'cli_flag': '--data-volumes-per-node',
        'providers': 'all',
        'description': 'Number of data volumes per node'
    },
    'data_volume_size': {
        'type': 'int',
        'cli_flag': '--data-volume-size',
        'providers': 'all',
        'description': 'Size of each data volume in GB'
    },
    'root_volume_size': {
        'type': 'int',
        'cli_flag': '--root-volume-size',
        'providers': 'all',
        'description': 'Size of root volume in GB'
    },
    
    # Test configuration parameters
    'use_portable_dependencies': {
        'type': 'bool',
        'cli_flag': None,  # Not a CLI parameter, only for E2E config
        'providers': 'all',
        'description': 'Install and use portable OpenTofu, jq, and Ansible for this test'
    },
    
    # Cloud provider parameters
    'instance_type': {
        'type': 'string',
        'cli_flag': '--instance-type',
        'providers': {'aws', 'azure', 'gcp', 'digitalocean', 'hetzner'},
        'description': 'Cloud instance type'
    },
    'libvirt_memory': {
        'type': 'int',
        'cli_flag': '--libvirt-memory',
        'providers': {'libvirt'},
        'description': 'Memory in GB for VMs'
    },
    'libvirt_vcpus': {
        'type': 'int',
        'cli_flag': '--libvirt-vcpus',
        'providers': {'libvirt'},
        'description': 'Number of vCPUs'
    },
    'libvirt_uri': {
        'type': 'string',
        'cli_flag': '--libvirt-uri',
        'providers': {'libvirt'},
        'description': 'Libvirt connection URI'
    },
    'libvirt_network': {
        'type': 'string',
        'cli_flag': '--libvirt-network',
        'providers': {'libvirt'},
        'description': 'Network name'
    },
    'libvirt_pool': {
        'type': 'string',
        'cli_flag': '--libvirt-pool',
        'providers': {'libvirt'},
        'description': 'Storage pool name'
    },
    
    # AWS-specific parameters
    'aws_region': {
        'type': 'string',
        'cli_flag': '--aws-region',
        'providers': {'aws'},
        'description': 'AWS region'
    },
    'aws_profile': {
        'type': 'string',
        'cli_flag': '--aws-profile',
        'providers': {'aws'},
        'description': 'AWS profile'
    },
    
    # Azure-specific parameters
    'azure_region': {
        'type': 'string',
        'cli_flag': '--azure-region',
        'providers': {'azure'},
        'description': 'Azure region'
    },
    'azure_subscription': {
        'type': 'string',
        'cli_flag': '--azure-subscription',
        'providers': {'azure'},
        'description': 'Azure subscription ID'
    },
    'azure_credentials_file': {
        'type': 'string',
        'cli_flag': '--azure-credentials-file',
        'providers': {'azure'},
        'description': 'Path to Azure service principal credentials JSON'
    },
    
    # GCP-specific parameters
    'gcp_region': {
        'type': 'string',
        'cli_flag': '--gcp-region',
        'providers': {'gcp'},
        'description': 'GCP region'
    },
    'gcp_zone': {
        'type': 'string',
        'cli_flag': '--gcp-zone',
        'providers': {'gcp'},
        'description': 'GCP zone'
    },
    'gcp_project': {
        'type': 'string',
        'cli_flag': '--gcp-project',
        'providers': {'gcp'},
        'description': 'GCP project ID'
    },
    'gcp_credentials_file': {
        'type': 'string',
        'cli_flag': '--gcp-credentials-file',
        'providers': {'gcp'},
        'description': 'Path to GCP service account key JSON'
    },
    
    # Hetzner-specific parameters
    'hetzner_location': {
        'type': 'string',
        'cli_flag': '--hetzner-location',
        'providers': {'hetzner'},
        'description': 'Hetzner location'
    },
    'hetzner_network_zone': {
        'type': 'string',
        'cli_flag': '--hetzner-network-zone',
        'providers': {'hetzner'},
        'description': 'Hetzner network zone'
    },
    'hetzner_token': {
        'type': 'string',
        'cli_flag': '--hetzner-token',
        'providers': {'hetzner'},
        'description': 'Hetzner API token'
    },
    
    # DigitalOcean-specific parameters
    'digitalocean_region': {
        'type': 'string',
        'cli_flag': '--digitalocean-region',
        'providers': {'digitalocean'},
        'description': 'DigitalOcean region'
    },
    'digitalocean_token': {
        'type': 'string',
        'cli_flag': '--digitalocean-token',
        'providers': {'digitalocean'},
        'description': 'DigitalOcean API token'
    },
    
    # Common security parameters
    'db_password': {
        'type': 'string',
        'cli_flag': '--db-password',
        'providers': 'all',
        'description': 'Database password'
    },
    'adminui_password': {
        'type': 'string',
        'cli_flag': '--adminui-password',
        'providers': 'all',
        'description': 'Admin UI password'
    },
    'host_password': {
        'type': 'string',
        'cli_flag': '--host-password',
        'providers': 'all',
        'description': 'Host OS password'
    },
    'owner': {
        'type': 'string',
        'cli_flag': '--owner',
        'providers': 'all',
        'description': 'Owner tag for resources'
    },
    'allowed_cidr': {
        'type': 'string',
        'cli_flag': '--allowed-cidr',
        'providers': 'all',
        'description': 'CIDR allowed to access cluster'
    },
    
    # Boolean flags
    'enable_multicast_overlay': {
        'type': 'bool',
        'cli_flag': '--enable-multicast-overlay',
        'providers': 'all',
        'description': 'Enable VXLAN overlay network for multicast support'
    },
    'aws_spot_instance': {
        'type': 'bool',
        'cli_flag': '--aws-spot-instance',
        'providers': {'aws'},
        'description': 'Enable spot instances for cost savings'
    },
    'azure_spot_instance': {
        'type': 'bool',
        'cli_flag': '--azure-spot-instance',
        'providers': {'azure'},
        'description': 'Enable low-priority instances for cost savings'
    },
    'gcp_spot_instance': {
        'type': 'bool',
        'cli_flag': '--gcp-spot-instance',
        'providers': {'gcp'},
        'description': 'Enable preemptible instances for cost savings'
    },
}


def validate_workflow_step(step: Dict, provider: str) -> List[str]:
    """Validate a workflow step configuration
    
    Args:
        step: Step configuration dictionary
        provider: Cloud provider name
        
    Returns:
        List of validation errors (empty if valid)
    """
    errors = []
    
    if 'step' not in step:
        errors.append("Missing required field 'step'")
        return errors
    
    step_type = step['step']
    
    if step_type not in WORKFLOW_STEPS:
        errors.append(f"Unknown step type: {step_type}")
        errors.append(f"Supported steps: {', '.join(sorted(WORKFLOW_STEPS.keys()))}")
        return errors
    
    schema = WORKFLOW_STEPS[step_type]
    
    # Check required fields
    for field in schema.required_fields:
        if field not in step:
            errors.append(f"Step '{step_type}' missing required field: {field}")
    
    # Check provider support
    if schema.supported_providers and provider not in schema.supported_providers:
        errors.append(f"Step '{step_type}' not supported for provider: {provider}")
        errors.append(f"Supported providers: {', '.join(sorted(schema.supported_providers))}")
    
    # Validate specific step requirements
    if step_type == 'validate':
        if 'checks' in step and not isinstance(step['checks'], list):
            errors.append("Field 'checks' must be a list")
        if 'retry' in step:
            retry = step['retry']
            if not isinstance(retry, dict):
                errors.append("Field 'retry' must be an object")
            elif 'max_attempts' in retry and not isinstance(retry['max_attempts'], int):
                errors.append("Field 'retry.max_attempts' must be an integer")
    elif step_type == 'custom_command':
        has_command = bool(step.get('command'))
        has_script = bool(step.get('script'))
        if not has_command and not has_script:
            errors.append("Step 'custom_command' requires 'command' or 'script'")
        if has_command and has_script:
            errors.append("Step 'custom_command' cannot specify both 'command' and 'script'")
    
    return errors


def validate_validation_check(check: str) -> List[str]:
    """Validate a validation check string
    
    Args:
        check: Validation check string
        
    Returns:
        List of validation errors (empty if valid)
    """
    errors = []
    
    # Check cluster_status pattern
    if check.startswith('cluster_status'):
        if '==' in check or '!=' in check:
            operator = '==' if '==' in check else '!='
            value = check.split(operator, 1)[1].strip()
            if value not in VALID_CLUSTER_STATUSES:
                errors.append(f"Unknown cluster status value: {value}")
                errors.append(f"Valid values: {', '.join(sorted(VALID_CLUSTER_STATUSES))}")
        else:
            errors.append(f"Invalid cluster_status check format: {check}")
            errors.append(f"Expected format: {VALIDATION_CHECK_PATTERNS['cluster_status']}")
    
    # Check health_status pattern
    elif check.startswith('health_status['):
        import re
        match = re.match(r'health_status\[([^\]]+)\]\.([^=!]+)(==|!=)(.+)', check)
        if not match:
            errors.append(f"Invalid health_status check format: {check}")
            errors.append(f"Expected format: {VALIDATION_CHECK_PATTERNS['health_status']}")
        else:
            component = match.group(2).strip()
            value = match.group(4).strip()
            
            if component not in HEALTH_CHECK_COMPONENTS:
                errors.append(f"Unknown health check component: {component}")
                errors.append(f"Valid components: {', '.join(sorted(HEALTH_CHECK_COMPONENTS.keys()))}")
            
            if value.lower() not in VALID_HEALTH_VALUES:
                errors.append(f"Unknown health check value: {value}")
                errors.append(f"Valid values: {', '.join(sorted(VALID_HEALTH_VALUES.keys()))}")
    else:
        errors.append(f"Unknown validation check format: {check}")
        errors.append(f"Supported patterns: {', '.join(VALIDATION_CHECK_PATTERNS.keys())}")
    
    return errors


def validate_sut_parameters(parameters: Dict, provider: str) -> List[str]:
    """Validate SUT parameters
    
    Args:
        parameters: Parameters dictionary
        provider: Cloud provider name
        
    Returns:
        List of validation errors (empty if valid)
    """
    errors = []
    
    for param_name, param_value in parameters.items():
        if param_name not in SUT_PARAMETERS:
            errors.append(f"Unknown parameter: {param_name}")
            continue
        
        param_schema = SUT_PARAMETERS[param_name]
        
        # Check provider support
        if param_schema['providers'] != 'all' and provider not in param_schema['providers']:
            errors.append(f"Parameter '{param_name}' not supported for provider: {provider}")
            errors.append(f"Supported providers: {', '.join(sorted(param_schema['providers']))}")
        
        # Check type
        expected_type = param_schema['type']
        if expected_type == 'int' and not isinstance(param_value, int):
            errors.append(f"Parameter '{param_name}' must be an integer, got: {type(param_value).__name__}")
        elif expected_type == 'string' and not isinstance(param_value, str):
            errors.append(f"Parameter '{param_name}' must be a string, got: {type(param_value).__name__}")
        elif expected_type == 'bool' and not isinstance(param_value, bool):
            errors.append(f"Parameter '{param_name}' must be a boolean, got: {type(param_value).__name__}")
    
    return errors
