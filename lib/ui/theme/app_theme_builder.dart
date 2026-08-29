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
    final scheme = baseTheme.colorScheme;
    // Menus/dropdowns abertos precisam de fundo 100% opaco: com plano de fundo
    // pintado, surface tint / translucidez do M3 deixa as opcoes ilegíveis.
    final menuSurface = Color.alphaBlend(
      scheme.surfaceContainerHighest,
      tema.isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF),
    );
    final campoSurface = Color.alphaBlend(
      scheme.surface,
      tema.isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF),
    );
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(menuSurface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.35)),
      elevation: const WidgetStatePropertyAll(10),
      shape: WidgetStatePropertyAll(globalShape),
      side: WidgetStatePropertyAll(
        BorderSide(color: scheme.outlineVariant),
      ),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: menuSurface,
      cardColor: campoSurface,
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
        filled: true,
        fillColor: campoSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          borderSide: BorderSide(
            color: scheme.error,
            width: 1.4,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: campoSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
          side: BorderSide(color: scheme.outlineVariant),
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
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: globalShape,
        backgroundColor: menuSurface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: menuSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: globalShape,
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      dropdownMenuTheme: DropdownMenuThemeData(menuStyle: menuStyle),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: menuSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_globalRadius)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_globalRadius),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
      ),
      extensions: [semantic],
    );
  }
}
