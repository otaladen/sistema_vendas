import 'package:flutter/material.dart';

import '../data/models/conta_pagar.dart';
import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../data/titulo_receber_repository.dart';
import '../data/venda_repository.dart';
import 'entrega_filtro_util.dart';
import 'filtro_contas_receber.dart';
import 'main_menu_destino.dart';

/// Tipo de alerta exibido no dashboard.
enum DashboardAlertaTipo {
  fiadoVencido,
  fiadoVenceHoje,
  entregaAtrasada,
  estoqueCritico,
  orcamentoAntigo,
  contaPagarVencida,
}

/// Alerta acionavel no painel inicial.
class DashboardAlerta {
  const DashboardAlerta({
    required this.tipo,
    required this.titulo,
    required this.detalhe,
    required this.cor,
    required this.icone,
    this.destino,
    this.filtroContasReceber,
    this.prioridade = 50,
  });

  final DashboardAlertaTipo tipo;
  final String titulo;
  final String detalhe;
  final Color cor;
  final IconData icone;
  final MainMenuDestino? destino;
  final FiltroContasReceber? filtroContasReceber;
  final int prioridade;
}

/// Monta alertas operacionais a partir dos dados ja existentes no ERP.
class DashboardAlertasService {
  DashboardAlertasService._();

  static List<DashboardAlerta> montar({
    required VendaRepository vendaRepository,
    required ProdutoRepository produtoRepository,
    required ObjectBox objectBox,
    required bool podeFinanceiro,
    required bool podeEstoque,
    required bool podeEntregas,
  }) {
    vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final alertas = <DashboardAlerta>[];

    if (podeFinanceiro) {
      final titulos = vendaRepository.titulos.listarTodosAbertos();
      final vencidos =
          titulos.where((l) => ContasReceberHelper.ehVencido(l)).toList();
      final venceHoje =
          titulos.where((l) => ContasReceberHelper.ehVenceHoje(l)).toList();
      final saldoVencido =
          vencidos.fold<double>(0, (s, l) => s + l.titulo.saldo);
      final saldoHoje =
          venceHoje.fold<double>(0, (s, l) => s + l.titulo.saldo);

      if (vencidos.isNotEmpty) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.fiadoVencido,
            titulo: 'Fiado vencido',
            detalhe:
                '${vencidos.length} titulo(s) · R\$ ${_fmt(saldoVencido)}',
            cor: const Color(0xFFC62828),
            icone: Icons.warning_amber_rounded,
            destino: MainMenuDestino.financeiro,
            filtroContasReceber: FiltroContasReceber.vencidos,
            prioridade: 10,
          ),
        );
      }

      if (venceHoje.isNotEmpty) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.fiadoVenceHoje,
            titulo: 'Fiado vence hoje',
            detalhe:
                '${venceHoje.length} titulo(s) · R\$ ${_fmt(saldoHoje)}',
            cor: const Color(0xFFE65100),
            icone: Icons.schedule_outlined,
            destino: MainMenuDestino.financeiro,
            filtroContasReceber: FiltroContasReceber.venceHoje,
            prioridade: 20,
          ),
        );
      }

      final cpAtrasadas = _contarContasPagarAtrasadas(objectBox);
      if (cpAtrasadas > 0) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.contaPagarVencida,
            titulo: 'Contas a pagar vencidas',
            detalhe: '$cpAtrasadas parcela(s) em atraso',
            cor: const Color(0xFFAD1457),
            icone: Icons.account_balance_outlined,
            destino: MainMenuDestino.financeiro,
            prioridade: 25,
          ),
        );
      }
    }

    if (podeEntregas) {
      final entregas = vendaRepository.listarEntregas();
      final atrasadas =
          entregas.where(EntregaFiltroUtil.ehAtrasada).length;
      if (atrasadas > 0) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.entregaAtrasada,
            titulo: 'Entregas atrasadas',
            detalhe: '$atrasadas entrega(s) com data passada',
            cor: const Color(0xFF0277BD),
            icone: Icons.local_shipping_outlined,
            destino: MainMenuDestino.entregas,
            prioridade: 15,
          ),
        );
      }
    }

    if (podeEstoque) {
      final critico = produtoRepository
          .listarTodos()
          .where((p) => p.estoqueReal < p.quantidadeMinima)
          .length;
      if (critico > 0) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.estoqueCritico,
            titulo: 'Estoque abaixo do minimo',
            detalhe: '$critico produto(s) precisam reposicao',
            cor: const Color(0xFFE65100),
            icone: Icons.inventory_2_outlined,
            destino: MainMenuDestino.estoque,
            prioridade: 30,
          ),
        );
      }
    }

    final orcs = vendaRepository.listarOrcamentosPendentes();
    final hoje = DateTime.now();
    final orcsAntigos = orcs.where((v) {
      final d = v.data.toLocal();
      final ref = DateTime(hoje.year, hoje.month, hoje.day);
      final vd = DateTime(d.year, d.month, d.day);
      return ref.difference(vd).inDays >= 7;
    }).length;
    if (orcsAntigos > 0) {
      alertas.add(
        DashboardAlerta(
          tipo: DashboardAlertaTipo.orcamentoAntigo,
          titulo: 'Orcamentos antigos',
          detalhe: '$orcsAntigos orcamento(s) com 7+ dias',
          cor: const Color(0xFF6A1B9A),
          icone: Icons.description_outlined,
          destino: MainMenuDestino.vendas,
          prioridade: 40,
        ),
      );
    }

    alertas.sort((a, b) => a.prioridade.compareTo(b.prioridade));
    return alertas;
  }

  static int _contarContasPagarAtrasadas(ObjectBox objectBox) {
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    var n = 0;
    for (final c in objectBox.contaPagarBox.getAll()) {
      if (c.status == ContaPagarStatus.pago) continue;
      final venc = DateTime(
        c.dataVencimento.year,
        c.dataVencimento.month,
        c.dataVencimento.day,
      );
      if (venc.isBefore(base)) n++;
    }
    return n;
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');
}

/// Classificacao de titulos para filtros e KPIs.
abstract final class ContasReceberHelper {
  static bool ehVencido(TituloReceberResumoLinha l) => l.diasAtraso > 0;

  static bool ehVenceHoje(TituloReceberResumoLinha l) {
    if (l.diasAtraso != 0) return false;
    final venc = l.titulo.vencimento.toLocal();
    final hoje = DateTime.now();
    return venc.year == hoje.year &&
        venc.month == hoje.month &&
        venc.day == hoje.day;
  }

  static bool ehProximos7(TituloReceberResumoLinha l) {
    final venc = l.titulo.vencimento.toLocal();
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final vd = DateTime(venc.year, venc.month, venc.day);
    final diff = vd.difference(base).inDays;
    return diff >= 0 && diff <= 7;
  }

  static bool ehEmDia(TituloReceberResumoLinha l) {
    final venc = l.titulo.vencimento.toLocal();
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final vd = DateTime(venc.year, venc.month, venc.day);
    return vd.isAfter(base);
  }

  static bool atendeFiltro(
    TituloReceberResumoLinha l,
    FiltroContasReceber filtro,
  ) {
    switch (filtro) {
      case FiltroContasReceber.todos:
        return true;
      case FiltroContasReceber.vencidos:
        return ehVencido(l);
      case FiltroContasReceber.venceHoje:
        return ehVenceHoje(l);
      case FiltroContasReceber.proximos7:
        return ehProximos7(l);
      case FiltroContasReceber.emDia:
        return ehEmDia(l);
    }
  }
}
