# WPM - Well.. Simple Package Manager

A lightweight, Git-based package manager for the Well.. Simple programming language.

## Overview

WPM (Well.. Simple Package Manager) allows you to install, manage, and update packages from Git repositories. It provides a simple command-line interface for managing dependencies in your Well.. Simple projects.

## Features

- 📦 **Install packages** from any Git repository
- 📋 **List installed packages** with detailed information
- 🗑️ **Remove packages** cleanly
- 🔄 **Update packages** to their latest versions
- 🔍 **Search** through installed packages
- 💾 **Automatic metadata tracking** for all packages
- 🎯 **Simple, intuitive commands**

## Requirements

- **Dart SDK** (for building and running)
- **Git** (must be installed and available in PATH)
- **Internet connection** (for installing packages)

## Installation

### Building from Source

1. Clone this repository
2. Run the build script for your platform:

**Linux/macOS:**
```bash
./build.sh
```

**Windows:**
```cmd
build.bat
```

The executable will be created in the `build/` directory.

3. (Optional) Add the executable to your PATH for system-wide access

## Usage

### Basic Commands

#### Install a Package
Install a package from a Git repository:
```bash
wpm install <git-url> [package-name]
```

**Examples:**
```bash
# Install with custom name
wpm install https://github.com/user/math-lib.git mathlib

# Install with auto-detected name
wpm install https://github.com/user/string-utils.git
```

#### List Installed Packages
Display all installed packages with details:
```bash
wpm list
# or
wpm ls
```

#### Remove a Package
Uninstall a package:
```bash
wpm remove <package-name>
# or
wpm rm <package-name>
wpm uninstall <package-name>
```

**Example:**
```bash
wpm remove mathlib
```

#### Update a Package
Update a package to its latest version:
```bash
wpm update <package-name>
# or
wpm upgrade <package-name>
```

**Example:**
```bash
wpm update mathlib
```

#### Search Packages
Search through installed packages:
```bash
wpm search <query>
# or
wpm find <query>
```

**Example:**
```bash
wpm search math
```

#### Help & Version
```bash
wpm help        # Show help message
wpm version     # Show version information
```

## Package Structure

### Storage Location
- **Packages directory:** `ws_packages/`
- **Metadata file:** `ws_packages.json`

All packages are cloned into the `ws_packages/` directory, with each package in its own subdirectory.

### Metadata
WPM automatically tracks metadata for each installed package:
- Package name
- Git URL
- Installation path
- Installation date
- Version information

## How It Works

1. **Installation:** WPM clones the Git repository into `ws_packages/<package-name>`
2. **Tracking:** Package metadata is stored in `ws_packages.json`
3. **Updates:** WPM pulls the latest changes from the Git repository
4. **Removal:** Package directory and metadata are cleaned up

## Examples

### Complete Workflow
```bash
# Install a math library
wpm install https://github.com/wslang/math-utils.git math

# List all packages
wpm list

# Update the package
wpm update math

# Search for it
wpm search math

# Remove when done
wpm remove math
```

### Installing Multiple Packages
```bash
wpm install https://github.com/wslang/stdlib.git
wpm install https://github.com/wslang/http-client.git
wpm install https://github.com/wslang/json-parser.git
wpm list
```

## Command Reference

| Command | Aliases | Arguments | Description |
|---------|---------|-----------|-------------|
| `install` | - | `<url> [name]` | Install a package from Git |
| `list` | `ls` | - | List all installed packages |
| `remove` | `rm`, `uninstall` | `<name>` | Remove a package |
| `update` | `upgrade` | `<name>` | Update a package |
| `search` | `find` | `<query>` | Search installed packages |
| `help` | `-h`, `--help` | - | Show help message |
| `version` | `-v`, `--version` | - | Show version |

## Development

### Project Structure
```
wpm/
├── wpm.dart          # Main source code
├── build.sh          # Unix build script
├── build.bat         # Windows build script
├── README.md         # This file
├── ws_packages/      # Installed packages (created at runtime)
└── ws_packages.json  # Package metadata (created at runtime)
```

### Building
The build scripts use `dart compile exe` to create a standalone native executable.

### Version
Current version: **1.0.0**

## Error Handling

WPM provides clear error messages with emoji indicators:
- ✅ Success messages
- ❌ Error messages
- 📦 Package operations
- 🔗 URL information
- 🗑️ Removal operations
- ⬇️ Download operations
- 🔄 Update operations
- 🔍 Search results

## Troubleshooting

### Git Not Found
If you see "git command not found":
- Ensure Git is installed: `git --version`
- Add Git to your system PATH

### Clone Failed
If package installation fails:
- Check your internet connection
- Verify the Git URL is correct and accessible
- Ensure you have permissions to access the repository

### Package Directory Issues
If packages aren't appearing:
- Check that `ws_packages/` directory exists
- Verify `ws_packages.json` is not corrupted

## License

This package manager is part of the Well.. Simple programming language project.

## Contributing

Contributions are welcome! Please ensure:
- Code follows Dart best practices
- Error handling is comprehensive
- User feedback is clear and helpful

## Support

For issues, questions, or contributions, please refer to the Well.. Simple project documentation.