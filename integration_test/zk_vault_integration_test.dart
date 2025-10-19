import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zk_vault/zk_vault.dart';
import 'package:flutter/foundation.dart';

/// Integration tests for ZK Vault with native KMS.
/// 
/// These tests require a physical device or emulator with biometric capabilities.
/// 
/// To run these tests:
/// 1. Connect a device or start an emulator
/// 2. For Android emulator: `adb -e emu finger touch 1` to simulate fingerprint
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('ZK Vault Native KMS Integration Tests', () {
    late PlatformKMS nativeKms;
    late PlatformKMS mockKms;

    setUpAll(() {
      nativeKms = NativePlatformKMS();
      mockKms = MockPlatformKMS();
    });

    testWidgets('Native KMS capabilities detection', (WidgetTester tester) async {
      // Test native KMS capabilities
      try {
        final bool hardwareBacked = await nativeKms.isHardwareBacked();
        final bool biometricAvailable = await nativeKms.isBiometricAvailable();

        debugPrint('Native KMS - Hardware backed: $hardwareBacked');
        debugPrint('Native KMS - Biometric available: $biometricAvailable');

        // On a real device, at least one should be true
        // On simulator/emulator, results may vary
        expect(hardwareBacked || biometricAvailable, isTrue,
            reason: 'Device should support either hardware keys or biometrics');
      } on SecureEnclaveUnavailableException {
        debugPrint('Native KMS not available on this device - test skipped');
        // This is acceptable on some test environments
      }
    });

    testWidgets('Mock KMS always reports capabilities', (WidgetTester tester) async {
      final bool hardwareBacked = await mockKms.isHardwareBacked();
      final bool biometricAvailable = await mockKms.isBiometricAvailable();
      
      expect(hardwareBacked, isFalse); // Mock is not hardware-backed
      expect(biometricAvailable, isTrue); // Mock simulates biometric availability
    });

    testWidgets('Vault operations with Mock KMS', (WidgetTester tester) async {
      // Test basic vault operations with mock KMS (should always work)
      final ZKVault vault = await ZKVault.open(
        'integration_test_vault_mock',
        requireBiometric: true,
        kms: mockKms,
      );

      // Store and retrieve data
  final Uint8List testData = Uint8List.fromList('Integration test data'.codeUnits);
      await vault.set('test_key', testData);

  final Uint8List? retrievedData = await vault.get('test_key');
  expect(retrievedData, isNotNull);
  expect(String.fromCharCodes(retrievedData!), equals('Integration test data'));

      // Clean up
      await vault.destroy();
    });

    testWidgets('Vault operations with Native KMS (if available)', (WidgetTester tester) async {
      try {
        // Attempt to use native KMS
        final ZKVault vault = await ZKVault.open(
          'integration_test_vault_native',
          requireBiometric: false, // Set to false to avoid biometric prompts in automated tests
          kms: nativeKms,
        );

        // Store and retrieve data
  final Uint8List testData = Uint8List.fromList('Native KMS test data'.codeUnits);
  await vault.set('native_test_key', testData);

  final Uint8List? retrievedData = await vault.get('native_test_key');
  expect(retrievedData, isNotNull);
  expect(String.fromCharCodes(retrievedData!), equals('Native KMS test data'));

        // Test hardware backing detection
  final bool isHardwareBacked = await nativeKms.isHardwareBacked();
  debugPrint('Vault using hardware-backed KMS: $isHardwareBacked');

        // Clean up
        await vault.destroy();
        
  debugPrint('Native KMS integration test completed successfully');
      } on SecureEnclaveUnavailableException {
        debugPrint('Native KMS not available - test skipped (this is normal on simulator)');
        // Skip this test on platforms where native KMS isn't available
      }
    });

    testWidgets('Biometric vault creation (manual test)', (WidgetTester tester) async {
      // This test requires manual interaction and should be run on a real device
      // It's disabled by default to avoid blocking automated tests
      
      // To enable this test, change skip to false and run on a device with enrolled biometrics
    }, skip: true);
    
    testWidgets('Error handling for invalid operations', (WidgetTester tester) async {
      final ZKVault vault = await ZKVault.open(
        'error_test_vault',
        kms: mockKms,
      );

      // Test accessing non-existent key
  final Uint8List? nonExistent = await vault.get('non_existent_key');
      expect(nonExistent, isNull);

      // Test operations on locked vault
      await vault.lock();
      
      expect(() => vault.get('any_key'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.set('any_key', Uint8List(1)), throwsA(isA<VaultLockedException>()));
      expect(() => vault.contains('any_key'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.delete('any_key'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.keys(), throwsA(isA<VaultLockedException>()));
    });

    testWidgets('Vault persistence across instances', (WidgetTester tester) async {
  const String vaultId = 'persistence_test_vault';
  const String testKey = 'persistent_data';
  final Uint8List testData = Uint8List.fromList('This data should persist'.codeUnits);

      // Create vault and store data
  ZKVault vault = await ZKVault.open(vaultId, kms: mockKms);
      await vault.set(testKey, testData);
      await vault.lock();

      // Reopen vault and verify data persists
  vault = await ZKVault.open(vaultId, kms: mockKms);
  final Uint8List? retrievedData = await vault.get(testKey);

  expect(retrievedData, isNotNull);
  expect(String.fromCharCodes(retrievedData!), equals('This data should persist'));

      // Clean up
      await vault.destroy();
    });
  });
}