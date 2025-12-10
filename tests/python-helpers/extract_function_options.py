#!/usr/bin/env python3
"""
Extract function options from shell script functions.
This script parses a shell script file and extracts command-line options
from a specific function, typically used for testing help documentation.
"""

import re
import sys


def extract_function_options(file_path, function_name):
    """
    Extract command-line options from a shell function.
    
    Args:
        file_path: Path to the shell script file
        function_name: Name of the function to parse
        
    Returns:
        List of option strings (e.g., ['--help', '--version'])
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = f.read()
    except FileNotFoundError:
        sys.stderr.write(f"File not found: {file_path}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error reading file {file_path}: {e}\n")
        sys.exit(1)

    # Find the function definition
    func_pattern = re.compile(rf'{re.escape(function_name)}\s*\(\)\s*{{', re.MULTILINE)
    match = func_pattern.search(data)
    if not match:
        sys.stderr.write(f"Function {function_name} not found in {file_path}\n")
        sys.exit(1)

    # Extract function body by matching braces
    idx = match.end()
    brace_depth = 1
    while idx < len(data) and brace_depth > 0:
        char = data[idx]
        if char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
        idx += 1

    body = data[match.end():idx - 1]
    options = set()

    # Try to find case statements first (most common pattern for option parsing)
    case_found = False
    for case_match in re.finditer(r'case\s+"?\$1"?\s+in(.*?)esac', body, re.DOTALL):
        case_found = True
        for opt in re.findall(r'--[a-z0-9][a-z0-9-]*', case_match.group(1)):
            options.add(opt)

    # If no case statements found, look for any --option pattern
    if not case_found:
        for opt in re.findall(r'--[a-z0-9][a-z0-9-]*', body):
            options.add(opt)

    return sorted(options)


def main():
    """Main entry point."""
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: extract_function_options.py <shell_script> <function_name>\n")
        sys.exit(1)
    
    file_path = sys.argv[1]
    function_name = sys.argv[2]
    
    options = extract_function_options(file_path, function_name)
    
    for opt in options:
        print(opt)


if __name__ == "__main__":
    main()
