import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/lista_compra_repository.dart';
import '../data/api/lista_compra_api_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/sugestao_compra_repository.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../domain/lista_compra_item_constantes.dart';
import '../domain/produto_embalagem.dart';
import '../model/item_lista_compra.dart';
import '../model/usuario_sistema.dart';
import '../services/lista_compra_export_service.dart';
import 'widgets/anotar_lista_compra_dialog.dart';
import 'widgets/lan_api_feedback.dart';
import 'shell/main_menu_deps.dart';

/// Lista de compras: anotacoes manuais, sugestoes do sistema e exportacao.
class ListaCompraPage extends StatefulWidget {
  const ListaCompraPage({
    super.key,
    required this.produtoRepository,
    this.usuarioLogado,
    this.listaCompraRepository,
  });

  final dynamic produtoRepository;
  final UsuarioSistema? usuarioLogado;
  final dynamic listaCompraRepository;

  @override
  State<ListaCompraPage> createState() => _ListaCompraPageState();
}

class _ListaCompraPageState extends State<ListaCompraPage>
    with SafeSyncRefreshMixin, SingleTickerProviderStateMixin {
  late final dynamic _repo;
  late final ListaCompraExportService _export;
  late final TabController _tabController;

  List<ItemListaCompra> _itens = [];
  List<LinhaSugestaoCompra> _sugestoes = [];
  String _filtroStatus = 'ativos';
  bool _carregandoSugestoes = false;
  static final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  String get _criadoPor => widget.usuarioLogado?.login ?? '';

  @override
  void initState() {
    super.initState();
    _repo = widget.listaCompraRepository ?? _criarRepositorio();
    _export = ListaCompraExportService(_repo);
    _tabController = TabController(length: 2, vsync: this);
    initSafeSyncRefresh(onReload: _recarregar);
    _carregarInicial();
  }

  dynamic _criarRepositorio() {
    try {
      return ListaCompraRepository(widget.produtoRepository.objectBox);
    } catch (_) {
      final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
      if (client == null) {
        throw StateError('Lista de compras requer conexao com o PC servidor.');
      }
      return ListaCompraApiRepository(
        client,
        produtoRepository: widget.produtoRepository,
      );
    }
  }

  Future<void> _carregarInicial() async {
    if (_repo is ListaCompraApiRepository) {
      try {
        await _repo.hidratar();
      } on LanApiException catch (e) {
        if (mounted) {
          LanApiFeedback.snackAviso(context, e, prefixo: 'Lista de compras');
        }
      }
    }
    _recarregar();
  }

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    _tabController.dispose();
    super.dispose();
  }

  void _recarregar() {
    if (!mounted) return;
    setState(() {
      _itens = _repo.listarTodos();
    });
    _carregarSugestoes();
  }

  Future<void> _carregarSugestoes() async {
    setState(() => _carregandoSugestoes = true);
    final s = await _repo.listarSugestoesSistemaFiltradas();
    if (!mounted) return;
    setState(() {
      _sugestoes = s;
      _carregandoSugestoes = false;
    });
  }

  List<ItemListaCompra> get _itensFiltrados {
    switch (_filtroStatus) {
      case 'urgente':
        return _itens
            .where(
              (i) =>
                  i.ativo && i.prioridade == ListaCompraItemPrioridade.urgente,
            )
            .toList();
      case 'recebidos':
        return _itens
            .where((i) => i.status == ListaCompraItemStatus.recebido)
            .toList();
      case 'cancelados':
        return _itens
            .where((i) => i.status == ListaCompraItemStatus.cancelado)
            .toList();
      case 'todos':
        return _itens;
      case 'ativos':
      default:
        return _itens.where((i) => i.ativo).toList();
    }
  }

  Future<void> _aceitarSugestao(LinhaSugestaoCompra linha) async {
    _repo.aceitarSugestaoSistema(linha: linha, criadoPor: _criadoPor);
    _recarregar();
  }

  Future<void> _ignorarSugestao(LinhaSugestaoCompra linha) async {
    await _repo.ignorarSugestaoSistema(linha.produto.id);
    _recarregar();
  }

  Future<void> _aceitarTodasSugestoes() async {
    for (final linha in _sugestoes) {
      _repo.aceitarSugestaoSistema(linha: linha, criadoPor: _criadoPor);
    }
    _recarregar();
  }

  Future<void> _alterarStatus(ItemListaCompra item, String status) async {
    _repo.atualizarStatus(item.id, status);
    _recarregar();
  }

  Future<void> _cancelarItem(ItemListaCompra item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar item'),
        content: Text(
          'Remover "${item.nomeExibicao(_repo.produtoDe(item))}" da lista?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar item'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _repo.cancelar(item.id);
      _recarregar();
    }
  }

  Future<void> _apagarItem(ItemListaCompra item) async {
    final nome = item.nomeExibicao(_repo.produtoDe(item));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar do historico'),
        content: Text(
          'Excluir permanentemente "$nome" da lista de compras?\n\n'
          'Esta acao nao afeta o cadastro do produto nem o estoque.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _repo.remover(item.id);
      _recarregar();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$nome" removido do historico.')));
    }
  }

  Future<void> _reabrirItem(ItemListaCompra item) async {
    final nome = item.nomeExibicao(_repo.produtoDe(item));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir item'),
        content: Text(
          'Voltar "$nome" para pendente na lista de compras?\n\n'
          'Use se a mercadoria ainda nao chegou ou a NF-e baixou por engano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _repo.reabrir(item.id);
      _recarregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$nome" reaberto como pendente.')),
      );
    }
  }

  Future<void> _abrirManutencaoHistorico() async {
    final qtdRecebidos = _repo.contarPorStatus(ListaCompraItemStatus.recebido);
    final qtdCancelados = _repo.contarPorStatus(
      ListaCompraItemStatus.cancelado,
    );
    final qtdAntigos = _repo.contarParaLimpeza(maisAntigosQueDias: 30);

    final acao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manutencao do historico'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recebidos: $qtdRecebidos · Cancelados: $qtdCancelados\n\n'
                'Itens finalizados ficam no historico ate voce apagar. '
                'Isso nao altera produtos nem estoque.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: qtdRecebidos <= 0
                    ? null
                    : () => Navigator.pop(ctx, 'recebidos'),
                icon: const Icon(Icons.inventory_outlined),
                label: Text('Apagar todos recebidos ($qtdRecebidos)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: qtdCancelados <= 0
                    ? null
                    : () => Navigator.pop(ctx, 'cancelados'),
                icon: const Icon(Icons.cancel_outlined),
                label: Text('Apagar todos cancelados ($qtdCancelados)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (qtdRecebidos + qtdCancelados) <= 0
                    ? null
                    : () => Navigator.pop(ctx, 'todos'),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(
                  'Apagar todo historico (${qtdRecebidos + qtdCancelados})',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: qtdAntigos <= 0
                    ? null
                    : () => Navigator.pop(ctx, 'antigos30'),
                icon: const Icon(Icons.history_outlined),
                label: Text('Apagar finalizados 30+ dias ($qtdAntigos)'),
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
      ),
    );
    if (acao == null || !mounted) return;

    late final String titulo;
    late final String corpo;
    late final Set<String> statuses;
    int? dias;
    switch (acao) {
      case 'recebidos':
        titulo = 'Apagar recebidos';
        corpo = 'Excluir permanentemente $qtdRecebidos item(ns) recebido(s)?';
        statuses = {ListaCompraItemStatus.recebido};
        dias = null;
      case 'cancelados':
        titulo = 'Apagar cancelados';
        corpo = 'Excluir permanentemente $qtdCancelados item(ns) cancelado(s)?';
        statuses = {ListaCompraItemStatus.cancelado};
        dias = null;
      case 'antigos30':
        titulo = 'Apagar antigos';
        corpo =
            'Excluir $qtdAntigos item(ns) recebido(s)/cancelado(s) com mais de 30 dias?';
        statuses = {
          ListaCompraItemStatus.recebido,
          ListaCompraItemStatus.cancelado,
        };
        dias = 30;
      case 'todos':
        titulo = 'Apagar historico';
        corpo =
            'Excluir permanentemente ${qtdRecebidos + qtdCancelados} '
            'item(ns) finalizado(s)?';
        statuses = {
          ListaCompraItemStatus.recebido,
          ListaCompraItemStatus.cancelado,
        };
        dias = null;
      default:
        return;
    }

    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(corpo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;
    final n = _repo.limparFinalizados(
      statuses: statuses,
      maisAntigosQueDias: dias,
    );
    _recarregar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n > 0 ? '$n item(ns) removido(s).' : 'Nenhum item removido.',
        ),
      ),
    );
  }

  Future<void> _abrirGruposFornecedor() async {
    final grupos = _repo.agruparAtivosPorFornecedor();
    if (grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum item ativo na lista.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Pedidos por fornecedor',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: grupos.length,
                    itemBuilder: (_, i) {
                      final g = grupos[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(g.fornecedor),
                          subtitle: Text(
                            '${g.itens.length} item(ns)'
                            '${g.valorEstimado > 0 ? ' · est. R\$ ${NumberFormat('#,##0.00', 'pt_BR').format(g.valorEstimado)}' : ''}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              final texto = _export.montarTextoPedidoFornecedor(
                                g,
                              );
                              if (v == 'whatsapp') {
                                await _export.compartilharWhatsApp(texto);
                              } else if (v == 'pdf') {
                                await _export.imprimirOuSalvarPdf(
                                  itens: g.itens,
                                  titulo: 'Pedido — ${g.fornecedor}',
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'whatsapp',
                                child: Text('Enviar WhatsApp'),
                              ),
                              PopupMenuItem(
                                value: 'pdf',
                                child: Text('Imprimir / PDF'),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final texto = _export.montarTextoPedidoFornecedor(
                              g,
                            );
                            await showDialog<void>(
                              context: ctx,
                              builder: (dCtx) => AlertDialog(
                                title: Text(g.fornecedor),
                                content: SingleChildScrollView(
                                  child: Text(texto),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx),
                                    child: const Text('Fechar'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(dCtx);
                                      await _export.compartilharWhatsApp(texto);
                                    },
                                    icon: const Icon(Icons.chat_outlined),
                                    label: const Text('WhatsApp'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportarCsv() async {
    final path = await _export.exportarCsv(itens: _itensFiltrados);
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('CSV salvo em: $path')));
  }

  Future<void> _exportarPdf() async {
    final path = await _export.salvarPdfEmArquivo(itens: _itensFiltrados);
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF salvo em: $path')));
    }
  }

  Future<void> _whatsappTodos() async {
    final texto = _export.montarTextoTodosFornecedores();
    await _export.compartilharWhatsApp(texto);
  }

  Widget _chipFiltro(String valor, String rotulo) {
    final sel = _filtroStatus == valor;
    return FilterChip(
      label: Text(rotulo),
      selected: sel,
      onSelected: (_) => setState(() => _filtroStatus = valor),
    );
  }

  Widget _buildListaItens() {
    final itens = _itensFiltrados;
    if (itens.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nenhum item neste filtro.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      itemCount: itens.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = itens[i];
        final prod = _repo.produtoDe(item);
        final nome = item.nomeExibicao(prod);
        final urgente = item.prioridade == ListaCompraItemPrioridade.urgente;
        final estoqueTxt = prod == null
            ? null
            : ProdutoEmbalagem.formatarEstoque(
                prod,
                prod.estoqueReal,
                comUnidade: true,
              );
        return Card(
          child: ListTile(
            isThreeLine: true,
            leading: CircleAvatar(
              backgroundColor: urgente
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                urgente ? Icons.priority_high : Icons.shopping_cart_outlined,
                size: 20,
              ),
            ),
            title: Text(
              nome,
              style: TextStyle(
                fontWeight: urgente ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantidadePendenteRecebimento} ${item.unidade}'
                  '${item.quantidadeRecebida > 0 ? ' (rec. ${item.quantidadeRecebida})' : ''}'
                  ' · ${ListaCompraItemStatus.rotulo(item.status)}'
                  '${estoqueTxt != null ? ' · est. $estoqueTxt' : ''}',
                ),
                if (item.fornecedorTexto.trim().isNotEmpty)
                  Text('Fornecedor: ${item.fornecedorTexto.trim()}'),
                if (item.observacao.trim().isNotEmpty)
                  Text(
                    item.observacao.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (item.resolvidoEm != null)
                  Text(
                    'Resolvido em ${_dataFmt.format(item.resolvidoEm!.toLocal())}'
                    '${item.nfeChaveResolucao.trim().isNotEmpty ? ' · NF-e' : ''}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                Text(
                  '${ListaCompraItemOrigem.rotulo(item.origem)} · ${_dataFmt.format(item.criadoEm.toLocal())}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'cancelar') {
                  await _cancelarItem(item);
                } else if (v == 'apagar') {
                  await _apagarItem(item);
                } else if (v == 'reabrir') {
                  await _reabrirItem(item);
                } else if (v.startsWith('status:')) {
                  await _alterarStatus(item, v.substring(7));
                }
              },
              itemBuilder: (_) => [
                if (item.ativo) ...[
                  const PopupMenuItem(
                    value: 'status:cotacao',
                    child: Text('Marcar: em cotacao'),
                  ),
                  const PopupMenuItem(
                    value: 'status:pedido',
                    child: Text('Marcar: pedido feito'),
                  ),
                  const PopupMenuItem(
                    value: 'status:recebido',
                    child: Text('Marcar: recebido'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'cancelar',
                    child: Text('Cancelar'),
                  ),
                ] else ...[
                  const PopupMenuItem(
                    value: 'reabrir',
                    child: Text('Reabrir como pendente'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'apagar',
                    child: Text('Apagar do historico'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSugestoes() {
    if (_carregandoSugestoes) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sugestoes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma sugestao pendente.\n'
            'O sistema usa giro, estoque minimo e ponto de pedido.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_sugestoes.length} produto(s) sugerido(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _aceitarTodasSugestoes,
                child: const Text('Aceitar todos'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            itemCount: _sugestoes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final l = _sugestoes[i];
              final p = l.produto;
              return Card(
                color: l.estoqueCritico
                    ? Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.35)
                    : null,
                child: ListTile(
                  title: Text(p.nome),
                  subtitle: Text(
                    'Sugerido: ${l.quantidadeSugerida} ${ProdutoEmbalagem.normalizarUnidade(p.unidade)} · '
                    'Estoque: ${ProdutoEmbalagem.formatarEstoque(p, p.estoqueReal, comUnidade: true)} · '
                    'PP: ${ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(p, l.pontoPedido)} '
                    '${ProdutoEmbalagem.normalizarUnidade(p.unidade)}'
                    '${l.estoqueCritico ? ' · CRITICO' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Ignorar',
                        onPressed: () => _ignorarSugestao(l),
                        icon: const Icon(Icons.close),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _aceitarSugestao(l),
                        child: const Text('Aceitar'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ativos = _repo.contarAtivos();
    final urgentes = _repo.contarAtivos(apenasUrgentes: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de compras'),
        actions: [
          IconButton(
            tooltip: 'Pedidos por fornecedor',
            onPressed: _abrirGruposFornecedor,
            icon: Badge(
              isLabelVisible: ativos > 0,
              label: Text('$ativos'),
              child: const Icon(Icons.store_outlined),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              if (v == 'csv') {
                await _exportarCsv();
              } else if (v == 'pdf') {
                await _exportarPdf();
              } else if (v == 'whatsapp') {
                await _whatsappTodos();
              } else if (v == 'manutencao') {
                await _abrirManutencaoHistorico();
              } else if (v == 'novo') {
                await mostrarAnotarListaCompraDialog(
                  context,
                  repository: _repo,
                  criadoPor: _criadoPor,
                );
                _recarregar();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'novo',
                child: Text('Anotar item livre'),
              ),
              const PopupMenuItem(
                value: 'manutencao',
                child: Text('Manutencao do historico...'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
              const PopupMenuItem(value: 'pdf', child: Text('Salvar PDF')),
              const PopupMenuItem(
                value: 'whatsapp',
                child: Text('WhatsApp (todos)'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Lista ($ativos)'),
            Tab(
              text: _sugestoes.isEmpty
                  ? 'Sugeridos'
                  : 'Sugeridos (${_sugestoes.length})',
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (urgentes > 0)
            MaterialBanner(
              content: Text('$urgentes item(ns) urgente(s) na lista.'),
              leading: const Icon(Icons.warning_amber_outlined),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _filtroStatus = 'urgente'),
                  child: const Text('Ver'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chipFiltro('ativos', 'Ativos'),
                _chipFiltro('urgente', 'Urgentes'),
                _chipFiltro('recebidos', 'Recebidos'),
                _chipFiltro('cancelados', 'Cancelados'),
                _chipFiltro('todos', 'Todos'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildListaItens(), _buildSugestoes()],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await mostrarAnotarListaCompraDialog(
            context,
            repository: _repo,
            criadoPor: _criadoPor,
          );
          _recarregar();
        },
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Anotar'),
      ),
    );
  }
}
