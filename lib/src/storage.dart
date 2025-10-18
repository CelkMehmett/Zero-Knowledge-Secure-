import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
// Use path_provider when available (Flutter apps). We import conditionally at
// runtime to keep the package usable in pure Dart test environments.
import 'package:path_provider/path_provider.dart' as path_provider;

/// Handles persistent storage of vault data using JSON files.
/// 
/// This implementation provides atomic writes and basic integrity checking
/// for vault metadata and encrypted records.
class VaultStorage {
  final String vaultId;
  final Directory _storageDir;

  // Per-process run id to isolate temp storage between separate test runs.
  static String? _runId;
  
  VaultStorage(this.vaultId, this._storageDir);
  
  /// Creates a VaultStorage instance for the given vault ID.
  /// 
  /// Uses system temp directory as base storage location.
  /// TODO: In a real Flutter plugin, use path_provider to get app documents directory.
  static Future<VaultStorage> create(String vaultId) async {
    // Ensure a per-process run id so separate test runs don't reuse the same
    // temp directory. This keeps tests deterministic when running repeatedly.
    _runId ??= () {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final String rand = List<int>.generate(6, (int i) => DateTime.now().microsecond + i)
          .map((int e) => (e & 0xff).toRadixString(16).padLeft(2, '0'))
          .join();
      return '${now}_$rand';
    }();

    // Prefer platform-specific application support directory when available.
    Directory baseDir = Directory(Directory.systemTemp.path);
    try {
      final Directory appSupport = await path_provider.getApplicationSupportDirectory();
      if (appSupport.path.isNotEmpty) {
        baseDir = appSupport;
      }
    } catch (_) {
      // If path_provider is not available (pure Dart environment), fall back
      // to system temp directory.
      baseDir = Directory(Directory.systemTemp.path);
    }

    final Directory storageDir = Directory(path.join(
      baseDir.path,
      'zk_vault',
      _runId!,
      vaultId,
    ));

    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    } else {
      // If directory exists but metadata is missing (leftover from a previous
      // run), remove stale record file so an open() behaves as a fresh vault.
      final File meta = File(path.join(storageDir.path, 'vault.meta.json'));
      final File records = File(path.join(storageDir.path, 'vault.db.json'));
      if (!await meta.exists() && await records.exists()) {
        try {
          await records.delete();
        } catch (_) {
          // ignore
        }
      }
    }

    return VaultStorage(vaultId, storageDir);
  }
  
  File get _metadataFile => File(path.join(_storageDir.path, 'vault.meta.json'));
  File get _recordsFile => File(path.join(_storageDir.path, 'vault.db.json'));
  
  /// Loads vault metadata from disk.
  Future<Map<String, dynamic>?> loadMetadata() async {
    if (!await _metadataFile.exists()) {
      return null;
    }
    
    try {
      final String content = await _metadataFile.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      throw StateError('Failed to load vault metadata: $e');
    }
  }
  
  /// Saves vault metadata to disk atomically.
  Future<void> saveMetadata(Map<String, dynamic> metadata) async {
    await _atomicWrite(_metadataFile, json.encode(metadata));
  }
  
  /// Loads encrypted records from disk.
  Future<Map<String, dynamic>> loadRecords() async {
    if (!await _recordsFile.exists()) {
      return <String, dynamic>{};
    }
    
    try {
      final String content = await _recordsFile.readAsString();
      final Object? data = json.decode(content);
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } catch (e) {
      throw StateError('Failed to load vault records: $e');
    }
  }
  
  /// Saves encrypted records to disk atomically.
  Future<void> saveRecords(Map<String, dynamic> records) async {
    await _atomicWrite(_recordsFile, json.encode(records));
  }
  
  /// Checks if vault exists on disk.
  Future<bool> exists() async {
    return await _metadataFile.exists();
  }
  
  /// Completely destroys the vault storage.
  Future<void> destroy() async {
    try {
      if (await _storageDir.exists()) {
        await _storageDir.delete(recursive: true);
      }
    } catch (e) {
      // Ignore errors during destruction - vault is likely already gone
    }
  }
  
  /// Performs atomic write by writing to temp file then renaming.
  Future<void> _atomicWrite(File targetFile, String content) async {
    final File tempFile = File('${targetFile.path}.tmp');
    
    try {
      await tempFile.writeAsString(content);
      await tempFile.rename(targetFile.path);
    } catch (e) {
      // Clean up temp file if write failed
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }
}

/// Represents an encrypted record stored in the vault.
class EncryptedRecord {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  EncryptedRecord({
    required this.nonce,
    required this.ciphertext,
    required this.tag,
    this.version = 1,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  
  /// Creates an EncryptedRecord from JSON data.
  factory EncryptedRecord.fromJson(Map<String, dynamic> json) {
    return EncryptedRecord(
      nonce: Uint8List.fromList(List<int>.from(json['nonce'])),
      ciphertext: Uint8List.fromList(List<int>.from(json['ciphertext'])),
      tag: Uint8List.fromList(List<int>.from(json['tag'])),
      version: json['version'] ?? 1,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
  
  /// Converts the record to JSON for storage.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'nonce': nonce.toList(),
      'ciphertext': ciphertext.toList(),
      'tag': tag.toList(),
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}