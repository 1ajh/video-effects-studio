import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/licensing/license.dart';
import '../../state/license_controller.dart';
import '../platform_actions.dart';
import '../theme.dart';

/// Shows [child] once this copy is unlocked; until then, the key screen.
class LicenseGate extends StatelessWidget {
  const LicenseGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseController>();
    return switch (license.state) {
      LicenseState.unlocked => child,
      LicenseState.checking => const Scaffold(body: Center(child: CircularProgressIndicator())),
      LicenseState.locked => const LicenseScreen(),
    };
  }
}

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate() => context.read<LicenseController>().activate(_key.text);

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _key.text = data!.text!.trim();
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseController>();
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Image.asset('assets/branding/logo_256.png', width: 88, height: 88)),
                const SizedBox(height: 16),
                Text('Unlock SRLE Studio', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Paste the license key from your order page. Unlocking needs internet this one time; '
                  'after that SRLE Studio works offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 22),
                TextField(
                  key: const Key('license-key'),
                  controller: _key,
                  enabled: !license.busy,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 0.5),
                  decoration: InputDecoration(
                    hintText: 'SRLE-XXXXX-XXXXX-XXXXX-XXXXX',
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste, size: 18),
                      onPressed: license.busy ? null : _paste,
                    ),
                  ),
                  onSubmitted: (_) => _activate(),
                ),
                if (license.error != null) ...[
                  const SizedBox(height: 10),
                  Text(license.error!, style: const TextStyle(color: AppColors.danger, height: 1.4)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('license-activate'),
                  onPressed: license.busy ? null : _activate,
                  child: license.busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Unlock'),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => openUrl('$storeUrl/buy'),
                  child: const Text("Don't have a key? Get one at srle.ajh.wtf"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
