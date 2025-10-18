/// Custom exceptions for ZKVault operations.
library zk_vault.src.exceptions;


/// Thrown when attempting to access a locked vault.
class VaultLockedException implements Exception {
  final String message;
  
  const VaultLockedException([this.message = 'Vault is locked']);
  
  @override
  String toString() => 'VaultLockedException: $message';
}

/// Thrown when data integrity checks fail.
class IntegrityException implements Exception {
  final String message;
  
  const IntegrityException([this.message = 'Data integrity check failed']);
  
  @override
  String toString() => 'IntegrityException: $message';
}

/// Thrown when secure enclave/hardware security is unavailable.
class SecureEnclaveUnavailableException implements Exception {
  final String message;
  
  const SecureEnclaveUnavailableException([
    this.message = 'Secure enclave is unavailable'
  ]);
  
  @override
  String toString() => 'SecureEnclaveUnavailableException: $message';
}