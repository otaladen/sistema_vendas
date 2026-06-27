import 'package:flutter/material.dart';

import '../../domain/dashboard_alertas.dart';
import '../../domain/main_menu_destino.dart';
import 'app_semantic_colors.dart';

/// Sub-itens de hubs (cadastros, vendas, financeiro) sem [MainMenuDestino].
enum AppModuloId {
  produtos,
  kitsOrcamento,
  promocoes,
  motoristasCadastro,
  funcionariosCadastro,
  clientesCadastro,
  vendedoresCadastro,
  usuariosCadastro,
  listagemVendas,
  orcamentos,
  relatoriosVendas,
  contasReceber,
  contasPagar,
  relatorioContasPagar,
  relatorioFiados,
  tesouraria,
  lojaAoVivo,
  inativo,
}

/// Cores de modulos derivadas do tema ativo (Material 3).
abstract final class AppModuloCores {
  static Color harmonizar(ColorScheme scheme, double graus) {
    final base = HSLColor.fromColor(scheme.primary);
    final hue = (base.hue + graus) % 360;
    final sat = scheme.brightness == Brightness.dark
        ? (base.saturation * 0.75).clamp(0.4, 0.85)
        : (base.saturation * 0.9).clamp(0.45, 0.85);
    final light = scheme.brightness == Brightness.dark
        ? base.lightness.clamp(0.58, 0.72)
        : base.lightness.clamp(0.38, 0.48);
    return HSLColor.fromAHSL(1, hue, sat, light).toColor();
  }

  static Color destino(BuildContext context, MainMenuDestino destino) {
    final scheme = Theme.of(context).colorScheme;
    switch (destino) {
      case MainMenuDestino.inicio:
        return scheme.primary;
      case MainMenuDestino.vendas:
      case MainMenuDestino.pdv:
        return scheme.primary;
      case MainMenuDestino.caixa:
        return scheme.tertiary;
      case MainMenuDestino.estoque:
        return harmonizar(scheme, 38);
      case MainMenuDestino.notasFiscais:
        return harmonizar(scheme, -18);
      case MainMenuDestino.entregas:
        return harmonizar(scheme, 195);
      case MainMenuDestino.financeiro:
        return scheme.secondary;
      case MainMenuDestino.cadastros:
        return harmonizar(scheme, 210);
      case MainMenuDestino.configuracoes:
        return harmonizar(scheme, 275);
      case MainMenuDestino.motorista:
        return scheme.onSurfaceVariant;
    }
  }

  static Color modulo(BuildContext context, AppModuloId id) {
    final scheme = Theme.of(context).colorScheme;
    switch (id) {
      case AppModuloId.produtos:
        return harmonizar(scheme, 38);
      case AppModuloId.kitsOrcamento:
        return harmonizar(scheme, 55);
      case AppModuloId.promocoes:
        return scheme.error;
      case AppModuloId.motoristasCadastro:
        return harmonizar(scheme, 195);
      case AppModuloId.funcionariosCadastro:
        return scheme.secondary;
      case AppModuloId.clientesCadastro:
        return harmonizar(scheme, 210);
      case AppModuloId.vendedoresCadastro:
        return scheme.primary;
      case AppModuloId.usuariosCadastro:
        return harmonizar(scheme, 275);
      case AppModuloId.listagemVendas:
        return harmonizar(scheme, 245);
      case AppModuloId.orcamentos:
        return harmonizar(scheme, 275);
      case AppModuloId.relatoriosVendas:
        return harmonizar(scheme, 42);
      case AppModuloId.contasReceber:
        return harmonizar(scheme, 210);
      case AppModuloId.contasPagar:
        return scheme.secondary;
      case AppModuloId.relatorioContasPagar:
        return harmonizar(scheme, 55);
      case AppModuloId.relatorioFiados:
        return harmonizar(scheme, 275);
      case AppModuloId.tesouraria:
        return scheme.tertiary;
      case AppModuloId.lojaAoVivo:
        return scheme.primary;
      case AppModuloId.inativo:
        return scheme.onSurfaceVariant;
    }
  }

  static Color alerta(BuildContext context, DashboardAlertaTipo tipo) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final scheme = Theme.of(context).colorScheme;
    switch (tipo) {
      case DashboardAlertaTipo.fiadoVencido:
        return semantic?.errorFg ?? scheme.error;
      case DashboardAlertaTipo.fiadoVenceHoje:
        return semantic?.warningFg ?? harmonizar(scheme, 38);
      case DashboardAlertaTipo.contaPagarVencida:
        return harmonizar(scheme, 320);
      case DashboardAlertaTipo.entregaAtrasada:
        return destino(context, MainMenuDestino.entregas);
      case DashboardAlertaTipo.listaCompraPendente:
        return harmonizar(scheme, 155);
      case DashboardAlertaTipo.estoqueCritico:
        return destino(context, MainMenuDestino.estoque);
      case DashboardAlertaTipo.orcamentoAntigo:
        return harmonizar(scheme, 275);
      case DashboardAlertaTipo.backupAtrasado:
        return semantic?.warningFg ?? destino(context, MainMenuDestino.configuracoes);
    }
  }
}

extension MainMenuDestinoCores on MainMenuDestino {
  Color cor(BuildContext context) => AppModuloCores.destino(context, this);
}

extension DashboardAlertaCores on DashboardAlerta {
  Color corTema(BuildContext context) => AppModuloCores.alerta(context, tipo);
}
