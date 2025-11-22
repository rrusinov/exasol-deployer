# Python Helper Scripts

This directory contains Python helper scripts that support the Exasol Deployer test scripts. These scripts extract and parse information from shell scripts and documentation files.

## Scripts

### extract_function_options.py

Extracts command-line options from shell script functions.

**Usage:**
```bash
python3 extract_function_options.py <shell_script> <function_name>
```

**Purpose:**
- Parses shell script files to find function definitions
- Extracts command-line options (e.g., `--help`, `--version`) from function implementations
- Used by test scripts to verify help documentation completeness

**Dependencies:** Python 3.6+ standard library only

### extract_readme_flags.py

Extracts command-line flags from README documentation sections.

**Usage:**
```bash
python3 extract_readme_flags.py <readme_file> [section_name]
```

**Purpose:**
- Parses README files to extract command-line flags from specific sections
- Used by test scripts to ensure documentation matches implementation
- Default section: "init"

**Dependencies:** Python 3.6+ standard library only

## Dependencies

All helper scripts use only Python standard library modules to minimize external dependencies:

- `re`: Regular expressions for text parsing
- `sys`: System interface and command-line argument handling
- `os`: Operating system interface (path operations)

## Requirements

- Python 3.6 or higher
- No external packages required (all scripts use standard library only)

## Integration with Shell Scripts

These Python helpers are called from the shell test scripts:

- `tests/test_helper.sh` uses `extract_function_options.py`
- `tests/test_documentation.sh` uses `extract_readme_flags.py`

The shell scripts automatically locate these Python helpers using relative paths from the script directory.

## Note on YAML Validation

YAML validation was previously handled by `validate_yaml.py` (removed). It is now performed by the `yamllint` tool in `tests/test_template_validation.sh`, which provides more comprehensive validation including syntax and style checking.