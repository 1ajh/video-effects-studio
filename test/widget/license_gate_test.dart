import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/app.dart';
import 'package:video_effects_studio/core/licensing/license.dart';
import 'package:video_effects_studio/state/license_controller.dart';
import 'package:video_effects_studio/state/store.dart';

import '../support/license_fakes.dart';

void main() {
  testWidgets('the app opens locked and unlocks with a key from the store', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final machine = 'a' * 64;
    final license = LicenseController(
      store,
      client: FakeClient((key, m) {
        if (key == 'SRLE-AAAAA-AAAAA-AAAAA-AAAAA') {
          throw const LicenseException("That key doesn't exist. Check it against your order page.");
        }
        return storeToken({'v': 1, 'key': key, 'machine': m, 'order': 'SRLE-ABCD-EFGH', 'at': 'now'});
      }),
      publicKey: nodePublicKey,
      machine: () async => machine,
      allowUnlicensed: false,
    );
    await tester.pumpWidget(StudioApp(store: store, playerAvailable: false, autoInit: false, license: license));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('Unlock SRLE Studio'), findsOneWidget);
    expect(find.byTooltip('Sparta Remix generator (Ctrl+3)'), findsNothing);

    // An order code is explained, not sent.
    await tester.enterText(find.byKey(const Key('license-key')), 'SRLE-ABCD-EFGH');
    await tester.tap(find.byKey(const Key('license-activate')));
    await tester.pump();
    expect(find.textContaining("That's your order code"), findsOneWidget);

    // The store's refusal is shown.
    await tester.enterText(find.byKey(const Key('license-key')), 'SRLE-AAAAA-AAAAA-AAAAA-AAAAA');
    await tester.runAsync(() => license.activate('SRLE-AAAAA-AAAAA-AAAAA-AAAAA'));
    await tester.pump();
    expect(find.textContaining("That key doesn't exist"), findsOneWidget);

    // A real key unlocks the editor.
    await tester.runAsync(() => license.activate('srle-abcde-fghjk-mnpqr-stvwx'));
    await tester.pump();
    expect(find.text('Unlock SRLE Studio'), findsNothing);
    expect(find.byTooltip('Sparta Remix generator (Ctrl+3)'), findsOneWidget);
  });
}
