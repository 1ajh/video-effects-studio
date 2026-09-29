import 'package:flutter/material.dart';

import '../theme.dart';

/// Title row at the top of a panel.
class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.title, this.icon, this.trailing = const [], this.subtitle});

  final String title;
  final IconData? icon;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: AppColors.muted), const SizedBox(width: 8)],
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: AppColors.muted,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                subtitle!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ),
          ],
          const Spacer(),
          ...trailing,
        ],
      ),
    );
  }
}

/// Small rounded label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.muted, this.icon, this.filled = false, this.tooltip});

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: filled ? 0.0 : 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.1),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Compact icon button with tooltip.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.size = 18,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: size,
            color: onPressed == null
                ? AppColors.faint.withValues(alpha: 0.5)
                : (color ?? (active ? AppColors.accentHi : AppColors.muted)),
          ),
        ),
      ),
    );
  }
}

/// Rebuilds with hover state.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.cursor = SystemMouseCursors.basic});
  final Widget Function(BuildContext context, bool hovering) builder;
  final MouseCursor cursor;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: widget.builder(context, _hover),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actions = const []});

  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.faint),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section title inside a panel body.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.faint),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// Colored square with a category icon.
class CategoryGlyph extends StatelessWidget {
  const CategoryGlyph({super.key, required this.color, required this.icon, this.size = 36});
  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.12)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: size * 0.5, color: color),
  );
}

void showMessage(BuildContext context, String message, {SnackBarAction? action, bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: error ? AppColors.danger : AppColors.accentHi,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        action: action,
        duration: Duration(seconds: action == null ? 3 : 6),
      ),
    );
}
