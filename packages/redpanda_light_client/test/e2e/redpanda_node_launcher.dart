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

  Future<void> start() async {
    // Locate the jar file relative to the project root
    // Assuming we are running tests from <project>/packages/redpanda_light_client
    // The jar is at <project>/references/redPandaj/target/redpanda.jar
    final projectRoot = _findProjectRoot();
    final jarPath = p.join(
      projectRoot,
      'references',
      'redPandaj',
      'target',
      'redpanda.jar',
    );

    if (!File(jarPath).existsSync()) {
      throw Exception(
        'redpanda.jar not found at $jarPath. Did you run "mvn package"?',
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

    // Wait for "Server started" or similar log (optimistic wait for now)
    await Future.delayed(const Duration(seconds: 5));

    if (await _processIsDead()) {
      throw Exception('Node process died immediately. Check logs.');
    }
    print('Node $port likely started.');
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
      await _process!.exitCode.timeout(
        const Duration(milliseconds: 100),
      );
      return true; // If we get an exit code, it's dead
    } on TimeoutException {
      return false; // Still running
    }
  }

  String _findProjectRoot() {
    // Hacky traversal up to find 'pubspec.yaml' of the root or similar marker
    var dir = Directory.current;
    while (true) {
      if (File(
        p.join(dir.path, 'references', 'redPandaj', 'pom.xml'),
      ).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw Exception(
          'Could not find project root containing references/redPandaj',
        );
      }
      dir = parent;
    }
  }
}
