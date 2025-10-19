// ignore_for_file: prefer_const_constructors

import 'package:flutter/services.dart';
import 'platform_kms.dart';
import 'exceptions.dart';

/// MethodChannel-backed PlatformKMS implementation.
///
/// Calls native platform code over the `zk_vault.kms` MethodChannel. If the
/// native plugin isn't registered, methods will throw
/// [SecureEnclaveUnavailableException]. This file is a scaffold — implement
/// the native side to provide hardware-backed wrapping/unwrapping.
class NativePlatformKMS implements PlatformKMS {
  static const MethodChannel _channel = MethodChannel('zk_vault.kms');

  @override
  Future<Uint8List> wrapKey(Uint8List key, {bool requireBiometric = false}) async {
    try {
      // ignore: prefer_const_literals_to_create_immutables
      final Object? raw = await _channel.invokeMethod<Object>('wrapKey', <String, dynamic>{
        'key': key,
        'requireBiometric': requireBiometric,
      });
      if (raw == null) throw SecureEnclaveUnavailableException('Native KMS returned null');
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
      throw SecureEnclaveUnavailableException('Unexpected wrapped key type from native KMS');
    } on MissingPluginException {
      throw SecureEnclaveUnavailableException('Native KMS plugin not available');
    }
  }

  @override
  Future<Uint8List> unwrapKey(Uint8List wrappedKey, {bool requireBiometric = false}) async {
    try {
      // ignore: prefer_const_literals_to_create_immutables
      final Object? raw = await _channel.invokeMethod<Object>('unwrapKey', <String, dynamic>{
        'wrappedKey': wrappedKey,
        'requireBiometric': requireBiometric,
      });
      if (raw == null) throw SecureEnclaveUnavailableException('Native KMS returned null');
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
      throw SecureEnclaveUnavailableException('Unexpected unwrapped key type from native KMS');
    } on MissingPluginException {
      throw SecureEnclaveUnavailableException('Native KMS plugin not available');
    }
  }

  @override
  Future<bool> isHardwareBacked() async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('isHardwareBacked');
      return res ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> isBiometricAvailable() async {
    try {
      final bool? res = await _channel.invokeMethod<bool>('isBiometricAvailable');
      return res ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
