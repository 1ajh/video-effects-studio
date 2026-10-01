import 'package:flutter/material.dart';

import '../../core/sparta/model.dart';
import '../theme.dart';

Color laneColor(SampleRole r) => switch (r) {
  SampleRole.pitch => const Color(0xFFA78BFA),
  SampleRole.word => const Color(0xFFF472B6),
  SampleRole.kick => const Color(0xFFFB923C),
  SampleRole.snare => const Color(0xFFFBBF24),
  SampleRole.hat => const Color(0xFF22D3EE),
  SampleRole.quote => const Color(0xFF34D399),
};

IconData laneIcon(SampleRole r) => switch (r) {
  SampleRole.pitch => Icons.music_note,
  SampleRole.word => Icons.record_voice_over_outlined,
  SampleRole.kick => Icons.circle,
  SampleRole.snare => Icons.album_outlined,
  SampleRole.hat => Icons.blur_on,
  SampleRole.quote => Icons.format_quote,
};

Color sectionColor(SectionKind k) => switch (k) {
  SectionKind.intro => const Color(0xFF64748B),
  SectionKind.chorus => const Color(0xFF7C5CFF),
  SectionKind.dundundenden => const Color(0xFF0EA5E9),
  SectionKind.preEpicness => const Color(0xFFFCD34D),
  SectionKind.postEpicness => const Color(0xFFD97706),
  SectionKind.epicness => const Color(0xFFF59E0B),
  SectionKind.madness => const Color(0xFFEF4444),
  SectionKind.awesomeness => const Color(0xFFEC4899),
  SectionKind.outro => const Color(0xFF10B981),
  SectionKind.other => const Color(0xFF94A3B8),
};

class LaneDot extends StatelessWidget {
  const LaneDot({super.key, required this.role, this.size = 8});
  final SampleRole role;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: laneColor(role), shape: BoxShape.circle),
  );
}

/// Numbered step card used by the setup column.
class SpartaCard extends StatelessWidget {
  const SpartaCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });
  final int step;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.sparta.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Text(
                  '$step',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.spartaHi),
                ),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(subtitle!, style: const TextStyle(fontSize: 11.5, color: AppColors.faint, height: 1.35)),
            ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });
  final bool selected;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected ? AppColors.sparta.withValues(alpha: 0.13) : AppColors.surface,
          border: Border.all(color: selected ? AppColors.sparta : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? AppColors.spartaHi : AppColors.faint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.faint, height: 1.3)),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

class FileRow extends StatelessWidget {
  const FileRow({super.key, required this.icon, required this.label, required this.onTap, this.onClear});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
            if (onClear != null)
              InkWell(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: AppColors.faint),
                ),
              )
            else
              const Icon(Icons.folder_open_outlined, size: 15, color: AppColors.faint),
          ],
        ),
      ),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12.5)),
                  if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.faint)),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
