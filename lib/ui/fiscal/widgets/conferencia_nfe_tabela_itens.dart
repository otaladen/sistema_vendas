import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/nfe_entrada_repository.dart';

/// Linha resumida para a grade de conferencia (desktop).
class ConferenciaNfeTabelaLinha {
  const ConferenciaNfeTabelaLinha({
    required this.indice,
    required this.numeroItem,
    required this.descricao,
    required this.unidadeXml,
    required this.quantidadeXml,
    required this.valorUnitarioXml,
    required this.destinoRotulo,
    required this.statusRotulo,
    required this.statusCor,
    required this.statusCorTexto,
    required this.entradaRotulo,
    required this.unidadeInterna,
    required this.fatorController,
    required this.embalagemMultiplica,
    required this.erroFator,
    required this.precisaAtencao,
    required this.temDestino,
    required this.temVinculoAtivo,
  });

  final int indice;
  final int numeroItem;
  final String descricao;
  final String unidadeXml;
  final double quantidadeXml;
  final double valorUnitarioXml;
  final String? destinoRotulo;
  final String statusRotulo;
  final Color statusCor;
  final Color statusCorTexto;
  final String entradaRotulo;
  final String unidadeInterna;
  final TextEditingController fatorController;
  final bool embalagemMultiplica;
  final String? erroFator;
  final bool precisaAtencao;
  final bool temDestino;
  final bool temVinculoAtivo;
}

/// Grade compacta de itens da conferencia NF-e (desktop).
class ConferenciaNfeTabelaItens extends StatelessWidget {
  const ConferenciaNfeTabelaItens({
    super.key,
    required this.linhas,
    required this.onUnidadeChanged,
    required this.onFatorChanged,
    required this.onEmbalagemModoChanged,
    required this.onVincular,
    required this.onDesfazerVinculo,
    required this.onAbrirDetalhe,
  });

  final List<ConferenciaNfeTabelaLinha> linhas;
  final void Function(int indice, String unidade) onUnidadeChanged;
  final void Function(int indice) onFatorChanged;
  final void Function(int indice, bool embalagemMultiplica) onEmbalagemModoChanged;
  final void Function(int indice) onVincular;
  final void Function(int indice) onDesfazerVinculo;
  final void Function(int indice) onAbrirDetalhe;

  static final _nfQtd = NumberFormat('#,##0.###', 'pt_BR');
  static final _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1020),
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              cs.surfaceContainerHighest.withValues(alpha: 0.65),
            ),
            headingRowHeight: 40,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 56,
            columnSpacing: 12,
            columns: const [
              DataColumn(label: Text('')),
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Produto (XML)')),
              DataColumn(label: Text('Un/Qtd')),
              DataColumn(label: Text('V. unit.')),
              DataColumn(label: Text('Destino')),
              DataColumn(label: Text('Un.')),
              DataColumn(label: Text('Qtd. emb.')),
              DataColumn(label: Text('Entrada')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final l in linhas)
                DataRow(
                  color: WidgetStatePropertyAll(
                    l.precisaAtencao
                        ? cs.errorContainer.withValues(alpha: 0.25)
                        : null,
                  ),
                  cells: [
                    DataCell(
                      Semantics(
                        label: l.statusRotulo,
                        child: Icon(
                          l.precisaAtencao
                              ? Icons.warning_amber_rounded
                              : l.temDestino
                                  ? Icons.check_circle_outline
                                  : Icons.fiber_new_outlined,
                          color: l.precisaAtencao
                              ? cs.error
                              : l.statusCorTexto,
                          size: 20,
                        ),
                      ),
                    ),
                    DataCell(Text('${l.numeroItem}')),
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Text(
                          l.descricao,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${l.unidadeXml} ${_nfQtd.format(l.quantidadeXml)}',
                      ),
                    ),
                    DataCell(Text('R\$ ${_nfMoeda.format(l.valorUnitarioXml)}')),
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          l.destinoRotulo ?? 'Novo cadastro',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: l.temDestino
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: l.temDestino ? null : cs.tertiary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(_celulaUnidade(context, l)),
                    DataCell(_celulaEmbalagem(context, l)),
                    DataCell(
                      Text(
                        l.entradaRotulo,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Vincular produto',
                            icon: const Icon(Icons.link, size: 20),
                            onPressed: () => onVincular(l.indice),
                          ),
                          if (l.temVinculoAtivo)
                            IconButton(
                              tooltip: 'Desvincular produto',
                              icon: const Icon(Icons.link_off, size: 20),
                              onPressed: () => onDesfazerVinculo(l.indice),
                            ),
                          IconButton(
                            tooltip: 'Ver detalhes',
                            icon: const Icon(Icons.open_in_full, size: 20),
                            onPressed: () {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                onAbrirDetalhe(l.indice);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirMenuUnidade(
    BuildContext context,
    ConferenciaNfeTabelaLinha l,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !context.mounted) return;
    final pos = box.localToGlobal(Offset.zero);
    final sel = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + box.size.height + 2,
        pos.dx + 96,
        pos.dy + box.size.height + 240,
      ),
      items: [
        for (final u in NfeEntradaRepository.unidadesInternasValidas)
          PopupMenuItem(value: u, child: Text(u)),
      ],
    );
    if (sel != null) onUnidadeChanged(l.indice, sel);
  }

  Widget _celulaUnidade(BuildContext context, ConferenciaNfeTabelaLinha l) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      height: 40,
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _abrirMenuUnidade(context, l),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.unidadeInterna,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _celulaEmbalagem(BuildContext context, ConferenciaNfeTabelaLinha l) {
    final cs = Theme.of(context).colorScheme;
    final temErro = l.erroFator != null && l.erroFator!.isNotEmpty;
    return Semantics(
      label: temErro ? l.erroFator : null,
      child: SizedBox(
        width: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 52,
              height: 36,
              child: TextField(
                controller: l.fatorController,
                onChanged: (_) => onFatorChanged(l.indice),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: temErro ? cs.error : cs.outlineVariant,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: temErro ? cs.error : cs.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _toggleEmbalagemCompacto(context, l),
          ],
        ),
      ),
    );
  }

  Widget _toggleEmbalagemCompacto(
    BuildContext context,
    ConferenciaNfeTabelaLinha l,
  ) {
    final cs = Theme.of(context).colorScheme;
    Widget botao(bool multiplica, String rotulo) {
      final selecionado = l.embalagemMultiplica == multiplica;
      return Material(
        color: selecionado ? cs.primaryContainer : Colors.transparent,
        child: InkWell(
          onTap: () => onEmbalagemModoChanged(l.indice, multiplica),
          child: SizedBox(
            width: 28,
            height: 32,
            child: Center(
              child: Text(
                rotulo,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selecionado ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            botao(true, '×'),
            Container(width: 1, height: 32, color: cs.outlineVariant),
            botao(false, '÷'),
          ],
        ),
      ),
    );
  }
}
