import 'package:flutter/material.dart';

import '../model/venda.dart';
import 'entrega_venda_helper.dart';

/// Criterio de ordenacao da fila de orcamentos no caixa.
enum CaixaFilaOrdenacao {
  tempoEspera,
  valorMaior,
  entregaPrimeiro,
  retiradaFuturaPrimeiro,
}

extension CaixaFilaOrdenacaoExt on CaixaFilaOrdenacao {
  String get rotulo {
    switch (this) {
      case CaixaFilaOrdenacao.tempoEspera:
        return 'Mais antigo na fila';
      case CaixaFilaOrdenacao.valorMaior:
        return 'Maior valor';
      case CaixaFilaOrdenacao.entregaPrimeiro:
        return 'Entrega primeiro';
      case CaixaFilaOrdenacao.retiradaFuturaPrimeiro:
        return 'Retirada futura primeiro';
    }
  }
}

/// Badge visual na fila do caixa.
class CaixaOrcamentoBadge {
  const CaixaOrcamentoBadge({
    required this.rotulo,
    required this.cor,
    this.icone,
  });

  final String rotulo;
  final Color cor;
  final IconData? icone;
}

class CaixaFilaOrcamentoHelper {
  CaixaFilaOrcamentoHelper._();

  static List<Venda> ordenar(
    List<Venda> origem,
    CaixaFilaOrdenacao criterio,
  ) {
    final lista = List<Venda>.from(origem);
    switch (criterio) {
      case CaixaFilaOrdenacao.tempoEspera:
        lista.sort((a, b) => a.data.compareTo(b.data));
        break;
      case CaixaFilaOrdenacao.valorMaior:
        lista.sort((a, b) => b.total.compareTo(a.total));
        break;
      case CaixaFilaOrdenacao.entregaPrimeiro:
        lista.sort((a, b) {
          final pa = _prioridadeEntrega(a);
          final pb = _prioridadeEntrega(b);
          if (pa != pb) return pb.compareTo(pa);
          return a.data.compareTo(b.data);
        });
        break;
      case CaixaFilaOrdenacao.retiradaFuturaPrimeiro:
        lista.sort((a, b) {
          final pa = _prioridadeRetiradaFutura(a);
          final pb = _prioridadeRetiradaFutura(b);
          if (pa != pb) return pb.compareTo(pa);
          return a.data.compareTo(b.data);
        });
        break;
    }
    return lista;
  }

  static List<Venda> filtrarTexto(List<Venda> origem, String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return origem;
    return origem.where((orc) {
      final n = orc.numeroOrcamento.toString();
      final cliente = (orc.cliente.target?.nomeRazao ?? '').toLowerCase();
      final vendedor = (orc.vendedor.target?.nomeCompleto ?? '').toLowerCase();
      return n.contains(t) || cliente.contains(t) || vendedor.contains(t);
    }).toList();
  }

  static int minutosNaFila(Venda v) {
    return DateTime.now().difference(v.data).inMinutes.clamp(0, 99999);
  }

  /// Tempo legivel na linha principal (unica exibicao do tempo na fila).
  static String formatarTempoEspera(Venda v) {
    final min = minutosNaFila(v);
    if (min < 1) return 'agora';
    if (min < 60) return 'ha $min min';
    final horas = min ~/ 60;
    if (horas < 24) return 'ha ${horas}h';
    final dias = horas ~/ 24;
    final horasResto = horas % 24;
    if (horasResto == 0) return 'ha ${dias}d';
    return 'ha ${dias}d ${horasResto}h';
  }

  /// Apenas forma de pagamento (fiado / misto) — sem entrega, urgencia ou fiscal.
  static List<CaixaOrcamentoBadge> badges(Venda v) {
    final b = <CaixaOrcamentoBadge>[];
    final temFiado = v.formaPagamento == 'fiado' ||
        (v.pagamentosJson.trim().isNotEmpty &&
            v.pagamentosJson.toLowerCase().contains('fiado'));
    if (temFiado) {
      b.add(const CaixaOrcamentoBadge(
        rotulo: 'Fiado',
        cor: Color(0xFFEF6C00),
        icone: Icons.account_balance_wallet_outlined,
      ));
    }
    if (v.formaPagamento == 'misto') {
      b.add(const CaixaOrcamentoBadge(
        rotulo: 'Misto',
        cor: Color(0xFF455A64),
        icone: Icons.payments_outlined,
      ));
    }
    return b;
  }

  static int _prioridadeEntrega(Venda v) {
    if (EntregaVendaHelper.vendaTemItensCarreto(v)) return 2;
    if (v.tipoEntrega == EntregaVendaHelper.tipoEntregaLoja) return 1;
    return 0;
  }

  static int _prioridadeRetiradaFutura(Venda v) {
    if (v.entregaPendente || EntregaVendaHelper.vendaTemItensRetiradaFutura(v)) {
      return 2;
    }
    return 0;
  }
}
