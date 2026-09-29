import 'package:flutter/material.dart';

import '../core/effects/effect.dart';

/// Design tokens for the dark "pro editor" look.
abstract final class AppColors {
  static const bg = Color(0xFF0E0E12);
  static const panel = Color(0xFF15151B);
  static const surface = Color(0xFF1B1B23);
  static const surfaceHi = Color(0xFF23232D);
  static const border = Color(0xFF2A2A36);
  static const borderHi = Color(0xFF3A3A4A);

  static const text = Color(0xFFECECF3);
  static const muted = Color(0xFF9A9AAE);
  static const faint = Color(0xFF6B6B7E);

  static const accent = Color(0xFF7C5CFF);
  static const accentHi = Color(0xFF9B82FF);
  static const compilation = Color(0xFF22D3EE);
  static const warn = Color(0xFFF5A524);
  static const danger = Color(0xFFF43F5E);
  static const success = Color(0xFF22C55E);

  static Color category(EffectCategory c) => switch (c) {
    EffectCategory.logoEditing => const Color(0xFFF472B6),
    EffectCategory.gMajor => const Color(0xFFA78BFA),
    EffectCategory.vocoder => const Color(0xFF60A5FA),
    EffectCategory.color => const Color(0xFFFBBF24),
    EffectCategory.distort => const Color(0xFF34D399),
    EffectCategory.glitch => const Color(0xFFF87171),
    EffectCategory.audio => const Color(0xFF22D3EE),
    EffectCategory.time => const Color(0xFFFB923C),
    EffectCategory.ytpmv => const Color(0xFFC084FC),
    EffectCategory.custom => const Color(0xFF94A3B8),
  };

  static IconData categoryIcon(EffectCategory c) => switch (c) {
    EffectCategory.logoEditing => Icons.auto_awesome,
    EffectCategory.gMajor => Icons.piano,
    EffectCategory.vocoder => Icons.graphic_eq,
    EffectCategory.color => Icons.palette_outlined,
    EffectCategory.distort => Icons.waves,
    EffectCategory.glitch => Icons.tv,
    EffectCategory.audio => Icons.equalizer,
    EffectCategory.time => Icons.speed,
    EffectCategory.ytpmv => Icons.queue_music,
    EffectCategory.custom => Icons.code,
  };
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.compilation,
    onSecondary: Colors.black,
    surface: AppColors.panel,
    onSurface: AppColors.text,
    surfaceContainerLowest: AppColors.bg,
    surfaceContainerLow: AppColors.panel,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHi,
    surfaceContainerHighest: AppColors.surfaceHi,
    outline: AppColors.borderHi,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.bg,
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
  );

  final text = base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text);

  return base.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, color: AppColors.muted, height: 1.35),
      labelSmall: text.labelSmall?.copyWith(fontSize: 11, letterSpacing: 0.4, color: AppColors.muted),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: AppColors.muted, size: 18),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHi,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderHi),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.faint, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Inter'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.borderHi),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Inter'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentHi,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Inter'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.borderHi)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.accent.withValues(alpha: 0.22) : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.text : AppColors.muted,
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.border,
      thumbColor: Colors.white,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      showValueIndicator: ShowValueIndicator.never,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.border,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(fontSize: 13, color: AppColors.text, fontFamily: 'Inter'),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHi,
      contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13, fontFamily: 'Inter'),
      actionTextColor: AppColors.accentHi,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderHi),
      ),
      width: 460,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.border,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppColors.borderHi.withValues(alpha: 0.8)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : Colors.transparent,
      ),
      side: const BorderSide(color: AppColors.borderHi, width: 1.4),
    ),
  );
}
