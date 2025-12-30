import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

class RedPandaNodeLauncher {
  Process? _process;
  final int port;
  final List<String> seeds;
  final String _workingDir;

  RedPandaNodeLauncher({required this.port, this.seeds = const []})
    : _workingDir = Directory.systemTemp
          .createTempSync('redpanda_node_$port')
          .path;

  static Future<bool> isJarAvailable() async {
    try {
      final launcher = RedPandaNodeLauncher(port: 0);
      final projectRoot = launcher._findProjectRoot();
      // Try to find the redpandaj directory (case-insensitive)
      final referencesDir = Directory(p.join(projectRoot, 'references'));
      String redpandajDirName = 'redPandaj'; // Default

      if (referencesDir.existsSync()) {
        final dirs = referencesDir.listSync().whereType<Directory>();
        for (final dir in dirs) {
          final name = p.basename(dir.path);
          if (name.toLowerCase() == 'redpandaj') {
            redpandajDirName = name;
            break;
          }
        }
      }

      final jarPath = p.join(
        projectRoot,
        'references',
        redpandajDirName,
        'target',
        'redpanda.jar',
      );
      return File(jarPath).existsSync();
    } catch (e) {
      return false;
    }
  }

  Future<void> start() async {
    // Locate the jar file relative to the project root
    final projectRoot = _findProjectRoot();

    // Try to find the redpandaj directory (case-insensitive)
    final referencesDir = Directory(p.join(projectRoot, 'references'));
    String redpandajDirName = 'redPandaj'; // Default

    if (referencesDir.existsSync()) {
      final dirs = referencesDir.listSync().whereType<Directory>();
      for (final dir in dirs) {
        final name = p.basename(dir.path);
        if (name.toLowerCase() == 'redpandaj') {
          redpandajDirName = name;
          break;
        }
      }
    }

    final jarPath = p.join(
      projectRoot,
      'references',
      redpandajDirName,
      'target',
      'redpanda.jar',
    );

    print('Looking for JAR at: $jarPath');

    if (!File(jarPath).existsSync()) {
      throw Exception(
        'redpanda.jar not found at $jarPath. Have you built the project with Maven?',
      );
    }

    // Create necessary config files in temp dir if needed, or pass args
    // For now, we assume we can pass port via args or minimal config
    // NOTE: Based on README, port is in Settings. This might need a custom config mechanism
    // if the jar doesn't accept CLI args for port.
    // Checking README again: "./data/localSettings<port>.dat".
    // We might need to adjust how the node picks up the port.
    // Let's assume for this first pass we rely on default or mechanism we can inject.
    // If redPandaj doesn't support CLI port override, we might need to write a properties file.

    // Based on ConnectionHandler.java, the app reads System.getenv("PORT")
    final env = {'PORT': port.toString()};

    final args = [
      '-jar',
      jarPath,
      // '--headless', // Not supported yet based on App.java source, but "headless" is default behavior essentially (console only)
    ];

    print('Starting Node on port $port...');
    _process = await Process.start(
      'java',
      args,
      workingDirectory: _workingDir,
      environment: env,
    );

    // Stream output to console for debugging
    _process!.stdout.listen((event) => stdout.add(event));
    _process!.stderr.listen((event) => stderr.add(event));

    // Wait for the port to be open (up to 60 seconds)
    print('Waiting for port $port to open...');
    bool connected = false;
    for (int i = 0; i < 120; i++) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 500),
        );
        await socket.close();
        connected = true;
        break;
      } catch (e) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (!connected) {
      throw Exception('Node failed to start on port $port after 60 seconds.');
    }

    // Give the node a moment to settle (initialize IDs, threads, etc.)
    print('Port open. Waiting 2 seconds for node to settle...');
    await Future.delayed(const Duration(seconds: 2));

    if (await _processIsDead()) {
      throw Exception('Node process died immediately. Check logs.');
    }
    print('Node $port successfully started and listening.');
  }

  Future<void> stop() async {
    _process?.kill();
    _process = null;
    try {
      Directory(_workingDir).deleteSync(recursive: true);
    } catch (e) {
      print('Failed to cleanup temp dir: $e');
    }
  }

  Future<bool> _processIsDead() async {
    try {
      await _process!.exitCode.timeout(const Duration(milliseconds: 100));
      return true; // If we get an exit code, it's dead
    } on TimeoutException {
      return false; // Still running
    }
  }

  String _findProjectRoot() {
    var dir = Directory.current;
    print('Searching for project root starting from: ${dir.path}');

    while (true) {
      // Check for references/redpandaj (case-insensitive)
      final refDir = Directory(p.join(dir.path, 'references'));
      if (refDir.existsSync()) {
        final children = refDir.listSync().whereType<Directory>();
        for (final child in children) {
          if (p.basename(child.path).toLowerCase() == 'redpandaj') {
            print('Found project root at: ${dir.path}');
            return dir.path;
          }
        }
      }

      // Also support direct redpandaj in root (sometimes CI flat structures)
      final redDir = Directory(p.join(dir.path, 'redpandaj'));
      if (redDir.existsSync()) {
        print('Found project root (direct redpandaj) at: ${dir.path}');
        return dir.path;
      }

      // Root of filesystem reached
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw Exception(
          'Could not find project root containing "references/redpandaj" or "redpandaj" directory. '
          'Started search from: ${Directory.current.path}',
        );
      }
      dir = parent;
    }
  }
}
