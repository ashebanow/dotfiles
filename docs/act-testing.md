# GitHub Actions Testing with Act

This project includes integration tests for GitHub Actions workflows using [`act`](https://github.com/nektos/act), which allows you to run GitHub Actions locally.

## Prerequisites

1. **Docker**: Required for act to run GitHub Actions
   ```bash
   # Install Docker Desktop or ensure Docker daemon is running
   docker --version
   ```

2. **Act**: Install from GitHub releases or package manager
   ```bash
   # macOS with Homebrew
   brew install act
   
   # Or download from: https://github.com/nektos/act/releases
   ```

## Configuration

### Act Configuration (`.actrc`)
The project includes an `.actrc` file with optimal settings:
- Uses `linux/amd64` architecture for compatibility
- Configures resource limits and security settings
- Sets up verbose logging for debugging

### Local Secrets (`.secrets`)
For testing purposes, a `.secrets` file provides fake credentials:
```bash
GITHUB_TOKEN=fake-token-for-local-testing
CODECOV_TOKEN=fake-codecov-token
```

## Running Tests

### Command Line
```bash
# Run GitHub Actions tests
./test.sh actions

# Or use just
just test-actions

# Run specific test
python tests/test_github_actions.py TestGitHubActionsIntegration.test_workflow_syntax_validation
```

### What Gets Tested

1. **Workflow Syntax Validation**
   - YAML syntax correctness
   - GitHub Actions schema compliance
   - Workflow trigger configuration

2. **Workflow Execution (when Docker is available)**
   - Dry-run execution of CI workflows
   - Package cache refresh workflows
   - Event trigger validation

3. **Environment Compatibility**
   - Python version matrix support
   - Ubuntu runner compatibility
   - Secret handling

## Test Behavior

### On CI
- Tests are automatically skipped since GitHub Actions run natively
- Prevents redundant testing and Docker dependency issues

### Local Development
- **With Docker**: Full workflow execution testing
- **Without Docker**: Only syntax validation (Docker-dependent tests are skipped)

### Error Handling
Tests gracefully handle:
- Missing Docker daemon
- Network connectivity issues
- Missing container images

## Example Usage

```bash
# Validate workflow syntax only
act --dryrun --list

# Test specific workflow
act --dryrun --job test

# Test with custom event
act workflow_dispatch --dryrun

# Test with secrets
act --secret-file .secrets --dryrun
```

## Workflow Testing Strategy

The integration tests follow this hierarchy:

1. **Basic Validation**: YAML syntax and structure
2. **Execution Testing**: Dry-run validation (requires Docker)
3. **Event Testing**: Trigger and matrix validation
4. **Environment Testing**: Platform and secret compatibility

## Troubleshooting

### Docker Issues
```bash
# Check Docker status
docker info

# Pull required images manually
docker pull catthehacker/ubuntu:act-latest
```

### Act Issues
```bash
# Check act version
act --version

# List available workflows
act --list

# Debug with verbose output
act --verbose --dryrun
```

### Common Errors

1. **"Cannot connect to Docker daemon"**
   - Solution: Start Docker Desktop or install Docker
   - Alternative: Tests will skip Docker-dependent checks

2. **"workflow is not valid"**
   - Solution: Check YAML syntax in workflow files
   - Use: `yamllint .github/workflows/`

3. **Container pull failures**
   - Solution: Check internet connection
   - Alternative: Use `--pull=false` in .actrc

## Benefits

- **Early Detection**: Catch workflow issues before pushing
- **Local Development**: Test workflow changes without CI runs
- **Documentation**: Workflows serve as executable documentation
- **Validation**: Ensure workflows work across different environments

## Limitations

- Requires Docker for full functionality
- Some GitHub-specific features may not work identically
- Container environment may differ from actual GitHub runners
- Network-dependent steps may fail in restricted environments