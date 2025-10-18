import Flutter
import UIKit
import LocalAuthentication
import Security

public class ZkVaultKmsPlugin: NSObject, FlutterPlugin {
  let keyPrefix = "zk_vault_"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "zk_vault.kms", binaryMessenger: registrar.messenger())
    let instance = ZkVaultKmsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "wrapKey":
      guard let args = call.arguments as? [String: Any], let keyData = args["key"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'key' argument", details: nil))
        return
      }
      let requireBiometric = args["requireBiometric"] as? Bool ?? false
      do {
        let tag = try storeKeyInKeychain(keyData.data, requireBiometric: requireBiometric)
        // Return the tag as Data so Dart can store it
        result(tag.data(using: .utf8))
      } catch {
        result(FlutterError(code: "KMS_ERROR", message: "wrapKey failed: \(error)", details: nil))
      }

    case "unwrapKey":
      guard let args = call.arguments as? [String: Any], let wrapped = args["wrappedKey"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'wrappedKey' argument", details: nil))
        return
      }
      let requireBiometric = args["requireBiometric"] as? Bool ?? false
      do {
        if let tag = String(data: wrapped.data, encoding: .utf8) {
          let key = try retrieveKeyFromKeychain(tag: tag, requireBiometric: requireBiometric)
          result(key)
        } else {
          result(FlutterError(code: "INVALID_WRAPPED", message: "Wrapped key is invalid", details: nil))
        }
      } catch {
        result(FlutterError(code: "KMS_ERROR", message: "unwrapKey failed: \(error)", details: nil))
      }

    case "isHardwareBacked":
      // Heuristic: if Secure Enclave available and device supports biometry
      let hasSE = isSecureEnclaveAvailable()
      result(hasSE)

    case "isBiometricAvailable":
      let ctx = LAContext()
      var err: NSError?
      let can = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
      result(can)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Store raw key data in Keychain under a generated tag, with optional biometric access control
  func storeKeyInKeychain(_ key: Data, requireBiometric: Bool) throws -> String {
    let tag = UUID().uuidString
    let account = keyPrefix + tag

    var access: SecAccessControl?
    if requireBiometric {
      access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil)
    }

    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecValueData as String: key
    ]

    if let ac = access {
      query[kSecAttrAccessControl as String] = ac
    } else {
      query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecSuccess {
      return tag
    } else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
    }
  }

  func retrieveKeyFromKeychain(tag: String, requireBiometric: Bool) throws -> Data {
    let account = keyPrefix + tag
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    if requireBiometric {
      // This will prompt the user for biometric auth if the item was protected
      query[kSecUseOperationPrompt as String] = "Authenticate to unlock vault"
    }

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess {
      if let data = item as? Data {
        return data
      } else {
        throw NSError(domain: "ZKVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid item type"])
      }
    } else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
    }
  }

  func isSecureEnclaveAvailable() -> Bool {
    // Heuristic: if device has biometric capability, assume Secure Enclave is available
    let ctx = LAContext()
    var err: NSError?
    if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
      return true
    }
    return false
  }
}

