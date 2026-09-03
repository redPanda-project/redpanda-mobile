# RedPanda Light Client

A lightweight, P2P networking library for Dart/Flutter, implementing the RedPanda protocol. This client is optimized for mobile environments, providing essential connectivity and messaging features without the overhead of a full node.

## 📦 Features

- **Decentralized Communication**: Direct TCP socket connections between peers.
- **Protocol Buffers**: Type-safe command serialization using Protobuf.
- **End-to-End Encryption**: 
  - ECC Key Pair generation.
  - Diffie-Hellman Shared Secret derivation.
  - Robust handshake state machine with handling for out-of-order encryption activation.
- **Smart Peer Discovery**: Kademlia-inspired peer exchange (`SEND_PEERLIST`).
- **Resilient Connection Management**:
  - Background connection/reconnection routine.
  - DNS-based peer deduplication to prevent redundant socket connections.
  - Support for multiple seed nodes.

## 🛠 Usage

### Initialization

```dart
final keys = KeyPair.generate();
final selfNodeId = NodeId.fromPublicKey(keys);

final client = RedPandaLightClient(
  selfNodeId: selfNodeId,
  selfKeys: keys,
  seeds: ['seed1.redpanda.im:59558', 'seed2.redpanda.im:59558'],
);

await client.connect();
```

### Listening for Status

```dart
client.connectionStatus.listen((status) {
  print('Connection Status: $status');
});

client.peerCountStream.listen((count) {
  print('Connected Peers: $count');
});
```

### Adding Peers

```dart
await client.addPeer('another-node.com:59558');
```

## 🏗 Architecture

The client follows a facade-based architecture:
- `RedPandaClient`: The public interface.
- `RedPandaLightClient`: The main implementation managing the peer pool.
- `ActivePeer`: Handles individual TCP connections, framing, and encryption status.
- `EncryptionManager`: Manages cryptographic handshakes and packet encryption/decryption.

## 🧬 Protobuf Schemas & Codegen

The wire schemas are **owned by the backend**, `redPanda-project/redpandaj`
(`src/main/proto/{commands,outbound}.proto`). The files in `protos/` here are
vendored copies and `lib/src/generated/` is machine-generated from them — both
are committed so that CI and `flutter pub get` never need `protoc`.

**Never hand-edit `protos/*.proto` or `lib/src/generated/*.pb*.dart.`** A
hand-maintained copy is exactly how the old `commands.proto` ended up three
milestones behind the generated code it was supposed to describe (DDD review
2026-08-31 §6 P0, task T107).

| File | Meaning |
|---|---|
| `protos/*.proto` | verbatim copies of the redpandaj schemas |
| `protos/UPSTREAM.lock` | pinned redpandaj commit + sha256 of each vendored file |
| `lib/src/generated/*.pb*.dart` | `protoc --dart_out` output, formatted with the pinned Dart |

### Syncing from redpandaj

```bash
tool/sync_protos.sh                    # local checkout: --source, $REDPANDAJ_DIR, ../redpandaj
tool/sync_protos.sh --ref v1.2.3       # or straight from GitHub at a tag/branch/commit
tool/sync_protos.sh --check            # verify only (used by tool/pre_push_validation.sh)
```

### Regenerating the Dart code

```bash
export PATH=~/tools/flutter/bin:$PATH   # dart/flutter
tool/generate_protos.sh                 # protoc from $PROTOC, PATH, or ~/tools/protoc
```

`protoc_plugin` is a `dev_dependency` of this package, so the generator version
is pinned by `pubspec.lock`; only `protoc` itself has to be installed. Commit
the protos, `UPSTREAM.lock` and the regenerated Dart in one change.

### Drift guard

* `test/unit/vendored_protos_test.dart` — offline: vendored protos still match
  `UPSTREAM.lock`, every proto has generated Dart, the lock pins a commit SHA.
* `tool/sync_protos.sh --check` — additionally diffs against live upstream when
  a redpandaj checkout or the GitHub API is reachable.

## 🔬 Testing

The package includes a comprehensive unit and E2E test suite. E2E tests can interact with a local Java-based RedPanda full node launcher.

```bash
flutter test
```

---
Part of the [RedPanda ecosystem](https://github.com/redPanda-project).
