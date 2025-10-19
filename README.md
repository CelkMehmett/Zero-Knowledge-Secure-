# ZK Vault

A Zero-Knowledge style secure storage package for Flutter/Dart applications with hardware-backed platform KMS integration.

## Features

- **AES-256-GCM Encryption**: All data is encrypted using industry-standard AES-256-GCM
- **Hardware-Backed Security**: Production-ready integration with Android Keystore and iOS Secure Enclave
- **Biometric Authentication**: Optional biometric requirement for vault access with platform-native prompts
- **StrongBox Support**: Automatic StrongBox utilization on supported Android devices (API 28+)
- **Zero-Knowledge Architecture**: Master keys never stored in plaintext on disk
- **Atomic Operations**: All storage operations are atomic with integrity checking
- **Memory Security**: Secure key clearing and memory management

## Platform Support

| Platform | Hardware KMS | Biometric Auth | Min Version |
|----------|--------------|----------------|-------------|
| Android  | ✅ Keystore + StrongBox | ✅ BiometricPrompt | API 21+ |
| iOS      | ✅ Secure Enclave | ✅ Touch/Face ID | iOS 11+ |
| Mock     | ⚠️ Testing only | ✅ Simulated | Any |

## Quick Start

```dart
import 'package:zk_vault/zk_vault.dart';

// Use hardware-backed KMS (recommended for production)
final vault = await ZKVault.open(
  'my_secure_vault',
  requireBiometric: true,
  kms: NativePlatformKMS(), // Uses Android Keystore or iOS Secure Enclave
);

// Store encrypted data
final secretData = Uint8List.fromList('My secret message'.codeUnits);
await vault.set('secret_key', secretData);

// Retrieve data (may prompt for biometric auth)
final retrievedData = await vault.get('secret_key');
if (retrievedData != null) {
  final message = String.fromCharCodes(retrievedData);
  print('Retrieved: $message');
}

// Check hardware capabilities
final kms = NativePlatformKMS();
print('Hardware-backed: ${await kms.isHardwareBacked()}');
print('Biometric available: ${await kms.isBiometricAvailable()}');

// Lock and destroy
await vault.lock();
await vault.destroy();
```

## Setup

### Android Setup

1. **Add biometric dependency** to `android/app/build.gradle`:
```gradle
dependencies {
    implementation 'androidx.biometric:biometric:1.2.0'
}
```

2. **Update minimum SDK** in `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 21  // Required for AndroidKeyStore
    }
}
```

3. **Add biometric permission** to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.USE_FINGERPRINT" />
```

### iOS Setup

1. **Add biometric usage description** to `ios/Runner/Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>This app uses Face ID to secure your vault data</string>
```

2. **Set minimum deployment target** in `ios/Runner.xcodeproj` or `ios/Podfile`:
```ruby
# ios/Podfile
platform :ios, '11.0'
```

3. **Enable Keychain Sharing** (if needed) in Xcode project capabilities.

## API Reference

### ZKVault Methods

- `static Future<ZKVault> open(String vaultId, {bool requireBiometric = false, PlatformKMS? kms})` - Opens or creates a vault
- `Future<void> set(String key, Uint8List value)` - Stores encrypted data
- `Future<Uint8List?> get(String key)` - Retrieves and decrypts data
- `Future<bool> contains(String key)` - Checks if key exists
- `Future<void> delete(String key)` - Deletes a key-value pair
- `Future<List<String>> keys()` - Lists all stored keys
- `Future<void> lock()` - Locks vault and clears master key from memory
- `Future<void> destroy()` - Permanently destroys vault and all data

### PlatformKMS Implementations

#### NativePlatformKMS (Production)
```dart
final kms = NativePlatformKMS();
final vault = await ZKVault.open('vault_id', kms: kms, requireBiometric: true);
```

#### MockPlatformKMS (Testing)
```dart
final kms = MockPlatformKMS();
final vault = await ZKVault.open('test_vault', kms: kms);
```

### Exceptions

- `VaultLockedException` - Thrown when accessing a locked vault
- `IntegrityException` - Thrown when data integrity checks fail
- `SecureEnclaveUnavailableException` - Thrown when hardware security is unavailable

## Security Implementation

### Android Security Features

- **KeyStore Integration**: RSA-2048 keys generated in AndroidKeyStore
- **StrongBox Support**: Automatic utilization on supported devices (Pixel 3+, etc.)
- **Biometric Authentication**: BiometricPrompt with hardware-bound Cipher operations
- **User Authentication**: Keys require biometric unlock for each use when `requireBiometric=true`

### iOS Security Features

- **Secure Enclave**: ECDSA P-256 keys generated directly in Secure Enclave
- **ECIES Encryption**: Elliptic Curve Integrated Encryption Scheme for key wrapping
- **Biometric Protection**: SecAccessControl with `.biometryCurrentSet` enforcement
- **Hardware Isolation**: Keys never leave Secure Enclave boundaries

### Storage Security

- **Wrapped Master Keys**: Platform KMS encrypts 256-bit AES master keys
- **Atomic File Operations**: Temporary file + rename prevents corruption
- **Application Sandbox**: Files stored in app-specific directories via `path_provider`
- **Memory Clearing**: Master keys zeroed on lock/destroy operations

## Testing

### Unit Tests
```bash
flutter test
```

### Device Integration Tests

#### Android Emulator
```bash
# Enable fingerprint on emulator
adb -e emu finger touch 1

# Run example app
flutter run example/lib/main.dart
```

#### iOS Simulator
```bash
# Enable biometrics in simulator
# Simulator > Features > Face ID / Touch ID > Enrolled

flutter run example/lib/main.dart
```

#### Physical Device Testing
```bash
# Ensure biometric enrollment on device
flutter run example/lib/main.dart

# Check logs for native KMS behavior
flutter logs
```

## Migration from Mock to Native KMS

### Step 1: Update Dependencies
```yaml
# pubspec.yaml - already included
dependencies:
  zk_vault: ^0.1.1
```

### Step 2: Replace KMS Implementation
```dart
// Before (mock)
final vault = await ZKVault.open('vault_id');

// After (native)
final vault = await ZKVault.open(
  'vault_id', 
  kms: NativePlatformKMS(),
  requireBiometric: true,
);
```

### Step 3: Handle Exceptions
```dart
try {
  final vault = await ZKVault.open('vault_id', kms: NativePlatformKMS());
} on SecureEnclaveUnavailableException {
  // Fallback to mock KMS or show error
  final vault = await ZKVault.open('vault_id', kms: MockPlatformKMS());
}
```

## Troubleshooting

### Android Issues

**"Biometric authentication failed"**
- Ensure device has enrolled fingerprint/face
- Check `minSdkVersion >= 21` in build.gradle
- Verify `androidx.biometric` dependency

**"StrongBox not available"**
- Normal on older devices (< API 28)
- Check logs: "StrongBox not available for zk_vault_master_key"

### iOS Issues

**"Secure Enclave unavailable"**
- Ensure device has Secure Enclave (iPhone 5s+, not simulator)
- Check deployment target >= iOS 11.0
- Verify app signing and entitlements

**"Face ID permission denied"**
- Add `NSFaceIDUsageDescription` to Info.plist
- Re-run app after adding description

### Debug Logging

**Android (Logcat)**
```bash
adb logcat | grep ZkVaultKmsPlugin
```

**iOS (Console)**
```bash
# Check device logs in Xcode Console or
flutter logs --verbose
```

## Example App

```bash
cd example
flutter run
```

The example app demonstrates:
- Native KMS vs Mock KMS comparison
- Biometric authentication flows
- Hardware capability detection
- Error handling patterns

## Publishing Notes

This package is production-ready with:
- ✅ Full native KMS implementation (Android + iOS)
- ✅ Comprehensive test coverage
- ✅ Hardware-backed security
- ✅ Biometric authentication
- ✅ Documentation and examples

Published at: https://pub.dev/packages/zk_vault

## License

MIT License - see LICENSE file for details.