import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zk_vault/zk_vault.dart';

void main() {
  runApp(const ZKVaultExampleApp());
}

class ZKVaultExampleApp extends StatelessWidget {
  const ZKVaultExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZK Vault Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const VaultDemoScreen(),
    );
  }
}

class VaultDemoScreen extends StatefulWidget {
  const VaultDemoScreen({super.key});

  @override
  State<VaultDemoScreen> createState() => _VaultDemoScreenState();
}

class _VaultDemoScreenState extends State<VaultDemoScreen> {
  ZKVault? _vault;
  final List<String> _logs = <String>[];
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZK Vault Demo'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _isLoading ? null : _openVault,
                  child: Text(_vault == null ? 'Open Vault' : 'Vault Opened'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _vault == null || _isLoading ? null : _storeData,
                  child: const Text('Store Sample Data'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _vault == null || _isLoading ? null : _retrieveData,
                  child: const Text('Retrieve Data'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _vault == null || _isLoading ? null : _listKeys,
                  child: const Text('List Keys'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _vault == null || _isLoading ? null : _lockVault,
                  child: const Text('Lock Vault'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _clearLogs,
                  child: const Text('Clear Logs'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                  const Text(
                    'Logs:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                                child: Text(
                          _logs.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const LinearProgressIndicator(),
        ],
      ),
    );
  }

  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toIso8601String()}] $message');
    });
  }

  Future<void> _openVault() async {
    setState(() => _isLoading = true);
    try {
      _log('Opening vault with biometric requirement...');
      
      // Open vault with biometric requirement
      // Note: This uses MockPlatformKMS so it will work without real hardware
      _vault = await ZKVault.open(
        'demo_vault',
        requireBiometric: true,
      );
      
      _log('✓ Vault opened successfully');
      _log('  - Vault ID: demo_vault');
      _log('  - Biometric required: true');
      _log('  - Using MockPlatformKMS for demonstration');
    } catch (e) {
      _log('✗ Failed to open vault: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _storeData() async {
    setState(() => _isLoading = true);
    try {
      _log('Storing sample data...');
      
  // Store some sample data
  final Uint8List sampleData = Uint8List.fromList('Hello, ZK Vault!'.codeUnits);
  await _vault!.set('greeting', sampleData);
      
  final Uint8List secretData = Uint8List.fromList('This is a secret message'.codeUnits);
  await _vault!.set('secret', secretData);
      
  final Uint8List numbers = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 42, 255]);
  await _vault!.set('numbers', numbers);
      
      _log('✓ Stored 3 items successfully');
      _log('  - greeting: "Hello, ZK Vault!"');
      _log('  - secret: "This is a secret message"');
      _log('  - numbers: [1, 2, 3, 4, 5, 42, 255]');
    } catch (e) {
      _log('✗ Failed to store data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _retrieveData() async {
    setState(() => _isLoading = true);
    try {
      _log('Retrieving stored data...');
      
      // Retrieve the greeting
      final Uint8List? greeting = await _vault!.get('greeting');
      if (greeting != null) {
        final String greetingText = String.fromCharCodes(greeting);
        _log('✓ Retrieved greeting: "$greetingText"');
      } else {
        _log('✗ Greeting not found');
      }
      
      // Retrieve the secret
      final Uint8List? secret = await _vault!.get('secret');
      if (secret != null) {
        final String secretText = String.fromCharCodes(secret);
        _log('✓ Retrieved secret: "$secretText"');
      } else {
        _log('✗ Secret not found');
      }
      
      // Retrieve numbers
      final Uint8List? numbers = await _vault!.get('numbers');
      if (numbers != null) {
        _log('✓ Retrieved numbers: ${numbers.toList()}');
      } else {
        _log('✗ Numbers not found');
      }
      
      // Try to retrieve non-existent key
      final Uint8List? nonExistent = await _vault!.get('nonexistent');
      if (nonExistent == null) {
        _log('✓ Non-existent key correctly returned null');
      }
    } catch (e) {
      _log('✗ Failed to retrieve data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _listKeys() async {
    setState(() => _isLoading = true);
    try {
      _log('Listing all keys...');
      
      final List<String> keys = await _vault!.keys();
      _log('✓ Found ${keys.length} keys: ${keys.join(', ')}');
      
      // Check if specific keys exist
      for (final String key in <String>['greeting', 'secret', 'numbers', 'nonexistent']) {
        final bool exists = await _vault!.contains(key);
        _log('  - $key: ${exists ? 'exists' : 'not found'}');
      }
    } catch (e) {
      _log('✗ Failed to list keys: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _lockVault() async {
    setState(() => _isLoading = true);
    try {
      _log('Locking vault...');
      
      await _vault!.lock();
      _vault = null;
      
      _log('✓ Vault locked successfully');
      _log('  - Master key cleared from memory');
      _log('  - Vault must be reopened to access data');
    } catch (e) {
      _log('✗ Failed to lock vault: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }
}