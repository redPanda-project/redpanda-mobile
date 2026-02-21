# RedPanda Mobile

RedPanda Mobile is a decentralized, peer-to-peer (P2P) messaging application built with Flutter. It implements the RedPanda protocol, enabling secure, end-to-end encrypted communication without relying on central servers. The app runs on **Android, iOS, Web, Linux, macOS, and Windows**.

## 🚀 Project Overview

The project consists of a Flutter application and a specialized `redpanda_light_client` Dart package designed for mobile and desktop environments. It communicates with the RedPanda network through a custom TCP-based protocol, featuring Kademlia-inspired peer discovery and end-to-end encryption.

### Key Components

- **Mobile App (`/lib`)**: The Flutter frontend with a modern chat UI, navigation, and state management.
- **Light Client (`/packages/redpanda_light_client`)**: A standalone Dart package that handles the P2P networking, protocol framing, and cryptographic operations. See [its own README](packages/redpanda_light_client/README.md) for details.
- **Protocol Buffer Definitions (`/packages/redpanda_light_client/protos`)**: Standardized message formats for cross-platform compatibility with other RedPanda nodes (e.g., the [Java Full Node](https://github.com/redPanda-project/redpandaj)).

## 📁 Project Structure

```
redpanda-mobile/
├── lib/
│   ├── main.dart                  # App entry point
│   ├── router.dart                # GoRouter navigation
│   ├── database/                  # Drift (SQLite) local database
│   ├── repositories/              # Data-access layer
│   ├── services/                  # Peer persistence service
│   ├── screens/                   # UI screens (home, chat, channels, onboarding, debug)
│   └── shared/                    # Riverpod providers & reusable widgets
├── packages/
│   └── redpanda_light_client/     # P2P networking & crypto library
├── integration_test/              # Flutter integration tests
├── assets/                        # Images & static resources
└── android/ ios/ web/ linux/ macos/ windows/   # Platform runners
```

## ✨ Features

- [x] **Protobuf Integration**: Fully functional command serialization/deserialization.
- [x] **End-to-End Encryption**: ECC-based handshake with Diffie-Hellman shared secret derivation (using `pointycastle`).
- [x] **Protocol Robustness**: Resolved race conditions in encryption activation; DNS/IP-based connection deduplication.
- [x] **Peer Discovery**: Automatic peer list exchange with Kademlia-inspired routing.
- [x] **Isolate-Based Client**: Key generation and networking run in a background isolate, keeping the UI responsive.
- [x] **Local Database**: Message and peer persistence via Drift (SQLite).
- [x] **Channel Management**: Create and join channels; share channel invites via QR codes.
- [x] **Real-Time UI**: Connection status badge with live peer count tracking.
- [x] **Onboarding Flow**: First-launch onboarding screen for new users.
- [x] **Multi-Platform**: Verified on Android, iOS, Web, Linux, macOS, and Windows.

## 🛠 Tech Stack

| Layer              | Technology                          |
|--------------------|-------------------------------------|
| UI Framework       | Flutter / Dart                      |
| State Management   | Riverpod                            |
| Navigation         | GoRouter                            |
| Local Database     | Drift (SQLite)                      |
| Networking         | TCP Sockets (`dart:io`)             |
| Cryptography       | PointyCastle (ECC, SHA-256)         |
| Serialization      | Protocol Buffers (Protobuf)         |
| QR Codes           | qr_flutter / mobile_scanner         |
| Architecture       | Import Lint & arch_test enforcement |

## 📦 Getting Started

### Prerequisites

- Flutter SDK (latest stable)
- Java 21+ (only if running the reference full node locally)
- Protobuf compiler (`protoc`) and Dart plugin (only for protocol changes)

### Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/redPanda-project/redpanda-mobile.git
   cd redpanda-mobile
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   cd packages/redpanda_light_client
   flutter pub get
   cd ../..
   ```

3. **Run code generation** (Drift database models):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**:
   ```bash
   flutter run
   ```

## 🧪 Testing

### Light Client – Unit & E2E Tests

```bash
cd packages/redpanda_light_client
flutter test
```

The light client includes tests for encryption handshakes, peer deduplication, connection logic, channel operations, backoff strategies, and full end-to-end client flows (E2E tests can interact with a local Java-based RedPanda full node).

### Main App – Integration Tests

```bash
flutter test integration_test
```

## ⚙️ CI/CD

A GitHub Actions workflow (`.github/workflows/flutter_ci.yml`) runs on every push to `main`/`develop` and on pull requests. It performs:

1. **Light Client**: dependency install → format check → static analysis → unit/e2e tests.
2. **Main App**: dependency install → format check → code generation → static analysis → tests.

## 🗺 Roadmap

- [x] Private Channel Implementation (QR-based key sharing).
- [x] Message Persistence (Local Database via Drift).
- [ ] Multi-device synchronization.
- [ ] Enhanced Kademlia routing for mobile peers.
- [ ] Push notifications for background message delivery.
- [ ] Group channels with multi-party encryption.

## 🤝 Contributing

1. Fork the repository.
2. Create a feature branch from `develop`.
3. Run `dart format .` and `flutter analyze` before submitting.
4. Open a pull request targeting `develop`.

---
**[RedPanda Project](https://github.com/redPanda-project)** – *Secure, Private, Decentralized.*
