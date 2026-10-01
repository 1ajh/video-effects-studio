import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/licensing/license.dart';
import 'store.dart';

enum LicenseState { checking, locked, unlocked }

/// Whether this copy is unlocked: a license key is activated once online,
/// and the store's signed activation is checked offline on every start.
class LicenseController extends ChangeNotifier {
  LicenseController(
    this._store, {
    LicenseClient? client,
    String publicKey = builtInPublicKey,
    Future<String> Function()? machine,
    bool? allowUnlicensed,
  }) : _client = client ?? LicenseClient(),
       _publicKey = publicKey,
       _machine = machine,
       // A development build made without the store's key has nothing to
       // check activations against: it runs unlocked. Release builds don't.
       _allowUnlicensed = allowUnlicensed ?? (kDebugMode && publicKey.isEmpty) {
    if (_allowUnlicensed) _state = LicenseState.unlocked;
  }

  static const _tokenKey = 'license.token';
  static const _installKey = 'license.install';

  final Store _store;
  final LicenseClient _client;
  final String _publicKey;
  final Future<String> Function()? _machine;
  final bool _allowUnlicensed;

  LicenseState _state = LicenseState.checking;
  Activation? _activation;
  String? _error;
  bool _busy = false;

  LicenseState get state => _state;
  bool get unlocked => _state == LicenseState.unlocked;
  bool get busy => _busy;
  String? get error => _error;
  Activation? get activation => _activation;

  /// Running without a license check (development builds only).
  bool get unlicensedBuild => _allowUnlicensed;

  /// This build can't unlock: it was made without the store's public key.
  bool get missingPublicKey => _publicKey.isEmpty && !_allowUnlicensed;

  /// The key with its middle hidden, for Settings.
  String get maskedKey {
    final k = _activation?.key ?? '';
    return k.length < 10 ? k : '${k.substring(0, 10)}…${k.substring(k.length - 5)}';
  }

  Future<String> _fingerprint() async {
    if (_machine != null) return _machine();
    return machineFingerprint(
      fallback: () async {
        var id = _store.getString(_installKey);
        if (id == null) {
          final r = Random.secure();
          id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
          await _store.setString(_installKey, id);
        }
        return id;
      },
    );
  }

  /// Checks the saved activation (offline).
  Future<void> load() async {
    if (_allowUnlicensed) {
      _state = LicenseState.unlocked;
      notifyListeners();
      return;
    }
    final token = _store.getString(_tokenKey);
    Activation? a;
    if (token != null) {
      a = await Activation.verify(token, _publicKey);
      if (a != null && a.machine != await _fingerprint()) a = null;
    }
    _activation = a;
    _state = a == null ? LicenseState.locked : LicenseState.unlocked;
    notifyListeners();
  }

  /// Activates [input] with the store. False (with [error] set) when it
  /// isn't accepted.
  Future<bool> activate(String input) async {
    if (_busy) return false;
    _error = null;
    final key = normalizeKey(input);
    if (key == null) {
      _error = isOrderCode(input)
          ? "That's your order code. Your license key shows on your order page once the payment is confirmed."
          : "That isn't a license key. It looks like SRLE-XXXXX-XXXXX-XXXXX-XXXXX; copy it from your order page.";
      notifyListeners();
      return false;
    }
    if (missingPublicKey) {
      _error = "This build can't be unlocked. Download SRLE Studio again from your order page.";
      notifyListeners();
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      final machine = await _fingerprint();
      final token = await _client.activate(key, machine);
      final a = await Activation.verify(token, _publicKey);
      if (a == null || a.machine != machine || a.key != key) {
        throw const LicenseException(
          "The store's answer didn't check out. Make sure this copy came from your order page.",
        );
      }
      await _store.setString(_tokenKey, token);
      _activation = a;
      _state = LicenseState.unlocked;
      return true;
    } on LicenseException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Frees this computer's slot and locks the app again.
  Future<void> deactivate() async {
    final a = _activation;
    if (a != null) await _client.deactivate(a.key, a.machine);
    await _store.remove(_tokenKey);
    _activation = null;
    _state = LicenseState.locked;
    notifyListeners();
  }
}
