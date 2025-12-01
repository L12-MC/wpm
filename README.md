# WPM - Well.. Simple Package Manager

Zip-based package manager and runner for Well.. Simple (WSlang) packages.

## Overview

WPM allows you to install, update, and remove packages described by a remote `mapping.json`. Packages are distributed as `.zip` files with a standard layout and can expose runnable modules via `assignment.json`.

## Features

- 🔗 **Registry-driven installs** via `mapping.json`
- 📦 **Install packages** from remote `.zip` URLs
- 📋 **List installed packages** with detailed information
- 🗑️ **Remove packages** cleanly
- 🔄 **Update packages** to their latest versions
- 🧾 **Project manifest** support via `wpackage.json` (`wpm get`)
- ▶️ **Run modules** (`wpm run <module_name>`) via `assignment.json`
- 💾 **Automatic metadata tracking** for all packages
- 🎯 **Simple, intuitive commands**

## Requirements

- **Dart SDK** (for building and running)
- **Internet connection** (for installing packages)
- WSlang interpreter in PATH (command `ws` or set `WS_INTERPRETER` env var)

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

### Configure Registry

Provide the URL to `mapping.json` using either an env var or a config file:

1) Environment variable (recommended):
```powershell
$env:WPM_MAPPING_URL = "https://example.com/path/to/mapping.json"
```

2) Local file `wpm_config.json` in the working directory:
```json
{ "mappingUrl": "https://example.com/path/to/mapping.json" }
```

Then pull the latest registry map:
```powershell
build\wpm.exe refresh
```

### Basic Commands

#### Install a Package
Install by name as defined in `mapping.json`:
```powershell
wpm install <package_name>
```

#### List Installed Packages
Display all installed packages with details:
```bash
wpm list
# or
wpm ls
```

#### Uninstall a Package
Uninstall a package:
```powershell
wpm uninstall <package_name>
```

**Example:**
```bash
wpm remove mathlib
```

#### Update a Package
Update a package to its latest version:
```powershell
wpm update <package_name>
```

**Example:**
```bash
wpm update mathlib
```

#### Sync From Project Manifest
Install/update packages listed in `wpackage.json` (in current directory):
```powershell
wpm get
```

`wpackage.json` structure:
```json
{
	"packages": ["package_name", "package_name2"]
}
```

#### Run a Module
Run a module exposed by any installed package via `assignment.json`:
```powershell
wpm run <module_name>
```
This locates the module in installed packages, preferring a `__main__.wsx` next to the mapped entry, otherwise it runs the mapped `.wsx` file.

#### Help & Version
```bash
wpm help        # Show help message
wpm version     # Show version information
```

## Package Structure

### Storage Location
- **Packages directory:** `ws_packages/`
- **Metadata file:** `ws_packages.json`
- **Cached registry:** `ws_packages/mapping.json`

All packages are cloned into the `ws_packages/` directory, with each package in its own subdirectory.

### Package Format

Each `.zip` should contain:
```
package_name/
	package.json
	assignment.json
	src/
		*.wsx
```

`package.json` example:
```json
{
	"name": "package_name",
	"version": "1.0.0",
	"url": "http://example.com/package_name.zip",
	"description": "A brief description of the package.",
	"author": "Author Name",
	"license": "MIT",
	"assignments": ["assignment.json"]
}
```

`assignment.json` example:
```json
{
	"modules": {
		"module_name": "test1.wsx",
		"module_name2": "test2.wsx"
	}
}
```

### Metadata Tracked
For each installed package, WPM tracks:
- Name, path, URL
- Version, description, author, license (from `package.json`/registry)
- Install timestamp

## How It Works

1. **Refresh:** Download `mapping.json` from the configured URL
2. **Install:** Download `.zip` and extract into `ws_packages/<package_name>`
3. **Track:** Read `package.json` and store metadata in `ws_packages.json`
4. **Update:** Compare remote vs local version; reinstall if newer
5. **Remove:** Delete the package directory and metadata entry

## Examples

### Complete Workflow
```powershell
# Configure registry (one-time)
$env:WPM_MAPPING_URL = "https://example.com/registry/mapping.json"
wpm refresh

# Install packages
wpm install mathlib
wpm install graphics

# List packages
wpm list

# Update a package
wpm update mathlib

# Run a module
wpm run drawHouse

# Remove when done
wpm uninstall graphics
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
| Command | Aliases | Arguments | Description |
|---------|---------|-----------|-------------|
| `refresh` | - | - | Download latest `mapping.json` |
| `install` | - | `<package>` | Install package by name |
| `update` | `upgrade` | `<package>` | Update a package |
| `uninstall` | `remove`, `rm` | `<package>` | Remove a package |
| `list` | `ls` | - | List installed packages |
| `get` | - | - | Sync from `wpackage.json` |
| `run` | - | `<module_name>` | Run a module |
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
The build scripts restore dependencies and compile a native executable:
```
# Windows
build.bat

# Linux/macOS
./build.sh
```

### Version
Current version: **2.0.0**

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

### Registry URL Missing
Set `WPM_MAPPING_URL` or create `wpm_config.json` with `mappingUrl`.

### Package Directory Issues
If packages aren't appearing:
- Check that `ws_packages/` directory exists
- Verify `ws_packages.json` is not corrupted

### WSlang Interpreter Missing
Set `WS_INTERPRETER` to your interpreter path, or ensure `ws` is available in PATH.

## License

This package manager is part of the Well.. Simple programming language project.

## Contributing

Contributions are welcome! Please ensure:
- Code follows Dart best practices
- Error handling is comprehensive
- User feedback is clear and helpful

## Support

For issues, questions, or contributions, please refer to the Well.. Simple project documentation.