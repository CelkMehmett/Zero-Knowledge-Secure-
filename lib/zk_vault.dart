/// Zero-Knowledge style secure storage for Flutter/Dart applications.
/// 
/// This library provides a secure vault that encrypts data using AES-256-GCM
/// with master keys protected by platform KMS (Key Management Service).
library zk_vault;

export 'src/zk_vault_impl.dart' show ZKVault;
export 'src/exceptions.dart';