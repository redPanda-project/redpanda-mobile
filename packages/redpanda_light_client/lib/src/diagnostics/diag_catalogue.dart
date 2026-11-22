/// The field-diagnostics event catalogue (T180, `plans/PLAN-field-diagnostics.md`).
///
/// This file is the interface between the app, the Java nodes (T181 mirrors
/// the node-side part of the same list) and the analysis (T182). Every event
/// name and every attribute key an event may carry is declared here and only
/// here; `diag_catalogue_test.dart` keeps the emitters honest.
///
/// On the wire (Sentry structured logs) every key is prefixed with `rp.`
/// ([DiagKey.prefix]). The envelope keys in [DiagKey.envelope] are added by
/// the app's uploader, not by the emitters.
///
/// Identifiers are full and in clear text (decision 2: own devices, testnet
/// only — see `RpNetwork`): mailbox ids, message ids, session/ack tags and
/// node ids as lower-case hex, peer addresses as `host:port`. Hashes are the
/// first 16 hex characters of SHA-256 over the exact bytes named in the
/// attribute's comment, so a node can compute the same value from the bytes
/// it handles.
class DiagEvt {
  DiagEvt._();

  /// App start / lifecycle change. Keys: [DiagKey.state].
  static const appLifecycle = 'app.lifecycle';

  /// Snapshot of the device's network interfaces. Keys: [DiagKey.trigger],
  /// [DiagKey.ifaces], [DiagKey.count].
  static const netIfaces = 'net.ifaces';

  /// One connection reached "can send commands" (handshake + encryption).
  static const connUp = 'conn.up';

  /// One connection (or a dial) ended.
  static const connDown = 'conn.down';

  /// The retry backoff for one address was armed.
  static const connBackoff = 'conn.backoff';

  /// An own mailbox (OH) registration finished.
  static const ohRegister = 'oh.register';

  /// An own mailbox renewal (or re-registration of a lost one) finished.
  static const ohRenew = 'oh.renew';

  /// A Notify subscription for an own mailbox finished.
  static const ohSubscribe = 'oh.subscribe';

  /// A fetch counted as "mailbox host unreachable" towards the failover
  /// threshold (only counted while another node is connected, T21).
  static const ohUnreachable = 'oh.unreachable';

  /// An own mailbox failover started ([DiagKey.phase] `start`, with the
  /// counters and conditions that triggered it) or ended (`done`).
  static const ohFailover = 'oh.failover';

  /// One garlic packet was handed to a node (one event per route).
  static const sendAttempt = 'send.attempt';

  /// An R-ACK (routing acknowledgement from the depositing node) arrived.
  static const ackRouted = 'ack.routed';

  /// A Channel-ACK (the partner received the message) arrived.
  static const ackDelivered = 'ack.delivered';

  /// No R-ACK arrived within the ack timeout.
  static const ackTimeout = 'ack.timeout';

  /// One fetched mail item and what happened to it.
  static const fetchItem = 'fetch.item';

  /// Routine polling, summarized once per minute (individual polls never
  /// produce an event).
  static const fetchSummary = 'fetch.summary';

  /// Result of a loopback self-test (also run by the connection doctor).
  static const loopbackResult = 'loopback.result';

  /// Diagnostics were switched on, the app started with them on, or events
  /// were lost (rate limit, buffer capacity) since the last report.
  static const diagState = 'diag.state';
}

/// Attribute keys (without the `rp.` prefix).
class DiagKey {
  DiagKey._();

  /// Prefix every key carries in Sentry.
  static const prefix = 'rp.';

  // --- envelope, added by the uploader -----------------------------------

  /// Event name (one of [DiagEvt]).
  static const evt = 'evt';

  /// `app` (this repo) or `node` (T181).
  static const role = 'role';

  /// User-chosen device name.
  static const device = 'device';

  /// Network id (`RpNetwork.id`).
  static const net = 'net';

  /// Build identifier (`--dart-define=RP_BUILD=…`, `unknown` otherwise).
  static const build = 'build';

  /// Device time of the event, ms since epoch (Sentry shows only seconds).
  /// THE order key: the time is taken where the event happened (worker or
  /// main isolate), [seq] only reflects arrival order on the main isolate.
  static const tMs = 't_ms';

  /// Per-process sequence number, assigned in arrival order on the main
  /// isolate; restarts at 0 with every process.
  static const seq = 'seq';

  /// Persisted process counter, +1 per app start. ([boot], [seq]) is the
  /// unique key of an event — the de-duplication key when a batch is
  /// uploaded again after the process was killed mid-upload. Not an order
  /// key (use [tMs]).
  static const boot = 'boot';

  /// Random id of the process; tells two installs apart whose [boot]
  /// counters both restarted.
  static const bootId = 'boot_id';

  static const envelope = [
    evt,
    role,
    device,
    net,
    build,
    tMs,
    seq,
    boot,
    bootId,
  ];

  // --- event fields -------------------------------------------------------

  static const state = 'state';
  static const trigger = 'trigger';
  static const ifaces = 'ifaces';
  static const count = 'count';

  /// Peer address `host:port`.
  static const addr = 'addr';

  /// Node id (hex) as learned from our own handshake with that connection.
  static const node = 'node';
  static const reason = 'reason';
  static const ageMs = 'age_ms';
  static const dialMs = 'dial_ms';
  static const wasUp = 'was_up';
  static const intentional = 'intentional';
  static const mailboxHost = 'mailbox_host';

  /// Number of connections that can carry commands right now.
  static const peers = 'peers';
  static const retry = 'retry';

  /// Failed dials NOT reported individually (a repeat of the address's last
  /// reported failure class). On `conn.up` / `conn.down`: for that address
  /// since its last reported failure; on `fetch.summary`: all addresses in
  /// the window.
  static const dialFail = 'dial_fail';
  static const waitMs = 'wait_ms';

  static const result = 'result';

  /// Address of the node hosting a mailbox.
  static const host = 'host';

  /// Own mailbox (OH) id, hex.
  static const mailbox = 'mailbox';
  static const channel = 'channel';
  static const purpose = 'purpose';
  static const phase = 'phase';
  static const from = 'from';
  static const to = 'to';
  static const toMailbox = 'to_mailbox';
  static const failCount = 'fail_count';
  static const threshold = 'threshold';

  /// `connected` / `connecting` / `disconnected` / `absent` for the mailbox
  /// host's connection.
  static const hostState = 'host_state';
  static const hostRetry = 'host_retry';
  static const hostBackoffMs = 'host_backoff_ms';
  static const hostDialing = 'host_dialing';

  /// Connections that can carry commands and are NOT the mailbox host.
  static const altPeers = 'alt_peers';

  /// `forward`, `rgb-reply`, `loopback`, `channel-ack`.
  static const kind = 'kind';

  /// Message id, hex (the id inside the encrypted ChannelMessage).
  static const msg = 'msg';

  /// Target mailbox id (counterpart OH), hex.
  static const target = 'target';
  static const targetHost = 'target_host';

  /// Index of the route within one fan-out (0 = primary).
  static const route = 'route';

  /// Forward hop node ids in order, comma separated.
  static const hops = 'hops';

  /// Number of forward hops (an int, unlike [hops]).
  static const hopCount = 'hop_count';

  /// The node the packet was handed to.
  static const submit = 'submit';
  static const submitNode = 'submit_node';

  /// SHA-256 (first 16 hex) over the exact packet bytes handed to the node
  /// (the command-142 payload).
  static const pktHash = 'pkt_hash';
  static const ackTag = 'ack_tag';

  /// R-ACK return path hop node ids in order, comma separated.
  static const retHops = 'ret_hops';
  static const selfHop = 'self_hop';
  static const ackRequested = 'ack_requested';

  /// Session tag of the reply path (RGB) a reply travels over, hex.
  static const sessionTag = 'session_tag';
  static const status = 'status';
  static const latencyMs = 'latency_ms';
  static const waitedMs = 'waited_ms';

  /// SHA-256 (first 16 hex) over the fetched `MailItem.payload` bytes.
  static const itemHash = 'item_hash';

  /// `accepted` or `dropped`.
  static const outcome = 'outcome';

  /// Node-side receive time of a mail item, ms since epoch.
  static const recvMs = 'recv_ms';
  static const windowMs = 'window_ms';
  static const polls = 'polls';
  static const fetchOk = 'fetch_ok';
  static const fetchFail = 'fetch_fail';
  static const items = 'items';
  static const notifies = 'notifies';
  static const mailboxes = 'mailboxes';
  static const intervalS = 'interval_s';

  /// Events the worker's rate limit dropped since the last summary.
  static const diagDropped = 'diag_dropped';
  static const ok = 'ok';
  static const rttMs = 'rtt_ms';
  static const error = 'error';
  static const enabled = 'enabled';
  static const buffered = 'buffered';

  /// Events the app's ring buffer evicted (capacity) since the last report.
  static const ringDropped = 'ring_dropped';
}

/// Which keys each event may carry — the machine-readable catalogue.
class DiagCatalogue {
  DiagCatalogue._();

  static const Map<String, List<String>> events = {
    DiagEvt.appLifecycle: [DiagKey.state],
    DiagEvt.netIfaces: [DiagKey.trigger, DiagKey.ifaces, DiagKey.count],
    DiagEvt.connUp: [
      DiagKey.dialFail,
      DiagKey.addr,
      DiagKey.node,
      DiagKey.dialMs,
      DiagKey.mailboxHost,
      DiagKey.peers,
    ],
    DiagEvt.connDown: [
      DiagKey.addr,
      DiagKey.node,
      DiagKey.reason,
      DiagKey.ageMs,
      DiagKey.wasUp,
      DiagKey.intentional,
      DiagKey.mailboxHost,
      DiagKey.peers,
      DiagKey.dialFail,
    ],
    DiagEvt.connBackoff: [DiagKey.addr, DiagKey.retry, DiagKey.waitMs],
    DiagEvt.ohRegister: [
      DiagKey.result,
      DiagKey.host,
      DiagKey.mailbox,
      DiagKey.channel,
      DiagKey.purpose,
    ],
    DiagEvt.ohRenew: [
      DiagKey.result,
      DiagKey.host,
      DiagKey.mailbox,
      DiagKey.channel,
    ],
    DiagEvt.ohSubscribe: [
      DiagKey.result,
      DiagKey.host,
      DiagKey.mailbox,
      DiagKey.channel,
    ],
    DiagEvt.ohUnreachable: [
      DiagKey.mailbox,
      DiagKey.channel,
      DiagKey.host,
      DiagKey.reason,
      DiagKey.failCount,
      DiagKey.threshold,
      DiagKey.hostState,
      DiagKey.hostRetry,
      DiagKey.hostBackoffMs,
      DiagKey.hostDialing,
      DiagKey.altPeers,
    ],
    DiagEvt.ohFailover: [
      DiagKey.phase,
      DiagKey.mailbox,
      DiagKey.channel,
      DiagKey.from,
      DiagKey.to,
      DiagKey.toMailbox,
      DiagKey.result,
      DiagKey.reason,
      DiagKey.failCount,
      DiagKey.threshold,
      DiagKey.hostState,
      DiagKey.hostRetry,
      DiagKey.hostBackoffMs,
      DiagKey.hostDialing,
      DiagKey.altPeers,
      DiagKey.peers,
    ],
    DiagEvt.sendAttempt: [
      DiagKey.kind,
      DiagKey.msg,
      DiagKey.channel,
      DiagKey.target,
      DiagKey.targetHost,
      DiagKey.route,
      DiagKey.hops,
      DiagKey.submit,
      DiagKey.submitNode,
      DiagKey.pktHash,
      DiagKey.ackTag,
      DiagKey.retHops,
      DiagKey.selfHop,
      DiagKey.ackRequested,
      DiagKey.sessionTag,
    ],
    DiagEvt.ackRouted: [
      DiagKey.msg,
      DiagKey.channel,
      DiagKey.status,
      DiagKey.latencyMs,
      DiagKey.ackTag,
    ],
    DiagEvt.ackDelivered: [
      DiagKey.msg,
      DiagKey.channel,
      DiagKey.latencyMs,
      DiagKey.mailbox,
    ],
    DiagEvt.ackTimeout: [
      DiagKey.msg,
      DiagKey.channel,
      DiagKey.waitedMs,
      DiagKey.hops,
    ],
    DiagEvt.fetchItem: [
      DiagKey.mailbox,
      DiagKey.channel,
      DiagKey.itemHash,
      DiagKey.kind,
      DiagKey.outcome,
      DiagKey.reason,
      DiagKey.sessionTag,
      DiagKey.recvMs,
      DiagKey.msg,
    ],
    DiagEvt.fetchSummary: [
      DiagKey.windowMs,
      DiagKey.dialFail,
      DiagKey.polls,
      DiagKey.fetchOk,
      DiagKey.fetchFail,
      DiagKey.items,
      DiagKey.notifies,
      DiagKey.mailboxes,
      DiagKey.peers,
      DiagKey.intervalS,
      DiagKey.diagDropped,
    ],
    DiagEvt.loopbackResult: [
      DiagKey.channel,
      DiagKey.ok,
      DiagKey.rttMs,
      DiagKey.hopCount,
      DiagKey.error,
    ],
    DiagEvt.diagState: [
      DiagKey.enabled,
      DiagKey.buffered,
      DiagKey.diagDropped,
      DiagKey.ringDropped,
    ],
  };

  /// `fetch.item` kinds.
  static const itemKinds = [
    'message',
    'r-ack',
    'channel-ack',
    'lookup-answer',
    'loopback',
    'oh-update',
    'group-handshake',
    'group',
    'unknown',
  ];
}
