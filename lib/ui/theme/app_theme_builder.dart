import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_tema_id.dart';

abstract final class AppThemeBuilder {
  static const _globalRadius = 12.0;

  static ThemeData build(AppTemaId tema) {
    final brightness = tema.isDark ? Brightness.dark : Brightness.light;
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: tema.corDestaque,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.standard,
    );
    final textoPrincipal = baseTheme.colorScheme.onSurface;
    final globalShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_globalRadius),
    );
    final semantic =
        tema.isDark ? AppSemanticColors.escuro : AppSemanticColors.claro;

    return baseTheme.copyWith(
      scaffoldBackgroundColor: baseTheme.colorScheme.surface,
      textTheme: baseTheme.textTheme.copyWith(
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
          fontSize: (baseTheme.textTheme.bodyLarge?.fontSize ?? 16) * 1.05,
          height: 1.35,
          color: textoPrincipal,
        ),
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
          fontSize: (baseTheme.textTheme.bodyMedium?.fontSize ?? 14) * 1.05,
          height: 1.35,
          color: textoPrincipal,
        ),
        bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
          fontSize: (baseTheme.textTheme.bodySmall?.fontSize ?? 12) * 1.05,
          height: 1.35,
          color: textoPrincipal,
        ),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
          color: textoPrincipal,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          color: textoPrincipal,
        ),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(color: baseTheme.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(
            color: baseTheme.colorScheme.primary,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(color: baseTheme.colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(
            color: baseTheme.colorScheme.error,
            width: 1.4,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          side: BorderSide(color: baseTheme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: globalShape,
          minimumSize: const Size(88, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: globalShape,
          minimumSize: const Size(88, 44),
          side: BorderSide(color: baseTheme.colorScheme.outline),
        ),
      ),
      dialogTheme: DialogThemeData(shape: globalShape),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: baseTheme.colorScheme.surfaceContainerLow,
        indicatorColor: baseTheme.colorScheme.primaryContainer,
      ),
      extensions: [semantic],
    );
  }
}
