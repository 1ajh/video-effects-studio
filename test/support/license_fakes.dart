import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:video_effects_studio/core/licensing/license.dart';

// Made by the store (store/lib/licensing.js) with a test key: the Ed25519
// key from the seed [7] * 32.
const nodePublicKey = '6kpsY-KcUgq-9VB7Ey7F-ZVHdq6-vnuSQh7qaRRG0iw';
const nodeToken =
    'eyJ2IjoxLCJrZXkiOiJTUkxFLUFCQ0RFLUZHSEpLLU1OUFFSLVNUVldYIiwibWFjaGluZSI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWEiLCJvcmRlciI6IlNSTEUtQUJDRC1FRkdIIiwiYXQiOiIyMDI2LTEwLTAxVDEyOjAwOjAwLjAwMFoifQ.f33aCWgKo8ioIilGG4cI_Co8sOops7AzCHfZ9iE4RzFkx6QBtbcGa7_jLdOZgDPqk6u-MYsM25sU3XC0GWWACg';

final machineA = 'a' * 64;
final machineB = 'b' * 64;

/// Base64url without padding, as the store writes it.
String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Signs an activation the way the store does.
Future<String> storeToken(Map<String, Object?> payload) async {
  final pair = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
  final body = utf8.encode(jsonEncode(payload));
  final sig = await Ed25519().sign(body, keyPair: pair);
  return '${b64url(body)}.${b64url(sig.bytes)}';
}

class FakeClient extends LicenseClient {
  FakeClient(this.answer);
  final Future<String> Function(String key, String machine) answer;
  final deactivated = <String>[];

  @override
  Future<String> activate(String key, String machine) => answer(key, machine);

  @override
  Future<void> deactivate(String key, String machine) async => deactivated.add(machine);
}
