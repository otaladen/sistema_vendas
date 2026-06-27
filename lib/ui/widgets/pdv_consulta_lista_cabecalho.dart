import 'package:flutter/material.dart';

/// Cabecalho de colunas fixas da lista de consulta PDV.
class PdvConsultaListaCabecalho extends StatelessWidget {
  const PdvConsultaListaCabecalho({
    super.key,
    required this.rotuloColunaPreco,
  });

  static const double altura = 28;

  final String rotuloColunaPreco;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estilo = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.2,
    );

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
              SizedBox(
                width: PdvConsultaColunas.larguraPreco,
                child: Text(
                  rotuloColunaPreco,
                  style: estilo,
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
  static const double larguraEstoque = 44;
  static const double larguraPreco = 84;
  static const double larguraAcao = 40;
}
