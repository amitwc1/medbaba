import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure Storage Service to safely store sensitive data on device.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(
        key: key,
        value: value,
        aOptions: _getAndroidOptions(),
      );
    } catch (e) {
      // Avoid printing secret values, log only the exception type/message.
      throw Exception('Failed to write key to secure storage: ${e.toString()}');
    }
  }

  Future<String?> read(String key) async {
    try {
      return await _storage.read(
        key: key,
        aOptions: _getAndroidOptions(),
      );
    } catch (e) {
      throw Exception('Failed to read key from secure storage: ${e.toString()}');
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(
        key: key,
        aOptions: _getAndroidOptions(),
      );
    } catch (e) {
      throw Exception('Failed to delete key from secure storage: ${e.toString()}');
    }
  }

  Future<void> clear() async {
    try {
      await _storage.deleteAll(
        aOptions: _getAndroidOptions(),
      );
    } catch (e) {
      throw Exception('Failed to clear secure storage: ${e.toString()}');
    }
  }
}
