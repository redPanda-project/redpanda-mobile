// Emulator duo E2E (T23): two Android emulators (Alice + Bob) chat with
// each other through a LOCAL backend node running on the host.
//
// Launched by tool/emu_duo_e2e/run.sh — see tool/emu_duo_e2e/README.md.
// Both emulators run the SAME apk (built with this file as --target); the
// role is derived from the AVD name (rp_alice / rp_bob). Coordination and
// latency timestamps go through a tiny HTTP key-value server on the host
// (tool/emu_duo_e2e/coord_server.dart) — server-side timestamps, so the
// latency numbers are immune to guest clock drift.
//
// Scenarios (selected via the `scenarios` key on the coord server, which
// run.sh fills from RP_SCENARIOS — S1 is the pairing foundation and always
// runs):
//   S1  fresh pairing (Alice creates the channel through the UI, Bob joins
//       via the QR JSON) + first message Alice -> Bob, delivery timed.
//   S2  10 messages ping-pong (odd from Alice, even from Bob), latency per
//       message; the coord server computes p50/p95/max for the report.
//   S3  kill/restart catch-up: the harness force-stops Bob's app, Alice
//       sends while Bob is dead, the harness restarts the app (bob_phase =
//       resume-s3) and the resumed process must show the message within the
//       catch-up budget (proves the T18 restart-requeue, mobile PR #50).
//   S4  airplane-mode reconnect: the harness cuts Bob's network, Alice
//       sends into the silence, the harness restores the network and Bob
//       must reconnect and receive (proves the T15 isolate resilience and
//       the #55 host-node fix).
//
// Everything runs through the real UI except the QR *scan* itself (no
// camera in a headless emulator): the joining side feeds the QR JSON
// through the same code path the scanner uses (Channel.fromJson +
// ChannelRepository.addChannel).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:integration_test/integration_test.dart';
import 'package:redpanda/main.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
import 'package:redpanda/services/field_logging.dart';
import 'package:redpanda/shared/providers.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// Host as seen from inside the emulator (Android emulator NAT).
const coordBase = String.fromEnvironment(
  'RP_COORD',
  defaultValue: 'http://10.0.2.2:8123',
);

/// Backend seeds — default is the local node the harness starts on the host.
/// Override with the testnet seeds for a (non-deterministic) real-net run.
const seedsRaw = String.fromEnvironment(
  'RP_SEEDS',
  defaultValue: '10.0.2.2:59558',
);

const channelLabel = 'Emu Duo E2E';
const s1Message = 'e2e-s1';
const s2Count = 10;
const s3Message = 'e2e-s3';
const s4Message = 'e2e-s4';

String s2Message(int i) => 'e2e-s2-${i.toString().padLeft(2, '0')}';

String role = 'unknown';

/// Enabled scenarios, filled from the coord server before the app starts.
/// S1 (pairing + first delivery) is the foundation and always runs.
Set<String> scenarios = {'s1', 's2', 's3', 's4'};

bool get runS2 => scenarios.contains('s2');
bool get runS3 => scenarios.contains('s3');
bool get runS4 => scenarios.contains('s4');

void log(String msg) {
  // Prefixed so `adb logcat` greps stay trivial ("flutter: [emu-duo]").
  debugPrint('[emu-duo] [${DateTime.now().toIso8601String()}] [$role] $msg');
}

// ---------------------------------------------------------------------------
// Coordination server client (plain dart:io, host-side timestamps)
// ---------------------------------------------------------------------------

final HttpClient _http = HttpClient()
  ..connectionTimeout = const Duration(seconds: 5);

Future<void> kvPut(String name, String value) async {
  // Retried: after an airplane-mode toggle (S4) the client may hold stale
  // pooled sockets whose first use fails — a fresh attempt gets a new one.
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final req = await _http.putUrl(Uri.parse('$coordBase/kv/$name'));
      req.write(value);
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode != 200) {
        throw StateError('kvPut $name failed: HTTP ${res.statusCode}');
      }
      return;
    } catch (e) {
      lastError = e;
      log('kvPut $name attempt $attempt failed: $e');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  throw StateError('kvPut $name failed after retries: $lastError');
}

Future<String?> kvGet(String name) async {
  final req = await _http.getUrl(Uri.parse('$coordBase/kv/$name'));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) {
    throw StateError('kvGet $name failed: HTTP ${res.statusCode}');
  }
  return body;
}

Future<void> writeResult(bool ok, String detail) async {
  await kvPut(
    '${role}_result',
    jsonEncode({
      'ok': ok,
      'role': role,
      'detail': detail,
      'time': DateTime.now().toIso8601String(),
    }),
  );
  log('RESULT ok=$ok detail=$detail');
}

/// The role comes from the AVD name (the harness creates rp_alice/rp_bob) —
/// both emulators run the identical apk, so it cannot be a dart-define.
Future<String> detectRole() async {
  for (final prop in ['ro.boot.qemu.avd_name', 'ro.kernel.qemu.avd_name']) {
    try {
      final result = await Process.run('getprop', [prop]);
      final value = (result.stdout as String).trim().toLowerCase();
      if (value.contains('alice')) return 'alice';
      if (value.contains('bob')) return 'bob';
    } catch (_) {
      // getprop missing/blocked — try the next property.
    }
  }
  throw StateError(
    'cannot derive role from AVD name — expected rp_alice or rp_bob',
  );
}

// ---------------------------------------------------------------------------
// Pump helpers (real frames, real time — the app keeps networking)
// ---------------------------------------------------------------------------

Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  String? what,
  // Optional one-line state dump, logged every 15 s while the wait runs. A
  // wait that ends in a timeout is the one place where "what did it look like
  // on the way there" is worth having (T89b).
  String Function()? progress,
}) async {
  final deadline = DateTime.now().add(timeout);
  var nextProgress = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    try {
      if (condition()) return true;
    } catch (_) {
      // Finder evaluation during transient states — keep waiting.
    }
    if (progress != null && DateTime.now().isAfter(nextProgress)) {
      nextProgress = DateTime.now().add(const Duration(seconds: 15));
      try {
        log('waiting for ${what ?? 'condition'}: ${progress()}');
      } catch (e) {
        log('waiting for ${what ?? 'condition'}: progress dump failed: $e');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  log('TIMEOUT waiting for: ${what ?? 'condition'}');
  dumpVisibleTexts(tester);
  return false;
}

/// How long a role waits for its first `ConnectionStatus.connected`.
///
/// The dial itself is cheap — `ActivePeer` reports `connected` as soon as the
/// node's 30-byte handshake header is in, one RTT after the TCP connect — so
/// this budget covers app start, the isolate spawn and a handful of retries
/// (`Socket.connect` timeout 10 s, peer backoff capped at 30 s), not the
/// network.
const connectWaitTimeout = Duration(minutes: 3);

/// One-line dump of what the client thinks the network looks like.
///
/// `<loading>` for a provider means no value has arrived yet, which is a very
/// different failure from `status=connecting` with a peer in flight.
String networkDiagnostics(ProviderContainer container) {
  String describe(AsyncValue<Object?> v) => v.when(
    data: (value) => value is ConnectionStatus ? value.name : '$value',
    loading: () => '<loading>',
    error: (e, _) => '<error: $e>',
  );

  final status = describe(container.read(connectionStatusProvider));
  final peers = describe(container.read(peerCountProvider));
  final stats = container.read(peerStatsSnapshotProvider).value;
  final active = stats?.activePeerAddresses.join(',') ?? '?';
  final connecting = stats?.connectingPeerAddresses.join(',') ?? '?';
  final known = stats?.allPeers.length ?? -1;
  return 'status=$status peerCount=$peers known=$known '
      'active=[$active] connecting=[$connecting] seeds=$seedsRaw';
}

/// Records every connection-status event instead of only the ones a poll
/// happens to land on.
///
/// `pumpUntil(() => ...connectionStatusProvider).value == connected)` samples
/// a snapshot every ~250 ms, so a connection that comes up and is torn down
/// again between two samples leaves no trace, and the verdict for a client
/// that connected twenty times is still `client never connected to the node`.
/// A node that keeps dropping the connection right after the handshake looks
/// exactly like that — which is what the node log of the 2026-07-29 run2
/// carried (the T88 duplicate loop) while the test reported the T81 signature
/// and sent everyone looking at the app's provider replay instead.
///
/// The wait itself still requires the client to be connected *now* (going on
/// while it is down would only burn OH-registration rate-limit budget). This
/// is about the verdict: `connectedCount` separates "never got a connection"
/// from "kept getting one and losing it again".
class ConnectionWatcher {
  ConnectionWatcher(ProviderContainer container) {
    _subscription = container.listen<AsyncValue<ConnectionStatus>>(
      connectionStatusProvider,
      (previous, next) => _record(next),
      fireImmediately: true,
    );
  }

  late final ProviderSubscription<AsyncValue<ConnectionStatus>> _subscription;
  final Map<ConnectionStatus, int> _seen = {};
  int _events = 0;

  void _record(AsyncValue<ConnectionStatus> value) {
    final status = value.value;
    if (status == null) return;
    _events++;
    _seen.update(status, (n) => n + 1, ifAbsent: () => 1);
  }

  /// How often the client reported a usable connection (0 is the real
  /// "never connected"; >0 with a failed wait means it kept losing it).
  int get connectedCount => _seen[ConnectionStatus.connected] ?? 0;

  String get summary {
    final parts = _seen.entries.map((e) => '${e.key.name}=${e.value}');
    return 'statusEvents=$_events [${parts.join(' ')}]';
  }

  void close() => _subscription.close();
}

Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

void dumpVisibleTexts(WidgetTester tester) {
  try {
    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '<rich>')
        .toList();
    log('visible texts: $texts');
  } catch (e) {
    log('could not dump texts: $e');
  }
}

Future<bool> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  String? what,
}) {
  return pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
    what: what ?? finder.toString(),
  );
}

/// Polls the coord server for [name] while pumping frames.
Future<String?> waitForKv(
  WidgetTester tester,
  String name, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    try {
      final value = await kvGet(name);
      if (value != null) return value;
    } catch (e) {
      log('kvGet $name error (will retry): $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  log('TIMEOUT waiting for kv $name');
  return null;
}

// ---------------------------------------------------------------------------
// UI flows (same widgets/texts as the real app — see duo_e2e_test.dart)
// ---------------------------------------------------------------------------

/// Sets [text] directly on the first visible text field's controller.
///
/// `tester.enterText` proved unreliable in profile builds (T27): it relies
/// on the test text-input channel, and with a live frame policy on a real
/// device the text silently never reached the widget — writing to the
/// controller is build-mode-independent.
Future<void> setTextField(WidgetTester tester, String text) async {
  final editable = tester.widget<EditableText>(find.byType(EditableText).first);
  editable.controller.text = text;
  await tester.pump();
}

Future<void> completeOnboarding(WidgetTester tester, String name) async {
  if (!await pumpUntilVisible(
    tester,
    find.text('Get Started'),
    timeout: const Duration(seconds: 90),
    what: 'onboarding screen',
  )) {
    throw StateError('onboarding screen never appeared');
  }
  await setTextField(tester, name);
  await tester.pump();
  // Retry the tap until the home screen actually shows up.
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (find.text('No channels yet').evaluate().isEmpty) {
    if (!DateTime.now().isBefore(deadline)) {
      dumpVisibleTexts(tester);
      throw StateError('home screen never appeared after onboarding');
    }
    if (find.text('Get Started').evaluate().isNotEmpty) {
      await tester.tap(find.text('Get Started'), warnIfMissed: false);
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (find.text('No channels yet').evaluate().isNotEmpty) break;
    }
  }
  log('onboarding done as "$name"');
}

Future<void> openChat(WidgetTester tester) async {
  // Wait for the HOME screen's channel tile specifically — plain
  // find.text(label) also matches the headline on the create-channel
  // success view during the exit transition.
  final tile = find.widgetWithText(ListTile, channelLabel);
  if (!await pumpUntilVisible(
    tester,
    tile,
    timeout: const Duration(seconds: 90),
    what: 'channel tile on home',
  )) {
    throw StateError('channel tile never appeared on home screen');
  }
  // Retry the tap: during route transitions the first tap can land on a
  // fading, non-interactive copy of the tile.
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (find.byIcon(Icons.send).evaluate().isEmpty) {
    if (!DateTime.now().isBefore(deadline)) {
      dumpVisibleTexts(tester);
      throw StateError('chat screen never appeared');
    }
    if (tile.evaluate().isNotEmpty) {
      await tester.tap(tile.first, warnIfMissed: false);
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (find.byIcon(Icons.send).evaluate().isNotEmpty) break;
    }
  }
  log('chat screen open');
}

/// Sends [text] through the chat UI and stamps `sent-<text>` on the coord
/// server (server-side timestamp — the delivery clock starts here).
///
/// The stamp goes out BEFORE the send tap: the tap dispatches the actual
/// network send, and with a loopback node delivery can complete in tens of
/// milliseconds — faster than our own `sent-` PUT when this emulator's vCPU
/// is starved. Stamping afterwards let the peer's `recv-` PUT win the race
/// to the coord server, which reported as a negative latency and failed the
/// run (TD046; -167/-47 ms on 2026-08-17/18). Stamping first can only
/// overestimate latency, never produce a negative — the overestimate is the
/// tap dispatch time plus whatever remains of the `sent-` PUT round-trip
/// after the server has stamped its arrival (the stamp is taken when the
/// request arrives, before the response leg and our local await complete;
/// TD049).
Future<void> sendChatMessage(WidgetTester tester, String text) async {
  await setTextField(tester, text);
  await tester.pump();
  await kvPut('sent-$text', role);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
  log('sent message: "$text"');
}

/// Waits for [text] from the peer in the chat UI and stamps `recv-<text>`.
Future<void> awaitChatMessage(
  WidgetTester tester,
  String text, {
  required Duration timeout,
}) async {
  if (!await pumpUntilVisible(
    tester,
    find.text(text),
    timeout: timeout,
    what: 'message "$text" in chat UI',
  )) {
    throw StateError('message "$text" never arrived');
  }
  await kvPut('recv-$text', role);
  log('received message: "$text"');
}

ProviderContainer containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(MyApp)),
    listen: false,
  );
}

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

Future<void> runAlice(WidgetTester tester) async {
  await completeOnboarding(tester, 'Alice');

  // Create the channel through the UI.
  await tester.tap(find.byIcon(Icons.add));
  await pumpUntilVisible(
    tester,
    find.text('Generate Secure Channel'),
    timeout: const Duration(seconds: 60),
    what: 'create-channel screen',
  );
  await setTextField(tester, channelLabel);
  await tester.pump();
  await tester.tap(find.text('Generate Secure Channel'));

  // Wait until the OWN outbound handle is registered on the node — only
  // then does the QR contain the `oh` field Bob needs to send to us. The
  // exact string below is shown only in the registered state.
  if (!await pumpUntilVisible(
    tester,
    find.text('Scan this code on another device to join.'),
    timeout: const Duration(minutes: 4),
    what: 'OH registration (QR upgrade)',
  )) {
    throw StateError('own OH was never registered on the node');
  }
  // QrImageView keeps its data private, so rebuild the exact same QR JSON
  // the screen builds: persisted channel + own OH descriptor (idempotent —
  // ensureOwnDescriptor returns the already-registered handle).
  final container = containerOf(tester);
  final myChannel =
      (await container.read(channelRepositoryProvider).getChannels())
          .singleWhere((c) => c.label == channelLabel);
  final ownDesc = await container
      .read(outboundHandleRepositoryProvider)
      .ensureOwnDescriptor(
        container.read(redPandaClientProvider),
        myChannel.id,
      );
  if (ownDesc == null) {
    throw StateError('own OH descriptor unavailable despite registered state');
  }
  // QR v4 carries only the channel secret; the OH is exchanged out of band
  // (in production over the rendezvous DHT — here over the coord server, which
  // stands in for the DHT so the pairing stays deterministic and fast).
  final qrData = myChannel.toJson();
  await kvPut('alice_qr', qrData);
  await kvPut('alice_oh', ownDesc.toJson());
  log('channel created, QR + OH exported (${qrData.length} chars)');

  await tester.tap(find.text('Done'));
  await openChat(tester);

  // Wait for Bob's channel secret + OH so we know where to send.
  final bobQr = await waitForKv(
    tester,
    'bob_qr',
    timeout: const Duration(minutes: 6),
  );
  if (bobQr == null) throw StateError('bob_qr never appeared');
  final bobOhJson = await waitForKv(
    tester,
    'bob_oh',
    timeout: const Duration(minutes: 6),
  );
  if (bobOhJson == null) throw StateError('bob_oh never appeared');
  final desc = OHDescriptor.fromJson(bobOhJson);
  if ((await Channel.fromJson(bobQr)).id !=
      (await Channel.fromJson(qrData)).id) {
    throw StateError('Bob QR is for a different channel');
  }

  // Attach the peer OH that rendezvous discovery contributes. Since #82
  // addChannel updates an existing row in place instead of INSERT OR REPLACE,
  // so it preserves the ratchet state and our creator role marker — the normal
  // repository path, no direct DB write needed.
  await container
      .read(channelRepositoryProvider)
      .addChannel(myChannel.copyWith(peerOhDescriptor: desc));
  // Re-register the channel keys with the peer OH — same call the app makes
  // on startup when restoring persisted state.
  final db = container.read(dbProvider);
  final row = await (db.select(
    db.channels,
  )..where((t) => t.uuid.equals(myChannel.id))).getSingle();
  container
      .read(redPandaClientProvider)
      .addChannelKeys(
        row.uuid,
        HEX.decode(row.encryptionKey),
        channelSecret: row.channelSecret != null
            ? HEX.decode(row.channelSecret!)
            : null,
        peerOhId: HEX.decode(row.peerOhId!),
        peerOhEndpoint: row.peerOhEndpoint,
        isChannelCreator: row.authPrivateKey != null,
        ratchetState: row.ratchetState,
      );
  log('Bob OH imported: ${desc.serverEndpoint}');

  // --- S1: first delivery on a fresh pairing ---
  await sendChatMessage(tester, s1Message);
  final s1Confirmed = await waitForKv(
    tester,
    'recv-$s1Message',
    timeout: const Duration(minutes: 10),
  );
  if (s1Confirmed == null) {
    throw StateError('Bob never confirmed receipt of the S1 message');
  }
  log('S1 delivered');

  // --- S2: ping-pong, Alice sends the odd messages ---
  if (runS2) {
    for (var i = 1; i <= s2Count; i++) {
      if (i.isOdd) {
        await sendChatMessage(tester, s2Message(i));
      } else {
        await awaitChatMessage(
          tester,
          s2Message(i),
          timeout: const Duration(minutes: 5),
        );
      }
    }
    // Delivery of our final send (s2-09) is confirmed by Bob's recv marker
    // before he sends s2-10, and s2-10 arriving above closes the loop.
    log('S2 complete ($s2Count messages)');
  }

  // --- S3: kill/restart catch-up — Bob is force-stopped by the harness,
  // we send into the void, the restarted app must catch up. ---
  if (runS3) {
    if (await waitForKv(
          tester,
          's3-bob-killed',
          timeout: const Duration(minutes: 5),
        ) ==
        null) {
      throw StateError('harness never signalled s3-bob-killed');
    }
    await sendChatMessage(tester, s3Message);
    if (await waitForKv(
          tester,
          'recv-$s3Message',
          timeout: const Duration(minutes: 10),
        ) ==
        null) {
      throw StateError('Bob never confirmed receipt of the S3 message');
    }
    log('S3 delivered (catch-up after restart)');
  }

  // --- S4: airplane-mode reconnect — the harness cuts Bob's network, we
  // send into the silence, Bob must reconnect and receive. ---
  if (runS4) {
    if (await waitForKv(
          tester,
          's4-net-down',
          timeout: const Duration(minutes: 5),
        ) ==
        null) {
      throw StateError('harness never signalled s4-net-down');
    }
    await sendChatMessage(tester, s4Message);
    if (await waitForKv(
          tester,
          'recv-$s4Message',
          timeout: const Duration(minutes: 10),
        ) ==
        null) {
      throw StateError('Bob never confirmed receipt of the S4 message');
    }
    log('S4 delivered (reconnect after airplane mode)');
  }

  await writeResult(true, 'scenarios complete: ${scenarios.join(',')}');

  // Stay alive until Bob has written his verdict too.
  await waitForKv(tester, 'bob_result', timeout: const Duration(minutes: 5));
}

Future<void> runBob(WidgetTester tester) async {
  await completeOnboarding(tester, 'Bob');

  final aliceQr = await waitForKv(
    tester,
    'alice_qr',
    timeout: const Duration(minutes: 6),
  );
  if (aliceQr == null) throw StateError('alice_qr never appeared');
  final aliceOhJson = await waitForKv(
    tester,
    'alice_oh',
    timeout: const Duration(minutes: 6),
  );
  if (aliceOhJson == null) throw StateError('alice_oh never appeared');

  // Same code path as the QR scanner (join screen), minus the camera. QR v4
  // carries only the secret; Alice's OH arrives out of band (stands in for the
  // rendezvous DHT) and is attached as the peer descriptor.
  final aliceDesc = OHDescriptor.fromJson(aliceOhJson);
  final channel = (await Channel.fromJson(
    aliceQr,
  )).copyWith(peerOhDescriptor: aliceDesc);
  final container = containerOf(tester);
  await container.read(channelRepositoryProvider).addChannel(channel);
  log('joined channel from Alice QR');

  await openChat(tester);

  // Wait until the client is actually connected — attempting an OH
  // registration earlier just burns node-side rate-limit budget
  // (max 5 registrations/min per connection, MS02b).
  //
  // T89(b): the wait logs the client's view of the network every 15 s and puts
  // the last one into the failure message. `client never connected to the
  // node` used to be the whole report, which is why the 2026-07-29 gate run
  // could not be told apart from the T81 provider race it looked like — the
  // interesting question ("did it never dial, dial and get nowhere, or connect
  // without the app noticing?") was only answerable from 3 MB of logcat.
  final watcher = ConnectionWatcher(container);
  final connected = await pumpUntil(
    tester,
    () =>
        container.read(connectionStatusProvider).value ==
        ConnectionStatus.connected,
    timeout: connectWaitTimeout,
    what: 'network connected',
    progress: () => '${networkDiagnostics(container)} ${watcher.summary}',
  );
  watcher.close();
  if (!connected) {
    throw StateError(
      watcher.connectedCount > 0
          ? 'client connected ${watcher.connectedCount}x but never stayed '
                'connected within ${connectWaitTimeout.inSeconds}s — the node '
                'keeps dropping us, check node.log (duplicate connections?) — '
                '${networkDiagnostics(container)} ${watcher.summary}'
          : 'client never connected to the node within '
                '${connectWaitTimeout.inSeconds}s — '
                '${networkDiagnostics(container)} ${watcher.summary}',
    );
  }
  log('connected, peers=${container.read(peerCountProvider).value}');

  // Register our own OH — same repository call the join screen and the
  // share dialog use. Spaced 30s apart to stay clear of the rate limit.
  final client = container.read(redPandaClientProvider);
  final handles = container.read(outboundHandleRepositoryProvider);
  OHDescriptor? ownDesc;
  for (var attempt = 1; attempt <= 8 && ownDesc == null; attempt++) {
    ownDesc = await handles.ensureOwnDescriptor(client, channel.id);
    if (ownDesc == null) {
      log(
        'OH registration attempt $attempt failed '
        '(status=${container.read(connectionStatusProvider).value}, '
        'peers=${container.read(peerCountProvider).value}) — retry in 30s',
      );
      await pumpFor(tester, const Duration(seconds: 30));
    }
  }
  if (ownDesc == null) {
    throw StateError('own OH never became available');
  }

  // QR v4 (secret only) plus our OH exchanged out of band, mirroring Alice.
  await kvPut('bob_qr', channel.toJson());
  await kvPut('bob_oh', ownDesc.toJson());
  log('own QR exported');

  // --- S1 ---
  await awaitChatMessage(
    tester,
    s1Message,
    timeout: const Duration(minutes: 10),
  );

  // --- S2: ping-pong, Bob sends the even messages ---
  if (runS2) {
    for (var i = 1; i <= s2Count; i++) {
      if (i.isOdd) {
        await awaitChatMessage(
          tester,
          s2Message(i),
          timeout: const Duration(minutes: 5),
        );
      } else {
        await sendChatMessage(tester, s2Message(i));
      }
    }

    // Our last send (s2-10) still needs to reach Alice — wait for her recv
    // marker so we do not tear the app down while retries are pending.
    final lastConfirmed = await waitForKv(
      tester,
      'recv-${s2Message(s2Count)}',
      timeout: const Duration(minutes: 5),
    );
    if (lastConfirmed == null) {
      throw StateError(
        'Alice never confirmed receipt of ${s2Message(s2Count)}',
      );
    }
    log('S2 complete ($s2Count messages)');
  }

  // --- S3: hand over to the harness — it force-stops this app (killing
  // this very test process), lets Alice send, then restarts the app. The
  // RESUMED process (bob_phase = resume-s3) continues in runBobResume. ---
  if (runS3) {
    await kvPut('bob_ready_s3', '1');
    log('ready for S3 — waiting to be force-stopped by the harness');
    await pumpFor(tester, const Duration(minutes: 30));
    throw StateError('harness never force-stopped the app for S3');
  }

  await runBobLifecycleTail(tester);
}

/// Second app start for Bob (S3): the harness force-stopped the app while
/// Alice's S3 message was in flight and restarted it with bob_phase =
/// resume-s3. Everything is persisted (onboarding, channel, peer OH) — the
/// app must come up, reconnect and catch up on the missed message. The
/// harness measures recv(s3) - restart against the 60 s budget.
Future<void> runBobResume(WidgetTester tester) async {
  // No onboarding, no QR exchange — straight to the persisted channel.
  await openChat(tester);
  await awaitChatMessage(
    tester,
    s3Message,
    timeout: const Duration(minutes: 5),
  );
  log('S3 catch-up message received after restart');

  await runBobLifecycleTail(tester);
}

/// Shared tail for Bob: S4 (airplane-mode reconnect) if enabled, then the
/// final verdict. Runs in the initial process when S3 is disabled, in the
/// resumed process otherwise.
Future<void> runBobLifecycleTail(WidgetTester tester) async {
  if (runS4) {
    await kvPut('bob_ready_s4', '1');
    log('ready for S4 — harness will cut the network');
    // The harness disables the network, Alice sends into the silence, the
    // harness restores the network. All we can observe is the message
    // finally showing up in the chat UI — awaitChatMessage stamps the
    // recv marker the harness measures against s4-net-up.
    await awaitChatMessage(
      tester,
      s4Message,
      timeout: const Duration(minutes: 10),
    );
    log('S4 message received after reconnect');
  }

  await writeResult(true, 'scenarios complete: ${scenarios.join(',')}');
  await waitForKv(tester, 'alice_result', timeout: const Duration(minutes: 5));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('emulator duo e2e', (tester) async {
    role = await detectRole();

    // Route RpLog info lines to logcat (T27): the harness artifacts
    // (alice.logcat / bob.logcat) then carry poll-cadence and send/fetch
    // telemetry for latency analysis.
    await FieldLogging.setEnabled(true);

    // Scenario selection + phase come from the coord server (run.sh writes
    // them before launching the apps) — no dart-define, so switching
    // scenarios does not need an apk rebuild.
    String? scenariosRaw;
    String? bobPhase;
    for (var attempt = 1; attempt <= 20; attempt++) {
      try {
        scenariosRaw = await kvGet('scenarios');
        bobPhase = role == 'bob' ? await kvGet('bob_phase') : null;
        if (scenariosRaw != null) break;
      } catch (e) {
        log('fetching scenarios attempt $attempt failed: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (scenariosRaw == null) {
      throw StateError('coord server never provided the scenario list');
    }
    scenarios = scenariosRaw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final resume = bobPhase == 'resume-s3';
    log(
      'starting app (coord=$coordBase seeds=$seedsRaw '
      'scenarios=${scenarios.join(',')} phase=${resume ? 'resume-s3' : 'initial'})',
    );

    final seeds = seedsRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Point the client at the harness node instead of the testnet.
          redPandaClientProvider.overrideWithValue(
            RedPandaIsolateClient(seeds: seeds),
          ),
        ],
        child: const MyApp(),
      ),
    );

    try {
      if (role == 'alice') {
        await runAlice(tester);
      } else if (resume) {
        await runBobResume(tester);
      } else {
        await runBob(tester);
      }
    } catch (e, st) {
      try {
        await writeResult(false, '$e');
      } catch (_) {
        // Coord server unreachable — the verdict is in logcat.
      }
      log('FAILED: $e\n$st');
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 50)));
}
