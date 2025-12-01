import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const String VERSION = "2.0.0";

// Well.. Simple Package Manager (wpm)
// Zip-based package manager with mapping.json registry and wsx runner

class Paths {
  static const String packagesDir = 'ws_packages';
  static const String metaFile = 'ws_packages.json';
  static const String cachedMappingFile = 'mapping.json';
}

class Config {
  final String mappingUrl;

  Config(this.mappingUrl);

  static Config load({String? overrideUrl}) {
    // Priority: explicit override > env var > config file > error
    final envUrl = Platform.environment['WPM_MAPPING_URL'];
    final configFile = File('wpm_config.json');
    String? fileUrl;
    if (configFile.existsSync()) {
      try {
        final data = jsonDecode(configFile.readAsStringSync());
        fileUrl = data['mappingUrl']?.toString();
      } catch (_) {}
    }
    final url = overrideUrl ?? envUrl ?? fileUrl;
    if (url == null || url.isEmpty) {
      throw Exception(
          'No mapping URL configured. Set env WPM_MAPPING_URL or create wpm_config.json {"mappingUrl": "https://.../mapping.json"}');
    }
    return Config(url);
  }
}

class Registry {
  final Map<String, dynamic> data;

  Registry(this.data);

  static Future<Registry> refresh(Config cfg) async {
    final dir = Directory(Paths.packagesDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(Paths.packagesDir, Paths.cachedMappingFile));
    stdout.writeln('Fetching mapping.json...');
    final client = HttpClient();
    try {
      final uri = Uri.parse(cfg.mappingUrl);
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception(
            'Failed to download mapping.json (HTTP ${resp.statusCode})');
      }
      final bytes = await _readAllBytes(resp);
      file.writeAsBytesSync(bytes);
      stdout.writeln('mapping.json updated.');
      return Registry(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  static Registry loadCached() {
    final file = File(p.join(Paths.packagesDir, Paths.cachedMappingFile));
    if (!file.existsSync()) {
      throw Exception('No cached mapping.json. Run "wpm refresh" first.');
    }
    return Registry(jsonDecode(file.readAsStringSync()));
  }

  Map<String, dynamic>? getPackage(String name) {
    // Expected format: { "packages": { name: { url, version, ... } } }
    if (data.containsKey('packages') && data['packages'] is Map) {
      final pkg = (data['packages'] as Map)[name];
      if (pkg is Map<String, dynamic>) return pkg;
    }
    // Also support flat structure: { name: { url, version } }
    if (data[name] is Map<String, dynamic>) {
      return data[name] as Map<String, dynamic>;
    }
    return null;
  }

  static Future<List<int>> _readAllBytes(HttpClientResponse resp) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class MetaStore {
  static Map<String, dynamic> load() {
    try {
      final f = File(Paths.metaFile);
      if (f.existsSync()) return jsonDecode(f.readAsStringSync());
    } catch (_) {}
    return {};
  }

  static void save(Map<String, dynamic> meta) {
    File(Paths.metaFile)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(meta));
  }
}

class ZipInstaller {
  static Future<void> downloadTo(String url, File outFile) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('Download failed (HTTP ${resp.statusCode})');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      outFile.writeAsBytesSync(bytes);
    } finally {
      client.close(force: true);
    }
  }

  static void extractZip(File zipFile, String destDir) {
    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    extractArchiveToDisk(archive, destDir);
  }
}

class Packages {
  static Future<bool> installByName(String pkgName,
      {Registry? registry}) async {
    final reg = registry ?? Registry.loadCached();
    final info = reg.getPackage(pkgName);
    if (info == null) {
      stderr.writeln('Package not found in mapping.json: $pkgName');
      return false;
    }
    final url = info['url']?.toString();
    if (url == null || url.isEmpty) {
      stderr.writeln('Package "$pkgName" has no url in mapping.json');
      return false;
    }

    final baseDir = Directory(Paths.packagesDir);
    if (!baseDir.existsSync()) baseDir.createSync(recursive: true);
    final dest = p.join(Paths.packagesDir, pkgName);
    final destDir = Directory(dest);
    if (destDir.existsSync()) {
      stdout.writeln('Removing existing "$pkgName"...');
      destDir.deleteSync(recursive: true);
    }
    destDir.createSync(recursive: true);

    stdout.writeln('Downloading $pkgName from $url');
    final tmpZip = File(p.join(dest, 'package.zip'));
    await ZipInstaller.downloadTo(url, tmpZip);

    stdout.writeln('Extracting...');
    ZipInstaller.extractZip(tmpZip, dest);
    if (tmpZip.existsSync()) tmpZip.deleteSync();

    // Normalize: if archive contains a top-level folder (package_name/...), move contents
    _flattenIfSingleTopLevelFolder(destDir);

    // Read package.json for metadata
    final pkgJsonFile = File(p.join(dest, 'package.json'));
    Map<String, dynamic> pkgJson = {};
    if (pkgJsonFile.existsSync()) {
      try {
        pkgJson = jsonDecode(pkgJsonFile.readAsStringSync());
      } catch (_) {}
    }

    // Persist metadata
    final meta = MetaStore.load();
    meta[pkgName] = {
      'name': pkgName,
      'path': dest,
      'url': url,
      'version': (pkgJson['version'] ?? info['version'] ?? '').toString(),
      'description':
          (pkgJson['description'] ?? info['description'] ?? '').toString(),
      'author': (pkgJson['author'] ?? info['author'] ?? '').toString(),
      'license': (pkgJson['license'] ?? info['license'] ?? '').toString(),
      'installed': DateTime.now().toIso8601String(),
      'assignments': pkgJson['assignments'] ?? []
    };
    MetaStore.save(meta);

    stdout.writeln('Installed "$pkgName" at $dest');
    return true;
  }

  static Future<void> updateByName(String pkgName) async {
    final reg = Registry.loadCached();
    final info = reg.getPackage(pkgName);
    if (info == null) {
      stderr.writeln('Package not found in mapping.json: $pkgName');
      return;
    }
    final meta = MetaStore.load();
    final local = meta[pkgName];
    String? localVersion;
    if (local is Map) localVersion = local['version']?.toString();
    final remoteVersion = info['version']?.toString();
    if (localVersion != null &&
        remoteVersion != null &&
        localVersion == remoteVersion) {
      stdout.writeln('"$pkgName" is up to date ($localVersion).');
      return;
    }
    stdout.writeln(
        'Updating "$pkgName" (${localVersion ?? 'unknown'} -> ${remoteVersion ?? 'unknown'})');
    await installByName(pkgName, registry: reg);
  }

  static void listInstalled() {
    final meta = MetaStore.load();
    if (meta.isEmpty) {
      stdout.writeln('No packages installed.');
      stdout.writeln('Use: wpm install <package_name>');
      return;
    }
    stdout.writeln('Installed packages:');
    stdout.writeln(''.padRight(60, '═'));
    meta.forEach((name, value) {
      if (value is Map) {
        final path = value['path'] ?? '';
        final version = value['version'] ?? '';
        final desc = value['description'] ?? '';
        stdout.writeln('\n$name');
        stdout.writeln('  Version: $version');
        stdout.writeln('  Path:    $path');
        if (desc.toString().isNotEmpty) stdout.writeln('  Desc:    $desc');
      }
    });
    stdout.writeln('\n'.padRight(60, '═'));
    stdout.writeln('Total: ${meta.length}');
  }

  static bool uninstall(String pkgName) {
    final meta = MetaStore.load();
    if (!meta.containsKey(pkgName)) {
      stderr.writeln('Package not installed: $pkgName');
      return false;
    }
    final path = (meta[pkgName]['path'] ?? '').toString();
    if (path.isNotEmpty) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
        stdout.writeln('Deleted $path');
      }
    }
    meta.remove(pkgName);
    MetaStore.save(meta);
    stdout.writeln('Uninstalled "$pkgName"');
    return true;
  }

  static Future<void> getFromManifest() async {
    final file = File('wpackage.json');
    if (!file.existsSync()) {
      stderr.writeln('wpackage.json not found in current directory.');
      exit(1);
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(file.readAsStringSync());
    } catch (e) {
      stderr.writeln('Invalid wpackage.json: $e');
      exit(1);
    }
    final pkgs =
        (data['packages'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (pkgs.isEmpty) {
      stdout.writeln('No packages listed in wpackage.json.');
      return;
    }
    // Ensure mapping is available
    try {
      Registry.loadCached();
    } catch (_) {
      final cfg = Config.load();
      await Registry.refresh(cfg);
    }
    for (final name in pkgs) {
      final meta = MetaStore.load();
      if (meta.containsKey(name)) {
        await updateByName(name);
      } else {
        await installByName(name);
      }
    }
  }

  static void runModule(String moduleName) async {
    final meta = MetaStore.load();
    if (meta.isEmpty) {
      stderr.writeln('No packages installed.');
      exit(1);
    }

    // Search all packages for a module mapping
    for (final entry in meta.entries) {
      final pkgName = entry.key;
      final pkgPath = (entry.value['path'] ?? '').toString();
      final assignFiles = _collectAssignmentFiles(pkgPath, entry.value);
      for (final assign in assignFiles) {
        final file = File(assign);
        if (!file.existsSync()) continue;
        try {
          final data = jsonDecode(file.readAsStringSync());
          final modules = data['modules'] as Map?;
          if (modules != null && modules.containsKey(moduleName)) {
            final rel = modules[moduleName].toString();
            final srcPath = p.join(pkgPath, 'src', rel);
            final resolved = _resolveModuleEntry(srcPath);
            if (resolved != null) {
              await _execWsx(resolved);
              return;
            } else {
              stderr.writeln(
                  'Module "$moduleName" found in "$pkgName" but entry not runnable.');
              exit(1);
            }
          }
        } catch (_) {
          // ignore malformed assignment.json
        }
      }
    }

    stderr.writeln('Module not found: $moduleName');
    exit(1);
  }

  static List<String> _collectAssignmentFiles(String pkgPath, Map value) {
    final files = <String>[];
    // from package.json assignments list
    final pkgJson = File(p.join(pkgPath, 'package.json'));
    if (pkgJson.existsSync()) {
      try {
        final j = jsonDecode(pkgJson.readAsStringSync());
        if (j['assignments'] is List) {
          for (final a in (j['assignments'] as List)) {
            files.add(p.join(pkgPath, a.toString()));
          }
        }
      } catch (_) {}
    }
    // include default assignment.json at root if present
    final defaultAssign = File(p.join(pkgPath, 'assignment.json'));
    if (defaultAssign.existsSync()) files.add(defaultAssign.path);
    return files;
  }

  static String? _resolveModuleEntry(String srcPath) {
    final fi = File(srcPath);
    final di = Directory(srcPath);
    if (fi.existsSync()) {
      // If sibling __main__.wsx exists in same dir as file, prefer that
      final mainCandidate = File(p.join(p.dirname(fi.path), '__main__.wsx'));
      if (mainCandidate.existsSync()) return mainCandidate.path;
      return fi.path;
    }
    if (di.existsSync()) {
      final mainFile = File(p.join(di.path, '__main__.wsx'));
      if (mainFile.existsSync()) return mainFile.path;
    }
    return null;
  }

  static Future<void> _execWsx(String filePath) async {
    final interpreter = _detectInterpreter();
    if (interpreter == null) {
      stderr.writeln(
          'No WSlang interpreter found. Set env WS_INTERPRETER to the executable, or add "ws" to PATH.');
      exit(1);
    }
    stdout.writeln('Running: $filePath');
    final proc = await Process.start(interpreter, [filePath],
        mode: ProcessStartMode.inheritStdio);
    final exitCode = await proc.exitCode;
    exit(exitCode);
  }

  static String? _detectInterpreter() {
    final env = Platform.environment['WS_INTERPRETER'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;
    // Try common names
    const candidates = ['ws', 'wslang', 'ws.exe', 'wslang.exe'];
    for (final c in candidates) {
      try {
        final result = Process.runSync(c, ['--version']);
        if (result.exitCode == 0 ||
            result.stdout.toString().isNotEmpty ||
            result.stderr.toString().isNotEmpty) {
          return c;
        }
      } catch (_) {}
    }
    return null;
  }

  static void _flattenIfSingleTopLevelFolder(Directory destDir) {
    final entries = destDir.listSync();
    if (entries.length == 1 && entries.first is Directory) {
      final inner = entries.first as Directory;
      // Move contents up one level
      for (final entity in inner.listSync(recursive: false)) {
        final newPath = p.join(destDir.path, p.basename(entity.path));
        entity.renameSync(newPath);
      }
      inner.deleteSync(recursive: true);
    }
  }
}

void printHelp() {
  print('''
╔═══════════════════════════════════════════════════════════╗
║  wpm - Well.. Simple Package Manager v$VERSION                 ║
╚═══════════════════════════════════════════════════════════╝

USAGE:
  wpm <command> [arguments]

COMMANDS:
  refresh                       Download latest mapping.json from registry
  install <package>             Install package by name (from mapping.json)
  update <package>              Update installed package if newer available
  uninstall <package>           Remove an installed package
  list                          List installed packages
  get                           Install/Update packages from wpackage.json
  run <module_name>             Run a module from installed packages
  help                          Show this help message
  version                       Show version information

NOTES:
  - Configure mapping URL via env WPM_MAPPING_URL or wpm_config.json
  - Packages are zip files extracted under ws_packages/<name>
  - assignment.json maps module names to entries under src/
  - run searches for __main__.wsx near the mapped module or runs the mapped .wsx
''');
}

void printVersion() {
  print('wpm (Well.. Simple Package Manager) v$VERSION');
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    printHelp();
    exit(0);
  }
  final cmd = args.first.toLowerCase();
  try {
    switch (cmd) {
      case 'refresh':
        final cfg = Config.load();
        await Registry.refresh(cfg);
        break;
      case 'install':
        if (args.length < 2) {
          stderr.writeln('Usage: wpm install <package_name>');
          exit(1);
        }
        Registry reg;
        try {
          reg = Registry.loadCached();
        } catch (_) {
          final cfg = Config.load();
          reg = await Registry.refresh(cfg);
        }
        final ok = await Packages.installByName(args[1], registry: reg);
        exit(ok ? 0 : 1);
      case 'update':
        if (args.length < 2) {
          stderr.writeln('Usage: wpm update <package_name>');
          exit(1);
        }
        await Packages.updateByName(args[1]);
        break;
      case 'uninstall':
      case 'remove':
      case 'rm':
        if (args.length < 2) {
          stderr.writeln('Usage: wpm uninstall <package_name>');
          exit(1);
        }
        final ok = Packages.uninstall(args[1]);
        exit(ok ? 0 : 1);
      case 'list':
      case 'ls':
        Packages.listInstalled();
        break;
      case 'get':
        await Packages.getFromManifest();
        break;
      case 'run':
        if (args.length < 2) {
          stderr.writeln('Usage: wpm run <module_name>');
          exit(1);
        }
        Packages.runModule(args[1]);
        break;
      case 'help':
      case '-h':
      case '--help':
        printHelp();
        break;
      case 'version':
      case '-v':
      case '--version':
        printVersion();
        break;
      default:
        stderr.writeln('Unknown command: $cmd');
        printHelp();
        exit(1);
    }
  } on Exception catch (e) {
    stderr.writeln('Error: ${e.toString()}');
    exit(1);
  }
}
