import 'package:flutter/material.dart';

import '../../domain/pdv_tabela_preco_util.dart';

/// Cabecalho de colunas fixas da lista de consulta PDV.
class PdvConsultaListaCabecalho extends StatelessWidget {
  const PdvConsultaListaCabecalho({
    super.key,
    required this.rotuloPreco,
    required this.precoListaAtivo,
  });

  static const double altura = 28;

  final String Function(String precoTipo) rotuloPreco;
  final String precoListaAtivo;

  static const _tiposPreco = ['preco1', 'preco2', 'preco3'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estilo = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.2,
    );
    final ativo = PdvTabelaPrecoUtil.normalizar(precoListaAtivo);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: SizedBox(
        height: altura,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Produto', style: estilo),
              ),
              SizedBox(
                width: PdvConsultaColunas.larguraUnidade,
                child: Text('Un.', style: estilo, textAlign: TextAlign.center),
              ),
              SizedBox(
                width: PdvConsultaColunas.larguraEstoque,
                child: Text('Est.', style: estilo, textAlign: TextAlign.end),
              ),
              for (final tipo in _tiposPreco)
                SizedBox(
                  width: PdvConsultaColunas.larguraPrecoColuna,
                  child: Text(
                    rotuloPreco(tipo),
                    style: estilo?.copyWith(
                      color: tipo == ativo
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight:
                          tipo == ativo ? FontWeight.w900 : FontWeight.w800,
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              SizedBox(width: PdvConsultaColunas.larguraAcao),
            ],
          ),
        ),
      ),
    );
  }
}

/// Larguras compartilhadas entre cabecalho e linhas da consulta.
abstract final class PdvConsultaColunas {
  PdvConsultaColunas._();

  static const double larguraUnidade = 32;
  static const double larguraEstoque = 56;
  /// Cada coluna de preco (Preco 1 / Preco 2 / Preco 3).
  static const double larguraPrecoColuna = 76;
  static const double larguraAcao = 40;

  /// Soma das tres colunas de preco (compat / layout).
  static const double larguraPrecos = larguraPrecoColuna * 3;
}
