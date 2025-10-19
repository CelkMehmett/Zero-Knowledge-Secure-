import 'dart:typed_data';

/// Abstract interface for platform-specific Key Management Service.
/// 
/// This interface will be implemented by native platform code to provide
/// hardware-backed key protection using Android Keystore, iOS Secure Enclave,
/// or similar platform security features.
abstract class PlatformKMS {
  /// Wraps a master key using platform KMS protection.
  /// 
  /// Returns an opaque blob that can only be unwrapped by this device's KMS.
  Future<Uint8List> wrapKey(Uint8List key, {bool requireBiometric = false});
  
  /// Unwraps a previously wrapped key using platform KMS.
  /// 
  /// If [requireBiometric] is true, the platform implementation should prompt
  /// for biometric authentication before returning the unwrapped key.
  Future<Uint8List> unwrapKey(Uint8List wrappedKey, {bool requireBiometric = false});
  
  /// Returns true if the platform KMS is hardware-backed.
  Future<bool> isHardwareBacked();
  
  /// Returns true if biometric authentication is available.
  Future<bool> isBiometricAvailable();
}

/// Mock implementation of PlatformKMS for testing and development.
/// 
/// This implementation provides a simple key wrapping mechanism that stores
/// wrapped keys encrypted with a local ephemeral secret. It does NOT provide
/// real hardware security and should only be used for testing.
class MockPlatformKMS implements PlatformKMS {
  static const int _keySize = 32;
  
  // Simple XOR-based "encryption" for mock wrapping (NOT secure!)
  final Uint8List _mockSecret = Uint8List.fromList(<int>[
    0x5A, 0x6B, 0x7C, 0x8D, 0x9E, 0xAF, 0xB0, 0xC1,
    0xD2, 0xE3, 0xF4, 0x05, 0x16, 0x27, 0x38, 0x49,
    0x5A, 0x6B, 0x7C, 0x8D, 0x9E, 0xAF, 0xB0, 0xC1,
    0xD2, 0xE3, 0xF4, 0x05, 0x16, 0x27, 0x38, 0x49
  ]);
  
  @override
  Future<Uint8List> wrapKey(Uint8List key, {bool requireBiometric = false}) async {
    if (key.length != _keySize) {
      throw ArgumentError('Key must be exactly $_keySize bytes');
    }
    
    // Mock wrapping: XOR with mock secret and add header
    final Uint8List wrapped = Uint8List(key.length + 4);
    wrapped[0] = 0xAA; // Mock header
    wrapped[1] = 0xBB;
    wrapped[2] = requireBiometric ? 0x01 : 0x00;
    wrapped[3] = 0xCC;
    
    for (int i = 0; i < key.length; i++) {
      wrapped[i + 4] = key[i] ^ _mockSecret[i];
    }
    
    return wrapped;
  }
  
  @override
  Future<Uint8List> unwrapKey(Uint8List wrappedKey, {bool requireBiometric = false}) async {
    if (wrappedKey.length != _keySize + 4) {
      throw ArgumentError('Invalid wrapped key format');
    }

    // Verify mock header
    if (wrappedKey[0] != 0xAA || wrappedKey[1] != 0xBB || wrappedKey[3] != 0xCC) {
      throw ArgumentError('Invalid wrapped key header');
    }

    final bool requiresBiometric = wrappedKey[2] == 0x01;
    if (requiresBiometric) {
      // In a real implementation, this would trigger biometric prompt
      // For mock, we just simulate success. If caller requested biometric
      // they can pass requireBiometric=true to simulate that path.
      if (requireBiometric) {
        // simulate user consent
      }
    }

    // Mock unwrapping: XOR with mock secret
    final Uint8List key = Uint8List(_keySize);
    for (int i = 0; i < _keySize; i++) {
      key[i] = wrappedKey[i + 4] ^ _mockSecret[i];
    }

    return key;
  }
  
  @override
  Future<bool> isHardwareBacked() async {
    return false; // Mock implementation is not hardware-backed
  }
  
  @override
  Future<bool> isBiometricAvailable() async {
    return true; // Mock always reports biometric available
  }
}