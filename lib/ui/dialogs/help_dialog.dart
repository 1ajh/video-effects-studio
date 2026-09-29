import 'package:flutter/material.dart';

import '../theme.dart';

const shortcuts = <(String, String)>[
  ('Ctrl + O', 'Add clips'),
  ('Ctrl + Enter', 'Render (effect or compilation)'),
  ('Ctrl + P', 'Render the effect preview now'),
  ('Space', 'Play / pause'),
  ('Home', 'Back to the start'),
  ('I / O', 'Set trim in / out at the playhead'),
  ('Ctrl + F', 'Search effects'),
  ('↑ / ↓', 'Previous / next effect'),
  ('Ctrl + D', 'Add effect to the compilation'),
  ('Ctrl + 1 / 2 / 3', 'Single effect / Compilation / Sparta Remix mode'),
  ('1 / 2 / 3', 'Original / Effect / Split view'),
  ('Ctrl + H', 'Render history'),
  ('Ctrl + ,', 'Settings'),
  ('Ctrl + Q', 'Render queue'),
  ('F1', 'This help'),
];

Future<void> showHelpDialog(BuildContext context) => showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Shortcuts & tips'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (keys, what) in shortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 130,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(keys, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(what, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            const Text('Tips', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final tip in const [
              'Compilation mode plays your clip once per effect, in order — like the "X effects" videos. '
                  'Use "All effects", "Add category" or "Random" to fill it fast, and drag cards to reorder.',
              'Each compilation item keeps its own settings: click a card to edit it in the inspector.',
              'Trim the clip first — everything (previews, renders, compilations) uses the trimmed range.',
              'Effects marked with a speaker icon are loud on purpose (no limiter). Mind your ears.',
              'Hourglass effects (reverse etc.) hold the whole clip in memory; keep those clips short.',
              'Make your own effects with raw FFmpeg filters: the + button in the effect list.',
              'Sparta Remix: more sources give more variety. Drop an .flp, .flm or .mid on the window to use it as the base.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(Icons.circle, size: 6, color: AppColors.accentHi),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tip, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
  ),
);
