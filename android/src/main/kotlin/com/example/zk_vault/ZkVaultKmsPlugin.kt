package com.example.zk_vault

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.KeyInfo
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.Executor
import java.security.PrivateKey
import java.security.KeyFactory
import android.util.Log

/** ZkVaultKmsPlugin: Android KeyStore-backed minimal implementation */
class ZkVaultKmsPlugin: FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var context: Context? = null
  private var activityBinding: ActivityPluginBinding? = null
  private var pendingResult: MethodChannel.Result? = null
  private var pendingWrapped: ByteArray? = null
  private var pendingCipher: Cipher? = null
  private val KEY_ALIAS = "zk_vault_master_key"

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "zk_vault.kms")
    channel.setMethodCallHandler(this)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
  }

  override fun onDetachedFromActivity() {
    activityBinding = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "wrapKey" -> {
          val keyList = call.argument<ByteArray>("key")
          val requireBiometric = call.argument<Boolean>("requireBiometric") ?: false
          if (keyList == null) {
            result.error("INVALID_ARGUMENT", "Missing 'key' argument", null)
            return
          }
          val wrapped = wrapKey(keyList, requireBiometric)
          result.success(wrapped)
        }
        "unwrapKey" -> {
          val wrapped = call.argument<ByteArray>("wrappedKey")
          val requireBiometric = call.argument<Boolean>("requireBiometric") ?: false
          if (wrapped == null) {
            result.error("INVALID_ARGUMENT", "Missing 'wrappedKey' argument", null)
            return
          }
          if (!requireBiometric) {
            val unwrapped = unwrapKey(wrapped)
            result.success(unwrapped)
          } else {
            // Start biometric auth and decrypt on success
            val act = activityBinding?.activity
            if (act == null) {
              result.error("NO_ACTIVITY", "Activity required for biometric prompt", null)
              return
            }
            try {
              val ks = KeyStore.getInstance("AndroidKeyStore")
              ks.load(null)
              val privateKey = ks.getKey(KEY_ALIAS, null) as? PrivateKey
              if (privateKey == null) {
                result.error("NO_KEY", "Biometric key not available", null)
                return
              }

              // Try to initialize the cipher. If the key requires user authentication,
              // this may throw UserNotAuthenticatedException. In that case, fall back
              // to prompting for biometric auth first, then initialize the cipher
              // and decrypt inside the success callback.
              val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
              val oaepParams = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec("SHA-256"), PSource.PSpecified.DEFAULT)

              var initSucceeded = false
              try {
                cipher.init(Cipher.DECRYPT_MODE, privateKey, oaepParams)
                initSucceeded = true
              } catch (e: Exception) {
                // Initialization failed likely due to UserNotAuthenticatedException.
                initSucceeded = false
              }

              pendingResult = result
              pendingWrapped = wrapped
              pendingCipher = if (initSucceeded) cipher else null

              val executor: Executor = ContextCompat.getMainExecutor(act)
              val prompt = BiometricPrompt(act as FragmentActivity, executor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(resultAuth: BiometricPrompt.AuthenticationResult) {
                  super.onAuthenticationSucceeded(resultAuth)
                  try {
                    var c = resultAuth.cryptoObject?.cipher ?: pendingCipher
                    if (c == null) {
                      // Cipher wasn't initialized before auth; initialize now using the private key
                      val ks2 = KeyStore.getInstance("AndroidKeyStore")
                      ks2.load(null)
                      val priv2 = ks2.getKey(KEY_ALIAS, null) as java.security.PrivateKey
                      val c2 = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
                      c2.init(Cipher.DECRYPT_MODE, priv2, oaepParams)
                      c = c2
                    }
                    val decrypted = c!!.doFinal(pendingWrapped)
                    pendingResult?.success(decrypted)
                  } catch (e: Exception) {
                    pendingResult?.error("UNWRAP_FAILED", e.message, null)
                  } finally {
                    pendingResult = null
                    pendingWrapped = null
                    pendingCipher = null
                  }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                  super.onAuthenticationError(errorCode, errString)
                  pendingResult?.error("AUTH_ERROR", errString.toString(), null)
                  pendingResult = null
                  pendingWrapped = null
                  pendingCipher = null
                }

                override fun onAuthenticationFailed() {
                  super.onAuthenticationFailed()
                }
              })

              val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Authenticate to unlock vault")
                .setSubtitle("Biometric authentication is required to retrieve keys")
                .setNegativeButtonText("Cancel")
                .build()

              if (initSucceeded) {
                prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
              } else {
                // Authenticate without a CryptoObject; we'll initialize the cipher after success.
                prompt.authenticate(info)
              }
            } catch (e: Exception) {
              result.error("AUTH_SETUP_FAILED", e.message, null)
            }
          }
        }
        "isHardwareBacked" -> {
          val hw = isHardwareBacked()
          result.success(hw)
        }
        "isBiometricAvailable" -> {
          val bio = isBiometricAvailable()
          result.success(bio)
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      result.error("KMS_ERROR", e.message, null)
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    context = null
  }

  private fun ensureKeyPair(requireBiometric: Boolean = false): java.security.KeyPair {
    val ks = KeyStore.getInstance("AndroidKeyStore")
    ks.load(null)
    val existing = ks.getEntry(KEY_ALIAS, null)
    if (existing != null) {
      // KeyPair exists
      val pub = ks.getCertificate(KEY_ALIAS).publicKey
      val priv = ks.getKey(KEY_ALIAS, null) as java.security.PrivateKey
      return java.security.KeyPair(pub, priv)
    }

    val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
    val specBuilder = KeyGenParameterSpec.Builder(
      KEY_ALIAS,
      KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
    ).apply {
      setKeySize(2048)
      setDigests(KeyProperties.DIGEST_SHA256)
      setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
      // Add user authentication requirement when requested. Using
      // a validity duration of 0 forces auth for every use (biometric each time).
      if (requireBiometric) {
        try {
          if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            // API 30+: prefer setUserAuthenticationParameters for finer control
            try {
              val timeoutSeconds = 0
              setUserAuthenticationParameters(timeoutSeconds, KeyProperties.AUTH_BIOMETRIC_STRONG)
              Log.d("ZkVaultKmsPlugin", "Configured user auth (params) for $KEY_ALIAS")
            } catch (e: Exception) {
              // Fall back to older API if unavailable
              setUserAuthenticationRequired(true)
              setUserAuthenticationValidityDurationSeconds(0)
              Log.d("ZkVaultKmsPlugin", "Fell back to setUserAuthenticationRequired for $KEY_ALIAS: ${e.message}")
            }
          } else {
            setUserAuthenticationRequired(true)
            setUserAuthenticationValidityDurationSeconds(0)
            Log.d("ZkVaultKmsPlugin", "Configured user auth (legacy) for $KEY_ALIAS")
          }
        } catch (e: Exception) {
          Log.w("ZkVaultKmsPlugin", "Failed to configure user authentication for $KEY_ALIAS: ${e.message}")
        }
      }

      // Try to prefer StrongBox when available (API 28+). This is optional and
      // may fail on devices without StrongBox support; ignore failures.
      if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
        try {
          setIsStrongBoxBacked(true)
          Log.d("ZkVaultKmsPlugin", "Requested StrongBox backing for $KEY_ALIAS")
        } catch (e: Exception) {
          Log.d("ZkVaultKmsPlugin", "StrongBox not available for $KEY_ALIAS: ${e.message}")
        }
      }
    }

    kpg.initialize(specBuilder.build())
    return kpg.generateKeyPair()
  }

  private fun wrapKey(keyBytes: ByteArray, requireBiometric: Boolean = false): ByteArray {
    val kp = ensureKeyPair(requireBiometric)
    val pub = kp.public
    val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
    val oaepParams = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec("SHA-256"), PSource.PSpecified.DEFAULT)
    cipher.init(Cipher.ENCRYPT_MODE, pub, oaepParams)
    return cipher.doFinal(keyBytes)
  }

  private fun unwrapKey(wrapped: ByteArray): ByteArray {
    val ks = KeyStore.getInstance("AndroidKeyStore")
    ks.load(null)
    val priv = ks.getKey(KEY_ALIAS, null) as java.security.PrivateKey
    val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
    val oaepParams = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec("SHA-256"), PSource.PSpecified.DEFAULT)
    cipher.init(Cipher.DECRYPT_MODE, priv, oaepParams)
    return cipher.doFinal(wrapped)
  }

  private fun isHardwareBacked(): Boolean {
    try {
      val ks = KeyStore.getInstance("AndroidKeyStore")
      ks.load(null)
      val privateKey = ks.getKey(KEY_ALIAS, null) ?: return false
      val kf = KeyFactory.getInstance(privateKey.algorithm, "AndroidKeyStore")
      val keyInfo = kf.getKeySpec(privateKey, KeyInfo::class.java) as KeyInfo
      return keyInfo.isInsideSecureHardware
    } catch (e: Exception) {
      return false
    }
  }

  private fun isBiometricAvailable(): Boolean {
    val ctx = context ?: return false
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      val pm = ctx.packageManager
      pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
    } else {
      false
    }
  }
}

