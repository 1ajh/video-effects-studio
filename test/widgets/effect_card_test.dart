import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/widgets/effect_card.dart';
import 'package:video_effects_studio/models/effect_mode.dart';

void main() {
  group('EffectCard Widget', () {
    testWidgets('displays effect name and description', (WidgetTester tester) async {
      final effect = EffectMode(
        id: 'test_effect',
        name: 'Test Effect',
        description: 'This is a test effect description',
        category: 'Test',
        ffmpegFilter: '-vf test',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EffectCard(
              effect: effect,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Effect'), findsOneWidget);
      expect(find.text('This is a test effect description'), findsOneWidget);
    });

    testWidgets('shows selected state correctly', (WidgetTester tester) async {
      final effect = EffectMode(
        id: 'test_effect',
        name: 'Test Effect',
        description: 'Description',
        category: 'Test',
        ffmpegFilter: '-vf test',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EffectCard(
              effect: effect,
              isSelected: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // The card should have a check icon when selected
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (WidgetTester tester) async {
      bool tapped = false;
      final effect = EffectMode(
        id: 'test_effect',
        name: 'Test Effect',
        description: 'Description',
        category: 'Test',
        ffmpegFilter: '-vf test',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EffectCard(
              effect: effect,
              isSelected: false,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(EffectCard));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('displays category chip', (WidgetTester tester) async {
      final effect = EffectMode(
        id: 'test_effect',
        name: 'Test Effect',
        description: 'Description',
        category: 'Vocoder',
        ffmpegFilter: '-vf test',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EffectCard(
              effect: effect,
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Vocoder'), findsOneWidget);
    });
  });
}
