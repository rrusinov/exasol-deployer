# Contributing to Exasol Deployer

Thank you for your interest in contributing to the Exasol Deployer project! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Process](#contributing-process)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Community](#community)

## Code of Conduct

This project adheres to a Code of Conduct that we expect all contributors to follow. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Operating System**: Linux (recommended) or macOS
- **Bash**: Version 4.0 or later
- **Git**: For version control
- **OpenTofu** or Terraform (>= 1.0)
- **Ansible** (>= 2.9)
- **jq**: For JSON processing
- **Python 3.6+**: For running tests
- **ShellCheck**: For shell script linting

### Development Dependencies

For development and testing:

```bash
# Install ShellCheck (used by test framework)
# On Ubuntu/Debian:
sudo apt-get install shellcheck

# On macOS:
brew install shellcheck

# Install Python dependencies for testing
pip3 install -r tests/python-helpers/requirements.txt
```

## Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/YOUR_USERNAME/exasol-deployer.git
   cd exasol-deployer
   ```

2. **Set up Development Environment**
   ```bash
   # Make scripts executable
   chmod +x exasol
   chmod +x tests/run_tests.sh
   
   # Run initial tests to verify setup
   ./tests/run_tests.sh
   ```

3. **Verify Installation**
   ```bash
   ./exasol version
   ```

## Contributing Process

### 1. Choose an Issue

- Look for issues labeled `good first issue` for newcomers
- Check existing issues and discussions before starting work
- For new features, create an issue first to discuss the approach

### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

### 3. Make Changes

- Follow the [coding standards](#coding-standards)
- Write tests for new functionality
- Update documentation as needed
- Ensure all tests pass

### 4. Test Your Changes

```bash
# Run all unit tests (includes shellcheck linting)
./tests/run_tests.sh

# Run specific tests
./tests/test_common.sh
./tests/test_shellcheck.sh

# Run E2E tests (manual execution only, requires cloud credentials)
./tests/run_e2e.sh --provider libvirt
```

## Coding Standards

### Shell Scripts (.sh)

- **Shebang**: Always use `#!/usr/bin/env bash`
- **Include Guards**: Use for library files:
  ```bash
  if [[ -n "${__FILE_INCLUDED__:-}" ]]; then return 0; fi
  readonly __FILE_INCLUDED__=1
  ```
- **Constants**: Use `readonly VAR_NAME='value'` (UPPER_CASE)
- **Functions**: Use `function_name() { ... }` (snake_case)
- **Error Handling**: Use `die "message"` for fatal errors
- **Dependencies**: Source common libraries: `source "$LIB_DIR/common.sh"`
- **Colors**: Use COLOR_* constants from common.sh
- **Avoid Embedded Python**: Do NOT use `python3 -c "..."` inline
  - Instead: Add functions to Python helper files
  - Call Python scripts with proper arguments

### Python Scripts (.py)

- **Standard Library Only**: Python 3.6+ standard library
- **Docstrings**: Use triple-quoted strings for modules/functions
- **Encoding**: UTF-8 for file operations
- **Error Handling**: Use try/except with specific exceptions
- **Imports**: Standard library only (re, sys, os, argparse)

### General Guidelines

- **Naming**: snake_case for functions/variables, UPPER_CASE for constants
- **Comments**: Descriptive comments for complex logic only
- **File Permissions**: Make scripts executable (+x)
- **Dependencies**: Pure bash/Python standard library

## Testing

### Testing Strategy

The project uses a multi-layered testing approach:

1. **Unit Tests** - Fast, automated, run in CI
2. **Integration Tests** - Medium speed, automated, run in CI  
3. **E2E Tests** - Slow, expensive, **manual execution only**

### Unit Tests

All shell scripts should have corresponding unit tests:

```bash
# Test naming convention
tests/test_<module_name>.sh

# Run specific test
./tests/test_common.sh

# Run all tests
./tests/run_tests.sh
```

### Property-Based Tests

For complex logic, consider property-based tests:

```bash
# Python property tests (run automatically with ./tests/run_tests.sh)
tests/test_<feature>_property.py

# Examples of existing property tests:
python3 tests/test_shellcheck_property.py
python3 tests/test_link_validation_property.py
python3 tests/test_style_consistency_property.py
```

### End-to-End Tests

E2E tests verify complete workflows and should be run manually before releases due to their resource requirements and cost:

```bash
# List available tests
./tests/run_e2e.sh --list-tests

# Run specific provider tests (manual execution recommended)
./tests/run_e2e.sh --provider libvirt

# Run with custom configuration
./tests/run_e2e.sh --config tests/e2e/configs/sut/libvirt-1n.json
```

**Important**: E2E tests are **not** run automatically in CI/CD pipelines due to:
- High resource consumption
- Cloud provider costs
- Extended execution time
- Requirement for cloud credentials

**When to run E2E tests**:
- Before major releases
- When adding new cloud provider support
- When modifying core deployment logic
- For manual validation of critical changes

### Test Requirements

- **Coverage**: New features must include tests
- **Isolation**: Tests should not depend on external services
- **Cleanup**: Tests must clean up resources
- **Documentation**: Complex tests should include comments

## Documentation

### Code Documentation

- **Shell Functions**: Include brief comments for complex functions
- **Python Functions**: Use docstrings following PEP 257
- **Configuration**: Document all configuration options

### User Documentation

- **README Updates**: Update README.md for new features
- **Cloud Setup Guides**: Update provider-specific guides in `clouds/`
- **Examples**: Include usage examples for new functionality

### Documentation Standards

- **Markdown**: Use standard Markdown formatting
- **Code Blocks**: Include language specification
- **Links**: Use relative links for internal documentation
- **Structure**: Follow existing documentation structure

## Submitting Changes

### Pull Request Process

1. **Update Documentation**: Ensure all documentation is current
2. **Test Coverage**: Verify tests pass and coverage is adequate
3. **Commit Messages**: Use clear, descriptive commit messages
4. **Pull Request Description**: Include:
   - Summary of changes
   - Related issue numbers
   - Testing performed
   - Breaking changes (if any)

### Commit Message Format

```
type(scope): brief description

Detailed explanation of the change, including:
- What was changed and why
- Any breaking changes
- Related issue numbers

Closes #123
```

**Types**: feat, fix, docs, style, refactor, test, chore

### Review Process

- All changes require review from maintainers
- Address review feedback promptly
- Maintain a clean commit history
- Squash commits if requested

## Community

### Getting Help

- **Issues**: Use GitHub issues for bugs and feature requests
- **Discussions**: Use GitHub discussions for questions
- **Documentation**: Check existing documentation first

### Communication Guidelines

- Be respectful and inclusive
- Provide clear, detailed information
- Search existing issues before creating new ones
- Use appropriate labels and templates

### Recognition

Contributors are recognized in:
- Release notes for significant contributions
- GitHub contributor statistics
- Project documentation

## Development Workflow

### Branch Strategy

- **main**: Stable release branch
- **feature/***: New features
- **fix/***: Bug fixes
- **docs/***: Documentation updates

### Release Process

1. Features merged to main via pull requests
2. Releases tagged with semantic versioning
3. Release notes generated automatically
4. Artifacts published to GitHub releases

### Continuous Integration

All pull requests automatically trigger:
- Unit test execution
- Shell script linting (ShellCheck)
- Documentation validation
- Template validation
- Security pattern analysis

**E2E tests are NOT run automatically** in CI due to cost and resource constraints. They should be executed manually before releases.

## Release Testing Procedures

### Pre-Release Testing Checklist

Before creating a release, maintainers should:

1. **Automated Tests** (run automatically in CI):
   - ✅ All unit tests pass
   - ✅ ShellCheck linting passes
   - ✅ Template validation passes
   - ✅ Documentation validation passes

2. **Manual E2E Testing** (run manually before release):
   - 🔧 Test libvirt deployment (local, fast)
   - 🔧 Test at least one major cloud provider (AWS/Azure/GCP)
   - 🔧 Test deployment lifecycle (init → deploy → stop → start → destroy)
   - 🔧 Verify installer script works correctly

3. **Release Validation**:
   - 🔧 Version numbers are correct
   - 🔧 Release notes are complete
   - 🔧 Installer artifact is built correctly

### E2E Test Execution for Releases

```bash
# Recommended E2E testing sequence for releases:

# 1. Quick local test (libvirt)
./tests/run_e2e.sh --provider libvirt --config tests/e2e/configs/sut/libvirt-1n.json

# 2. Cloud provider test (choose one major provider)
./tests/run_e2e.sh --provider aws --config tests/e2e/configs/sut/aws-1n.json

# 3. Multi-node test (if significant changes)
./tests/run_e2e.sh --provider libvirt --config tests/e2e/configs/sut/libvirt-2n.json
```

## Advanced Topics

### Cloud Provider Support

Adding new cloud providers requires:
- Terraform templates in `templates/terraform-<provider>/`
- Cloud setup documentation in `clouds/CLOUD_SETUP_<PROVIDER>.md`
- Provider-specific initialization logic
- Comprehensive testing

### Template Development

Terraform and Ansible templates follow:
- Consistent variable naming
- Proper resource tagging
- Security best practices
- Cross-platform compatibility

### Testing Infrastructure

The project uses:
- Shell-based unit testing framework
- Python property-based testing
- Docker-based E2E testing
- Resource-aware test scheduling

## License

By contributing to this project, you agree that your contributions will be licensed under the Apache License 2.0.

## Questions?

If you have questions not covered in this guide:
1. Check existing documentation
2. Search GitHub issues and discussions
3. Create a new discussion or issue
4. Contact maintainers through GitHub

Thank you for contributing to Exasol Deployer!