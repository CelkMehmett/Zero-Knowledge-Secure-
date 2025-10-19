import 'dart:typed_data';
import 'package:zk_vault/zk_vault.dart';

/// Migration utilities for transitioning between different KMS implementations.
/// 
/// These utilities help migrate vault data from MockPlatformKMS to NativePlatformKMS
/// or between different vault configurations.
class VaultMigrationHelper {
  
  /// Migrates a vault from one KMS implementation to another.
  /// 
  /// This is useful when transitioning from MockPlatformKMS (development/testing)
  /// to NativePlatformKMS (production) or when changing security requirements.
  /// 
  /// Example usage:
  /// ```dart
  /// final helper = VaultMigrationHelper();
  /// await helper.migrateVault(
  ///   vaultId: 'my_vault',
  ///   sourceKms: MockPlatformKMS(),
  ///   targetKms: NativePlatformKMS(),
  ///   targetRequireBiometric: true,
  /// );
  /// ```
  static Future<void> migrateVault({
    required String vaultId,
    required PlatformKMS sourceKms,
    required PlatformKMS targetKms,
    bool sourceRequireBiometric = false,
    bool targetRequireBiometric = false,
    String? targetVaultId,
  }) async {
    final String actualTargetVaultId = targetVaultId ?? vaultId;
    
    // Open source vault
    final ZKVault sourceVault = await ZKVault.open(
      vaultId,
      requireBiometric: sourceRequireBiometric,
      kms: sourceKms,
    );
    
    try {
      // Get all keys and data from source vault
      final List<String> keys = await sourceVault.keys();
      final Map<String, Uint8List> allData = <String, Uint8List>{};
      
      for (final String key in keys) {
        final Uint8List? data = await sourceVault.get(key);
        if (data != null) {
          allData[key] = data;
        }
      }
      
      // Create target vault with new KMS
      final ZKVault targetVault = await ZKVault.open(
        actualTargetVaultId,
        requireBiometric: targetRequireBiometric,
        kms: targetKms,
      );
      
      try {
        // Transfer all data to target vault
        for (final MapEntry<String, Uint8List> entry in allData.entries) {
          await targetVault.set(entry.key, entry.value);
        }
        
        // If migration was to a different vault ID, destroy the source
        if (actualTargetVaultId != vaultId) {
          await sourceVault.destroy();
        }
      } finally {
        await targetVault.lock();
      }
    } finally {
      await sourceVault.lock();
    }
  }
  
  /// Creates a backup of vault data to a Map.
  /// 
  /// This can be used for data backup or migration purposes.
  /// Note: The returned data is decrypted and should be handled securely.
  static Future<Map<String, Uint8List>> backupVaultData({
    required String vaultId,
    required PlatformKMS kms,
    bool requireBiometric = false,
  }) async {
    final ZKVault vault = await ZKVault.open(
      vaultId,
      requireBiometric: requireBiometric,
      kms: kms,
    );
    
    try {
      final List<String> keys = await vault.keys();
      final Map<String, Uint8List> backup = <String, Uint8List>{};
      
      for (final String key in keys) {
        final Uint8List? data = await vault.get(key);
        if (data != null) {
          backup[key] = data;
        }
      }
      
      return backup;
    } finally {
      await vault.lock();
    }
  }
  
  /// Restores vault data from a backup Map.
  /// 
  /// This overwrites any existing data in the target vault.
  static Future<void> restoreVaultData({
    required String vaultId,
    required Map<String, Uint8List> backupData,
    required PlatformKMS kms,
    bool requireBiometric = false,
  }) async {
    final ZKVault vault = await ZKVault.open(
      vaultId,
      requireBiometric: requireBiometric,
      kms: kms,
    );
    
    try {
      // Clear existing data
      final List<String> existingKeys = await vault.keys();
      for (final String key in existingKeys) {
        await vault.delete(key);
      }
      
      // Restore backup data
      for (final MapEntry<String, Uint8List> entry in backupData.entries) {
        await vault.set(entry.key, entry.value);
      }
    } finally {
      await vault.lock();
    }
  }
  
  /// Checks if a vault exists and can be opened with the given KMS.
  static Future<bool> isVaultAccessible({
    required String vaultId,
    required PlatformKMS kms,
    bool requireBiometric = false,
  }) async {
    try {
      final ZKVault vault = await ZKVault.open(
        vaultId,
        requireBiometric: requireBiometric,
        kms: kms,
      );
      await vault.lock();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Validates that a KMS implementation is working correctly.
  /// 
  /// This performs a simple wrap/unwrap test to verify KMS functionality.
  static Future<bool> validateKms(PlatformKMS kms, {bool requireBiometric = false}) async {
    try {
      // Test key wrapping/unwrapping
  final Uint8List testKey = Uint8List.fromList(List<int>.generate(32, (int i) => i));
      final Uint8List wrappedKey = await kms.wrapKey(testKey, requireBiometric: requireBiometric);
      final Uint8List unwrappedKey = await kms.unwrapKey(wrappedKey, requireBiometric: requireBiometric);
      
      // Verify the keys match
      if (testKey.length != unwrappedKey.length) return false;
      for (int i = 0; i < testKey.length; i++) {
        if (testKey[i] != unwrappedKey[i]) return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Provides a migration strategy recommendation based on device capabilities.
  static Future<MigrationStrategy> recommendMigrationStrategy() async {
    try {
  final NativePlatformKMS nativeKms = NativePlatformKMS();
  final bool hardwareBacked = await nativeKms.isHardwareBacked();
  final bool biometricAvailable = await nativeKms.isBiometricAvailable();
      
      if (hardwareBacked && biometricAvailable) {
        return MigrationStrategy(
          recommendedKms: () => NativePlatformKMS(),
          requireBiometric: true,
          reason: 'Device supports hardware-backed keys with biometric authentication',
        );
      } else if (hardwareBacked) {
        return MigrationStrategy(
          recommendedKms: () => NativePlatformKMS(),
          requireBiometric: false,
          reason: 'Device supports hardware-backed keys',
        );
      } else {
        return MigrationStrategy(
          recommendedKms: () => MockPlatformKMS(),
          requireBiometric: false,
          reason: 'Hardware KMS not available, using mock implementation',
        );
      }
    } on SecureEnclaveUnavailableException {
      return MigrationStrategy(
        recommendedKms: () => MockPlatformKMS(),
        requireBiometric: false,
        reason: 'Native KMS unavailable, using mock implementation',
      );
    }
  }
}

/// Represents a recommended migration strategy for a device.
class MigrationStrategy {
  const MigrationStrategy({
    required this.recommendedKms,
    required this.requireBiometric,
    required this.reason,
  });
  
  /// Factory function to create the recommended KMS implementation.
  final PlatformKMS Function() recommendedKms;
  
  /// Whether biometric authentication should be required.
  final bool requireBiometric;
  
  /// Human-readable reason for this recommendation.
  final String reason;
  
  @override
  String toString() {
    return 'MigrationStrategy(requireBiometric: $requireBiometric, reason: "$reason")';
  }
}