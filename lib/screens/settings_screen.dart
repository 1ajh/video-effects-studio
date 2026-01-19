import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/preferences_service.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PreferencesService? _prefs;
  String _appVersion = '1.0.0';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await PreferencesService.getInstance();
    
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } catch (_) {}
    
    setState(() => _isLoading = false);
  }

  Future<void> _selectOutputDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await _prefs?.setOutputDirectory(result);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: [
          _buildSection(
            'General',
            [
              if (isDesktop)
                _buildSettingTile(
                  icon: Icons.folder,
                  title: 'Output Directory',
                  subtitle: _prefs?.outputDirectory ?? 'Default',
                  onTap: _selectOutputDirectory,
                ),
              _buildSwitchTile(
                icon: Icons.update,
                title: 'Auto Check for Updates',
                subtitle: 'Automatically check for new versions',
                value: _prefs?.autoCheckUpdates ?? true,
                onChanged: (value) async {
                  await _prefs?.setAutoCheckUpdates(value);
                  setState(() {});
                },
              ),
              _buildSwitchTile(
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Show notifications when processing completes',
                value: _prefs?.notificationsEnabled ?? true,
                onChanged: (value) async {
                  await _prefs?.setNotificationsEnabled(value);
                  setState(() {});
                },
              ),
            ],
          ),
          _buildSection(
            'Processing',
            [
              _buildDropdownTile(
                icon: Icons.high_quality,
                title: 'Default Quality',
                value: _prefs?.defaultQuality ?? 'high',
                items: QualityPreset.all.map((q) => DropdownMenuItem(
                  value: q,
                  child: Text(QualityPreset.getLabel(q)),
                )).toList(),
                onChanged: (value) async {
                  if (value != null) {
                    await _prefs?.setDefaultQuality(value);
                    setState(() {});
                  }
                },
              ),
              _buildSwitchTile(
                icon: Icons.volume_up,
                title: 'Preserve Original Audio',
                subtitle: 'Keep original audio track when possible',
                value: _prefs?.preserveOriginalAudio ?? false,
                onChanged: (value) async {
                  await _prefs?.setPreserveOriginalAudio(value);
                  setState(() {});
                },
              ),
              _buildSwitchTile(
                icon: Icons.computer,
                title: 'Show Desktop-Only Effects',
                subtitle: 'Display effects that require desktop features',
                value: _prefs?.showDesktopOnlyEffects ?? true,
                onChanged: (value) async {
                  await _prefs?.setShowDesktopOnlyEffects(value);
                  setState(() {});
                },
              ),
            ],
          ),
          _buildSection(
            'Data Management',
            [
              _buildSettingTile(
                icon: Icons.history,
                title: 'Clear Recent Files',
                subtitle: '${_prefs?.recentFiles.length ?? 0} files in history',
                onTap: () => _showClearConfirmDialog(
                  'Clear Recent Files',
                  'This will remove all recent files from the list.',
                  () async {
                    await _prefs?.clearRecentFiles();
                    setState(() {});
                  },
                ),
              ),
              _buildSettingTile(
                icon: Icons.delete_sweep,
                title: 'Clear Processing History',
                subtitle: '${_prefs?.processingHistory.length ?? 0} entries',
                onTap: () => _showClearConfirmDialog(
                  'Clear Processing History',
                  'This will remove all processing history.',
                  () async {
                    await _prefs?.clearHistory();
                    setState(() {});
                  },
                ),
              ),
              _buildSettingTile(
                icon: Icons.restore,
                title: 'Reset All Settings',
                subtitle: 'Restore default settings',
                textColor: Colors.red,
                onTap: () => _showClearConfirmDialog(
                  'Reset All Settings',
                  'This will reset all settings to their default values. This action cannot be undone.',
                  () async {
                    await _prefs?.resetToDefaults();
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          _buildSection(
            'About',
            [
              _buildSettingTile(
                icon: Icons.info,
                title: 'Version',
                subtitle: _appVersion,
              ),
              _buildSettingTile(
                icon: Icons.code,
                title: 'Source Code',
                subtitle: 'View on GitHub',
                onTap: () => _launchUrl('https://github.com/1ajh/video-effects-studio'),
              ),
              _buildSettingTile(
                icon: Icons.bug_report,
                title: 'Report a Bug',
                subtitle: 'Submit an issue on GitHub',
                onTap: () => _launchUrl('https://github.com/1ajh/video-effects-studio/issues'),
              ),
              _buildSettingTile(
                icon: Icons.description,
                title: 'License',
                subtitle: 'MIT License',
                onTap: () => _showLicenseDialog(),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Made with ❤️ by AJH',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: textColor),
      title: Text(title, style: TextStyle(color: textColor)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: textColor?.withOpacity(0.7)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownTile<T>({
    required IconData icon,
    required String title,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
      ),
    );
  }

  void _showClearConfirmDialog(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showLicenseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('MIT License'),
        content: SingleChildScrollView(
          child: Text(
            '''MIT License

Copyright (c) 2024 AJH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
