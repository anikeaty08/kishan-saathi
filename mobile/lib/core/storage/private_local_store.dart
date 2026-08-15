import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PrivateLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readPrefix(String prefix);
  Future<void> deletePrefix(String prefix);
}

class SecurePrivateLocalStore implements PrivateLocalStore {
  SecurePrivateLocalStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readPrefix(String prefix) async {
    final values = await _storage.readAll();
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix)) entry.key: entry.value,
    };
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    final values = await readPrefix(prefix);
    await Future.wait(values.keys.map((key) => _storage.delete(key: key)));
  }
}

class InMemoryPrivateLocalStore implements PrivateLocalStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readPrefix(String prefix) async => {
    for (final entry in _values.entries)
      if (entry.key.startsWith(prefix)) entry.key: entry.value,
  };

  @override
  Future<void> deletePrefix(String prefix) async {
    _values.removeWhere((key, _) => key.startsWith(prefix));
  }
}
