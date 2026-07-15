// Coordination server for the emulator duo E2E harness (T23).
//
// A tiny HTTP key-value store the two emulator apps use as rendezvous
// (QR exchange, result verdicts) and as a drift-free latency clock: every
// first PUT of a key is timestamped HERE on the host, so per-message
// latency = t(recv-<msg>) - t(sent-<msg>) needs no synchronized guest
// clocks.
//
// Endpoints:
//   PUT  /kv/<name>   store body (first write wins the timestamp)
//   GET  /kv/<name>   200 body | 404
//   GET  /events      all recorded (name, tMs) pairs
//   GET  /report      S1-S4 latency report (S2: p50/p95/max, nearest-rank)
//
// Usage: dart run tool/emu_duo_e2e/coord_server.dart [port]

import 'dart:convert';
import 'dart:io';

final Map<String, String> store = {};
final Map<String, int> firstSeenMs = {};
final Stopwatch clock = Stopwatch()..start();

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 8123;
  // Loopback only — the emulator reaches it via its 10.0.2.2 host alias,
  // and nothing on the LAN should be able to write markers.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('coord server listening on 127.0.0.1:$port');

  await for (final req in server) {
    try {
      await handle(req);
    } catch (e) {
      stderr.writeln('error handling ${req.method} ${req.uri}: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {
        // Response already broken — nothing left to clean up.
      }
    }
  }
}

Future<void> handle(HttpRequest req) async {
  final path = req.uri.path;
  final res = req.response;

  if (req.method == 'PUT' && path.startsWith('/kv/')) {
    final name = path.substring('/kv/'.length);
    final body = await utf8.decoder.bind(req).join();
    store[name] = body;
    firstSeenMs.putIfAbsent(name, () => clock.elapsedMilliseconds);
    stdout.writeln(
      '[${clock.elapsedMilliseconds} ms] PUT $name (${body.length} bytes)',
    );
    res.write('ok');
  } else if (req.method == 'GET' && path.startsWith('/kv/')) {
    final name = path.substring('/kv/'.length);
    final value = store[name];
    if (value == null) {
      res.statusCode = HttpStatus.notFound;
    } else {
      res.write(value);
    }
  } else if (req.method == 'GET' && path == '/events') {
    res.headers.contentType = ContentType.json;
    res.write(
      jsonEncode([
        for (final e in firstSeenMs.entries) {'name': e.key, 'tMs': e.value},
      ]),
    );
  } else if (req.method == 'GET' && path == '/report') {
    res.headers.contentType = ContentType.json;
    res.write(const JsonEncoder.withIndent('  ').convert(buildReport()));
  } else {
    res.statusCode = HttpStatus.notFound;
  }
  await res.close();
}

/// Latency of one message id, or null while sent/recv marks are missing.
int? latencyMs(String id) {
  final sent = firstSeenMs['sent-$id'];
  final recv = firstSeenMs['recv-$id'];
  if (sent == null || recv == null) return null;
  return recv - sent;
}

Map<String, dynamic> buildReport() {
  // Must mirror the ids in integration_test/emu_duo_e2e_test.dart:
  // S1 = 'e2e-s1', S2 = 'e2e-s2-01'..'e2e-s2-10' (odd from Alice).
  final s2 = <Map<String, dynamic>>[];
  final s2Latencies = <int>[];
  for (var i = 1; i <= 10; i++) {
    final id = 'e2e-s2-${i.toString().padLeft(2, '0')}';
    final lat = latencyMs(id);
    s2.add({
      'id': id,
      'direction': i.isOdd ? 'alice->bob' : 'bob->alice',
      'sentAtMs': firstSeenMs['sent-$id'],
      'recvAtMs': firstSeenMs['recv-$id'],
      'latencyMs': lat,
    });
    if (lat != null) s2Latencies.add(lat);
  }
  s2Latencies.sort();

  // Nearest-rank percentile on the sorted latencies.
  int? pct(int p) {
    if (s2Latencies.isEmpty) return null;
    final rank = (p * s2Latencies.length / 100).ceil().clamp(
      1,
      s2Latencies.length,
    );
    return s2Latencies[rank - 1];
  }

  Map<String, dynamic>? decodeResult(String key) {
    final raw = store[key];
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'raw': raw};
    }
  }

  // Difference of two host-side marker timestamps, null while either is
  // missing. Used for the S3/S4 lifecycle numbers.
  int? span(String from, String to) {
    final a = firstSeenMs[from];
    final b = firstSeenMs[to];
    if (a == null || b == null) return null;
    return b - a;
  }

  // S3 acceptance (T24): catch-up after an app restart must complete within
  // 60 s — this proves the T18 restart-requeue (mobile PR #50).
  const s3CatchupBudgetMs = 60000;
  final s3Catchup = span('s3-bob-restart', 'recv-e2e-s3');

  return {
    'generatedAt': DateTime.now().toIso8601String(),
    'scenarios': store['scenarios'],
    's1': {
      'sentAtMs': firstSeenMs['sent-e2e-s1'],
      'recvAtMs': firstSeenMs['recv-e2e-s1'],
      'latencyMs': latencyMs('e2e-s1'),
    },
    's2': {
      'messages': s2,
      'measured': s2Latencies.length,
      'p50Ms': pct(50),
      'p95Ms': pct(95),
      'maxMs': s2Latencies.isEmpty ? null : s2Latencies.last,
    },
    's3': {
      'bobKilledAtMs': firstSeenMs['s3-bob-killed'],
      'sentAtMs': firstSeenMs['sent-e2e-s3'],
      'bobRestartAtMs': firstSeenMs['s3-bob-restart'],
      'recvAtMs': firstSeenMs['recv-e2e-s3'],
      // Acceptance number: app start -> message visible in the chat UI.
      'catchupMs': s3Catchup,
      'catchupBudgetMs': s3CatchupBudgetMs,
      'withinCatchupBudget': s3Catchup == null
          ? null
          : s3Catchup <= s3CatchupBudgetMs,
      // For reference: full send -> receive latency across the kill window.
      'deliveryMs': latencyMs('e2e-s3'),
    },
    's4': {
      'netDownAtMs': firstSeenMs['s4-net-down'],
      'sentAtMs': firstSeenMs['sent-e2e-s4'],
      'netUpAtMs': firstSeenMs['s4-net-up'],
      'recvAtMs': firstSeenMs['recv-e2e-s4'],
      'silenceMs': span('s4-net-down', 's4-net-up'),
      // Acceptance number: network restored -> message visible on Bob.
      'reconnectDeliveryMs': span('s4-net-up', 'recv-e2e-s4'),
      'deliveryMs': latencyMs('e2e-s4'),
    },
    'results': {
      'alice': decodeResult('alice_result'),
      'bob': decodeResult('bob_result'),
    },
  };
}
