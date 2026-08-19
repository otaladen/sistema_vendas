import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import 'app_modulo_cores.dart';

/// Identificadores de relatorios no hub gerencial.
enum AppRelatorioId {
  dashboard,
  abc,
  fiados,
  contasPagar,
  vendasPeriodo,
  horariosPico,
  metasVendedor,
  orcamentos,
  vendasVendedor,
  comissao,
  topClientes,
  produtosRanking,
  estoqueMin,
  saidasProduto,
  vendasPromocao,
  tabelaPrecos,
  logSistema,
  fechamentoHist,
  entregasResumo,
  sugestoesVenda,
  movimentacaoEstoque,
  devolucoesPeriodo,
  pendenciasEntrega,
  historicoEntregas,
  margemMarkup,
  performanceEntregas,
  sugestaoCompra,
  fiscalMensal,
}

/// Cores de destaque dos relatorios derivadas do tema ativo.
abstract final class AppRelatorioCores {
  static Color cor(BuildContext context, AppRelatorioId id) {
    final scheme = Theme.of(context).colorScheme;
    switch (id) {
      case AppRelatorioId.dashboard:
        return AppModuloCores.harmonizar(scheme, 245);
      case AppRelatorioId.abc:
        return AppModuloCores.harmonizar(scheme, 320);
      case AppRelatorioId.fiados:
      case AppRelatorioId.vendasPromocao:
        return scheme.error;
      case AppRelatorioId.contasPagar:
        return AppModuloCores.modulo(context, AppModuloId.relatorioContasPagar);
      case AppRelatorioId.vendasPeriodo:
        return AppModuloCores.harmonizar(scheme, 210);
      case AppRelatorioId.horariosPico:
        return AppModuloCores.harmonizar(scheme, 285);
      case AppRelatorioId.metasVendedor:
        return scheme.tertiary;
      case AppRelatorioId.orcamentos:
        return AppModuloCores.harmonizar(scheme, 255);
      case AppRelatorioId.vendasVendedor:
        return scheme.tertiary;
      case AppRelatorioId.comissao:
        return AppModuloCores.harmonizar(scheme, 275);
      case AppRelatorioId.topClientes:
        return AppModuloCores.harmonizar(scheme, 195);
      case AppRelatorioId.produtosRanking:
        return scheme.primary;
      case AppRelatorioId.estoqueMin:
        return AppModuloCores.destino(context, MainMenuDestino.estoque);
      case AppRelatorioId.saidasProduto:
        return AppModuloCores.harmonizar(scheme, 55);
      case AppRelatorioId.tabelaPrecos:
        return scheme.secondary;
      case AppRelatorioId.logSistema:
        return AppModuloCores.harmonizar(scheme, 265);
      case AppRelatorioId.fechamentoHist:
        return scheme.primary;
      case AppRelatorioId.entregasResumo:
        return AppModuloCores.destino(context, MainMenuDestino.entregas);
      case AppRelatorioId.sugestoesVenda:
        return AppModuloCores.harmonizar(scheme, 165);
      case AppRelatorioId.movimentacaoEstoque:
        return AppModuloCores.destino(context, MainMenuDestino.estoque);
      case AppRelatorioId.devolucoesPeriodo:
        return scheme.error;
      case AppRelatorioId.pendenciasEntrega:
        return AppModuloCores.destino(context, MainMenuDestino.entregas);
      case AppRelatorioId.historicoEntregas:
        return AppModuloCores.harmonizar(scheme, 230);
      case AppRelatorioId.margemMarkup:
        return AppModuloCores.harmonizar(scheme, 145);
      case AppRelatorioId.performanceEntregas:
        return AppModuloCores.destino(context, MainMenuDestino.entregas);
      case AppRelatorioId.sugestaoCompra:
        return AppModuloCores.destino(context, MainMenuDestino.estoque);
      case AppRelatorioId.fiscalMensal:
        return AppModuloCores.destino(context, MainMenuDestino.notasFiscais);
    }
  }
}
