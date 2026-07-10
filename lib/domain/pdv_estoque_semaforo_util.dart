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
    final disponivel = produto.estoqueLivreExibicao;
    final fisico = produto.estoqueExibicao;
    final minimo = produto.quantidadeMinima.toDouble();
    final noOrc = quantidadeNoOrcamento.clamp(0, 1 << 30).toDouble();
    final restante = disponivel - noOrc;

    if (fisico <= 0 || disponivel <= 0 || restante < 0) {
      return PdvEstoqueSemaforoNivel.vermelho;
    }
    if (minimo > 0 &&
        (fisico < minimo || disponivel <= minimo || restante <= minimo)) {
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
    final disponivelTxt = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueLivreParaVenda,
      comUnidade: true,
    );
    final fisicoTxt = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueReal,
      comUnidade: true,
    );
    final reservadoTxt = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueReservado,
      comUnidade: true,
    );
    final noOrc = quantidadeNoOrcamento.clamp(0, 1 << 30).toDouble();
    final restante = produto.estoqueLivreExibicao - noOrc;
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
      '${rotuloNivel(nivel)} · Disp. $disponivelTxt · '
      'Fis. $fisicoTxt · Res. $reservadoTxt',
    );
    if (noOrc > 0) {
      buf.write(' · Orc. $noOrcTxt · Rest. $restanteTxt');
    }
    return buf.toString();
  }

  /// Texto fixo na coluna Est. da lista (m² fracionado ou inteiro).
  static String rotuloQuantidadeLista(Produto produto, int estoqueArmazenado) {
    if (ProdutoEmbalagem.estoqueUsaEscalaFracionada(produto)) {
      return ProdutoEmbalagem.formatarEstoque(produto, estoqueArmazenado);
    }
    final quantidade = estoqueArmazenado;
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
