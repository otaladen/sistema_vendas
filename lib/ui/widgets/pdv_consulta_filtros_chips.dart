import 'package:flutter/material.dart';

import '../../domain/pdv_consulta_detalhe_linha.dart';

/// Filtros rapidos abaixo da busca na consulta de produtos.
class PdvConsultaFiltrosChips extends StatelessWidget {
  const PdvConsultaFiltrosChips({
    super.key,
    required this.somenteComEstoque,
    required this.somentePromocao,
    required this.modoSugestao,
    required this.mostrarModosSugestao,
    this.mostrarFiltroPromocao = true,
    this.mostrarFiltroAplicacao = false,
    required this.onSomenteComEstoqueChanged,
    required this.onSomentePromocaoChanged,
    this.somenteAplicacao = false,
    this.onSomenteAplicacaoChanged,
    required this.onModoSugestaoChanged,
  });

  final bool somenteComEstoque;
  final bool somentePromocao;
  final PdvConsultaModoSugestao modoSugestao;
  final bool mostrarModosSugestao;
  final bool mostrarFiltroPromocao;
  final bool mostrarFiltroAplicacao;
  final ValueChanged<bool> onSomenteComEstoqueChanged;
  final ValueChanged<bool> onSomentePromocaoChanged;
  final bool somenteAplicacao;
  final ValueChanged<bool>? onSomenteAplicacaoChanged;
  final ValueChanged<PdvConsultaModoSugestao> onModoSugestaoChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FiltroChip(
          rotulo: 'Com estoque',
          selecionado: somenteComEstoque,
          onTap: () => onSomenteComEstoqueChanged(!somenteComEstoque),
        ),
        if (mostrarFiltroPromocao)
          _FiltroChip(
            rotulo: 'Promocao',
            selecionado: somentePromocao,
            onTap: () => onSomentePromocaoChanged(!somentePromocao),
          ),
        if (mostrarFiltroAplicacao && onSomenteAplicacaoChanged != null)
          _FiltroChip(
            rotulo: 'Aplicacao',
            selecionado: somenteAplicacao,
            onTap: () => onSomenteAplicacaoChanged!(!somenteAplicacao),
          ),
        if (mostrarModosSugestao) ...[
          _FiltroChip(
            rotulo: 'Recentes',
            selecionado: modoSugestao == PdvConsultaModoSugestao.recentes,
            onTap: () => onModoSugestaoChanged(
              modoSugestao == PdvConsultaModoSugestao.recentes
                  ? PdvConsultaModoSugestao.misto
                  : PdvConsultaModoSugestao.recentes,
            ),
          ),
          _FiltroChip(
            rotulo: 'Mais vendidos',
            selecionado: modoSugestao == PdvConsultaModoSugestao.maisVendidos,
            onTap: () => onModoSugestaoChanged(
              modoSugestao == PdvConsultaModoSugestao.maisVendidos
                  ? PdvConsultaModoSugestao.misto
                  : PdvConsultaModoSugestao.maisVendidos,
            ),
          ),
          _FiltroChip(
            rotulo: 'A–Z',
            selecionado: modoSugestao == PdvConsultaModoSugestao.catalogoAz,
            onTap: () => onModoSugestaoChanged(
              modoSugestao == PdvConsultaModoSugestao.catalogoAz
                  ? PdvConsultaModoSugestao.misto
                  : PdvConsultaModoSugestao.catalogoAz,
            ),
          ),
        ],
      ],
    );
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({
    required this.rotulo,
    required this.selecionado,
    required this.onTap,
  });

  final String rotulo;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(rotulo),
      selected: selecionado,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: scheme.primaryContainer.withValues(alpha: 0.65),
      checkmarkColor: scheme.primary,
    );
  }
}
