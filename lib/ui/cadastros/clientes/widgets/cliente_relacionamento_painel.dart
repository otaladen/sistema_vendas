import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/api/venda_api_repository.dart';
import '../../../../domain/entrega_venda_helper.dart';
import '../../../../domain/orcamento_condicoes_pagamento.dart';
import '../../../../domain/venda_documento_rotulo_helper.dart';
import '../../../../model/item_venda.dart';
import '../../../../model/venda.dart';

typedef ItensDaCompraResolver = List<ItemVenda> Function(Venda compra);

/// Painel CRM leve: KPIs do periodo, top produtos e historico de vendas.
class ClienteRelacionamentoPainel extends StatefulWidget {
  const ClienteRelacionamentoPainel({
    super.key,
    required this.emEdicao,
    required this.carregandoCompras,
    required this.periodoHistorico,
    required this.compras,
    required this.vendaRepository,
    required this.resolveItensDaCompra,
    required this.onPeriodoChanged,
    this.scrollController,
  });

  final bool emEdicao;
  final bool carregandoCompras;
  final String periodoHistorico;
  final List<Venda> compras;
  final dynamic vendaRepository;
  final ItensDaCompraResolver resolveItensDaCompra;
  final ValueChanged<String> onPeriodoChanged;
  final ScrollController? scrollController;

  @override
  State<ClienteRelacionamentoPainel> createState() =>
      _ClienteRelacionamentoPainelState();
}

class _ProdutoTopAgg {
  _ProdutoTopAgg(this.nome);

  final String nome;
  int quantidade = 0;
  double faturamento = 0;
}

class _ClienteRelacionamentoPainelState extends State<ClienteRelacionamentoPainel> {
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _inteiro = NumberFormat('#,##0', 'pt_BR');

  String _formatarMoeda(double valor) => _moeda.format(valor);

  String _rotuloPeriodo(String value) {
    switch (value) {
      case 'ultimos_30':
        return 'Últimos 30 dias';
      case 'ultimos_90':
        return 'Últimos 90 dias';
      case 'ano_atual':
        return 'Ano atual';
      case 'todo':
      default:
        return 'Todo o período';
    }
  }

  String _mesAnoGrupo(DateTime data) {
    final raw = DateFormat('MMMM / yyyy', 'pt_BR').format(data.toLocal());
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  List<ItemVenda> _itensSync(Venda v) {
    final repo = widget.vendaRepository;
    try {
      final viaRepo = repo.listarItensPorVenda(v.id) as List<ItemVenda>?;
      if (viaRepo != null && viaRepo.isNotEmpty) return viaRepo;
    } catch (_) {}
    return widget.resolveItensDaCompra(v);
  }

  Future<List<ItemVenda>> _itensAsync(Venda v) async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        return await repo.carregarItensRemoto(v.id);
      } catch (_) {
        return _itensSync(v);
      }
    }
    return _itensSync(v);
  }

  String _rotuloEntrega(Venda v) {
    if (v.tipoEntrega == EntregaVendaHelper.tipoMisto) {
      final tipos = _itensSync(v).map((i) => i.tipoEntregaItem);
      return '${EntregaVendaHelper.rotuloTipoEntregaVenda(v.tipoEntrega)} '
          '(${EntregaVendaHelper.resumoContagem(tipos)})';
    }
    return EntregaVendaHelper.rotuloTipoEntregaVenda(v.tipoEntrega);
  }

  String _rotuloPagamento(Venda v) {
    return OrcamentoCondicoesPagamento.rotuloMeio(v.formaPagamento);
  }

  int _contagemLinhasProduto(List<Venda> compras) {
    var linhas = 0;
    for (final compra in compras) {
      linhas += _itensSync(compra).length;
    }
    return linhas;
  }

  int _contagemUnidades(List<Venda> compras) {
    var unidades = 0;
    for (final compra in compras) {
      for (final item in _itensSync(compra)) {
        unidades += item.quantidade;
      }
    }
    return unidades;
  }

  List<_ProdutoTopAgg> _topProdutosPorFaturamento(
    List<Venda> compras,
    double totalFaturado,
  ) {
    final map = <String, _ProdutoTopAgg>{};
    for (final compra in compras) {
      for (final item in _itensSync(compra)) {
        final nome = item.nomeProduto.trim();
        if (nome.isEmpty) continue;
        final agg = map.putIfAbsent(nome, () => _ProdutoTopAgg(nome));
        agg.quantidade += item.quantidade;
        agg.faturamento += item.subtotal;
      }
    }
    final lista = map.values.toList()
      ..sort((a, b) => b.faturamento.compareTo(a.faturamento));
    if (totalFaturado <= 0) return lista.take(5).toList();
    return lista.take(5).toList();
  }

  Future<void> _abrirDetalheVenda(Venda compra) async {
    if (!mounted) return;
    dynamic atual = compra;
    try {
      atual = widget.vendaRepository.obterPorId(compra.id) ?? compra;
    } catch (_) {}
    final venda = atual is Venda ? atual : compra;
    final itens = await _itensAsync(venda);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(
            'Detalhes — ${VendaDocumentoRotuloHelper.rotuloTituloLista(venda)}',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _dataHora.format(venda.data.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_rotuloPagamento(venda)} · ${_rotuloEntrega(venda)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (itens.isEmpty)
                  const Text('Nenhum item registrado nesta venda.')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final item in itens)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      EntregaVendaHelper.abreviacaoTipoItem(
                                        item.tipoEntregaItem,
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${item.quantidadeExibicaoVenda} × ${item.nomeProduto}',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatarMoeda(item.subtotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total: ${_formatarMoeda(venda.total)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compras = widget.compras;
    final totalFaturado =
        compras.fold<double>(0, (acc, v) => acc + v.total);
    final ticketMedio =
        compras.isEmpty ? 0.0 : totalFaturado / compras.length;
    final linhas = _contagemLinhasProduto(compras);
    final unidades = _contagemUnidades(compras);
    final topProdutos = _topProdutosPorFaturamento(compras, totalFaturado);
    final maxFatTop = topProdutos.isEmpty
        ? 0.0
        : topProdutos.map((e) => e.faturamento).reduce((a, b) => a > b ? a : b);

    final sorted = [...compras]
      ..sort((a, b) => b.data.compareTo(a.data));
    final gruposOrdem = <String>[];
    final grupos = <String, List<Venda>>{};
    final subtotaisMes = <String, double>{};
    for (final compra in sorted) {
      final chave = _mesAnoGrupo(compra.data);
      grupos.putIfAbsent(chave, () => []).add(compra);
      subtotaisMes[chave] = (subtotaisMes[chave] ?? 0) + compra.total;
      if (!gruposOrdem.contains(chave)) gruposOrdem.add(chave);
    }

    return Scrollbar(
      controller: widget.scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView(
        controller: widget.scrollController,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: [
          _SectionCard(
            title: 'Histórico de compras',
            icon: Icons.history_outlined,
            children: [
              if (!widget.emEdicao)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Salve o cliente para habilitar o histórico de compras.',
                  ),
                )
              else ...[
                if (widget.carregandoCompras)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: widget.periodoHistorico,
                  decoration: const InputDecoration(
                    labelText: 'Período do histórico',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'todo',
                      child: Text('Todo o período'),
                    ),
                    DropdownMenuItem(
                      value: 'ultimos_30',
                      child: Text('Últimos 30 dias'),
                    ),
                    DropdownMenuItem(
                      value: 'ultimos_90',
                      child: Text('Últimos 90 dias'),
                    ),
                    DropdownMenuItem(
                      value: 'ano_atual',
                      child: Text('Ano atual'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    widget.onPeriodoChanged(value);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Resumo referente a: ${_rotuloPeriodo(widget.periodoHistorico)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Os valores abaixo não incluem o total acumulado (lifetime) '
                  'exibido no cabeçalho do cadastro.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 720 ? 4 : 2;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: cols >= 4 ? 2.35 : 2.1,
                      children: [
                        _KpiMiniCard(
                          icon: Icons.payments_outlined,
                          rotulo: 'Total faturado',
                          valor: _formatarMoeda(totalFaturado),
                          theme: theme,
                        ),
                        _KpiMiniCard(
                          icon: Icons.receipt_outlined,
                          rotulo: 'Ticket médio',
                          valor: _formatarMoeda(ticketMedio),
                          theme: theme,
                        ),
                        _KpiMiniCard(
                          icon: Icons.shopping_bag_outlined,
                          rotulo: 'Compras / pedidos',
                          valor: '${compras.length}',
                          theme: theme,
                        ),
                        _KpiMiniCard(
                          icon: Icons.inventory_2_outlined,
                          rotulo: 'Linhas · unidades',
                          valor: '${_inteiro.format(linhas)} · '
                              '${_inteiro.format(unidades)}',
                          theme: theme,
                        ),
                      ],
                    );
                  },
                ),
                if (topProdutos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Produtos mais comprados',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...topProdutos.map((p) {
                    final pct = totalFaturado > 0
                        ? (p.faturamento / totalFaturado * 100)
                        : 0.0;
                    final bar = maxFatTop > 0
                        ? (p.faturamento / maxFatTop).clamp(0.0, 1.0)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.nome,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_inteiro.format(p.quantidade)} un · '
                                '${pct.toStringAsFixed(1)}%',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: bar,
                              minHeight: 6,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                Text(
                  'Vendas no período',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (!widget.carregandoCompras && compras.isEmpty)
                  _EmptyState(theme: theme)
                else
                  ...gruposOrdem.map((mes) {
                    final vendasMes = grupos[mes] ?? const [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  mes,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                'Subtotal: ${_formatarMoeda(subtotaisMes[mes] ?? 0)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...vendasMes.map((compra) {
                          final itens = _itensSync(compra);
                          final qtdItens = itens.length;
                          final fiscalBadges = <Widget>[];
                          if (compra.nfceEmitida) {
                            fiscalBadges.add(
                              _FiscalBadge(
                                label: 'NFC-e',
                                color: theme.colorScheme.tertiaryContainer,
                                onColor: theme.colorScheme.onTertiaryContainer,
                              ),
                            );
                          }
                          if (compra.nfe55Autorizada) {
                            fiscalBadges.add(
                              _FiscalBadge(
                                label: 'NF-e',
                                color: theme.colorScheme.secondaryContainer,
                                onColor: theme.colorScheme.onSecondaryContainer,
                              ),
                            );
                          }
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              leading: Icon(
                                Icons.receipt_long_outlined,
                                size: 22,
                                color: theme.colorScheme.primary,
                              ),
                              title: Text(
                                VendaDocumentoRotuloHelper.rotuloTituloLista(
                                  compra,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _dataHora.format(compra.data.toLocal()),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_rotuloPagamento(compra)} · '
                                    '${_rotuloEntrega(compra)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (fiscalBadges.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: fiscalBadges,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatarMoeda(compra.total),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '$qtdItens ${qtdItens == 1 ? 'item' : 'itens'}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              onTap: () => _abrirDetalheVenda(compra),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhuma compra neste período',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Altere o filtro de período ou aguarde novas vendas finalizadas '
            'para este cliente.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FiscalBadge extends StatelessWidget {
  const _FiscalBadge({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: onColor,
        ),
      ),
    );
  }
}

class _KpiMiniCard extends StatelessWidget {
  const _KpiMiniCard({
    required this.icon,
    required this.rotulo,
    required this.valor,
    required this.theme,
  });

  final IconData icon;
  final String rotulo;
  final String valor;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              valor,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}
