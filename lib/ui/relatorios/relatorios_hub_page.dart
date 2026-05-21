import 'package:flutter/material.dart';

import '../../data/cliente_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../relatorio_fiados_page.dart';
import '../widgets/hub_nav_button.dart';
import '../widgets/relatorios/relatorio_hub_secao.dart';
import 'relatorio_comissao_vendedores_page.dart';
import 'relatorio_cores.dart';
import 'relatorio_curva_abc_page.dart';
import 'relatorio_dashboard_executivo_page.dart';
import 'relatorio_entregas_resumo_page.dart';
import 'relatorio_estoque_minimo_page.dart';
import 'relatorio_historico_fechamento_page.dart';
import 'relatorio_orcamentos_abertos_page.dart';
import 'relatorio_produtos_mais_vendidos_page.dart';
import 'relatorio_saidas_produto_page.dart';
import 'relatorio_tabela_precos_page.dart';
import 'relatorio_vendas_promocao_page.dart';
import '../../data/promocao_repository.dart';
import 'relatorio_top_clientes_page.dart';
import 'relatorio_vendas_periodo_page.dart';
import 'relatorio_vendas_por_vendedor_page.dart';

/// Item do hub de relatorios (categoria + metadados para busca).
class _RelatorioHubItem {
  const _RelatorioHubItem({
    required this.categoriaId,
    required this.categoriaTitulo,
    required this.categoriaIcone,
    required this.icon,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.palavrasChave,
    required this.onTap,
  });

  final String categoriaId;
  final String categoriaTitulo;
  final IconData categoriaIcone;
  final IconData icon;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final List<String> palavrasChave;
  final VoidCallback onTap;
}

/// Hub de relatorios gerenciais (material de construcao) — categorizado + busca.
class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
    required this.produtoRepository,
    this.onAbrirModuloEntregas,
    this.onAbrirModuloCaixa,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;
  final ProdutoRepository produtoRepository;
  final VoidCallback? onAbrirModuloEntregas;
  final VoidCallback? onAbrirModuloCaixa;

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  final _buscaController = TextEditingController();
  final _buscaFocus = FocusNode();

  static const _ordemCategorias = [
    'executivo',
    'financeiro',
    'vendas',
    'clientes',
    'produtos',
    'operacional',
  ];

  @override
  void dispose() {
    _buscaController.dispose();
    _buscaFocus.dispose();
    super.dispose();
  }

  List<_RelatorioHubItem> _todasEntradas() {
    final v = widget.vendaRepository;
    final c = widget.clienteRepository;
    final vd = widget.vendedorRepository;
    final p = widget.produtoRepository;

    return [
      _RelatorioHubItem(
        categoriaId: 'executivo',
        categoriaTitulo: 'Visao executiva',
        categoriaIcone: Icons.dashboard_outlined,
        icon: Icons.insights_outlined,
        cor: corRelDashboard,
        titulo: 'Painel executivo',
        subtitulo:
            'KPIs do mes, comparativo e alertas (fiado, estoque, orcamentos, entregas).',
        palavrasChave: const [
          'dashboard',
          'executivo',
          'kpi',
          'alerta',
          'resumo',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioDashboardExecutivoPage(
              vendaRepository: v,
              clienteRepository: c,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'executivo',
        categoriaTitulo: 'Visao executiva',
        categoriaIcone: Icons.dashboard_outlined,
        icon: Icons.pie_chart_outline,
        cor: corRelAbc,
        titulo: 'Curva ABC',
        subtitulo:
            'Classificacao A/B/C de clientes e produtos por faturamento no periodo.',
        palavrasChave: const [
          'abc',
          'curva',
          'classificacao',
          'pareto',
          'clientes',
          'produtos',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioCurvaAbcPage(
              vendaRepository: v,
              clienteRepository: c,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'financeiro',
        categoriaTitulo: 'Financeiro e credito',
        categoriaIcone: Icons.account_balance_wallet_outlined,
        icon: Icons.receipt_long_outlined,
        cor: corRelFiados,
        titulo: 'Fiados em aberto',
        subtitulo:
            'Titulos a receber por cliente, vencimento e saldo; filtro de vencidos.',
        palavrasChave: const [
          'fiado',
          'credito',
          'receber',
          'vencido',
          'titulo',
          'financeiro',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioFiadosPage(
              vendaRepository: v,
              clienteRepository: c,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.date_range_outlined,
        cor: corRelVendasPeriodo,
        titulo: 'Vendas por periodo',
        subtitulo:
            'Lista vendas finalizadas no intervalo; inclui ajuste por devolucoes/trocas.',
        palavrasChave: const [
          'vendas',
          'periodo',
          'faturamento',
          'nota',
          'finalizada',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioVendasPeriodoPage(
              vendaRepository: v,
              clienteRepository: c,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.description_outlined,
        cor: corRelOrcamentos,
        titulo: 'Orcamentos em aberto',
        subtitulo:
            'Orcamentos ainda nao finalizados no caixa — valor em pipeline.',
        palavrasChave: const [
          'orcamento',
          'aberto',
          'pipeline',
          'pendente',
          'caixa',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioOrcamentosAbertosPage(
              vendaRepository: v,
              clienteRepository: c,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.person_search_outlined,
        cor: corRelVendasVendedor,
        titulo: 'Vendas por vendedor',
        subtitulo:
            'Total por representante no periodo, com ajuste de devolucoes/trocas.',
        palavrasChave: const [
          'vendedor',
          'representante',
          'vendas',
          'ranking',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioVendasPorVendedorPage(
              vendaRepository: v,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'vendas',
        categoriaTitulo: 'Vendas e faturamento',
        categoriaIcone: Icons.point_of_sale_outlined,
        icon: Icons.payments_outlined,
        cor: corRelComissao,
        titulo: 'Comissao de vendedores',
        subtitulo:
            'Percentual do cadastro; base em venda ou lucro (ajustado por devolucoes).',
        palavrasChave: const [
          'comissao',
          'vendedor',
          'lucro',
          'percentual',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioComissaoVendedoresPage(
              vendaRepository: v,
              vendedorRepository: vd,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'clientes',
        categoriaTitulo: 'Clientes',
        categoriaIcone: Icons.groups_outlined,
        icon: Icons.leaderboard_outlined,
        cor: corRelTopClientes,
        titulo: 'Clientes que mais compraram',
        subtitulo:
            'Ranking por valor no periodo (vendas menos devolucoes/trocas).',
        palavrasChave: const [
          'cliente',
          'ranking',
          'top',
          'compraram',
          'fidelidade',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioTopClientesPage(
              vendaRepository: v,
              clienteRepository: c,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.trending_up_outlined,
        cor: corRelProdutosRanking,
        titulo: 'Produtos mais vendidos',
        subtitulo:
            'Quantidade e valor no periodo, ajustado por devolucoes/trocas.',
        palavrasChave: const [
          'produto',
          'mais vendidos',
          'ranking',
          'quantidade',
          'estoque',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioProdutosMaisVendidosPage(
              vendaRepository: v,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.warning_amber_outlined,
        cor: corRelEstoqueMin,
        titulo: 'Estoque abaixo do minimo',
        subtitulo:
            'Produtos com saldo menor que a quantidade minima cadastrada.',
        palavrasChave: const [
          'estoque',
          'minimo',
          'ruptura',
          'reposicao',
          'saldo',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioEstoqueMinimoPage(
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.unarchive_outlined,
        cor: corRelSaidasProduto,
        titulo: 'Saidas por produto',
        subtitulo:
            'Vendas finalizadas do item no periodo: quantidade, lucro e cliente.',
        palavrasChave: const [
          'saida',
          'produto',
          'movimentacao',
          'lucro',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioSaidasProdutoPage(
              vendaRepository: v,
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.local_offer_outlined,
        cor: corRelVendasPromocao,
        titulo: 'Vendas em promocao',
        subtitulo:
            'Itens vendidos com campanha promocional no periodo: campanha, lucro e cliente.',
        palavrasChave: const [
          'promocao',
          'campanha',
          'oferta',
          'desconto',
          'promo',
        ],
        onTap: () {
          final promoRepo = PromocaoRepository(p.objectBox);
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RelatorioVendasPromocaoPage(
                vendaRepository: v,
                promocaoRepository: promoRepo,
              ),
            ),
          );
        },
      ),
      _RelatorioHubItem(
        categoriaId: 'produtos',
        categoriaTitulo: 'Produtos e estoque',
        categoriaIcone: Icons.inventory_2_outlined,
        icon: Icons.table_chart_outlined,
        cor: corRelTabelaPrecos,
        titulo: 'Tabela de precos',
        subtitulo:
            'PDF alfabetico com estoque; precos de venda ou com custo; somente ativos.',
        palavrasChave: const [
          'tabela',
          'preco',
          'pdf',
          'catalogo',
          'lista',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioTabelaPrecosPage(
              produtoRepository: p,
            ),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.lock_clock_outlined,
        cor: corRelFechamentoHist,
        titulo: 'Historico de fechamento',
        subtitulo:
            'Fechamentos de caixa gravados na auditoria local; detalhe e exportacao.',
        palavrasChave: const [
          'fechamento',
          'caixa',
          'turno',
          'historico',
          'auditoria',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const RelatorioHistoricoFechamentoPage(),
          ),
        ),
      ),
      _RelatorioHubItem(
        categoriaId: 'operacional',
        categoriaTitulo: 'Operacional',
        categoriaIcone: Icons.settings_suggest_outlined,
        icon: Icons.local_shipping_outlined,
        cor: corRelEntregasResumo,
        titulo: 'Entregas — resumo',
        subtitulo:
            'Status, atrasadas e agenda de hoje; atalho para romaneios no modulo Entregas.',
        palavrasChave: const [
          'entrega',
          'romaneio',
          'carreto',
          'motorista',
          'logistica',
          'atrasada',
        ],
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RelatorioEntregasResumoPage(
              vendaRepository: v,
              onAbrirModuloEntregas: widget.onAbrirModuloEntregas,
            ),
          ),
        ),
      ),
    ];
  }

  List<_RelatorioHubItem> _entradasFiltradas() {
    final termo = _buscaController.text.trim().toLowerCase();
    final todas = _todasEntradas();
    if (termo.isEmpty) return todas;
    return todas.where((item) {
      final blob = [
        item.titulo,
        item.subtitulo,
        item.categoriaTitulo,
        ...item.palavrasChave,
      ].join(' ').toLowerCase();
      return blob.contains(termo);
    }).toList();
  }

  Map<String, List<_RelatorioHubItem>> _agruparPorCategoria(
    List<_RelatorioHubItem> itens,
  ) {
    final map = <String, List<_RelatorioHubItem>>{};
    for (final id in _ordemCategorias) {
      map[id] = [];
    }
    for (final item in itens) {
      map.putIfAbsent(item.categoriaId, () => []).add(item);
    }
    return map;
  }

  Widget _buildCard(_RelatorioHubItem item) {
    return HubNavButton(
      icon: item.icon,
      corDestaque: item.cor,
      titulo: item.titulo,
      subtitulo: item.subtitulo,
      onTap: item.onTap,
    );
  }

  List<Widget> _buildSecoesHub(
    Map<String, List<_RelatorioHubItem>> agrupados,
  ) {
    final widgets = <Widget>[];
    for (final catId in _ordemCategorias) {
      final itens = agrupados[catId] ?? const <_RelatorioHubItem>[];
      if (itens.isEmpty) continue;
      final primeiro = itens.first;
      widgets.addAll([
        RelatorioHubSecao(
          titulo: primeiro.categoriaTitulo,
          icone: primeiro.categoriaIcone,
          quantidadeItens: itens.length,
        ),
        _buildGridSecao(itens),
      ]);
    }
    return widgets;
  }

  Widget _buildGridSecao(List<_RelatorioHubItem> itens) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final duasColunas = constraints.maxWidth >= 640;
        if (!duasColunas) {
          return Column(
            children: [
              for (var i = 0; i < itens.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildCard(itens[i]),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < itens.length; i += 2) {
          final esquerda = itens[i];
          final direita = i + 1 < itens.length ? itens[i + 1] : null;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildCard(esquerda)),
                const SizedBox(width: 12),
                Expanded(
                  child: direita == null
                      ? const SizedBox.shrink()
                      : _buildCard(direita),
                ),
              ],
            ),
          );
          if (i + 2 < itens.length) {
            rows.add(const SizedBox(height: 12));
          }
        }
        return Column(children: rows);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _entradasFiltradas();
    final agrupados = _agruparPorCategoria(filtrados);
    final termoBusca = _buscaController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatorios'),
        actions: [
          IconButton(
            tooltip: 'Focar busca',
            icon: const Icon(Icons.search),
            onPressed: () => _buscaFocus.requestFocus(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Escolha o relatorio por area da loja. Use a busca para filtrar por nome.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscaController,
            focusNode: _buscaFocus,
            decoration: InputDecoration(
              labelText: 'Buscar relatorio',
              hintText: 'Ex.: fiado, estoque, comissao...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: termoBusca.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() {});
                      },
                    ),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'Nenhum relatorio encontrado para "$termoBusca".',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            ..._buildSecoesHub(agrupados),
        ],
      ),
    );
  }
}
