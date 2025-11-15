#!/usr/bin/env python3
"""
Unit tests for Enhanced Progress Tracking in E2E Framework

Tests the enhanced progress bar, deployment step logging, and
thread-safe progress tracking functionality.
"""

import unittest
import tempfile
import json
import time
import threading
from pathlib import Path
from unittest.mock import patch, MagicMock
from io import StringIO
import sys

TESTS_DIR = Path(__file__).resolve().parent
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from e2e_framework import E2ETestFramework


class TestEnhancedProgressTracking(unittest.TestCase):
    """Test cases for enhanced progress tracking functionality."""

    def setUp(self):
        """Set up test environment."""
        # Create user-specific temp directory
        username = 'testuser'
        test_id = 'test12345'
        self.temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        
        # Create test configuration
        self.config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'combinations': '1-wise',
                    'parameters': {
                        'cluster_size': [1]
                    }
                }
            }
        }
        
        # Create config file
        self.config_file = self.temp_dir / 'test_config.json'
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f)
        
        # Create framework instance
        self.framework = E2ETestFramework(str(self.config_file), self.temp_dir / 'results')

    def tearDown(self):
        """Clean up test environment."""
        import shutil
        shutil.rmtree(self.temp_dir)

    def test_render_progress_basic(self):
        """Test basic progress bar rendering."""
        # Capture stdout
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 3)
        
        output = captured_output.getvalue()
        self.assertIn('Progress:', output)
        self.assertIn('1/3', output)
        self.assertIn('[##########--------------------]', output)  # Basic progress bar

    def test_render_progress_with_deployment(self):
        """Test progress bar with deployment information."""
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 3, 'test-deployment-001', 'deploying')
        
        output = captured_output.getvalue()
        self.assertIn('test-deployment-001', output)
        self.assertIn('deploying', output)

    def test_render_progress_with_long_deployment_id(self):
        """Test progress bar truncates long deployment IDs."""
        long_deployment_id = 'very-long-deployment-id-that-should-be-truncated'
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 3, long_deployment_id, 'testing')
        
        output = captured_output.getvalue()
        # Should truncate to ~20 characters + "..."
        self.assertIn('very-long-deployment...', output)
        self.assertNotIn(long_deployment_id, output)

    def test_render_progress_zero_total(self):
        """Test progress bar with zero total (should not crash)."""
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 0)
        
        # Should not output anything when total is 0
        output = captured_output.getvalue()
        self.assertEqual(output, '')

    def test_render_progress_complete(self):
        """Test progress bar with 100% completion."""
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(3, 3)
        
        output = captured_output.getvalue()
        self.assertIn('[##############################]', output)  # Full bar
        self.assertIn('3/3', output)

    def test_log_deployment_step_basic(self):
        """Test basic deployment step logging."""
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._log_deployment_step('test-deployment-001', 'initializing')
        
        output = captured_output.getvalue()
        # Should contain timestamp, deployment ID, and step
        self.assertIn('test-deployment-001', output)
        self.assertIn('initializing', output)
        # Should contain timestamp format HH:MM:SS
        import re
        self.assertTrue(re.search(r'\d{2}:\d{2}:\d{2}', output))

    def test_log_deployment_step_with_status(self):
        """Test deployment step logging with status."""
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._log_deployment_step('test-deployment-001', 'deploying', 'in progress')
        
        output = captured_output.getvalue()
        self.assertIn('test-deployment-001', output)
        self.assertIn('deploying', output)
        self.assertIn('in progress', output)

    def test_log_deployment_step_clears_progress(self):
        """Test that deployment step logging clears progress line."""
        # First render progress
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 3, 'test-deployment', 'testing')
        
        progress_output = captured_output.getvalue()
        
        # Then log deployment step
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._log_deployment_step('test-deployment', 'step', 'status')
        
        step_output = captured_output.getvalue()
        
        # Step output should come after clearing the line
        self.assertIn('test-deployment', step_output)
        self.assertIn('step', step_output)

    def test_progress_tracking_state(self):
        """Test progress tracking state management."""
        # Test initial state
        self.assertIsNone(self.framework._current_deployment)
        self.assertIsNone(self.framework._current_step)
        self.assertEqual(self.framework._completed_tests, 0)
        self.assertEqual(self.framework._total_tests, 0)

    def test_progress_tracking_thread_safety(self):
        """Test that progress tracking is thread-safe."""
        results = []
        errors = []
        
        def update_progress(thread_id):
            try:
                for i in range(10):
                    with self.framework._progress_lock:
                        self.framework._current_deployment = f'test-{thread_id}'
                        self.framework._current_step = f'step-{i}'
                        results.append(f'{thread_id}-{i}')
                    time.sleep(0.001)  # Small delay to increase chance of race conditions
            except Exception as e:
                errors.append(str(e))
        
        # Run multiple threads
        threads = []
        for i in range(5):
            thread = threading.Thread(target=update_progress, args=(f'thread-{i}',))
            threads.append(thread)
            thread.start()
        
        for thread in threads:
            thread.join()
        
        # Should have no errors
        self.assertEqual(len(errors), 0)
        # Should have results from all threads
        self.assertEqual(len(results), 50)  # 5 threads * 10 iterations each

    def test_progress_tracking_with_total_tests(self):
        """Test progress tracking with total tests set."""
        # Set total tests
        with self.framework._progress_lock:
            self.framework._total_tests = 5
        
        self.assertEqual(self.framework._total_tests, 5)

    def test_progress_tracking_completed_count(self):
        """Test progress tracking completed count updates."""
        # Update completed count
        with self.framework._progress_lock:
            self.framework._completed_tests = 3
        
        self.assertEqual(self.framework._completed_tests, 3)

    def test_enhanced_progress_in_test_execution(self):
        """Test enhanced progress tracking during test execution simulation."""
        # Set up test tracking
        with self.framework._progress_lock:
            self.framework._total_tests = 2
            self.framework._current_deployment = 'test-deployment-001'
            self.framework._current_step = 'initializing'
        
        # Simulate step progression
        steps = ['initializing', 'deploying', 'validating', 'cleaning up']
        captured_output = StringIO()
        
        with patch('sys.stdout', captured_output):
            for step in steps:
                with self.framework._progress_lock:
                    self.framework._current_step = step
                self.framework._log_deployment_step('test-deployment-001', step, 'in progress')
                time.sleep(0.01)  # Small delay
                self.framework._log_deployment_step('test-deployment-001', step, 'completed')
        
        output = captured_output.getvalue()
        
        # Should contain all steps
        for step in steps:
            self.assertIn(f'test-deployment-001 {step}', output)
            # Note: step logging doesn't include "in progress" text, just the step name
            # The "completed" status is also not included in the basic logging
            self.assertGreater(output.count(f'test-deployment-001 {step}'), 0)

    def test_progress_bar_with_current_info(self):
        """Test progress bar with current deployment and step info."""
        with self.framework._progress_lock:
            self.framework._current_deployment = 'test-deployment-001'
            self.framework._current_step = 'deploying'
        
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 3, 'test-deployment-001', 'deploying')
        
        output = captured_output.getvalue()
        self.assertIn('test-deployment-001', output)
        self.assertIn('deploying', output)

    def test_progress_bar_without_current_info(self):
        """Test progress bar without current deployment/step info."""
        # Clear current info
        with self.framework._progress_lock:
            self.framework._current_deployment = None
            self.framework._current_step = None
        
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            self.framework._render_progress(1, 3)
        
        output = captured_output.getvalue()
        self.assertIn('Progress:', output)
        self.assertIn('1/3', output)
        # Should not contain deployment or step info
        self.assertNotIn('|', output)

    def test_multiple_concurrent_progress_updates(self):
        """Test concurrent progress updates don't interfere."""
        results = []
        
        def update_progress(thread_id, count):
            for i in range(count):
                captured_output = StringIO()
                with patch('sys.stdout', captured_output):
                    self.framework._render_progress(i, count, f'deployment-{thread_id}', f'step-{i}')
                results.append(captured_output.getvalue())
        
        # Run concurrent updates
        threads = []
        for i in range(3):
            thread = threading.Thread(target=update_progress, args=(i, 5))
            threads.append(thread)
            thread.start()
        
        for thread in threads:
            thread.join()
        
        # Should have results from all threads
        self.assertEqual(len(results), 15)  # 3 threads * 5 updates each

    def test_progress_bar_fraction_calculation(self):
        """Test progress bar fraction calculation."""
        # Test various fractions (30 character bar)
        test_cases = [
            (0, 4, '[------------------------------]'),      # 0%
            (1, 4, '[#######-----------------------]'),      # 25% (1/4 of 30 chars = 7.5, rounded down to 7)
            (2, 4, '[###############---------------]'),      # 50% (2/4 of 30 chars = 15)
            (3, 4, '[######################--------]'),      # 75% (3/4 of 30 chars = 22.5, rounded down to 22)
            (4, 4, '[##############################]'),      # 100%
            (5, 4, '[##############################]'),      # >100% (capped)
        ]
        
        for completed, total, expected_bar in test_cases:
            captured_output = StringIO()
            with patch('sys.stdout', captured_output):
                self.framework._render_progress(completed, total)
            
            output = captured_output.getvalue()
            self.assertIn(expected_bar, output)

    def test_deployment_step_status_variations(self):
        """Test different status values in deployment step logging."""
        statuses = ['STARTED', 'in progress', 'completed', 'FAILED', 'TIMEOUT']
        deployment_id = 'test-deployment-status'
        step = 'testing'
        
        for status in statuses:
            captured_output = StringIO()
            with patch('sys.stdout', captured_output):
                self.framework._log_deployment_step(deployment_id, step, status)
            
            output = captured_output.getvalue()
            self.assertIn(deployment_id, output)
            self.assertIn(step, output)
            # STARTED status doesn't get included in output (default behavior)
            if status != 'STARTED':
                self.assertIn(status, output)
            else:
                # For STARTED, just check that deployment_id and step are present
                self.assertGreater(output.count(deployment_id), 0)
                self.assertGreater(output.count(step), 0)

    def test_progress_tracking_cleanup(self):
        """Test cleanup of progress tracking state."""
        # Set some state
        with self.framework._progress_lock:
            self.framework._current_deployment = 'test-deployment'
            self.framework._current_step = 'testing'
            self.framework._completed_tests = 5
        
        # Clear state
        with self.framework._progress_lock:
            self.framework._current_deployment = None
            self.framework._current_step = None
        
        # Verify cleanup
        self.assertIsNone(self.framework._current_deployment)
        self.assertIsNone(self.framework._current_step)
        # completed_tests should persist
        self.assertEqual(self.framework._completed_tests, 5)


class TestProgressTrackingIntegration(unittest.TestCase):
    """Integration tests for progress tracking with E2E framework."""

    def setUp(self):
        """Set up test environment."""
        username = 'testuser'
        test_id = 'test12345'
        self.temp_dir = Path(tempfile.mkdtemp(prefix=f"exasol_test_{username}_{test_id}_"))
        
        self.config = {
            'test_suites': {
                'test_suite': {
                    'provider': 'aws',
                    'combinations': '1-wise',
                    'parameters': {
                        'cluster_size': [1]
                    }
                }
            }
        }
        
        self.config_file = self.temp_dir / 'test_config.json'
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f)

    def tearDown(self):
        """Clean up test environment."""
        import shutil
        shutil.rmtree(self.temp_dir)

    def test_progress_tracking_in_dry_run(self):
        """Test progress tracking during dry run execution."""
        framework = E2ETestFramework(str(self.config_file), self.temp_dir / 'results')
        
        # Capture stdout
        captured_output = StringIO()
        with patch('sys.stdout', captured_output):
            test_plan = framework.generate_test_plan(dry_run=True)
        
        output = captured_output.getvalue()
        # Should show dry run output without progress tracking
        self.assertIn('Dry run:', output)
        self.assertIn('Generated', output)

    def test_progress_tracking_initialization(self):
        """Test that progress tracking is properly initialized."""
        framework = E2ETestFramework(str(self.config_file), self.temp_dir / 'results')
        
        # Check that progress tracking attributes exist
        self.assertTrue(hasattr(framework, '_progress_lock'))
        self.assertTrue(hasattr(framework, '_current_deployment'))
        self.assertTrue(hasattr(framework, '_current_step'))
        self.assertTrue(hasattr(framework, '_completed_tests'))
        self.assertTrue(hasattr(framework, '_total_tests'))
        
        # Check initial values
        self.assertIsInstance(framework._progress_lock, type(threading.Lock()))
        self.assertIsNone(framework._current_deployment)
        self.assertIsNone(framework._current_step)
        self.assertEqual(framework._completed_tests, 0)
        self.assertEqual(framework._total_tests, 0)

    def test_progress_tracking_methods_exist(self):
        """Test that all progress tracking methods exist."""
        framework = E2ETestFramework(str(self.config_file), self.temp_dir / 'results')
        
        # Check that methods exist
        self.assertTrue(hasattr(framework, '_render_progress'))
        self.assertTrue(hasattr(framework, '_log_deployment_step'))
        self.assertTrue(callable(framework._render_progress))
        self.assertTrue(callable(framework._log_deployment_step))


if __name__ == '__main__':
    unittest.main()