import 'package:flutter/material.dart';

import '../caixa_etapa.dart';

/// Indicador visual das 3 etapas do wizard do caixa (+ fiscal pos-pagamento).
class CaixaEtapasBar extends StatelessWidget {
  const CaixaEtapasBar({
    super.key,
    required this.etapaAtual,
  });

  final CaixaEtapa etapaAtual;

  int _indice(CaixaEtapa e) => switch (e) {
        CaixaEtapa.fila => 0,
        CaixaEtapa.conferencia => 1,
        CaixaEtapa.cobranca => 2,
        CaixaEtapa.fiscal => 3,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final atual = _indice(etapaAtual);

    Widget passo(int numero, String rotulo, CaixaEtapa etapa) {
      final idx = _indice(etapa);
      final ativo = etapaAtual == etapa;
      final concluido = atual > idx;
      return _ChipEtapa(
        numero: numero,
        rotulo: rotulo,
        ativo: ativo,
        concluido: concluido,
        scheme: scheme,
        theme: theme,
      );
    }

    Widget conector(bool preenchido) {
      return Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: preenchido
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      );
    }

    return Row(
      children: [
        passo(1, 'Conferencia', CaixaEtapa.conferencia),
        conector(atual >= _indice(CaixaEtapa.cobranca)),
        passo(2, 'Cobranca', CaixaEtapa.cobranca),
        conector(atual >= _indice(CaixaEtapa.fiscal)),
        passo(3, 'Fiscal', CaixaEtapa.fiscal),
      ],
    );
  }
}

class _ChipEtapa extends StatelessWidget {
  const _ChipEtapa({
    required this.numero,
    required this.rotulo,
    required this.ativo,
    required this.concluido,
    required this.scheme,
    required this.theme,
  });

  final int numero;
  final String rotulo;
  final bool ativo;
  final bool concluido;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final corFundo = ativo
        ? scheme.primaryContainer
        : concluido
            ? scheme.secondaryContainer.withValues(alpha: 0.65)
            : scheme.surfaceContainerHighest;
    final corTexto = ativo
        ? scheme.onPrimaryContainer
        : concluido
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;

    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: corFundo,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ativo
                ? scheme.primary.withValues(alpha: 0.45)
                : scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: ativo ? scheme.primary : scheme.outlineVariant,
              child: concluido && !ativo
                  ? Icon(Icons.check, size: 12, color: scheme.onPrimary)
                  : Text(
                      '$numero',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ativo ? scheme.onPrimary : scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                rotulo,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: corTexto,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
