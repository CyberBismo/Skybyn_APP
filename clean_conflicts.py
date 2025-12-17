#!/usr/bin/env python3
"""
Clean Git conflict markers from Dart files
This script removes conflict markers left from incomplete merges/reverts
"""

import os
import re
import sys


def clean_conflict_markers(content):
    """
    Remove Git conflict markers from content
    Keeps the HEAD version (newer code)
    """
    # Pattern to match conflict markers
    # <<<<<<< HEAD
    # ... code ...
    # =======
    # ... old code ...
    # >>>>>>> parent of ...

    lines = content.split("\n")
    cleaned_lines = []
    in_conflict = False
    keep_section = True
    conflict_depth = 0

    i = 0
    while i < len(lines):
        line = lines[i]

        # Start of conflict marker
        if line.startswith("<<<<<<< HEAD"):
            in_conflict = True
            keep_section = True
            conflict_depth += 1
            i += 1
            continue

        # Middle of conflict marker
        elif line.startswith("======="):
            if in_conflict:
                keep_section = False
            i += 1
            continue

        # End of conflict marker
        elif line.startswith(">>>>>>> "):
            if conflict_depth > 0:
                conflict_depth -= 1
                if conflict_depth == 0:
                    in_conflict = False
                    keep_section = True
            i += 1
            continue

        # Regular line
        else:
            if not in_conflict or (in_conflict and keep_section):
                cleaned_lines.append(line)
            i += 1

    return "\n".join(cleaned_lines)


def process_file(filepath):
    """Process a single file to remove conflict markers"""
    try:
        print(f"Processing: {filepath}")

        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        # Check if file has conflict markers
        if (
            "<<<<<<< HEAD" not in content
            and "=======" not in content
            and ">>>>>>> " not in content
        ):
            print(f"  ✓ No conflict markers found")
            return True

        # Clean the content
        cleaned_content = clean_conflict_markers(content)

        # Count removed markers
        original_lines = content.count("\n")
        cleaned_lines = cleaned_content.count("\n")
        removed_lines = original_lines - cleaned_lines

        # Write back
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(cleaned_content)

        print(f"  ✓ Cleaned! Removed {removed_lines} lines of conflict markers")
        return True

    except Exception as e:
        print(f"  ✗ Error: {e}")
        return False


def find_dart_files(directory):
    """Find all Dart files in directory"""
    dart_files = []
    for root, dirs, files in os.walk(directory):
        # Skip build and cache directories
        if (
            "build" in root
            or ".dart_tool" in root
            or "android" in root
            or "ios" in root
        ):
            continue

        for file in files:
            if file.endswith(".dart"):
                dart_files.append(os.path.join(root, file))

    return dart_files


def main():
    """Main function"""
    print("Git Conflict Marker Cleaner")
    print("=" * 50)

    # Get current directory
    current_dir = os.path.dirname(os.path.abspath(__file__))
    lib_dir = os.path.join(current_dir, "lib")

    if not os.path.exists(lib_dir):
        print(f"Error: lib directory not found at {lib_dir}")
        sys.exit(1)

    # Find all Dart files
    dart_files = find_dart_files(lib_dir)
    print(f"\nFound {len(dart_files)} Dart files")
    print()

    # Process each file
    success_count = 0
    error_count = 0

    for filepath in dart_files:
        if process_file(filepath):
            success_count += 1
        else:
            error_count += 1

    # Summary
    print()
    print("=" * 50)
    print(f"Summary:")
    print(f"  ✓ Successfully processed: {success_count}")
    print(f"  ✗ Errors: {error_count}")
    print()

    if error_count == 0:
        print("✓ All files cleaned successfully!")
        sys.exit(0)
    else:
        print("✗ Some files had errors")
        sys.exit(1)


if __name__ == "__main__":
    main()
