import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.successBg,
    required this.successBorder,
    required this.successFg,
    required this.warningBg,
    required this.warningBorder,
    required this.warningFg,
    required this.errorBg,
    required this.errorBorder,
    required this.errorFg,
    required this.infoBg,
    required this.infoBorder,
    required this.infoFg,
  });

  final Color successBg;
  final Color successBorder;
  final Color successFg;
  final Color warningBg;
  final Color warningBorder;
  final Color warningFg;
  final Color errorBg;
  final Color errorBorder;
  final Color errorFg;
  final Color infoBg;
  final Color infoBorder;
  final Color infoFg;

  static const AppSemanticColors claro = AppSemanticColors(
    successBg: Color(0xFFEAF8EF),
    successBorder: Color(0xFF8FD1A8),
    successFg: Color(0xFF166534),
    warningBg: Color(0xFFFFF8E6),
    warningBorder: Color(0xFFF2CC7A),
    warningFg: Color(0xFF8A5B00),
    errorBg: Color(0xFFFDECEC),
    errorBorder: Color(0xFFF1A3A3),
    errorFg: Color(0xFF9B1C1C),
    infoBg: Color(0xFFEAF2FF),
    infoBorder: Color(0xFF9EC0FF),
    infoFg: Color(0xFF1E3A8A),
  );

  static const AppSemanticColors escuro = AppSemanticColors(
    successBg: Color(0xFF1B3D2A),
    successBorder: Color(0xFF3D8B5E),
    successFg: Color(0xFF86EFAC),
    warningBg: Color(0xFF3D3418),
    warningBorder: Color(0xFF9A7B2E),
    warningFg: Color(0xFFFCD34D),
    errorBg: Color(0xFF3D1E1E),
    errorBorder: Color(0xFF9A4A4A),
    errorFg: Color(0xFFFCA5A5),
    infoBg: Color(0xFF1E2A45),
    infoBorder: Color(0xFF4A6FA5),
    infoFg: Color(0xFF93C5FD),
  );

  @override
  ThemeExtension<AppSemanticColors> copyWith({
    Color? successBg,
    Color? successBorder,
    Color? successFg,
    Color? warningBg,
    Color? warningBorder,
    Color? warningFg,
    Color? errorBg,
    Color? errorBorder,
    Color? errorFg,
    Color? infoBg,
    Color? infoBorder,
    Color? infoFg,
  }) {
    return AppSemanticColors(
      successBg: successBg ?? this.successBg,
      successBorder: successBorder ?? this.successBorder,
      successFg: successFg ?? this.successFg,
      warningBg: warningBg ?? this.warningBg,
      warningBorder: warningBorder ?? this.warningBorder,
      warningFg: warningFg ?? this.warningFg,
      errorBg: errorBg ?? this.errorBg,
      errorBorder: errorBorder ?? this.errorBorder,
      errorFg: errorFg ?? this.errorFg,
      infoBg: infoBg ?? this.infoBg,
      infoBorder: infoBorder ?? this.infoBorder,
      infoFg: infoFg ?? this.infoFg,
    );
  }

  @override
  ThemeExtension<AppSemanticColors> lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      successBg: Color.lerp(successBg, other.successBg, t) ?? successBg,
      successBorder:
          Color.lerp(successBorder, other.successBorder, t) ?? successBorder,
      successFg: Color.lerp(successFg, other.successFg, t) ?? successFg,
      warningBg: Color.lerp(warningBg, other.warningBg, t) ?? warningBg,
      warningBorder:
          Color.lerp(warningBorder, other.warningBorder, t) ?? warningBorder,
      warningFg: Color.lerp(warningFg, other.warningFg, t) ?? warningFg,
      errorBg: Color.lerp(errorBg, other.errorBg, t) ?? errorBg,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t) ?? errorBorder,
      errorFg: Color.lerp(errorFg, other.errorFg, t) ?? errorFg,
      infoBg: Color.lerp(infoBg, other.infoBg, t) ?? infoBg,
      infoBorder: Color.lerp(infoBorder, other.infoBorder, t) ?? infoBorder,
      infoFg: Color.lerp(infoFg, other.infoFg, t) ?? infoFg,
    );
  }
}
