import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:zk_vault/zk_vault.dart';
import 'package:zk_vault/src/platform_kms.dart';

void main() {
  group('ZKVault', () {
  late MockPlatformKMS mockKms;
    
    setUp(() {
      mockKms = MockPlatformKMS();
    });
    
    test('creates new vault and stores/retrieves data', () async {
    final ZKVault vault = await ZKVault.open('test_vault_1', kms: mockKms);
      
      // Store some data
    final Uint8List testData = Uint8List.fromList('Hello, World!'.codeUnits);
      await vault.set('greeting', testData);
      
      // Retrieve the data
    final Uint8List? retrievedData = await vault.get('greeting');
      
      expect(retrievedData, isNotNull);
      expect(String.fromCharCodes(retrievedData!), equals('Hello, World!'));
      
      // Clean up
      await vault.destroy();
    });
    
    test('handles non-existent keys correctly', () async {
  final ZKVault vault = await ZKVault.open('test_vault_2', kms: mockKms);
      
      // Try to get non-existent key
  final Uint8List? result = await vault.get('nonexistent');
      expect(result, isNull);
      
      // Check contains for non-existent key
  final bool exists = await vault.contains('nonexistent');
      expect(exists, isFalse);
      
      await vault.destroy();
    });
    
    test('lists keys correctly', () async {
      final ZKVault vault = await ZKVault.open('test_vault_3', kms: mockKms);
      
      // Initially should be empty
      final List<String> keysInitial = await vault.keys();
      List<String> keys = keysInitial;
      expect(keys, isEmpty);
      
  // Add some data
  await vault.set('key1', Uint8List.fromList(<int>[1, 2, 3]));
  await vault.set('key2', Uint8List.fromList(<int>[4, 5, 6]));
  await vault.set('key3', Uint8List.fromList(<int>[7, 8, 9]));
      
      // Check keys
    keys = await vault.keys();
  expect(keys.length, equals(3));
  expect(keys, containsAll(<String>['key1', 'key2', 'key3']));
      
      // Check contains
      expect(await vault.contains('key1'), isTrue);
      expect(await vault.contains('key2'), isTrue);
      expect(await vault.contains('key3'), isTrue);
      expect(await vault.contains('key4'), isFalse);
      
      await vault.destroy();
    });
    
    test('deletes keys correctly', () async {
      final ZKVault vault = await ZKVault.open('test_vault_4', kms: mockKms);
      
      // Add some data
  await vault.set('temp_key', Uint8List.fromList(<int>[1, 2, 3]));
      
      // Verify it exists
      expect(await vault.contains('temp_key'), isTrue);
      
      // Delete it
      await vault.delete('temp_key');
      
      // Verify it's gone
      expect(await vault.contains('temp_key'), isFalse);
      expect(await vault.get('temp_key'), isNull);
      
      await vault.destroy();
    });
    
    test('handles locking and unlocking', () async {
      ZKVault vault = await ZKVault.open('test_vault_5', kms: mockKms);
      
  // Store some data
  final Uint8List testData = Uint8List.fromList('Test data'.codeUnits);
      await vault.set('test', testData);
      
      // Lock the vault
      await vault.lock();
      
      // Should throw exception when trying to access locked vault
      expect(() => vault.get('test'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.set('new', testData), throwsA(isA<VaultLockedException>()));
      expect(() => vault.contains('test'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.keys(), throwsA(isA<VaultLockedException>()));
      expect(() => vault.delete('test'), throwsA(isA<VaultLockedException>()));
      
      // Reopen the vault
  vault = await ZKVault.open('test_vault_5', kms: mockKms);
      
      // Should be able to access data again
    final Uint8List? retrievedData = await vault.get('test');
    expect(retrievedData, isNotNull);
    expect(String.fromCharCodes(retrievedData!), equals('Test data'));
      
      await vault.destroy();
    });
    
    test('handles biometric requirement', () async {
      // Should work with mock KMS
      final ZKVault vault = await ZKVault.open(
        'test_vault_6',
        requireBiometric: true,
        kms: mockKms,
      );
      
      // Should be able to store and retrieve data
      final Uint8List testData = Uint8List.fromList('Biometric test'.codeUnits);
  await vault.set('bio_test', testData);
      
  final Uint8List? retrieved = await vault.get('bio_test');
  expect(retrieved, isNotNull);
  expect(String.fromCharCodes(retrieved!), equals('Biometric test'));
      
      await vault.destroy();
    });
    
    test('handles multiple vaults independently', () async {
      final ZKVault vault1 = await ZKVault.open('vault_a', kms: mockKms);
      final ZKVault vault2 = await ZKVault.open('vault_b', kms: mockKms);
      
      // Store different data in each vault
  await vault1.set('data', Uint8List.fromList('Vault A data'.codeUnits));
  await vault2.set('data', Uint8List.fromList('Vault B data'.codeUnits));
      
      // Verify each vault has its own data
  final Uint8List? data1 = await vault1.get('data');
  final Uint8List? data2 = await vault2.get('data');
      
      expect(String.fromCharCodes(data1!), equals('Vault A data'));
      expect(String.fromCharCodes(data2!), equals('Vault B data'));
      
  // Verify vaults are independent
  await vault1.set('unique_to_a', Uint8List.fromList(<int>[1]));
  await vault2.set('unique_to_b', Uint8List.fromList(<int>[2]));
      
      expect(await vault1.contains('unique_to_a'), isTrue);
      expect(await vault1.contains('unique_to_b'), isFalse);
      expect(await vault2.contains('unique_to_a'), isFalse);
      expect(await vault2.contains('unique_to_b'), isTrue);
      
      await vault1.destroy();
      await vault2.destroy();
    });
    
    test('persists data across vault instances', () async {
      // Create vault and store data
  ZKVault vault = await ZKVault.open('persistent_vault', kms: mockKms);
  final Uint8List testData = Uint8List.fromList('Persistent data'.codeUnits);
      await vault.set('persistent', testData);
      await vault.lock();
      
      // Reopen vault in new instance
      vault = await ZKVault.open('persistent_vault', kms: mockKms);
      
      // Data should still be there
  final Uint8List? retrieved = await vault.get('persistent');
  expect(retrieved, isNotNull);
  expect(String.fromCharCodes(retrieved!), equals('Persistent data'));
      
      await vault.destroy();
    });
    
    test('updates existing keys correctly', () async {
      final ZKVault vault = await ZKVault.open('update_vault', kms: mockKms);
      
  // Store initial data
  await vault.set('updatable', Uint8List.fromList('Original'.codeUnits));
      
      // Update the data
      await vault.set('updatable', Uint8List.fromList('Updated'.codeUnits));
      
      // Verify update
  final Uint8List? retrieved = await vault.get('updatable');
  expect(String.fromCharCodes(retrieved!), equals('Updated'));
      
      // Should still have only one key
  final List<String> keys = await vault.keys();
      expect(keys.length, equals(1));
      expect(keys.first, equals('updatable'));
      
      await vault.destroy();
    });
  });
  
  group('MockPlatformKMS', () {
    late MockPlatformKMS kms;
    
    setUp(() {
      kms = MockPlatformKMS();
    });
    
    test('wraps and unwraps keys correctly', () async {
      final Uint8List originalKey = Uint8List.fromList(List<int>.generate(32, (int i) => i));
      
  // Wrap the key
  final Uint8List wrapped = await kms.wrapKey(originalKey);
        
  // Unwrap the key
  final Uint8List unwrapped = await kms.unwrapKey(wrapped);
      
      // Should be identical to original
      expect(unwrapped, equals(originalKey));
    });
    
    test('handles biometric requirement', () async {
      final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int i) => i));
      
  // Wrap with biometric requirement
  final Uint8List wrapped = await kms.wrapKey(key, requireBiometric: true);
        
  // Should still be able to unwrap (mock implementation)
  final Uint8List unwrapped = await kms.unwrapKey(wrapped);
      expect(unwrapped, equals(key));
    });
    
    test('reports correct capabilities', () async {
      expect(await kms.isHardwareBacked(), isFalse);
      expect(await kms.isBiometricAvailable(), isTrue);
    });
    
    test('rejects invalid key sizes', () async {
      final Uint8List shortKey = Uint8List(16); // Too short
      final Uint8List longKey = Uint8List(64);  // Too long
      
      expect(() => kms.wrapKey(shortKey), throwsArgumentError);
      expect(() => kms.wrapKey(longKey), throwsArgumentError);
    });
    
    test('rejects invalid wrapped keys', () async {
  final Uint8List invalidWrapped = Uint8List(10); // Too short
      
      expect(() => kms.unwrapKey(invalidWrapped), throwsArgumentError);
    });
  });
  
  group('Error Handling', () {
    test('throws VaultLockedException for locked vault operations', () async {
      final ZKVault vault = await ZKVault.open('error_vault', kms: MockPlatformKMS());
      await vault.lock();
      
      expect(() => vault.get('key'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.set('key', Uint8List(1)), throwsA(isA<VaultLockedException>()));
      expect(() => vault.contains('key'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.delete('key'), throwsA(isA<VaultLockedException>()));
      expect(() => vault.keys(), throwsA(isA<VaultLockedException>()));
    });
  });
}