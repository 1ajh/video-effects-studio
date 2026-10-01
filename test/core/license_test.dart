import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/core/licensing/license.dart';
import 'package:video_effects_studio/state/license_controller.dart';
import 'package:video_effects_studio/state/store.dart';

import '../support/license_fakes.dart';

Future<Store> emptyStore() async {
  SharedPreferences.setMockInitialValues({});
  return Store(await SharedPreferences.getInstance());
}

void main() {
  test('typed keys are read the way the store reads them', () {
    expect(normalizeKey('srle abcde-fghjk mnpqr stvwx'), 'SRLE-ABCDE-FGHJK-MNPQR-STVWX');
    expect(normalizeKey(' SRLE-0O1IL-22222-33333-44444 '), 'SRLE-00111-22222-33333-44444');
    expect(normalizeKey('SRLE-ABCD-EFGH'), isNull);
    expect(isOrderCode('srle-abcd-efgh'), isTrue);
    expect(isOrderCode('SRLE-ABCDE-FGHJK-MNPQR-STVWX'), isFalse);
  });

  test("an activation signed by the store verifies; changed or someone else's does not", () async {
    final a = await Activation.verify(nodeToken, nodePublicKey);
    expect(a?.key, 'SRLE-ABCDE-FGHJK-MNPQR-STVWX');
    expect(a?.machine, machineA);
    expect(a?.order, 'SRLE-ABCD-EFGH');

    final parts = nodeToken.split('.');
    final forged = b64url(
      utf8.encode(jsonEncode({'v': 1, 'key': 'SRLE-ABCDE-FGHJK-MNPQR-STVWX', 'machine': machineB})),
    );
    expect(await Activation.verify('$forged.${parts[1]}', nodePublicKey), isNull);
    final other = await (await Ed25519().newKeyPairFromSeed(List.filled(32, 9))).extractPublicKey();
    expect(await Activation.verify(nodeToken, b64url(other.bytes)), isNull);
    expect(await Activation.verify('garbage', nodePublicKey), isNull);
  });

  group('LicenseController', () {
    test('a development build without the store key runs unlocked', () async {
      final c = LicenseController(await emptyStore(), publicKey: '', allowUnlicensed: true);
      expect(c.unlocked, isTrue);
      expect(c.unlicensedBuild, isTrue);
    });

    test('locked until a key is activated, then unlocked offline on every start', () async {
      final store = await emptyStore();
      final client = FakeClient(
        (key, machine) => storeToken({'v': 1, 'key': key, 'machine': machine, 'order': 'SRLE-ABCD-EFGH', 'at': 'now'}),
      );
      final c = LicenseController(store, client: client, publicKey: nodePublicKey, machine: () async => machineA);
      await c.load();
      expect(c.state, LicenseState.locked);

      expect(await c.activate('srle abcde fghjk mnpqr stvwx'), isTrue);
      expect(c.unlocked, isTrue);
      expect(c.maskedKey, 'SRLE-ABCDE…STVWX');

      // Next start: no network, the saved activation is enough.
      final offline = LicenseController(
        store,
        client: FakeClient((_, _) => throw const LicenseException('offline')),
        publicKey: nodePublicKey,
        machine: () async => machineA,
      );
      await offline.load();
      expect(offline.unlocked, isTrue);

      // Copied to another computer, it doesn't unlock.
      final copied = LicenseController(store, client: client, publicKey: nodePublicKey, machine: () async => machineB);
      await copied.load();
      expect(copied.state, LicenseState.locked);

      await c.deactivate();
      expect(c.state, LicenseState.locked);
      expect(client.deactivated, [machineA]);
      await offline.load();
      expect(offline.state, LicenseState.locked);
    });

    test('explains order codes, typos and refusals; never trusts an unsigned answer', () async {
      final store = await emptyStore();
      var answer = 'unsigned.token';
      final c = LicenseController(
        store,
        client: FakeClient((key, machine) async {
          if (answer == 'refuse') throw const LicenseException('This key is already on 3 computers.');
          return answer;
        }),
        publicKey: nodePublicKey,
        machine: () async => machineA,
      );
      await c.load();
      expect(await c.activate('SRLE-ABCD-EFGH'), isFalse);
      expect(c.error, contains('order code'));
      expect(await c.activate('hello'), isFalse);
      expect(c.error, contains("isn't a license key"));
      expect(await c.activate('SRLE-ABCDE-FGHJK-MNPQR-STVWX'), isFalse);
      expect(c.error, contains("didn't check out"));
      answer = 'refuse';
      expect(await c.activate('SRLE-ABCDE-FGHJK-MNPQR-STVWX'), isFalse);
      expect(c.error, contains('3 computers'));
      // A valid signature for a different key or computer is refused too.
      answer = await storeToken({'v': 1, 'key': 'SRLE-ABCDE-FGHJK-MNPQR-STVWX', 'machine': machineB});
      expect(await c.activate('SRLE-ABCDE-FGHJK-MNPQR-STVWX'), isFalse);
      expect(c.state, LicenseState.locked);
    });

    test('a release build made without the store key says it cannot unlock', () async {
      final c = LicenseController(
        await emptyStore(),
        publicKey: '',
        allowUnlicensed: false,
        machine: () async => machineA,
      );
      await c.load();
      expect(c.missingPublicKey, isTrue);
      expect(await c.activate('SRLE-ABCDE-FGHJK-MNPQR-STVWX'), isFalse);
      expect(c.error, contains("can't be unlocked"));
    });
  });

  test('the fingerprint is a 64-character hash, the same each time', () async {
    final a = await machineFingerprint(fallback: () async => 'install-1');
    final b = await machineFingerprint(fallback: () async => 'install-1');
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(a, b);
  });
}
