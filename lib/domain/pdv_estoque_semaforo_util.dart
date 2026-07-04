import 'package:flutter/material.dart';

import '../model/produto.dart';
import 'produto_embalagem.dart';

enum PdvEstoqueSemaforoNivel { verde, amarelo, vermelho }

/// Cores do semaforo de estoque (lista e painel PDV).
abstract final class PdvEstoqueSemaforoUtil {
  PdvEstoqueSemaforoUtil._();

  static PdvEstoqueSemaforoNivel nivelDe(
    Produto produto, {
    num quantidadeNoOrcamento = 0,
  }) {
    final disponivel = produto.estoqueLivreParaVenda;
    final noOrc = quantidadeNoOrcamento.clamp(0, 1 << 30).toDouble();
    final restante = disponivel - noOrc;

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
    num quantidadeNoOrcamento = 0,
  }) {
    final disponivel = produto.estoqueLivreParaVenda;
    final noOrc = quantidadeNoOrcamento.clamp(0, 1 << 30).toDouble();
    final restante = disponivel - noOrc;
    final noOrcTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
      produto,
      noOrc,
    );
    final restanteTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
      produto,
      restante.clamp(0, double.infinity),
    );
    final nivel = nivelDe(produto, quantidadeNoOrcamento: noOrc);
    final buf = StringBuffer(
      '${rotuloNivel(nivel)} · Disp. $disponivel · '
      'Fis. ${produto.estoqueReal} · Res. ${produto.estoqueReservado}',
    );
    if (noOrc > 0) {
      buf.write(' · Orc. $noOrcTxt · Rest. $restanteTxt');
    }
    return buf.toString();
  }

  /// Texto fixo na coluna Est. da lista (ate 4 digitos inteiros; acima compacta).
  static String rotuloQuantidadeLista(int quantidade) {
    final abs = quantidade.abs();
    if (abs < 10000) return '$quantidade';
    if (abs < 1000000) {
      final mil = quantidade / 1000;
      if (mil.abs() >= 100) return '${mil.round()}k';
      return '${mil.toStringAsFixed(1).replaceAll('.', ',')}k';
    }
    final mi = quantidade / 1000000;
    if (mi.abs() >= 100) return '${mi.round()}M';
    return '${mi.toStringAsFixed(1).replaceAll('.', ',')}M';
  }
}
