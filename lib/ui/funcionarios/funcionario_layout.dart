import 'package:flutter/material.dart';

import '../layout/app_layout.dart';

/// Quebras de layout para notebooks 15" (1366x768 tipico).
abstract final class FuncionarioLayout {
  /// Largura tipica de notebook 15".
  static const double laptopWidth = 1366;

  /// Altura tipica 768px + barra de tarefas.
  static const double shortHeight = 820;

  static const double sidebarWide = 280;
  static const double sidebarMedium = 260;
  static const double sidebarNarrow = 240;

  static double sidebarWidth(double screenWidth) {
    if (screenWidth < 1200) return sidebarNarrow;
    if (screenWidth < laptopWidth) return sidebarMedium;
    return sidebarWide;
  }

  /// Desktop compacto: notebook 15" ou tela baixa.
  static bool isCompactDesktop(double width, double height) =>
      width < laptopWidth || height < shortHeight;

  /// KPIs da equipe ficam na sidebar (ficha limpa, estilo ERP).
  static bool kpisNaSidebar(double width, double height) =>
      width >= AppBreakpoints.desktop;

  /// Duas colunas na aba Documentos.
  static bool documentosDuasColunas(double contentWidth) =>
      contentWidth >= 640;

  static bool folhaCompacta(double contentWidth) => contentWidth < 920;

  static bool acoesEmWrap(double contentWidth) => contentWidth < 720;
}

extension FuncionarioLayoutContext on BuildContext {
  Size get _screenSize => MediaQuery.sizeOf(this);

  double get funcionarioSidebarWidth =>
      FuncionarioLayout.sidebarWidth(_screenSize.width);

  bool get isFuncionarioCompactDesktop =>
      FuncionarioLayout.isCompactDesktop(_screenSize.width, _screenSize.height);

  bool get funcionarioKpisNaSidebar => FuncionarioLayout.kpisNaSidebar(
        _screenSize.width,
        _screenSize.height,
      );
}
