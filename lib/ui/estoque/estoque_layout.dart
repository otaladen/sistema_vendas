import 'package:flutter/material.dart';

/// Breakpoints e constantes de layout da tela de Estoque.
abstract final class EstoqueLayout {
  EstoqueLayout._();

  /// Abaixo desta largura usa cards compactos em vez da tabela.
  static const double breakpointMobile = 720;

  static const double breakpointDesktopLargo = 960;

  /// KPIs em faixa (em vez de linha cheia) abaixo desta largura.
  static const double breakpointKpisFaixa = 900;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointMobile;

  static bool isKpisFaixa(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointKpisFaixa;
}
