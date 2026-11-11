import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static const radius = BorderRadius.all(Radius.circular(4));

  /// Use for prices, quantities, barcodes and IDs so digits line up
  /// in columns. Example: Text('1,250.00', style: AppTheme.numeric)
  static const numeric = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Menlo', 'Roboto Mono', 'monospace'],
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.navy,
      error: AppColors.danger,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.danger,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.compact,
      dividerColor: AppColors.border,
    );

    const side = BorderSide(color: AppColors.border);
    const shape = RoundedRectangleBorder(borderRadius: radius);

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.navy,
        displayColor: AppColors.navy,
      ),
      iconTheme: const IconThemeData(size: 18, color: AppColors.navy),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius, side: side),
      ),
      dialogTheme: const DialogThemeData(
        elevation: 0,
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius, side: side),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: radius, borderSide: side),
        enabledBorder:
            OutlineInputBorder(borderRadius: radius, borderSide: side),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(64, 40),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 40),
          shape: shape,
          side: side,
          foregroundColor: AppColors.navy,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape),
      ),
    );
  }
}