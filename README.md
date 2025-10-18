# ZK Vault

A Zero-Knowledge style secure storage package for Flutter/Dart applications with platform KMS integration.

## Features

- **AES-256-GCM Encryption**: All data is encrypted using industry-standard AES-256-GCM
- **Platform KMS Integration**: Master keys are protected by platform Key Management Services (Android Keystore, iOS Secure Enclave)
- **Biometric Authentication**: Optional biometric requirement for vault access
- **Zero-Knowledge Architecture**: Master keys never stored in plaintext on disk
- **Atomic Operations**: All storage operations are atomic with integrity checking
- **Memory Security**: Secure key clearing and memory management

## Quick Start

```dart
import 'package:zk_vault/zk_vault.dart';

// Open or create a vault
final vault = await ZKVault.open(
  'my_secure_vault',
  requireBiometric: true,
);

// Store encrypted data
final secretData = Uint8List.fromList('My secret message'.codeUnits);
await vault.set('secret_key', secretData);

// Retrieve and decrypt data
final retrievedData = await vault.get('secret_key');
if (retrievedData != null) {
  final message = String.fromCharCodes(retrievedData);
  print('Retrieved: $message');
}

// List all keys
final keys = await vault.keys();
print('Stored keys: $keys');

// Lock the vault (clears master key from memory)
await vault.lock();

// Destroy the vault completely
await vault.destroy();
```

## API Reference

### ZKVault Methods

- `static Future<ZKVault> open(String vaultId, {bool requireBiometric = false})` - Opens or creates a vault
- `Future<void> set(String key, Uint8List value)` - Stores encrypted data
- `Future<Uint8List?> get(String key)` - Retrieves and decrypts data
- `Future<bool> contains(String key)` - Checks if key exists
- `Future<void> delete(String key)` - Deletes a key-value pair
- `Future<List<String>> keys()` - Lists all stored keys
- `Future<void> lock()` - Locks vault and clears master key from memory
- `Future<void> destroy()` - Permanently destroys vault and all data

### Exceptions

- `VaultLockedException` - Thrown when accessing a locked vault
- `IntegrityException` - Thrown when data integrity checks fail
- `SecureEnclaveUnavailableException` - Thrown when hardware security is unavailable

## Security Features

- **Master Key Protection**: Generated master keys are wrapped using platform KMS
- **Hardware-Backed Security**: Leverages Android Keystore and iOS Secure Enclave when available
- **Integrity Checking**: All stored data includes integrity verification
- **Memory Security**: Master keys are zeroed out when vault is locked
- **Atomic Storage**: All operations use atomic file writes to prevent corruption

## Development

This package includes a mock KMS implementation for testing and development. In production, the platform KMS will be implemented using native Android and iOS code.

## Native integration & next steps

- Implement platform-specific `PlatformKMS` using Android Keystore and iOS Secure Enclave.
- Replace `MockPlatformKMS` wiring in plugin registration to use the native implementation when available.
- Storage location: the package now prefers the platform application-support directory (via `path_provider`) for persistent vault files and will automatically fall back to the system temporary directory when an application directory is not available (for example in some pure-Dart or test environments). The vault data is persisted as two JSON files inside a folder named after the vault id: `vault.meta.json` (vault metadata, wrapped master key) and `vault.db.json` (encrypted records).
  - To control where files are stored, open the `VaultStorage.create()` implementation in `lib/src/storage.dart` and adapt the base path selection logic to suit your application's needs.
- Add integration tests that exercise real biometric/key-store flows on device or emulator.

Quick notes:

- The public API surface is `ZKVault` in `lib/zk_vault.dart`.
- Native code should expose two operations: `wrapKey` and `unwrapKey` (opaque wrapped blob returned/stored in `vault.meta.json`).
- Ensure native code never logs raw keys or returns secret material to non-secure contexts.

Run example (Flutter):

```bash
# from package root
flutter pub get
flutter run -t example/lib/main.dart
```

## License

This project is licensed under the MIT License.

## Publishing

To publish this package to pub.dev:

1. Update the `version` field in `pubspec.yaml` following semver.
2. Ensure `pubspec.yaml` has a valid `homepage` and `repository` fields.
3. Run `dart pub publish --dry-run` to validate the package.
4. If the dry-run succeeds, run `dart pub publish` and follow the interactive prompts.

Notes:
- Remove any debug-only code and the `MockPlatformKMS` usage from production examples.
- Implement platform-native `PlatformKMS` before publishing if you need hardware-backed KMS.