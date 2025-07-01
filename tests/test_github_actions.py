#!/usr/bin/env python3
"""
Integration tests for GitHub Actions using act

These tests use 'act' to run GitHub Actions locally for validation.
They are designed to run only locally and are skipped on CI since
CI already runs the actual GitHub Actions.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


class TestGitHubActionsIntegration(unittest.TestCase):
    """Test GitHub Actions workflows using act"""

    @classmethod
    def setUpClass(cls):
        """Set up class-level fixtures"""
        cls.project_root = Path(__file__).parent.parent
        cls.workflows_dir = cls.project_root / ".github" / "workflows"
        
        # Check if we're running on CI
        cls.is_ci = os.getenv("CI", "false").lower() == "true"
        
        # Check if act is available
        try:
            result = subprocess.run(
                ["act", "--version"], 
                capture_output=True, 
                text=True, 
                check=True
            )
            cls.act_available = True
            cls.act_version = result.stdout.strip()
            
            # Check if Docker is available for act
            docker_result = subprocess.run(
                ["docker", "info"], 
                capture_output=True, 
                text=True
            )
            cls.docker_available = docker_result.returncode == 0
        except (subprocess.CalledProcessError, FileNotFoundError):
            cls.act_available = False
            cls.act_version = None
            cls.docker_available = False

    def setUp(self):
        """Set up test fixtures"""
        if self.is_ci:
            self.skipTest("Skipping act tests on CI - GitHub Actions already run natively")
            
        if not self.act_available:
            self.skipTest("act is not available - install from https://github.com/nektos/act")

    def test_act_is_working(self):
        """Test that act is properly installed and working"""
        result = subprocess.run(
            ["act", "--list"],
            cwd=self.project_root,
            capture_output=True,
            text=True
        )
        
        self.assertEqual(result.returncode, 0, "act --list should succeed")
        self.assertIn("CI - Comprehensive Tests", result.stdout)
        self.assertIn("Refresh Package Cache", result.stdout)

    def test_workflow_syntax_validation(self):
        """Test that all workflow files have valid syntax"""
        for workflow_file in self.workflows_dir.glob("*.yml"):
            with self.subTest(workflow=workflow_file.name):
                # Use act to validate workflow syntax
                result = subprocess.run(
                    ["act", "--dryrun", "--workflows", str(workflow_file)],
                    cwd=self.project_root,
                    capture_output=True,
                    text=True
                )
                
                # Check for YAML syntax errors specifically
                if "yaml:" in result.stderr or "workflow is not valid" in result.stderr:
                    self.fail(f"Workflow {workflow_file.name} has YAML syntax errors:\n{result.stderr}")
                
                # Docker connection errors are OK for syntax validation
                if "Cannot connect to the Docker daemon" in result.stderr:
                    self.skipTest(f"Docker not available for {workflow_file.name} - YAML syntax is valid")

    def test_ci_workflow_dry_run(self):
        """Test CI workflow in dry-run mode"""
        if not self.docker_available:
            self.skipTest("Docker is not available - required for act workflow execution")
            
        result = subprocess.run(
            ["act", "--dryrun", "--job", "test"],
            cwd=self.project_root,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Should succeed in dry-run mode
        self.assertEqual(result.returncode, 0, f"CI workflow dry-run failed: {result.stderr}")
        
        # Check that expected steps are present
        self.assertIn("Install Python dependencies", result.stdout)
        self.assertIn("Run Python unit tests", result.stdout)

    def test_refresh_cache_workflow_dry_run(self):
        """Test refresh cache workflow in dry-run mode"""
        if not self.docker_available:
            self.skipTest("Docker is not available - required for act workflow execution")
            
        result = subprocess.run(
            ["act", "--dryrun", "workflow_dispatch", "--job", "refresh-cache"],
            cwd=self.project_root,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Should succeed in dry-run mode
        self.assertEqual(result.returncode, 0, f"Refresh cache workflow dry-run failed: {result.stderr}")
        
        # Check that expected steps are present
        self.assertIn("Determine cache segment", result.stdout)
        self.assertIn("Create cache refresh script", result.stdout)

    def test_workflow_event_triggers(self):
        """Test that workflows respond to correct event triggers"""
        if not self.docker_available:
            self.skipTest("Docker is not available - required for act workflow execution")
            
        # Test CI workflow triggers
        for event in ["push", "pull_request", "workflow_dispatch"]:
            with self.subTest(event=event):
                result = subprocess.run(
                    ["act", event, "--dryrun", "--job", "test"],
                    cwd=self.project_root,
                    capture_output=True,
                    text=True,
                    timeout=20
                )
                
                self.assertEqual(result.returncode, 0, 
                    f"CI workflow should trigger on {event}: {result.stderr}")

    def test_refresh_cache_validation_mode(self):
        """Test refresh cache workflow in validation mode (PR simulation)"""
        if not self.docker_available:
            self.skipTest("Docker is not available - required for act workflow execution")
            
        result = subprocess.run(
            ["act", "pull_request", "--dryrun", "--job", "refresh-cache"],
            cwd=self.project_root,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        self.assertEqual(result.returncode, 0, f"Validation mode failed: {result.stderr}")


class TestActConfiguration(unittest.TestCase):
    """Test act configuration and setup"""

    def setUp(self):
        """Set up test fixtures"""
        self.project_root = Path(__file__).parent.parent
        
        # Skip if on CI
        if os.getenv("CI", "false").lower() == "true":
            self.skipTest("Skipping act configuration tests on CI")

    def test_act_config_file_creation(self):
        """Test creating and validating act configuration"""
        actrc_path = self.project_root / ".actrc"
        
        # Create a temporary .actrc file for testing
        with tempfile.NamedTemporaryFile(mode='w', suffix='.actrc', delete=False) as f:
            f.write("# Act configuration for dotfiles project\n")
            f.write("--container-architecture linux/amd64\n")
            f.write("--pull=false\n")  # Don't auto-pull images for faster testing
            f.write("--verbose\n")
            temp_actrc = f.name
        
        try:
            # Test that act accepts this configuration
            result = subprocess.run(
                ["act", "--list", "--config", temp_actrc],
                cwd=self.project_root,
                capture_output=True,
                text=True
            )
            
            self.assertEqual(result.returncode, 0, "act should accept configuration file")
            
        finally:
            # Clean up
            os.unlink(temp_actrc)

    def test_workflow_secrets_handling(self):
        """Test that workflows handle missing secrets gracefully in act"""
        # Create a temporary secrets file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.secrets', delete=False) as f:
            secrets = {
                "GITHUB_TOKEN": "fake-token-for-testing"
            }
            for key, value in secrets.items():
                f.write(f"{key}={value}\n")
            temp_secrets = f.name
        
        try:
            # Test that workflows can run with fake secrets
            result = subprocess.run(
                ["act", "--dryrun", "--secret-file", temp_secrets],
                cwd=self.project_root,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            # Should not fail due to missing secrets
            self.assertEqual(result.returncode, 0, 
                f"Workflows should handle fake secrets: {result.stderr}")
            
        finally:
            # Clean up
            os.unlink(temp_secrets)


class TestWorkflowEnvironmentCompatibility(unittest.TestCase):
    """Test workflow compatibility across different environments"""

    def setUp(self):
        """Set up test fixtures"""
        if os.getenv("CI", "false").lower() == "true":
            self.skipTest("Skipping environment compatibility tests on CI")

    def test_python_version_matrix(self):
        """Test that CI workflow handles Python version matrix correctly"""
        project_root = Path(__file__).parent.parent
        
        # Test with specific Python version
        result = subprocess.run(
            ["act", "--dryrun", "--matrix", "python-version:3.12"],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        self.assertEqual(result.returncode, 0, "Python version matrix should work")

    def test_ubuntu_runner_compatibility(self):
        """Test that workflows are compatible with ubuntu-latest runner"""
        project_root = Path(__file__).parent.parent
        
        # Use Ubuntu image that act uses by default
        result = subprocess.run(
            ["act", "--dryrun", "--platform", "ubuntu-latest=catthehacker/ubuntu:act-latest"],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        self.assertEqual(result.returncode, 0, "Should work with Ubuntu runner")


def run_act_tests():
    """Run act-based integration tests"""
    # Check if we should skip these tests
    if os.getenv("CI", "false").lower() == "true":
        print("Skipping act tests on CI - GitHub Actions run natively")
        return True
    
    # Check if act is available
    try:
        subprocess.run(["act", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("act is not available - skipping integration tests")
        print("Install act from: https://github.com/nektos/act")
        return True
    
    # Run the tests
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test classes
    for test_class in [TestGitHubActionsIntegration, TestActConfiguration, TestWorkflowEnvironmentCompatibility]:
        suite.addTests(loader.loadTestsFromTestCase(test_class))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return result.wasSuccessful()


if __name__ == "__main__":
    # Set up environment
    project_root = Path(__file__).parent.parent
    os.chdir(project_root)
    
    success = run_act_tests()
    sys.exit(0 if success else 1)