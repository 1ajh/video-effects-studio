import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/effects/effect.dart';
import '../core/effects/registry.dart';
import '../state/update_controller.dart';
import 'theme.dart';

/// Shown on web and mobile: explains that rendering needs the desktop app
/// and lets people browse the effect library.
class UnsupportedPlatformApp extends StatelessWidget {
  const UnsupportedPlatformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SRLE Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Landing(),
    );
  }
}

class _Landing extends StatelessWidget {
  const _Landing();

  @override
  Widget build(BuildContext context) {
    final effects = EffectRegistry.builtIn;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, Color(0xFFE040FB), AppColors.compilation],
                        ),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 18),
                    Text('SRLE Studio', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26)),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: const Text(
                        'Rendering runs FFmpeg on your computer, so the studio is a desktop app for Windows, macOS and Linux. '
                        'Here is everything it can do:',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () =>
                          launchUrl(Uri.parse(UpdateController.releasesUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.download),
                      label: const Text('Download the desktop app'),
                    ),
                    const SizedBox(height: 28),
                    Text('${effects.length} effects', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: 76,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _EffectCard(effect: effects[i]),
                  childCount: effects.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EffectCard extends StatelessWidget {
  const _EffectCard({required this.effect});
  final Effect effect;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.category(effect.category);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(AppColors.categoryIcon(effect.category), color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(effect.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  effect.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
