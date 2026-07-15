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
// Scenarios:
//   S1  fresh pairing (Alice creates the channel through the UI, Bob joins
//       via the QR JSON) + first message Alice -> Bob, delivery timed.
//   S2  10 messages ping-pong (odd from Alice, even from Bob), latency per
//       message; the coord server computes p50/p95/max for the report.
//
// Everything runs through the real UI except the QR *scan* itself (no
// camera in a headless emulator): the joining side feeds the QR JSON
// through the same code path the scanner uses (Channel.fromJson +
// ChannelRepository.addChannel).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:integration_test/integration_test.dart';
import 'package:redpanda/database/database.dart' as appdb;
import 'package:redpanda/main.dart';
import 'package:redpanda/repositories/channel_repository.dart';
import 'package:redpanda/repositories/outbound_handle_repository.dart';
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

String s2Message(int i) => 'e2e-s2-${i.toString().padLeft(2, '0')}';

String role = 'unknown';

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
  final req = await _http.putUrl(Uri.parse('$coordBase/kv/$name'));
  req.write(value);
  final res = await req.close();
  await res.drain<void>();
  if (res.statusCode != 200) {
    throw StateError('kvPut $name failed: HTTP ${res.statusCode}');
  }
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
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    try {
      if (condition()) return true;
    } catch (_) {
      // Finder evaluation during transient states — keep waiting.
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  log('TIMEOUT waiting for: ${what ?? 'condition'}');
  dumpVisibleTexts(tester);
  return false;
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

Future<void> completeOnboarding(WidgetTester tester, String name) async {
  if (!await pumpUntilVisible(
    tester,
    find.text('Get Started'),
    timeout: const Duration(seconds: 90),
    what: 'onboarding screen',
  )) {
    throw StateError('onboarding screen never appeared');
  }
  await tester.enterText(find.byType(TextField), name);
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
Future<void> sendChatMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
  await kvPut('sent-$text', role);
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
  await tester.enterText(find.byType(TextField), channelLabel);
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
  final qrData = myChannel.copyWith(peerOhDescriptor: ownDesc).toJson();
  await kvPut('alice_qr', qrData);
  log('channel created, QR exported (${qrData.length} chars)');

  await tester.tap(find.text('Done'));
  await openChat(tester);

  // Wait for Bob's QR (his OH descriptor) so we know where to send.
  final bobQr = await waitForKv(
    tester,
    'bob_qr',
    timeout: const Duration(minutes: 6),
  );
  if (bobQr == null) throw StateError('bob_qr never appeared');
  final bobChannel = Channel.fromJson(bobQr);
  final desc = bobChannel.peerOhDescriptor;
  if (desc == null) throw StateError('Bob QR contains no OH descriptor');
  if (bobChannel.id != Channel.fromJson(qrData).id) {
    throw StateError('Bob QR is for a different channel');
  }

  // The in-app path for this step is scanning Bob's QR, which goes through
  // addChannel/insertOrReplace and would WIPE our channel auth private key
  // (QR v3 carries only public material). Instead update just the peer-OH
  // columns — the part the scan is actually supposed to contribute.
  final db = container.read(dbProvider);
  await (db.update(
    db.channels,
  )..where((t) => t.uuid.equals(bobChannel.id))).write(
    appdb.ChannelsCompanion(
      peerOhEndpoint: drift.Value(desc.serverEndpoint),
      peerOhId: drift.Value(HEX.encode(desc.handleId)),
      peerOhPublicKey: drift.Value(HEX.encode(desc.authPublicKey)),
    ),
  );
  // Re-register the channel keys with the peer OH — same call the app makes
  // on startup when restoring persisted state.
  final row = await (db.select(
    db.channels,
  )..where((t) => t.uuid.equals(bobChannel.id))).getSingle();
  container
      .read(redPandaClientProvider)
      .addChannelKeys(
        row.uuid,
        HEX.decode(row.encryptionKey),
        peerOhId: HEX.decode(row.peerOhId!),
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
  await writeResult(true, 'S1 + S2 complete ($s2Count messages)');

  // Stay alive until Bob has written his verdict too.
  await waitForKv(tester, 'bob_result', timeout: const Duration(minutes: 3));
}

Future<void> runBob(WidgetTester tester) async {
  await completeOnboarding(tester, 'Bob');

  final aliceQr = await waitForKv(
    tester,
    'alice_qr',
    timeout: const Duration(minutes: 6),
  );
  if (aliceQr == null) throw StateError('alice_qr never appeared');

  // Same code path as the QR scanner (join screen), minus the camera.
  final channel = Channel.fromJson(aliceQr);
  final container = containerOf(tester);
  await container.read(channelRepositoryProvider).addChannel(channel);
  log('joined channel from Alice QR');

  await openChat(tester);

  // Wait until the client is actually connected — attempting an OH
  // registration earlier just burns node-side rate-limit budget
  // (max 5 registrations/min per connection, MS02b).
  if (!await pumpUntil(
    tester,
    () =>
        container.read(connectionStatusProvider).value ==
        ConnectionStatus.connected,
    timeout: const Duration(minutes: 3),
    what: 'network connected',
  )) {
    throw StateError('client never connected to the node');
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

  // Same QR JSON the chat share dialog builds (v3: public material + oh).
  final db = container.read(dbProvider);
  final row = await (db.select(
    db.channels,
  )..where((t) => t.uuid.equals(channel.id))).getSingle();
  await kvPut(
    'bob_qr',
    jsonEncode({
      'l': row.label,
      'k_enc': row.encryptionKey,
      'k_auth_pub': row.authPublicKey,
      'oh': ownDesc.toJsonMap(),
      'v': 3,
    }),
  );
  log('own QR exported');

  // --- S1 ---
  await awaitChatMessage(
    tester,
    s1Message,
    timeout: const Duration(minutes: 10),
  );

  // --- S2: ping-pong, Bob sends the even messages ---
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
    throw StateError('Alice never confirmed receipt of ${s2Message(s2Count)}');
  }
  await writeResult(true, 'S1 + S2 complete ($s2Count messages)');

  await waitForKv(tester, 'alice_result', timeout: const Duration(minutes: 3));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('emulator duo e2e', (tester) async {
    role = await detectRole();
    log('starting app (coord=$coordBase seeds=$seedsRaw)');

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
