import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

class RedPandaNodeLauncher {
  Process? _process;
  final int port;
  final List<String> seeds;
  final String _workingDir;

  // Node stdout/stderr are piped to the test console. The subscriptions are
  // cancelled on stop(): a leaked subscription keeps the child's stdio pipes
  // attached, which prevents the dart test runner process from exiting even
  // after all tests finished — the classic "flutter test hangs forever after
  // the last test" failure that let a run sit for hours in CI.
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  RedPandaNodeLauncher({required this.port, this.seeds = const []})
    : _workingDir = Directory.systemTemp
          .createTempSync('redpanda_node_$port')
          .path;

  static Future<bool> isJarAvailable() async {
    try {
      final launcher = RedPandaNodeLauncher(port: 0);
      return File(launcher._findJarPath()).existsSync();
    } catch (e) {
      return false;
    }
  }

  Future<void> start() async {
    final jarPath = _findJarPath();

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

    // Based on ConnectionHandler.java, the app reads System.getenv("PORT").
    // A non-empty seeds list isolates the node from the public testnet:
    // Settings reads REDPANDA_KNOWN_NODES (comma-separated) and only falls
    // back to the built-in defaults when the list is empty/invalid.
    final env = {
      'PORT': port.toString(),
      if (seeds.isNotEmpty) 'REDPANDA_KNOWN_NODES': seeds.join(','),
    };

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

    // Stream output to console for debugging. Keep the subscriptions so
    // stop() can cancel them (see the field doc) and drain the pipes so a
    // chatty node can never block on a full stdout buffer.
    _stdoutSub = _process!.stdout.listen((event) => stdout.add(event));
    _stderrSub = _process!.stderr.listen((event) => stderr.add(event));

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
    final process = _process;
    _process = null;
    if (process != null) {
      // Graceful first (lets the JVM shutdown hook free the ports), then a
      // hard kill if it lingers — a SIGTERM the JVM ignores must never leave
      // a node running that holds a port or keeps the runner alive.
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        // Reap the exit so the OS pipes are fully released before we return.
        await process.exitCode
            .timeout(const Duration(seconds: 5))
            .catchError((_) => -1);
      }
    }
    // Cancel AFTER the process exited so the final output is drained and the
    // inherited stdio pipes are closed — otherwise the dart test runner can
    // hang waiting for them at the end of the suite.
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
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

  String _findJarPath() {
    final projectRoot = _findProjectRoot();

    // Try references/redpandaj first (case-insensitive)
    final referencesDir = Directory(p.join(projectRoot, 'references'));
    if (referencesDir.existsSync()) {
      for (final dir in referencesDir.listSync().whereType<Directory>()) {
        if (p.basename(dir.path).toLowerCase() == 'redpandaj') {
          final candidate = p.join(dir.path, 'target', 'redpanda.jar');
          if (File(candidate).existsSync()) return candidate;
        }
      }
    }

    // Fallback: direct redpandaj in root
    final directJar = p.join(
      projectRoot,
      'redpandaj',
      'target',
      'redpanda.jar',
    );
    return directJar;
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
