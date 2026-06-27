import 'package:flutter/material.dart';

import '../model/produto.dart';

enum PdvEstoqueSemaforoNivel { verde, amarelo, vermelho }

/// Cores do semaforo de estoque (lista e painel PDV).
abstract final class PdvEstoqueSemaforoUtil {
  PdvEstoqueSemaforoUtil._();

  static PdvEstoqueSemaforoNivel nivelDe(
    Produto produto, {
    int quantidadeNoOrcamento = 0,
  }) {
    final disponivel = produto.estoqueLivreParaVenda;
    final restante = disponivel - quantidadeNoOrcamento.clamp(0, 1 << 30);

    if (produto.estoqueReal <= 0 || disponivel <= 0 || restante < 0) {
      return PdvEstoqueSemaforoNivel.vermelho;
    }
    if (produto.estoqueReal < produto.quantidadeMinima ||
        disponivel <= produto.quantidadeMinima ||
        restante <= produto.quantidadeMinima) {
      return PdvEstoqueSemaforoNivel.amarelo;
    }
    return PdvEstoqueSemaforoNivel.verde;
  }

  static Color corDe(BuildContext context, PdvEstoqueSemaforoNivel nivel) {
    final scheme = Theme.of(context).colorScheme;
    switch (nivel) {
      case PdvEstoqueSemaforoNivel.vermelho:
        return scheme.error;
      case PdvEstoqueSemaforoNivel.amarelo:
        return scheme.tertiary;
      case PdvEstoqueSemaforoNivel.verde:
        return scheme.primary;
    }
  }

  static String rotuloNivel(PdvEstoqueSemaforoNivel nivel) {
    switch (nivel) {
      case PdvEstoqueSemaforoNivel.vermelho:
        return 'Sem estoque';
      case PdvEstoqueSemaforoNivel.amarelo:
        return 'Estoque baixo';
      case PdvEstoqueSemaforoNivel.verde:
        return 'Disponivel';
    }
  }

  static String tooltipDe(
    Produto produto, {
    int quantidadeNoOrcamento = 0,
  }) {
    final disponivel = produto.estoqueLivreParaVenda;
    final noOrc = quantidadeNoOrcamento.clamp(0, 1 << 30);
    final restante = disponivel - noOrc;
    final nivel = nivelDe(produto, quantidadeNoOrcamento: noOrc);
    final buf = StringBuffer(
      '${rotuloNivel(nivel)} · Disp. $disponivel · '
      'Fis. ${produto.estoqueReal} · Res. ${produto.estoqueReservado}',
    );
    if (noOrc > 0) {
      buf.write(' · Orc. $noOrc · Rest. $restante');
    }
    return buf.toString();
  }
}
