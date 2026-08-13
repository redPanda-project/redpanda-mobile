import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

/// Environment variable that lets a CI run continue without the backend JAR.
/// Deliberate exceptions only — see [e2eJarAvailable].
const String kAllowMissingJarEnv = 'E2E_ALLOW_MISSING_JAR';

/// Whether the backend JAR the e2e suites need is present.
///
/// Every e2e suite asks this exactly once and passes the result to the
/// `skip:` argument of its tests — a missing JAR skips the suite instead of
/// failing it, which is what a developer without a built backend wants.
///
/// In CI that same skip is a trap (TD033): the workflow downloads the JAR
/// from redpandaj's `latest` release in a `continue-on-error` step, so a gap
/// in that release — or any download hiccup — leaves no JAR behind, every
/// e2e test skips, and the run goes green with ZERO e2e coverage. That
/// happened for real on 2026-08-09 (PR #90: ~3 min instead of ~17). A green
/// run that tested nothing is worse than a red one, so in CI this fails
/// closed and throws instead of returning `false`.
///
/// CI is detected via `CI` / `GITHUB_ACTIONS`, both of which GitHub Actions
/// always sets. Set [kAllowMissingJarEnv] to `1`/`true` to opt out and get
/// the local skip behaviour back.
bool e2eJarAvailable() {
  if (RedPandaNodeLauncher.locateJar() != null) return true;

  final ciSignal = _ciSignal();
  if (ciSignal == null || _missingJarAllowed) return false;

  throw StateError(
    'E2E backend JAR is missing in CI — refusing to skip the e2e suites.\n'
    'Expected: <repo>/references/redPandaj/target/redpanda.jar '
    '(or <repo>/redpandaj/target/redpanda.jar), non-empty.\n'
    'In CI the JAR comes from the "Download RedPanda JAR (Backend)" step '
    '(gh release download latest --repo redPanda-project/redpandaj). That '
    'step is continue-on-error, so a missing/incomplete redpandaj `latest` '
    'release leaves the JAR absent. Skipping here would produce a green run '
    'with zero e2e coverage (TD033), so the suite fails instead.\n'
    'Fix the release/download; set $kAllowMissingJarEnv=1 only to allow the '
    'skip on purpose.\n'
    'CI was detected via $ciSignal — if that is wrong, this is a local shell '
    'exporting a CI variable, and the same opt-out applies.',
  );
}

/// The environment variable that identifies this run as CI, or `null` when it
/// is not one.
///
/// GitHub Actions sets CI=true and GITHUB_ACTIONS=true on every runner;
/// GITHUB_RUN_ID is a presence-only backstop in case a runner image or an
/// `env:` override drops the boolean ones. The name is reported in the failure
/// message so a false positive (a dev shell that exports `CI`) is obvious
/// rather than mysterious.
String? _ciSignal() {
  for (final name in const ['CI', 'GITHUB_ACTIONS']) {
    if (_envFlag(name)) return '$name=${Platform.environment[name]}';
  }
  if (Platform.environment.containsKey('GITHUB_RUN_ID')) return 'GITHUB_RUN_ID';
  return null;
}

bool get _missingJarAllowed => _envFlag(kAllowMissingJarEnv);

bool _envFlag(String name) {
  final value = Platform.environment[name]?.trim().toLowerCase();
  return value == 'true' || value == '1';
}

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

  // T78: forward through the NON-BLOCKING sinks, never through `stdout` /
  // `stderr` directly. Those are documented blocking IOSinks ("Provides a
  // *blocking* IOSink", dart:io/stdio.dart) whose consumer writes with
  // `writeFromSync`. Under `flutter test` the test process' stdout is a pipe
  // (flutter_tester -> flutter_tools -> CI runner, hence the "Shell: " prefix
  // on every node line). If that pipe's 64 KiB kernel buffer fills because the
  // reader stalls, a blocking write freezes the whole isolate *synchronously*:
  // no timer runs, so the suite's @Timeout can never fire, and since this very
  // subscription is what drains the node's stdout pipe, the java node blocks on
  // its next write too. Both sides go dead silent until the CI step's 30 min
  // ceiling kills the job — which is exactly the signature of the T78 hangs
  // (15-24 min without a single log line, node and dart stopping in the same
  // instant, no test failure reported). It never reproduced locally because a
  // terminal or a redirect to a file applies no backpressure; only a pipe does.
  // The non-blocking sinks buffer in memory instead, so a stalled reader can
  // slow the output down but can no longer deadlock the test isolate.
  static final IOSink _consoleOut = stdout.nonBlocking;
  static final IOSink _consoleErr = stderr.nonBlocking;

  RedPandaNodeLauncher({required this.port, this.seeds = const []})
    : _workingDir = Directory.systemTemp
          .createTempSync('redpanda_node_$port')
          .path;

  /// Absolute path of the backend JAR, or `null` when it cannot be located.
  ///
  /// Callers in tests should go through [e2eJarAvailable], which additionally
  /// enforces the fail-closed rule for CI (TD033).
  static String? locateJar() {
    try {
      final path = _findJarPath();
      final jar = File(path);
      // Zero bytes means a failed or half-written download, not a usable JAR.
      // Treating it as missing keeps the diagnosis at the guard instead of
      // surfacing 60 s later as "Node failed to start on port ...".
      if (!jar.existsSync() || jar.lengthSync() == 0) return null;
      return path;
    } catch (e, stack) {
      // Never swallow silently: a permissions error or a broken checkout would
      // otherwise be reported as "the release download failed". Goes to stderr
      // (through the non-blocking sink, see the T78 note on the field) so it
      // stays separate from the node log stream on stdout, with the stack
      // trace attached — a CI-only path is expensive to reproduce locally.
      _consoleErr.writeln('Could not locate redpanda.jar: $e\n$stack');
      return null;
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
    // REDPANDA_KNOWN_NODES is ALWAYS set (T30): without it the jar falls
    // back to its built-in defaults — which include 127.0.0.1:59558 — and a
    // long-running foreign node on this host contaminates deterministic
    // tests. Explicit seeds when given, otherwise "none" (T29,
    // redpandaj#262): start with no bootstrap peers at all.
    final env = {
      'PORT': port.toString(),
      'REDPANDA_KNOWN_NODES': seeds.isNotEmpty ? seeds.join(',') : 'none',
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
    // chatty node can never block on a full stdout buffer. The sinks must stay
    // the non-blocking ones (T78) — draining the node only helps as long as
    // forwarding cannot block this isolate in turn.
    _stdoutSub = _process!.stdout.listen((event) => _consoleOut.add(event));
    _stderrSub = _process!.stderr.listen((event) => _consoleErr.add(event));

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

  static String _findJarPath() {
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

  static String _findProjectRoot() {
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
