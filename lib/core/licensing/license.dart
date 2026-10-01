import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Where keys are sold and activated.
const storeUrl = 'https://srle.ajh.wtf';

/// The store's Ed25519 public key (base64url of its 32 raw bytes), given to
/// release builds with `--dart-define=SRLE_LICENSE_PUBLIC_KEY=...`.
const builtInPublicKey = String.fromEnvironment('SRLE_LICENSE_PUBLIC_KEY');

// Crockford base32, as the store writes keys.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String? _canonical(String input, int length) {
  var s = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!s.startsWith('SRLE')) return null;
  s = s.substring(4).replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
  if (s.length != length || s.split('').any((c) => !_alphabet.contains(c))) return null;
  return s;
}

/// A typed or pasted license key in the store's form
/// (SRLE-XXXXX-XXXXX-XXXXX-XXXXX), or null. Case, spaces and dashes don't
/// matter; O reads as 0 and I/L as 1.
String? normalizeKey(String input) {
  final s = _canonical(input, 20);
  if (s == null) return null;
  return 'SRLE-${s.substring(0, 5)}-${s.substring(5, 10)}-${s.substring(10, 15)}-${s.substring(15)}';
}

/// Whether [input] is an order code (SRLE-XXXX-XXXX) rather than a key.
bool isOrderCode(String input) => _canonical(input, 8) != null;

/// What a signed activation says.
class Activation {
  const Activation({required this.key, required this.machine, required this.order, required this.at});

  final String key;
  final String machine;
  final String order;
  final String at;

  /// The activation in [token] when the store signed it with the key whose
  /// public half is [publicKey] (base64url); null otherwise.
  static Future<Activation?> verify(String token, String publicKey) async {
    try {
      final parts = token.split('.');
      if (parts.length != 2 || publicKey.isEmpty) return null;
      final body = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      final key = base64Url.decode(base64Url.normalize(publicKey));
      final ok = await Ed25519().verify(
        body,
        signature: Signature(signature, publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)),
      );
      if (!ok) return null;
      final j = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      return Activation(
        key: j['key'] as String? ?? '',
        machine: j['machine'] as String? ?? '',
        order: j['order'] as String? ?? '',
        at: j['at'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// A one-way fingerprint of this computer (64 hex characters), so a key
/// isn't used on more computers than it allows. Built from the system's
/// own install id, which survives reinstalling the app; [fallback] is used
/// where there is none.
Future<String> machineFingerprint({required Future<String> Function() fallback}) async {
  String? id;
  try {
    if (Platform.isLinux) {
      for (final f in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
        final file = File(f);
        if (await file.exists()) {
          id = (await file.readAsString()).trim();
          if (id.isNotEmpty) break;
        }
      }
    } else if (Platform.isMacOS) {
      final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      id = RegExp(r'"IOPlatformUUID" = "([^"]+)"').firstMatch('${r.stdout}')?.group(1);
    } else if (Platform.isWindows) {
      final r = await Process.run('reg', ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
      id = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${r.stdout}')?.group(1);
    }
  } catch (_) {
    id = null;
  }
  if (id == null || id.isEmpty) id = await fallback();
  return hash.sha256.convert(utf8.encode('srle-studio:$id')).toString();
}

/// A key the store turned down, with the store's explanation.
class LicenseException implements Exception {
  const LicenseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the store's key API.
class LicenseClient {
  LicenseClient({http.Client? client, this.baseUrl = storeUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// The signed activation for [key] on [machine].
  Future<String> activate(String key, String machine) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('$baseUrl/api/activate'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'key': key, 'machine': machine, 'platform': Platform.operatingSystem}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const LicenseException("The store didn't answer. Check your internet and try again.");
    } on Exception {
      throw const LicenseException("Couldn't reach the store. Unlocking needs internet this one time.");
    }
    Map<String, Object?> body;
    try {
      body = jsonDecode(r.body) as Map<String, Object?>;
    } catch (_) {
      throw LicenseException('The store gave an unexpected answer (${r.statusCode}). Try again in a bit.');
    }
    final token = body['token'];
    if (r.statusCode == 200 && token is String) return token;
    throw LicenseException(body['message'] as String? ?? 'That key was not accepted.');
  }

  /// Frees this computer's slot on [key]. Best effort.
  Future<void> deactivate(String key, String machine) async {
    try {
      await _client
          .post(
            Uri.parse('$baseUrl/api/deactivate'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'key': key, 'machine': machine}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline: the slot can be reset from the store instead.
    }
  }
}
