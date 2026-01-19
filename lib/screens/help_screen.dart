import 'package:flutter/material.dart';
import '../models/effect_mode.dart';
import '../models/effects_registry.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & FAQ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick Start Guide
          _buildSection(
            context,
            icon: Icons.play_circle,
            title: 'Quick Start Guide',
            children: [
              _buildStep(
                '1',
                'Select Videos',
                'Tap "Add Videos" or drag & drop video files into the app.',
              ),
              _buildStep(
                '2',
                'Choose Effect',
                'Browse and select an effect from the effects grid.',
              ),
              _buildStep(
                '3',
                'Adjust Parameters',
                'If available, customize the effect parameters to your liking.',
              ),
              _buildStep(
                '4',
                'Process',
                'Tap the "Process" button to apply the effect to your videos.',
              ),
              _buildStep(
                '5',
                'View Results',
                'Find your processed videos in the output folder.',
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Effect Categories
          _buildSection(
            context,
            icon: Icons.category,
            title: 'Effect Categories',
            children: [
              _buildCategoryInfo(
                EffectCategory.vocoder,
                'Vocoder Effects',
                'Audio effects that create robotic or synthesized voice sounds with matching visual filters.',
                Icons.mic,
                Colors.purple,
              ),
              _buildCategoryInfo(
                EffectCategory.colorGrade,
                'Color Grading',
                'Visual effects that change color schemes, hues, and saturation of your videos.',
                Icons.palette,
                Colors.orange,
              ),
              _buildCategoryInfo(
                EffectCategory.glitch,
                'Glitch & Distortion',
                'G Major effects and other distortion-based audio/visual effects.',
                Icons.broken_image,
                Colors.red,
              ),
              _buildCategoryInfo(
                EffectCategory.audio,
                'Audio Effects',
                'Pure audio manipulation like pitch shifting and audio export options.',
                Icons.audiotrack,
                Colors.blue,
              ),
              _buildCategoryInfo(
                EffectCategory.ytpmv,
                'YTPMV Tools',
                'Tools for creating YouTube Poop Music Videos and Sparta remixes.',
                Icons.music_note,
                Colors.green,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // FAQ Section
          _buildSection(
            context,
            icon: Icons.help,
            title: 'Frequently Asked Questions',
            children: [
              _buildFAQ(
                'What video formats are supported?',
                'Video Effects Studio supports most common video formats '
                    'including MP4, MOV, AVI, MKV, and WebM.',
              ),
              _buildFAQ(
                'Where are processed videos saved?',
                'By default, processed videos are saved to the '
                    'VideoEffectsStudio folder in your Documents/Videos '
                    'directory. You can change this in Settings.',
              ),
              _buildFAQ(
                'What does "Desktop Only" mean?',
                'Some effects require desktop-specific features (like Wine '
                    'for autotune.exe) and may not work correctly on mobile '
                    'devices or web.',
              ),
              _buildFAQ(
                'Can I process multiple videos at once?',
                'Yes! You can select multiple videos and process them all '
                    'at once. They will be processed in sequence.',
              ),
              _buildFAQ(
                'Why is processing slow?',
                'Video processing is computationally intensive. Processing '
                    'time depends on video length, resolution, and the '
                    'complexity of the selected effect.',
              ),
              _buildFAQ(
                'How do I cancel processing?',
                'Click the "Cancel" button in the processing dialog to '
                    'stop the current operation.',
              ),
              _buildFAQ(
                'What is G Major?',
                'G Major is a type of audio/visual effect popular in the '
                    'YouTube Poop community. It typically involves inverted '
                    'colors and pitch-shifted audio harmonies.',
              ),
              _buildFAQ(
                'How do I update the app?',
                'The app automatically checks for updates. When available, '
                    'you\'ll see a banner at the top of the screen with '
                    'update details.',
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Keyboard Shortcuts (for desktop)
          _buildSection(
            context,
            icon: Icons.keyboard,
            title: 'Keyboard Shortcuts (Desktop)',
            children: [
              _buildShortcut('Ctrl/Cmd + O', 'Open file picker'),
              _buildShortcut('Ctrl/Cmd + Enter', 'Start processing'),
              _buildShortcut('Escape', 'Cancel processing'),
              _buildShortcut('Ctrl/Cmd + ,', 'Open settings'),
              _buildShortcut('/', 'Focus search'),
            ],
          ),

          const SizedBox(height: 24),

          // Troubleshooting
          _buildSection(
            context,
            icon: Icons.build,
            title: 'Troubleshooting',
            children: [
              _buildTroubleshoot(
                'Processing fails immediately',
                'Make sure the video file is not corrupted and is in a supported format. Try with a different video to verify.',
              ),
              _buildTroubleshoot(
                'No audio in output',
                'Some effects may not preserve audio. Check if the effect is audio-only or if "Preserve Original Audio" is enabled in Settings.',
              ),
              _buildTroubleshoot(
                'App crashes during processing',
                'This may happen with very large files. Try reducing the video quality setting or processing smaller videos.',
              ),
              _buildTroubleshoot(
                'Output video looks wrong',
                'Different effects have different expected outputs. Check the effect description for what to expect.',
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Contact Support
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.support_agent,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Need More Help?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Submit an issue on GitHub or check the documentation for more information.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      // Launch GitHub issues page
                    },
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Report Issue'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryInfo(
    String category,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    final count = EffectsRegistry.getByCategory(category).length;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count effects',
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQ(String question, String answer) {
    return ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(fontSize: 14),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcut(String keys, String action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            action,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTroubleshoot(String issue, String solution) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Text(
              solution,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
