import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// VERSION 2.0.1
const String VERSION = "2.0.1";

// ------------------------------------------------------------------
// Constants & Paths
// ------------------------------------------------------------------

class Paths {
  static const String packagesDir = 'ws_packages';
  static const String metaFile = 'ws_packages.json';
  static const String cachedMappingFile = 'mapping.json';
}

// ------------------------------------------------------------------
// Configuration & Registry
// ------------------------------------------------------------------

class Config {
  final String mappingUrl;
  Config(this.mappingUrl);

  static Config load({String? overrideUrl}) {
    const defaultUrl =
        'https://raw.githubusercontent.com/L12-MC/wpmmap/refs/heads/main/mapping.json';
    final envUrl = Platform.environment['WPM_MAPPING_URL'];
    final configFile = File('wpm_config.json');
    String? fileUrl;
    if (configFile.existsSync()) {
      try {
        final data = jsonDecode(configFile.readAsStringSync());
        fileUrl = data['mappingUrl']?.toString();
      } catch (_) {}
    }
    return Config(overrideUrl ?? envUrl ?? fileUrl ?? defaultUrl);
  }
}

class Registry {
  final Map<String, dynamic> data;
  Registry(this.data);

  static Future<Registry> refresh(Config cfg) async {
    final dir = Directory(Paths.packagesDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(Paths.packagesDir, Paths.cachedMappingFile));

    stdout.writeln('Connecting to registry: ${cfg.mappingUrl}');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(cfg.mappingUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Registry server returned HTTP ${response.statusCode}');
      }

      final bytes = await response
          .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
          .then((b) => b.takeBytes());
      
      file.writeAsBytesSync(bytes);
      stdout.writeln('Registry updated successfully.');
      return Registry(jsonDecode(utf8.decode(bytes)));
    } catch (e) {
      throw Exception('Failed to refresh registry: $e');
    } finally {
      client.close();
    }
  }

  static Registry loadCached() {
    final file = File(p.join(Paths.packagesDir, Paths.cachedMappingFile));
    if (!file.existsSync()) {
      throw Exception('No cached registry found. Run "wpm refresh" first.');
    }
    try {
      return Registry(jsonDecode(file.readAsStringSync()));
    } catch (e) {
      throw Exception('Registry cache is corrupted. Run "wpm refresh".');
    }
  }

  Map<String, dynamic>? getPackage(String name) {
    if (data['packages'] != null && data['packages'] is Map) {
      final pkg = data['packages'][name];
      if (pkg is Map<String, dynamic>) return pkg;
    }
    if (data[name] is Map<String, dynamic>) return data[name];
    return null;
  }
}

// ------------------------------------------------------------------
// Utilities: UI & Progress
// ------------------------------------------------------------------

class ConsoleUI {
  static void progressBar(int received, int total, {int width = 30}) {
    if (total <= 0) {
      stdout.write('\rDownloading: ${_formatBytes(received)}...');
      return;
    }
    final progress = received / total;
    final filledCount = (progress * width).clamp(0, width).toInt();
    final percent = (progress * 100).toStringAsFixed(1);

    final bar = '█' * filledCount + '░' * (width - filledCount);
    stdout.write('\r[$bar] $percent% (${_formatBytes(received)} / ${_formatBytes(total)})');
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static void clearLine() {
    try {
      // Check if there is actually a terminal attached
      if (stdout.hasTerminal) {
        final width = stdout.terminalColumns;
        stdout.write('\r${' ' * width}\r');
      } else {
        stdout.write('\n'); // Fallback: just move to a new line
      }
    } catch (_) {
      // Final fallback for environments where terminalColumns throws
      stdout.write('\r\r'); 
    }
  }
}
// ------------------------------------------------------------------
// Metadata & File Handling
// ------------------------------------------------------------------

class MetaStore {
  static Map<String, dynamic> load() {
    final f = File(Paths.metaFile);
    if (!f.existsSync()) return {};
    try {
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      return {};
    }
  }

  static void save(Map<String, dynamic> meta) {
    File(Paths.metaFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(meta),
    );
  }
}

class ZipInstaller {
  static void extract(File zipFile, String dest) {
    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final totalFiles = archive.length;
    int current = 0;

    for (final file in archive) {
      current++;
      final path = p.normalize(p.join(dest, file.name));
      
      // Security: Prevent Zip-Slip attacks
      if (!p.isWithin(dest, path)) continue;

      if (file.isFile) {
        final data = file.content as List<int>;
        final f = File(path);
        f.createSync(recursive: true);
        f.writeAsBytesSync(data, flush: true);
      } else {
        Directory(path).createSync(recursive: true);
      }
      
      if (current % 10 == 0 || current == totalFiles) {
        // Use \r to stay on the same line without overflowing
        stdout.write('\rExtracting: $current / $totalFiles files...'.padRight(40));
      }
    }
    stdout.writeln('\nExtraction complete.');
  }
}

// ------------------------------------------------------------------
// Core Package Logic
// ------------------------------------------------------------------

class Packages {
  static Future<bool> installByName(String pkgName, {Registry? registry}) async {
    final reg = registry ?? Registry.loadCached();
    final info = reg.getPackage(pkgName);
    if (info == null) {
      stderr.writeln('Error: Package "$pkgName" not found.');
      return false;
    }

    final url = info['url']?.toString();
    if (url == null || url.isEmpty) {
      stderr.writeln('Error: Invalid URL for "$pkgName".');
      return false;
    }

    final pkgPath = p.absolute(p.join(Paths.packagesDir, pkgName));
    final dir = Directory(pkgPath);

    if (dir.existsSync()) {
      stdout.writeln('Cleaning old installation...');
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        stderr.writeln('Warning: Could not fully delete old folder. Trying to overwrite.');
      }
    }
    dir.createSync(recursive: true);

    final zipFile = File(p.join(pkgPath, 'source.zip'));
    final client = HttpClient();
    
    try {
      stdout.writeln('Installing "$pkgName" from $url');
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      int received = 0;
      final IOSink sink = zipFile.openWrite();

      await for (final List<int> chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        ConsoleUI.progressBar(received, contentLength);
      }

      await sink.close();
      ConsoleUI.clearLine(); // This will now use the safe check
      stdout.writeln('Download complete.');

      ZipInstaller.extract(zipFile, pkgPath);
      zipFile.deleteSync();

      _normalizeFolder(pkgPath);

      final pkgJson = _readPackageJson(pkgPath);
      final meta = MetaStore.load();
      meta[pkgName] = {
        'name': pkgName,
        'path': p.relative(pkgPath),
        'url': url,
        'version': (pkgJson['version'] ?? info['version'] ?? '0.0.0').toString(),
        'description': (pkgJson['description'] ?? info['description'] ?? '').toString(),
        'installed_at': DateTime.now().toIso8601String(),
        'assignments': pkgJson['assignments'] ?? []
      };
      MetaStore.save(meta);

      stdout.writeln('Package "$pkgName" successfully installed.');
      return true;
    } catch (e) {
      stderr.writeln('\nInstallation failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _readPackageJson(String pkgPath) {
    final file = File(p.join(pkgPath, 'package.json'));
    if (!file.existsSync()) return {};
    try {
      return jsonDecode(file.readAsStringSync());
    } catch (_) {
      return {};
    }
  }

  static void _normalizeFolder(String root) {
    final dir = Directory(root);
    final items = dir.listSync();
    
    if (items.length == 1 && items.first is Directory) {
      final innerDir = items.first as Directory;
      for (final item in innerDir.listSync()) {
        final newName = p.join(root, p.basename(item.path));
        item.renameSync(newName);
      }
      innerDir.deleteSync();
    }
  }

  static void list() {
    final meta = MetaStore.load();
    if (meta.isEmpty) {
      print('No packages installed.');
      return;
    }
    print('\nINSTALLED PACKAGES:');
    print('=' * 60);
    meta.forEach((name, data) {
      final v = data['version'] ?? '?.?.?';
      print('${name.padRight(20)} | v${v.toString().padRight(10)} | ${data['path']}');
    });
    print('=' * 60);
  }

  static void uninstall(String name) {
    final meta = MetaStore.load();
    if (!meta.containsKey(name)) {
      print('Package "$name" is not installed.');
      return;
    }

    final path = meta[name]['path'];
    final dir = Directory(path);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    
    meta.remove(name);
    MetaStore.save(meta);
    print('Successfully uninstalled "$name".');
  }

  static Future<void> getFromManifest() async {
    final file = File('wpackage.json');
    if (!file.existsSync()) {
      print('Error: No wpackage.json found.');
      return;
    }
    try {
      final data = jsonDecode(file.readAsStringSync());
      final List pkgs = data['packages'] ?? [];
      if (pkgs.isEmpty) return;

      Registry reg;
      try { reg = Registry.loadCached(); } catch (_) { reg = await Registry.refresh(Config.load()); }

      for (String name in pkgs) {
        await installByName(name, registry: reg);
      }
    } catch (e) {
      print('Error processing wpackage.json: $e');
    }
  }

  static Future<void> runModule(String moduleName) async {
    final meta = MetaStore.load();
    final interpreter = _detectInterpreter();

    if (interpreter == null) {
      stderr.writeln('Error: WS interpreter not found.');
      exit(1);
    }

    for (final entry in meta.entries) {
      final pkgPath = entry.value['path'].toString();
      final assignments = _getAssignmentFiles(pkgPath, entry.value);

      for (final assignmentPath in assignments) {
        final f = File(assignmentPath);
        if (!f.existsSync()) continue;

        try {
          final data = jsonDecode(f.readAsStringSync());
          final modules = data['modules'] as Map?;
          if (modules != null && modules.containsKey(moduleName)) {
            final relPath = modules[moduleName].toString();
            final fullPath = p.join(pkgPath, 'src', relPath);
            final execPath = _resolveEntryFile(fullPath);

            if (execPath != null) {
              print(execPath);
              final proc = await Process.start(interpreter, [execPath],
                  mode: ProcessStartMode.inheritStdio);
              exit(await proc.exitCode);
            }
          }
        } catch (_) {}
      }
    }
    stderr.writeln('Error: Module "$moduleName" not found.');
    exit(1);
  }

  static List<String> _getAssignmentFiles(String pkgPath, Map meta) {
    final paths = <String>[p.join(pkgPath, 'assignment.json')];
    if (meta['assignments'] is List) {
      for (var a in meta['assignments']) paths.add(p.join(pkgPath, a.toString()));
    }
    return paths;
  }

  static String? _resolveEntryFile(String base) {
    if (File(base).existsSync()) {
      if (FileSystemEntity.isDirectorySync(base)) {
        final m = p.join(base, '__main__.wsx');
        if (File(m).existsSync()) return m;
      }
      return base;
    }
    if (File('$base.wsx').existsSync()) return '$base.wsx';
    return null;
  }

  static String? _detectInterpreter() {
    final env = Platform.environment['WS_INTERPRETER'];
    if (env != null && File(env).existsSync()) return env;
    final search = Platform.isWindows ? ['wslang.exe', 'wslang'] : ['wslang.exe', 'wslang'];
    for (var cmd in search) {
      try {
        final res = Process.runSync(cmd, ['--version']);
        if (res.exitCode == 0) return cmd;
      } catch (_) {}
    }
    return null;
  }
}

// ------------------------------------------------------------------
// Main Entry Point
// ------------------------------------------------------------------

void main(List<String> args) async {
  if (args.isEmpty) {
    _printHelp();
    return;
  }

  final command = args[0].toLowerCase();
  try {
    switch (command) {
      case 'refresh':
        await Registry.refresh(Config.load());
        break;
      case 'install':
      case 'i':
        if (args.length < 2) return print('Usage: wpm install <pkg>');
        await Packages.installByName(args[1]);
        break;
      case 'get':
        await Packages.getFromManifest();
        break;
      case 'list':
      case 'ls':
        Packages.list();
        break;
      case 'uninstall':
      case 'rm':
        if (args.length < 2) return print('Usage: wpm uninstall <pkg>');
        Packages.uninstall(args[1]);
        break;
      case 'run':
        if (args.length < 2) return print('Usage: wpm run <module>');
        await Packages.runModule(args[1]);
        break;
      case 'version':
      case '-v':
        print('wpm v$VERSION');
        break;
      default:
        print('Unknown command: $command');
        _printHelp();
    }
  } catch (e) {
    stderr.writeln('\n[CRITICAL ERROR] $e');
    exit(1);
  }
}

void _printHelp() {
  print('''
wpm (Well.. Simple Package Manager) v$VERSION

COMMANDS:
  refresh           Update registry cache
  install <name>    Install a package
  uninstall <name>  Remove a package
  list              Show installed packages
  get               Install from wpackage.json
  run <module>      Run a module
  version           Show version
''');
}