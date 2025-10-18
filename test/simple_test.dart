import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:zk_vault/zk_vault.dart';
import 'package:zk_vault/src/platform_kms.dart';

void main() {
  test('simple vault test', () async {
  final MockPlatformKMS mockKms = MockPlatformKMS();
  final ZKVault vault = await ZKVault.open('simple_test', kms: mockKms);
  final Uint8List testData = Uint8List.fromList('Hello'.codeUnits);
  await vault.set('test', testData);
  final Uint8List? result = await vault.get('test');
    
    expect(result, isNotNull);
    expect(String.fromCharCodes(result!), equals('Hello'));
    
  await vault.lock();
  }, timeout: const Timeout(Duration(seconds: 10)));
}