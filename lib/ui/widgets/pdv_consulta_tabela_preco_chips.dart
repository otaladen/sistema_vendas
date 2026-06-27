import 'package:flutter/material.dart';

import '../../domain/pdv_tabela_preco_util.dart';

/// Chips F1–F3 para tabela ativa na consulta de produtos do PDV.
class PdvConsultaTabelaPrecoChips extends StatelessWidget {
  const PdvConsultaTabelaPrecoChips({
    super.key,
    required this.precoListaAtivo,
    required this.rotuloPreco,
    required this.onSelecionar,
    this.inline = false,
  });

  static const _tipos = ['preco1', 'preco2', 'preco3'];
  static const _atalhos = ['F1', 'F2', 'F3'];

  final String precoListaAtivo;
  final String Function(String precoTipo) rotuloPreco;
  final ValueChanged<String> onSelecionar;
  /// Cabecalho compacto: chips alinhados a direita, sem rotulo longo.
  final bool inline;

  Color _corChip(BuildContext context, String tipo) {
    final scheme = Theme.of(context).colorScheme;
    switch (PdvTabelaPrecoUtil.normalizar(tipo)) {
      case 'preco2':
        return scheme.tertiary;
      case 'preco3':
        return scheme.secondary;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ativo = PdvTabelaPrecoUtil.normalizar(precoListaAtivo);

    return Wrap(
      spacing: inline ? 6 : 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: inline ? WrapAlignment.end : WrapAlignment.start,
      children: [
        if (!inline)
          Text(
            'Adicionar com:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        for (var i = 0; i < _tipos.length; i++)
          _ChipTabela(
            rotulo: rotuloPreco(_tipos[i]),
            atalho: _atalhos[i],
            selecionado: ativo == _tipos[i],
            cor: _corChip(context, _tipos[i]),
            onTap: () => onSelecionar(_tipos[i]),
          ),
      ],
    );
  }
}

class _ChipTabela extends StatelessWidget {
  const _ChipTabela({
    required this.rotulo,
    required this.atalho,
    required this.selecionado,
    required this.cor,
    required this.onTap,
  });

  final String rotulo;
  final String atalho;
  final bool selecionado;
  final Color cor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fundo = selecionado
        ? cor.withValues(alpha: 0.14)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.65);
    final borda = selecionado
        ? cor.withValues(alpha: 0.75)
        : scheme.outlineVariant.withValues(alpha: 0.45);

    return Material(
      color: fundo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: borda, width: selecionado ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selecionado
                      ? cor.withValues(alpha: 0.22)
                      : scheme.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  atalho,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: selecionado ? cor : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                rotulo,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selecionado ? FontWeight.w800 : FontWeight.w600,
                  color: selecionado ? cor : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
