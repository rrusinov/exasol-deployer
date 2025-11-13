#!/usr/bin/env python3
"""
Extract command-line flags from README documentation.
This script parses a README file and extracts command-line flags
from a specific section, used for testing documentation completeness.
"""

import re
import sys


def extract_readme_flags(readme_path, section_name="init"):
    """
    Extract command-line flags from README section.
    
    Args:
        readme_path: Path to the README file
        section_name: Name of the section to parse (default: "init")
        
    Returns:
        List of flag strings (e.g., ['--help', '--version'])
    """
    try:
        with open(readme_path, "r", encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        sys.stderr.write(f"File not found: {readme_path}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error reading file {readme_path}: {e}\n")
        sys.exit(1)

    # Find the section (e.g., ### `init` ... ### `deploy`)
    section_pattern = rf'### `{re.escape(section_name)}`(.*?)(?=### `|$)'
    section_match = re.search(section_pattern, text, re.DOTALL)
    if not section_match:
        sys.stderr.write(f"Could not locate {section_name} section in README\n")
        sys.exit(1)

    section = section_match.group(1)
    
    # Find the flags block
    flags_anchor = section.find("**Flags:**")
    if flags_anchor == -1:
        sys.stderr.write(f"Could not locate **Flags:** block in README {section_name} section\n")
        sys.exit(1)

    # Look for the end of the flags block (next section or end of section)
    config_anchor = section.find("**Configuration")
    if config_anchor == -1:
        config_anchor = section.find("**Examples")
    if config_anchor == -1:
        config_anchor = len(section)

    flags_block = section[flags_anchor:config_anchor]
    flags = set()
    
    # Extract flags from code snippets
    for snippet in re.findall(r'`([^`]+)`', flags_block):
        for flag in re.findall(r'--[a-z0-9-]+', snippet, re.IGNORECASE):
            flags.add(flag.lower())
    
    flags = sorted(flags)
    if not flags:
        sys.stderr.write(f"No flags extracted from README {section_name} section\n")
        sys.exit(1)

    return flags


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: extract_readme_flags.py <readme_file> [section_name]\n")
        sys.exit(1)
    
    readme_path = sys.argv[1]
    section_name = sys.argv[2] if len(sys.argv) > 2 else "init"
    
    flags = extract_readme_flags(readme_path, section_name)
    
    for flag in flags:
        print(flag)


if __name__ == "__main__":
    main()