import 'package:flutter/material.dart';

typedef ListagemVendasFiltrosBuilder = Widget Function(
  BuildContext context,
  BoxConstraints constraints,
);

/// Painel de filtros colapsavel com busca em destaque.
class ListagemVendasFiltrosPanel extends StatefulWidget {
  const ListagemVendasFiltrosPanel({
    super.key,
    required this.buscaController,
    required this.filtrosAvancados,
    required this.onPesquisar,
    this.onBuscaChanged,
    required this.onLimpar,
    required this.onExportarCsv,
    required this.onExportarPdf,
    this.periodoPersonalizado,
    this.filtrosAtivos = 0,
  });

  final TextEditingController buscaController;
  final ListagemVendasFiltrosBuilder filtrosAvancados;
  final VoidCallback onPesquisar;
  final VoidCallback? onBuscaChanged;
  final VoidCallback onLimpar;
  final VoidCallback onExportarCsv;
  final VoidCallback onExportarPdf;
  final Widget? periodoPersonalizado;
  final int filtrosAtivos;

  @override
  State<ListagemVendasFiltrosPanel> createState() =>
      _ListagemVendasFiltrosPanelState();
}

class _ListagemVendasFiltrosPanelState extends State<ListagemVendasFiltrosPanel> {
  bool _expandido = false;
  final ScrollController _filtrosScrollController = ScrollController();

  @override
  void dispose() {
    _filtrosScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final estreito = constraints.maxWidth < 720;
                final busca = TextField(
                  controller: widget.buscaController,
                  decoration: InputDecoration(
                    hintText:
                        'Buscar por controle, NFC-e, cliente, vendedor ou produto...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => widget.onPesquisar(),
                  onChanged: (_) => widget.onBuscaChanged?.call(),
                );
                final acoes = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.onPesquisar,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Pesquisar'),
                    ),
                    OutlinedButton(
                      onPressed: widget.onLimpar,
                      child: const Text('Limpar'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Exportar',
                      onSelected: (v) {
                        if (v == 'csv') {
                          widget.onExportarCsv();
                        } else if (v == 'pdf') {
                          widget.onExportarPdf();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'csv',
                          child: Text('Exportar CSV'),
                        ),
                        PopupMenuItem(
                          value: 'pdf',
                          child: Text('Exportar / imprimir PDF'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Icon(Icons.download_outlined),
                      ),
                    ),
                  ],
                );

                if (estreito) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      busca,
                      const SizedBox(height: 10),
                      acoes,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: busca),
                    const SizedBox(width: 10),
                    acoes,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expandido = !_expandido),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      _expandido
                          ? Icons.expand_less
                          : Icons.tune_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _expandido ? 'Ocultar filtros' : 'Filtros avancados',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.filtrosAtivos > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${widget.filtrosAtivos} ativo(s)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_expandido) ...[
              const SizedBox(height: 8),
              // Limita altura dos filtros para a tabela nao ficar espremida
              // (e evita sensacao de "scroll travado" na listagem).
              LayoutBuilder(
                builder: (context, outer) {
                  final tela = MediaQuery.sizeOf(context).height;
                  final maxFiltros = (tela * 0.28).clamp(140.0, 260.0);
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxFiltros),
                    child: Scrollbar(
                      controller: _filtrosScrollController,
                      thumbVisibility: true,
                      interactive: true,
                      child: SingleChildScrollView(
                        controller: _filtrosScrollController,
                        primary: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            widget.filtrosAvancados(context, outer),
                            if (widget.periodoPersonalizado != null) ...[
                              const SizedBox(height: 8),
                              widget.periodoPersonalizado!,
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grade responsiva para dropdowns de filtro.
class ListagemVendasFiltrosGrade extends StatelessWidget {
  const ListagemVendasFiltrosGrade({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 720
                ? 3
                : constraints.maxWidth >= 480
                    ? 2
                    : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
