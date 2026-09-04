import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:hex/hex.dart';
import 'package:redpanda/database/database.dart';
import 'package:redpanda_light_client/redpanda_light_client.dart';

/// The counterpart mailbox columns of [Channels] are written as ONE unit.
///
/// `counterpartOhSet` holds the full known mailbox set of the counterpart; the
/// single-target `counterpartOh{Endpoint,Id,PublicKey}` columns mirror its
/// FIRST entry (see the column docs in `database.dart`). Two call sites used to
/// fill them independently — `MessageSyncService.handleCounterpartOhUpdate`
/// wrote all four, `DriftChannelRepository.addChannel` only the primary three —
/// so the primary could stop being the head of the set (TD118). Every writer
/// now derives all four columns here.
///
/// An empty [descriptors] yields an all-absent companion: an UPDATE then leaves
/// the columns as they are (a re-scanned QR code carries no mailbox data and
/// must not clear what a rendezvous lookup already found), an INSERT leaves
/// them NULL.
ChannelsCompanion counterpartOhColumns(List<OHDescriptor> descriptors) {
  if (descriptors.isEmpty) return const ChannelsCompanion();
  final primary = descriptors.first;
  return ChannelsCompanion(
    counterpartOhEndpoint: Value(primary.serverEndpoint),
    counterpartOhId: Value(HEX.encode(primary.handleId)),
    counterpartOhPublicKey: Value(HEX.encode(primary.authPublicKey)),
    counterpartOhSet: Value(
      jsonEncode([for (final d in descriptors) d.toJsonMap()]),
    ),
  );
}

/// Decodes the persisted counterpart OH set JSON into descriptors, or null when
/// absent/malformed (the client then falls back to the primary OH columns).
List<OHDescriptor>? decodeCounterpartOhSet(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return null;
    final out = [
      for (final entry in decoded)
        OHDescriptor.fromJsonMap(entry as Map<String, dynamic>),
    ];
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

/// [primary] promoted to the head of [existing], which is the shape
/// [counterpartOhColumns] expects. Mailboxes already known stay in the set —
/// they are only ever added, never dropped by a re-scan — but the one the QR
/// code names becomes the primary.
List<OHDescriptor> promoteToPrimary(
  OHDescriptor primary,
  List<OHDescriptor>? existing,
) {
  final primaryId = HEX.encode(primary.handleId);
  return [
    primary,
    if (existing != null)
      for (final d in existing)
        if (HEX.encode(d.handleId) != primaryId) d,
  ];
}
