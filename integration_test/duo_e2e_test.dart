// Duo E2E: two real app instances (Alice + Bob) on one machine exchange
// messages over the live testnet.
//
// Run one process per role, e.g.:
//   RP_ROLE=alice RP_RENDEZVOUS=/tmp/rp-duo XDG_DATA_HOME=/tmp/rp-duo/alice \
//     build/linux/x64/debug/bundle/redpanda
//
// The processes coordinate through the rendezvous directory:
//   alice_qr.json    Alice's QR v4 JSON (channel secret only, no OH)
//   alice_oh.json    Alice's OH descriptor, exchanged out of band (stands in
//                    for the rendezvous DHT that carries it in production)
//   bob_qr.json / bob_oh.json   the same for Bob
//   alice_result.json / bob_result.json   final verdict per role
//
// Everything runs through the real UI except the QR *scan* itself (desktop
// has no camera): the joining side feeds the QR JSON through the same code
// path the scanner uses (Channel.fromJson + ChannelRepository.addChannel).

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

const channelLabel = 'Duo E2E';
const aliceMessage = 'Hallo Bob!';
const bobMessage = 'Hallo Alice!';

final String role = Platform.environment['RP_ROLE'] ?? 'alice';
final Directory rendezvous = Directory(
  Platform.environment['RP_RENDEZVOUS'] ?? '/tmp/rp-duo',
);

void log(String msg) {
  final line = '[${DateTime.now().toIso8601String()}] [$role] $msg';
  debugPrint(line);
  File(
    '${rendezvous.path}/$role.log',
  ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

void writeAtomically(String name, String content) {
  final tmp = File('${rendezvous.path}/$name.tmp');
  tmp.writeAsStringSync(content, flush: true);
  tmp.renameSync('${rendezvous.path}/$name');
}

void writeResult(bool ok, String detail) {
  writeAtomically(
    '${role}_result.json',
    jsonEncode({
      'ok': ok,
      'role': role,
      'detail': detail,
      'time': DateTime.now().toIso8601String(),
    }),
  );
  log('RESULT ok=$ok detail=$detail');
}

/// Pumps real frames until [condition] is true or [timeout] elapses.
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

/// Keeps pumping frames for [duration] (real time).
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

/// Logs every Text widget currently in the tree — diagnostic aid on timeout.
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

Future<String?> waitForFile(
  WidgetTester tester,
  String name, {
  required Duration timeout,
}) async {
  final file = File('${rendezvous.path}/$name');
  final found = await pumpUntil(
    tester,
    () => file.existsSync(),
    timeout: timeout,
    what: 'file $name',
  );
  if (!found) return null;
  return file.readAsStringSync();
}

Future<void> completeOnboarding(WidgetTester tester, String name) async {
  if (!await pumpUntilVisible(
    tester,
    find.text('Get Started'),
    timeout: const Duration(seconds: 60),
    what: 'onboarding screen',
  )) {
    throw StateError('onboarding screen never appeared');
  }
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  // Retry the tap until the home screen actually shows up.
  final deadline = DateTime.now().add(const Duration(seconds: 60));
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
    timeout: const Duration(seconds: 60),
    what: 'channel tile on home',
  )) {
    throw StateError('channel tile never appeared on home screen');
  }
  // Retry the tap: during route transitions the first tap can land on a
  // fading, non-interactive copy of the tile.
  final deadline = DateTime.now().add(const Duration(seconds: 60));
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

Future<void> sendChatMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pump();
  log('sent message: "$text"');
}

ProviderContainer containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(MyApp)),
    listen: false,
  );
}

Future<void> runAlice(WidgetTester tester) async {
  await completeOnboarding(tester, 'Alice');

  // Create the channel through the UI.
  await tester.tap(find.byIcon(Icons.add));
  await pumpUntilVisible(
    tester,
    find.text('Generate Secure Channel'),
    timeout: const Duration(seconds: 30),
    what: 'create-channel screen',
  );
  await tester.enterText(find.byType(TextField), channelLabel);
  await tester.pump();
  await tester.tap(find.text('Generate Secure Channel'));

  // Wait until the OWN outbound handle is registered on the testnet — only
  // then does the QR contain the `oh` field Bob needs to send to us. The
  // exact string below is shown only in the registered state.
  if (!await pumpUntilVisible(
    tester,
    find.text('Scan this code on another device to join.'),
    timeout: const Duration(minutes: 4),
    what: 'OH registration (QR upgrade)',
  )) {
    throw StateError('own OH was never registered on the testnet');
  }
  // QrImageView keeps its data private, so rebuild the exact same QR JSON
  // the screen builds: persisted channel + own OH descriptor (idempotent —
  // ensureOwnDescriptor returns the already-registered handle).
  final aliceContainer = containerOf(tester);
  final myChannel =
      (await aliceContainer.read(channelRepositoryProvider).getChannels())
          .singleWhere((c) => c.label == channelLabel);
  final ownDesc = await aliceContainer
      .read(outboundHandleRepositoryProvider)
      .ensureOwnDescriptor(
        aliceContainer.read(redPandaClientProvider),
        myChannel.id,
      );
  if (ownDesc == null) {
    throw StateError('own OH descriptor unavailable despite registered state');
  }
  // QR v4 carries only the channel secret; the OH is exchanged out of band
  // (in production over the rendezvous DHT — here alongside the QR file).
  final qrData = myChannel.toJson();
  writeAtomically('alice_qr.json', qrData);
  writeAtomically('alice_oh.json', ownDesc.toJson());
  log('channel created, QR + OH exported (${qrData.length} chars)');

  await tester.tap(find.text('Done'));
  await openChat(tester);

  // Wait for Bob's channel secret + OH so we know where to send.
  final bobQr = await waitForFile(
    tester,
    'bob_qr.json',
    timeout: const Duration(minutes: 6),
  );
  if (bobQr == null) throw StateError('bob_qr.json never appeared');
  final bobOhJson = await waitForFile(
    tester,
    'bob_oh.json',
    timeout: const Duration(minutes: 6),
  );
  if (bobOhJson == null) throw StateError('bob_oh.json never appeared');
  final desc = OHDescriptor.fromJson(bobOhJson);
  if ((await Channel.fromJson(bobQr)).id !=
      (await Channel.fromJson(qrData)).id) {
    throw StateError('Bob QR is for a different channel');
  }

  // Import just the peer-OH columns (the part rendezvous discovery contributes)
  // without going through addChannel, which would wipe our role marker.
  final container = containerOf(tester);
  final db = container.read(dbProvider);
  await (db.update(
    db.channels,
  )..where((t) => t.uuid.equals(myChannel.id))).write(
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

  await sendChatMessage(tester, aliceMessage);

  // Generous window: on a fresh channel the first send attempt can fail
  // (garlic session not yet established) and delivery then rides the
  // SendRetryQueue's exponential backoff (2^n minutes).
  if (!await pumpUntilVisible(
    tester,
    find.text(bobMessage),
    timeout: const Duration(minutes: 14),
    what: 'Bob reply in chat UI',
  )) {
    throw StateError('Bob reply never arrived');
  }
  log('received Bob reply in UI');
  writeResult(true, 'sent "$aliceMessage", received "$bobMessage"');
}

Future<void> runBob(WidgetTester tester) async {
  await completeOnboarding(tester, 'Bob');

  final aliceQr = await waitForFile(
    tester,
    'alice_qr.json',
    timeout: const Duration(minutes: 6),
  );
  if (aliceQr == null) throw StateError('alice_qr.json never appeared');
  final aliceOhJson = await waitForFile(
    tester,
    'alice_oh.json',
    timeout: const Duration(minutes: 6),
  );
  if (aliceOhJson == null) throw StateError('alice_oh.json never appeared');

  // Same code path as the QR scanner (join screen), minus the camera. QR v4
  // carries only the secret; Alice's OH arrives out of band and is attached
  // as the peer descriptor.
  final aliceDesc = OHDescriptor.fromJson(aliceOhJson);
  final channel = (await Channel.fromJson(
    aliceQr,
  )).copyWith(peerOhDescriptor: aliceDesc);
  final container = containerOf(tester);
  await container.read(channelRepositoryProvider).addChannel(channel);
  log('joined channel from Alice QR');

  await openChat(tester);

  // Wait until the client is actually connected to the testnet — attempting
  // an OH registration earlier just burns node-side rate-limit budget
  // (max 5 registrations/min per connection, MS02b).
  if (!await pumpUntil(
    tester,
    () =>
        container.read(connectionStatusProvider).value ==
        ConnectionStatus.connected,
    timeout: const Duration(minutes: 3),
    what: 'network connected',
  )) {
    throw StateError('client never connected to the testnet');
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
  writeAtomically('bob_qr.json', channel.toJson());
  writeAtomically('bob_oh.json', ownDesc.toJson());
  log('own QR + OH exported');

  if (!await pumpUntilVisible(
    tester,
    find.text(aliceMessage),
    timeout: const Duration(minutes: 6),
    what: 'Alice message in chat UI',
  )) {
    throw StateError('Alice message never arrived');
  }
  log('received Alice message in UI');

  await sendChatMessage(tester, bobMessage);
  writeResult(true, 'received "$aliceMessage", sent "$bobMessage"');

  // Stay alive until Alice confirms receipt — our reply may still need the
  // retry queue (up to several backoff windows) before it is deposited.
  await waitForFile(
    tester,
    'alice_result.json',
    timeout: const Duration(minutes: 14),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('duo e2e ($role)', (tester) async {
    rendezvous.createSync(recursive: true);
    log('starting app (dataHome=${Platform.environment['XDG_DATA_HOME']})');
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    try {
      if (role == 'alice') {
        await runAlice(tester);
      } else {
        await runBob(tester);
      }
    } catch (e, st) {
      writeResult(false, '$e');
      log('FAILED: $e\n$st');
      rethrow;
    } finally {
      // Keep the window visible briefly so a human can see the end state.
      final end = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
