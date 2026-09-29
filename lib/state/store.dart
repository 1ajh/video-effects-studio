import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny JSON-on-SharedPreferences persistence layer.
class Store {
  Store(this._prefs);

  final SharedPreferences _prefs;

  static Future<Store> open() async => Store(await SharedPreferences.getInstance());

  T? readJson<T>(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) => _prefs.setString(key, jsonEncode(value));

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int? getInt(String key) => _prefs.getInt(key);
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  double? getDouble(String key) => _prefs.getDouble(key);
  Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  Future<void> clearAll() => _prefs.clear();
}
