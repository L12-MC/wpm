import 'dart:io';
import 'dart:convert';

const String VERSION = "1.1";

// Well.. Simple Package Manager (wpm)
// Standalone package manager for Well.. Simple

class PackageManager {
  static const String packagesDir = 'ws_packages';
  static const String packagesFile = 'ws_packages.json';
  
  static Map<String, dynamic> loadInstalledPackages() {
    try {
      final file = File(packagesFile);
      if (file.existsSync()) {
        String content = file.readAsStringSync();
        return jsonDecode(content);
      }
    } catch (e) {
      // Return empty map if error
    }
    return {};
  }
  
  static void saveInstalledPackages(Map<String, dynamic> packages) {
    try {
      final file = File(packagesFile);
      file.writeAsStringSync(jsonEncode(packages));
    } catch (e) {
      print("Error saving package metadata: $e");
    }
  }
  
  static Future<bool> installPackage(String url, String? name) async {
    try {
      // Extract package name from URL if not provided
      if (name == null || name.isEmpty) {
        name = url.split('/').last.replaceAll('.git', '');
      }
      
      print("Installing package: $name");
      print("From: $url");
      
      // Create packages directory if it doesn't exist
      final dir = Directory(packagesDir);
      if (!dir.existsSync()) {
        dir.createSync();
      }
      
      final packagePath = '$packagesDir/$name';
      final packageDir = Directory(packagePath);
      
      // Remove existing package if it exists
      if (packageDir.existsSync()) {
        print("Removing existing version...");
        packageDir.deleteSync(recursive: true);
      }
      
      // Clone the repository
      print("Cloning repository...");
      var result = await Process.run('git', ['clone', url, packagePath]);
      
      if (result.exitCode != 0) {
        print("Error cloning repository:");
        print(result.stderr);
        return false;
      }
      
      print("Package installed successfully!");
      print("Location: $packagePath");
      
      // Save package info
      var packages = loadInstalledPackages();
      packages[name] = {
        'url': url,
        'path': packagePath,
        'installed': DateTime.now().toIso8601String(),
        'version': '1.0.0' // Could parse from package if available
      };
      saveInstalledPackages(packages);
      
      return true;
    } catch (e) {
      print("Error installing package: $e");
      return false;
    }
  }
  
  static void listPackages() {
    var packages = loadInstalledPackages();
    
    if (packages.isEmpty) {
      print("No packages installed.");
      print("");
      print("To install a package, run:");
      print("  wpm install <git-url> [package-name]");
      return;
    }
    
    print("Installed packages:");
    print("═" * 60);
    packages.forEach((name, info) {
      print("");
      print("Package: $name");
      print("  URL:       ${info['url']}");
      print("  Path:      ${info['path']}");
      print("  Installed: ${info['installed']}");
      if (info.containsKey('version')) {
        print("  Version:   ${info['version']}");
      }
    });
    print("");
    print("═" * 60);
    print("Total packages: ${packages.length}");
  }
  
  static bool removePackage(String name) {
    try {
      var packages = loadInstalledPackages();
      
      if (!packages.containsKey(name)) {
        print("Package not found: $name");
        return false;
      }
      
      final packagePath = packages[name]['path'];
      final packageDir = Directory(packagePath);
      
      if (packageDir.existsSync()) {
        packageDir.deleteSync(recursive: true);
        print("Removed package directory: $packagePath");
      }
      
      packages.remove(name);
      saveInstalledPackages(packages);
      
      print("Package removed: $name");
      return true;
    } catch (e) {
      print("Error removing package: $e");
      return false;
    }
  }
  
  static Future<void> updatePackage(String name) async {
    var packages = loadInstalledPackages();
    
    if (!packages.containsKey(name)) {
      print("Package not found: $name");
      return;
    }
    
    String url = packages[name]['url'];
    String path = packages[name]['path'];
    
    print("Updating package: $name");
    
    // Try to pull latest changes
    var result = await Process.run('git', ['pull'], workingDirectory: path);
    
    if (result.exitCode == 0) {
      print("Package updated successfully!");
      packages[name]['updated'] = DateTime.now().toIso8601String();
      saveInstalledPackages(packages);
    } else {
      print("Error updating package:");
      print(result.stderr);
      print("");
      print("Trying full reinstall...");
      await installPackage(url, name);
    }
  }
  
  static void searchPackages(String query) {
    var packages = loadInstalledPackages();
    
    var matches = packages.entries.where((entry) {
      String name = entry.key.toLowerCase();
      String url = entry.value['url'].toString().toLowerCase();
      return name.contains(query.toLowerCase()) || url.contains(query.toLowerCase());
    }).toList();
    
    if (matches.isEmpty) {
      print("No packages found matching: $query");
      return;
    }
    
    print("Search results for '$query':");
    print("═" * 60);
    for (var entry in matches) {
      print("");
      print("Package: ${entry.key}");
      print("  URL: ${entry.value['url']}");
    }
    print("");
    print("═" * 60);
    print("Found ${matches.length} package(s)");
  }
}

void printHelp() {
  print("""
╔═══════════════════════════════════════════════════════════╗
║  wpm - Well.. Simple Package Manager v$VERSION                 ║
╚═══════════════════════════════════════════════════════════╝

USAGE:
  wpm <command> [arguments]

COMMANDS:
  install <url> [name]  Install a package from Git repository
  list                  List all installed packages
  remove <name>         Remove an installed package
  update <name>         Update a package to latest version
  search <query>        Search installed packages
  help                  Show this help message
  version               Show version information

EXAMPLES:
  # Install a package
  wpm install https://github.com/user/math-lib.git mathlib

  # Install with auto-detected name
  wpm install https://github.com/user/string-utils.git

  # List installed packages
  wpm list

  # Update a package
  wpm update mathlib

  # Remove a package
  wpm remove mathlib

  # Search packages
  wpm search math

PACKAGE STRUCTURE:
  Packages are stored in: ws_packages/
  Metadata file: ws_packages.json

REQUIREMENTS:
  - Git must be installed and available in PATH
  - Internet connection for installing packages

For more information, visit:
  docs/package-manager.md
""");
}

void printVersion() {
  print("wpm (Well.. Simple Package Manager) v$VERSION");
  print("Package manager for Well.. Simple programming language");
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    printHelp();
    exit(0);
  }
  
  String command = args[0].toLowerCase();
  
  switch (command) {
    case 'install':
      if (args.length < 2) {
        print("Error: URL required");
        print("Usage: wpm install <git-url> [package-name]");
        exit(1);
      }
      String url = args[1];
      String? name = args.length > 2 ? args[2] : null;
      bool success = await PackageManager.installPackage(url, name);
      exit(success ? 0 : 1);
      
    case 'list':
    case 'ls':
      PackageManager.listPackages();
      break;
      
    case 'remove':
    case 'rm':
    case 'uninstall':
      if (args.length < 2) {
        print("Error: Package name required");
        print("Usage: wpm remove <package-name>");
        exit(1);
      }
      String name = args[1];
      bool success = PackageManager.removePackage(name);
      exit(success ? 0 : 1);
      
    case 'update':
    case 'upgrade':
      if (args.length < 2) {
        print("Error: Package name required");
        print("Usage: wpm update <package-name>");
        exit(1);
      }
      String name = args[1];
      await PackageManager.updatePackage(name);
      break;
      
    case 'search':
    case 'find':
      if (args.length < 2) {
        print("Error: Search query required");
        print("Usage: wpm search <query>");
        exit(1);
      }
      String query = args[1];
      PackageManager.searchPackages(query);
      break;
      
    case 'help':
    case '--help':
    case '-h':
      printHelp();
      break;
      
    case 'version':
    case '--version':
    case '-v':
      printVersion();
      break;
      
    default:
      print("Unknown command: $command");
      print("");
      printHelp();
      exit(1);
  }
}
