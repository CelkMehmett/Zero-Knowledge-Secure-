import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:synchronized/synchronized.dart';

import 'exceptions.dart';
import 'platform_kms.dart';
import 'storage.dart';

/// Zero-Knowledge style secure vault for storing encrypted data.
/// 
/// This vault encrypts all data using AES-256-GCM with a master key that is
/// protected by the platform's Key Management Service (KMS). The master key
/// is never stored in plaintext on disk.
class ZKVault {
  static const int _masterKeySize = 32;
  static const int _nonceSize = 12;
  
  final String _vaultId;
  final VaultStorage _storage;
  final PlatformKMS _kms;
  final Lock _lock = Lock();
  
  Uint8List? _masterKey;
  bool _requiresBiometric = false;
  
  ZKVault._(this._vaultId, this._storage, this._kms);
  
  /// Opens or creates a vault with the specified ID.
  /// 
  /// If [requireBiometric] is true, accessing the vault will require biometric
  /// authentication (if supported by the platform).
  /// 
  /// Throws [SecureEnclaveUnavailableException] if biometric is required but
  /// not available.
  static Future<ZKVault> open(
    String vaultId, {
    bool requireBiometric = false,
    PlatformKMS? kms,
  }) async {
  final VaultStorage storage = await VaultStorage.create(vaultId);
  final PlatformKMS platformKms = kms ?? MockPlatformKMS();
    
    if (requireBiometric && !await platformKms.isBiometricAvailable()) {
      throw const SecureEnclaveUnavailableException(
        'Biometric authentication is not available'
      );
    }
    
  final ZKVault vault = ZKVault._(vaultId, storage, platformKms);
    vault._requiresBiometric = requireBiometric;
    
    await vault._initialize();
    return vault;
  }
  
  /// Stores a value in the vault under the specified key.
  /// 
  /// The value is encrypted using AES-256-GCM before storage.
  /// Throws [VaultLockedException] if the vault is locked.
  Future<void> set(String key, Uint8List value) async {
    return _lock.synchronized(() async {
      _ensureUnlocked();
      
  final Map<String, dynamic> records = await _storage.loadRecords();
  final EncryptedRecord encryptedRecord = await _encryptValue(value);
      
      records[key] = encryptedRecord.toJson();
      await _storage.saveRecords(records);
    });
  }
  
  /// Retrieves a value from the vault by key.
  /// 
  /// Returns null if the key doesn't exist.
  /// Throws [VaultLockedException] if the vault is locked.
  /// Throws [IntegrityException] if the stored data is corrupted.
  Future<Uint8List?> get(String key) async {
    return _lock.synchronized(() async {
      _ensureUnlocked();
      
  final Map<String, dynamic> records = await _storage.loadRecords();
  final Object? recordData = records[key];
      
      if (recordData == null) {
        return null;
      }
      
      try {
        final EncryptedRecord record = EncryptedRecord.fromJson(recordData as Map<String, dynamic>);
        return await _decryptValue(record);
      } catch (e) {
        throw IntegrityException('Failed to decrypt value for key "$key": $e');
      }
    });
  }
  
  /// Checks if a key exists in the vault.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  Future<bool> contains(String key) async {
    return _lock.synchronized(() async {
      _ensureUnlocked();
      
  final Map<String, dynamic> records = await _storage.loadRecords();
      return records.containsKey(key);
    });
  }
  
  /// Deletes a key-value pair from the vault.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  Future<void> delete(String key) async {
    return _lock.synchronized(() async {
      _ensureUnlocked();
      
  final Map<String, dynamic> records = await _storage.loadRecords();
      records.remove(key);
      await _storage.saveRecords(records);
    });
  }
  
  /// Returns all keys stored in the vault.
  /// 
  /// Throws [VaultLockedException] if the vault is locked.
  Future<List<String>> keys() async {
    return _lock.synchronized(() async {
      _ensureUnlocked();
      
  final Map<String, dynamic> records = await _storage.loadRecords();
  final List<String> keys = records.keys.toList();
  return keys;
    });
  }
  
  /// Locks the vault by clearing the master key from memory.
  /// 
  /// After locking, the vault must be reopened to access data.
  Future<void> lock() async {
    return _lock.synchronized(() async {
      if (_masterKey != null) {
        // Zero out the master key in memory
        _masterKey!.fillRange(0, _masterKey!.length, 0);
        _masterKey = null;
      }
    });
  }
  
  /// Completely destroys the vault and all its data.
  /// 
  /// This operation is irreversible.
  Future<void> destroy() async {
    return _lock.synchronized(() async {
      // Zero master key material directly while holding the lock to avoid
      // re-entrancy deadlock caused by calling `lock()` which also acquires
      // the same [_lock].
      if (_masterKey != null) {
        _masterKey!.fillRange(0, _masterKey!.length, 0);
        _masterKey = null;
      }

      await _storage.destroy();
    });
  }
  
  /// Placeholder for migrating data from other storage systems.
  /// 
  /// This method should be implemented based on specific migration requirements.
  Future<void> migrateFromOtherStorage() async {
    // TODO: Implement migration logic based on requirements
    throw UnimplementedError('Migration not yet implemented');
  }
  
  /// Initializes the vault, creating master key if needed.
  Future<void> _initialize() async {
    final Map<String, dynamic>? metadata = await _storage.loadMetadata();
    
    if (metadata == null) {
      // Create new vault
      await _createNewVault();
    } else {
      // Load existing vault
      await _loadExistingVault(metadata);
    }
  }
  
  /// Creates a new vault with a fresh master key.
  Future<void> _createNewVault() async {
    // Generate new master key
    final Random random = Random.secure();
    _masterKey = Uint8List(_masterKeySize);
    for (int i = 0; i < _masterKeySize; i++) {
      _masterKey![i] = random.nextInt(256);
    }
    
    // Wrap master key with platform KMS
    final Uint8List wrappedKey = await _kms.wrapKey(
      _masterKey!,
      requireBiometric: _requiresBiometric,
    );
    
    // Save metadata
    final Map<String, Object> metadata = <String, Object>{
      'version': 1,
      'vaultId': _vaultId,
      'wrappedMasterKey': wrappedKey.toList(),
      'requiresBiometric': _requiresBiometric,
      'createdAt': DateTime.now().toIso8601String(),
      'isHardwareBacked': await _kms.isHardwareBacked(),
    };
    
    await _storage.saveMetadata(metadata);
    
    // Initialize empty records
    await _storage.saveRecords(<String, dynamic>{});
  }
  
  /// Loads an existing vault and unwraps the master key.
  Future<void> _loadExistingVault(Map<String, dynamic> metadata) async {
    final Object? wrappedKeyList = metadata['wrappedMasterKey'];
    if (wrappedKeyList == null) {
      throw const IntegrityException('Vault metadata is corrupted: missing wrapped key');
    }
    
  // JSON decode produces List<dynamic>. Safely convert entries to int.
  final List<dynamic> rawList = wrappedKeyList as List<dynamic>;
  final List<int> intList = rawList.map((dynamic e) => (e as num).toInt()).toList();
  final Uint8List wrappedKey = Uint8List.fromList(intList);
    
    try {
      _masterKey = await _kms.unwrapKey(wrappedKey);
    } catch (e) {
      throw IntegrityException('Failed to unwrap master key: $e');
    }
    
    // Verify master key size
    if (_masterKey!.length != _masterKeySize) {
      throw const IntegrityException('Invalid master key size');
    }
  }
  
  /// Encrypts a value using AES-256-GCM.
  Future<EncryptedRecord> _encryptValue(Uint8List value) async {
    final AesGcm algorithm = AesGcm.with256bits();
    
    // Generate random nonce
    final Random random = Random.secure();
    final Uint8List nonce = Uint8List(_nonceSize);
    for (int i = 0; i < _nonceSize; i++) {
      nonce[i] = random.nextInt(256);
    }
    
    // Create secret key from master key
    final SecretKey secretKey = SecretKey(_masterKey!);
    
    // Encrypt the value
    final SecretBox secretBox = await algorithm.encrypt(
      value,
      secretKey: secretKey,
      nonce: nonce,
    );
    
    return EncryptedRecord(
      nonce: nonce,
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      tag: Uint8List.fromList(secretBox.mac.bytes),
    );
  }
  
  /// Decrypts a value using AES-256-GCM.
  Future<Uint8List> _decryptValue(EncryptedRecord record) async {
    final AesGcm algorithm = AesGcm.with256bits();
    
    // Create secret key from master key
    final SecretKey secretKey = SecretKey(_masterKey!);
    
    // Create SecretBox from stored data
    final SecretBox secretBox = SecretBox(
      record.ciphertext,
      nonce: record.nonce,
      mac: Mac(record.tag),
    );
    
    try {
      final List<int> decrypted = await algorithm.decrypt(secretBox, secretKey: secretKey);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw const IntegrityException('Decryption failed - data may be corrupted');
    }
  }
  
  /// Ensures the vault is unlocked before accessing data.
  void _ensureUnlocked() {
    if (_masterKey == null) {
      throw const VaultLockedException('Vault is locked - call open() to unlock');
    }
  }
}