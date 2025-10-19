import Flutter
import UIKit
import LocalAuthentication
import Security
import CryptoKit

public class ZkVaultKmsPlugin: NSObject, FlutterPlugin {
  let keyTag = "com.zkvault.master_key"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zk_vault.kms", binaryMessenger: registrar.messenger())
    let instance = ZkVaultKmsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "wrapKey":
      guard let args = call.arguments as? [String: Any], 
            let keyData = args["key"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'key' argument", details: nil))
        return
      }
      let requireBiometric = args["requireBiometric"] as? Bool ?? false
      
      do {
        let wrappedKey = try wrapKeyWithSecureEnclave(keyData.data, requireBiometric: requireBiometric)
        result(wrappedKey)
      } catch {
        result(FlutterError(code: "KMS_ERROR", message: "wrapKey failed: \(error)", details: nil))
      }

    case "unwrapKey":
      guard let args = call.arguments as? [String: Any], 
            let wrapped = args["wrappedKey"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'wrappedKey' argument", details: nil))
        return
      }
      let requireBiometric = args["requireBiometric"] as? Bool ?? false
      
      do {
        let unwrappedKey = try unwrapKeyWithSecureEnclave(wrapped.data, requireBiometric: requireBiometric)
        result(unwrappedKey)
      } catch {
        result(FlutterError(code: "KMS_ERROR", message: "unwrapKey failed: \(error)", details: nil))
      }

    case "isHardwareBacked":
      result(isSecureEnclaveAvailable())

    case "isBiometricAvailable":
      let ctx = LAContext()
      var err: NSError?
      let available = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
      result(available)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  
  // MARK: - Secure Enclave Key Operations
  
  func wrapKeyWithSecureEnclave(_ keyData: Data, requireBiometric: Bool) throws -> Data {
    // Get or create the Secure Enclave private key
    let privateKey = try getOrCreateSecureEnclaveKey(requireBiometric: requireBiometric)
    
    // Get the public key for encryption
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get public key"])
    }
    
    // Encrypt the key data using the public key
    var error: Unmanaged<CFError>?
    guard let encryptedData = SecKeyCreateEncryptedData(
      publicKey,
      .eciesEncryptionCofactorX963SHA256AESGCM,
      keyData as CFData,
      &error
    ) else {
      if let error = error?.takeRetainedValue() {
        throw error
      } else {
        throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encryption failed"])
      }
    }
    
    return encryptedData as Data
  }
  
  func unwrapKeyWithSecureEnclave(_ wrappedKey: Data, requireBiometric: Bool) throws -> Data {
    // Get the Secure Enclave private key (this may prompt for biometric auth)
    let privateKey = try getSecureEnclaveKey(requireBiometric: requireBiometric)
    
    // Decrypt the wrapped key using the private key
    var error: Unmanaged<CFError>?
    guard let decryptedData = SecKeyCreateDecryptedData(
      privateKey,
      .eciesEncryptionCofactorX963SHA256AESGCM,
      wrappedKey as CFData,
      &error
    ) else {
      if let error = error?.takeRetainedValue() {
        throw error
      } else {
        throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Decryption failed"])
      }
    }
    
    return decryptedData as Data
  }
  
  func getOrCreateSecureEnclaveKey(requireBiometric: Bool) throws -> SecKey {
    // Try to get existing key first
    do {
      return try getSecureEnclaveKey(requireBiometric: requireBiometric)
    } catch {
      // Key doesn't exist, create it
      return try createSecureEnclaveKey(requireBiometric: requireBiometric)
    }
  }
  
  func getSecureEnclaveKey(requireBiometric: Bool) throws -> SecKey {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true
    ]
    
    if requireBiometric {
      query[kSecUseOperationPrompt as String] = "Authenticate to access vault key"
    }
    
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
        NSLocalizedDescriptionKey: "Failed to retrieve Secure Enclave key: \(status)"
      ])
    }
    
    guard let key = item as? SecKey else {
      throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid key type"])
    }
    
    return key
  }
  
  func createSecureEnclaveKey(requireBiometric: Bool) throws -> SecKey {
    var accessControl: SecAccessControl?
    
    if requireBiometric {
      accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        [.privateKeyUsage, .biometryCurrentSet],
        nil
      )
    } else {
      accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .privateKeyUsage,
        nil
      )
    }
    
    guard let access = accessControl else {
      throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create access control"])
    }
    
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
        kSecAttrAccessControl as String: access
      ]
    ]
    
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      if let error = error?.takeRetainedValue() {
        throw error
      } else {
        throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create Secure Enclave key"])
      }
    }
    
    return privateKey
  }
  
  func isSecureEnclaveAvailable() -> Bool {
    // Check if device supports Secure Enclave by trying to query for it
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave
    ]
    
    var error: Unmanaged<CFError>?
    let testKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)
    
    if testKey != nil {
      // Clean up test key
      let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecValueRef as String: testKey!
      ]
      SecItemDelete(deleteQuery as CFDictionary)
      return true
    }
    
    return false
  }
}
}

