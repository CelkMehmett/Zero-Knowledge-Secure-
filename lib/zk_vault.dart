/// Zero-Knowledge style secure storage for Flutter/Dart applications.
/// 
/// This library provides encrypted storage with platform Key Management Service
/// integration for maximum security.
library zk_vault;

export 'src/zk_vault_impl.dart' show ZKVault;
export 'src/platform_kms.dart' show PlatformKMS, MockPlatformKMS;
export 'src/native_platform_kms.dart' show NativePlatformKMS;
export 'src/exceptions.dart' show VaultLockedException, IntegrityException, SecureEnclaveUnavailableException;
export 'src/migration_helper.dart' show VaultMigrationHelper, MigrationStrategy;