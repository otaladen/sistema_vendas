import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/produto_repository.dart';
import '../data/reajuste_preco_repository.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../data/usuario_repository.dart';
import '../main.dart';
import '../domain/estoque/filtro_estoque_operacional.dart';
import '../domain/permissao_usuario.dart';
import '../domain/produto_unidade_exibicao.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/produto.dart';
import '../model/usuario_sistema.dart';
import '../services/compras_preditivas_service.dart';
import '../services/pdf_tabela_produtos_texto.dart';
import 'reajuste_preco_autorizacao.dart';
import 'reajuste_preco_historico_page.dart';
import 'reajuste_preco_lote_page.dart';
import 'estoque/ajuste_estoque_dialog.dart';
import 'estoque/extrato_movimento_estoque_panel.dart';
import 'sugestao_compra_page.dart';
import 'widgets/produto_busca_input.dart';

final NumberFormat _moedaBRL = NumberFormat('#,##0.00', 'pt_BR');

class EstoquePage extends StatefulWidget {
  const EstoquePage({
    super.key,
    required this.produtoRepository,
    required this.usuarioLogado,
  });

  final ProdutoRepository produtoRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> with SafeSyncRefreshMixin {
  final _usuarioRepository = UsuarioRepository();

  ReajustePrecoRepository get _reajusteRepo => ReajustePrecoRepository(
        widget.produtoRepository.objectBox,
        widget.produtoRepository,
      );

  final TextEditingController _buscaController = TextEditingController();
  String _filtroBusca = '';
  FiltroEstoqueOperacional _filtroOperacional = FiltroEstoqueOperacional.todos;
  String? _filtroCategoria;
  String? _filtroFornecedor;
  List<Produto> _produtos = [];
  Map<int, bool> _criticoPpPorProdutoId = {};
  Map<int, int> _consumo60dPorProdutoId = {};
  int _qtdCriticosPp = 0;

  ComprasPreditivasService get _comprasSvc =>
      ComprasPreditivasService(widget.produtoRepository.objectBox);

  @override
  void initState() {
    super.initState();
    _recarregarProdutos();
    initSafeSyncRefresh(
      onReload: _recarregarProdutos,
      aoConcluir: _snackbarDadosAtualizados,
    );
  }

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    _buscaController.dispose();
    super.dispose();
  }

  void _recarregarProdutos() {
    if (!mounted) return;
    final produtos = widget.produtoRepository.listarTodos();
    final consumo = _comprasSvc.montarConsumoPorProdutoNoPeriodo(dias: 60);
    final criticos = _comprasSvc.mapaProdutosAtivosCriticos(
      consumoPrecalculado: consumo,
    );
    setState(() {
      _produtos = produtos;
      _consumo60dPorProdutoId = consumo;
      _criticoPpPorProdutoId = criticos;
      _qtdCriticosPp = criticos.length;
      if (_filtroOperacional == FiltroEstoqueOperacional.ppCritico &&
          _qtdCriticosPp == 0) {
        _filtroOperacional = FiltroEstoqueOperacional.todos;
      }
    });
  }

  List<String> _categoriasDisponiveis() {
    final set = <String>{};
    for (final p in _produtos) {
      final c = p.categoria.trim();
      if (c.isNotEmpty) set.add(c);
    }
    final lista = set.toList()..sort();
    return lista;
  }

  List<String> _fornecedoresDisponiveis() {
    final set = <String>{};
    for (final p in _produtos) {
      final f = p.fornecedor.trim();
      if (f.isNotEmpty) set.add(f);
    }
    final lista = set.toList()..sort();
    return lista;
  }

  bool _produtoSemGiro(Produto p, int dias) {
    final consumo = _consumo60dPorProdutoId[p.id] ?? 0;
    if (consumo > 0 && dias <= 60) return false;
    final ref = p.ultimaVendaEm ?? p.criadoEm;
    return DateTime.now().difference(ref.toLocal()).inDays >= dias;
  }

  double _valorEstoqueTotal(Iterable<Produto> produtos) {
    return produtos.where((p) => p.ativo).fold<double>(0, (s, p) {
      final custo = p.custoMedio > 0 ? p.custoMedio : p.precoCusto;
      return s + p.estoqueReal * custo;
    });
  }

  int _totalReservado(Iterable<Produto> produtos) =>
      produtos.fold<int>(0, (s, p) => s + p.estoqueReservado);

  Future<void> _abrirAjusteEstoque(Produto produto) async {
    final resultado = await showAjusteEstoqueDialog(
      context: context,
      produto: produto,
    );
    if (resultado == null || !mounted) return;
    try {
      widget.produtoRepository.ajustarEstoqueManual(
        produtoId: produto.id,
        novaQuantidadeFisica: resultado.novaQuantidadeFisica,
        motivo: resultado.motivo,
        usuarioLogin: widget.usuarioLogado.login,
      );
      _recarregarProdutos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estoque de "${produto.nome}" ajustado para '
            '${resultado.novaQuantidadeFisica}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao ajustar estoque: $e')),
      );
    }
  }

  Future<void> _abrirExtratoEstoque(Produto produto) {
    return showExtratoMovimentoEstoque(
      context: context,
      tituloProduto: produto.nome,
      child: ExtratoMovimentoEstoquePanel(
        produtoRepository: widget.produtoRepository,
        produtoId: produto.id,
      ),
    );
  }

  Widget _kpiCard({
    required String titulo,
    required String valor,
    required Color bg,
    required Color border,
    required Color fg,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: tile,
      ),
    );
  }

  Future<void> _abrirSugestaoCompra() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SugestaoCompraPage(
          produtoRepository: widget.produtoRepository,
        ),
      ),
    );
    if (mounted) _recarregarProdutos();
  }

  Future<void> _abrirReajustePrecos(List<Produto> escopo) async {
    if (!usuarioPodeReajustePrecoLote(widget.usuarioLogado)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem permissao para reajuste em lote. Ative em Cadastros > Usuarios.',
          ),
        ),
      );
      return;
    }
    if (escopo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum item na lista filtrada.')),
      );
      return;
    }
    final filtros = <String>[];
    if (_filtroBusca.trim().isNotEmpty) {
      filtros.add('busca "${_filtroBusca.trim()}"');
    }
    if (_filtroOperacional != FiltroEstoqueOperacional.todos) {
      filtros.add(_filtroOperacional.rotulo);
    }
    final tituloEscopo = filtros.isEmpty
        ? 'Todos os itens visiveis na Estoque (${escopo.length}).'
        : 'Filtros: ${filtros.join(' · ')} (${escopo.length} itens).';

    final aplicou = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReajustePrecoLotePage(
          produtoRepository: widget.produtoRepository,
          reajusteRepository: _reajusteRepo,
          usuarioRepository: _usuarioRepository,
          usuarioLogado: widget.usuarioLogado,
          escopoInicial: escopo,
          tituloEscopo: tituloEscopo,
        ),
      ),
    );
    if (aplicou == true && mounted) _recarregarProdutos();
  }

  void _abrirHistoricoReajustes() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReajustePrecoHistoricoPage(
          reajusteRepository: _reajusteRepo,
          usuarioRepository: _usuarioRepository,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
  }

  void _snackbarDadosAtualizados({required bool daRede}) {
    if (!daRede || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Dados atualizados da rede'),
      ),
    );
  }

  String _formatarMoedaBRL(double valor) {
    return 'R\$ ${_moedaBRL.format(valor)}';
  }

  String _csvSeguro(String valor) {
    final texto = valor.replaceAll('"', '""');
    return '"$texto"';
  }

  String _formatarNumeroCsv(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _precoAVista(Produto produto) {
    return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
  }

  Future<void> _mostrarProgressoExportacao(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Exportando arquivo, aguarde...')),
          ],
        ),
      ),
    );
  }

  Future<void> _exportarTabelaProdutos(
    BuildContext context, {
    required bool incluirCustos,
  }) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar a tabela',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    if (!context.mounted) return;
    _mostrarProgressoExportacao(context);
    try {
      final produtos = widget.produtoRepository.listarTodos();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo = incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final arquivo = File(p.join(pastaDestino, '${tipoArquivo}_$timestamp.csv'));
      final linhas = <String>[];
      linhas.add(
        incluirCustos
            ? 'SKU;Nome;Unidade;Categoria;Estoque;Minimo;Custo;Custo medio;Preco venda;Preco a vista'
            : 'SKU;Nome;Unidade;Categoria;Estoque;Minimo;Preco venda;Preco a vista',
      );
      for (final produto in produtos) {
        if (incluirCustos) {
          linhas.add([
            _csvSeguro(produto.codigoInterno),
            _csvSeguro(produto.nome),
            _csvSeguro(produto.unidade),
            _csvSeguro(produto.categoria),
            '${produto.estoqueReal}',
            '${produto.quantidadeMinima}',
            _formatarNumeroCsv(produto.precoCusto),
            _formatarNumeroCsv(produto.custoMedio),
            _formatarNumeroCsv(produto.precoVenda),
            _formatarNumeroCsv(_precoAVista(produto)),
          ].join(';'));
        } else {
          linhas.add([
            _csvSeguro(produto.codigoInterno),
            _csvSeguro(produto.nome),
            _csvSeguro(produto.unidade),
            _csvSeguro(produto.categoria),
            '${produto.estoqueReal}',
            '${produto.quantidadeMinima}',
            _formatarNumeroCsv(produto.precoVenda),
            _formatarNumeroCsv(_precoAVista(produto)),
          ].join(';'));
        }
      }
      await arquivo.writeAsString('\uFEFF${linhas.join('\n')}', encoding: utf8);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('CSV exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar CSV: $e'),
        ),
      );
    }
  }

  Future<void> _exportarTabelaProdutosPdf(
    BuildContext context, {
    required bool incluirCustos,
  }) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar o PDF',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    if (!context.mounted) return;
    _mostrarProgressoExportacao(context);
    try {
      final produtos = widget.produtoRepository.listarTodos();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo = incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final arquivo = File(p.join(pastaDestino, '${tipoArquivo}_$timestamp.pdf'));
      final titulo =
          incluirCustos ? 'Tabela de precos e custos' : 'Tabela de precos';
      final bytes = await gerarPdfTabelaProdutosTexto(
        produtos: produtos,
        incluirCustos: incluirCustos,
        titulo: titulo,
        incluirColunaEstoque: false,
      );
      await arquivo.writeAsBytes(bytes);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('PDF exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar PDF: $e'),
        ),
      );
    }
  }

  List<Produto> _aplicarFiltrosLista(List<Produto> produtos) {
    final termo = _filtroBusca.trim();
    final porBusca = termo.isEmpty
        ? produtos
        : widget.produtoRepository.pesquisarNaBasePadraoPdv(
            termo,
            produtos,
            limite: 500,
            somenteAtivos: false,
          );
    return porBusca.where((p) {
      if (_filtroCategoria != null &&
          p.categoria.trim() != _filtroCategoria) {
        return false;
      }
      if (_filtroFornecedor != null &&
          p.fornecedor.trim() != _filtroFornecedor) {
        return false;
      }
      switch (_filtroOperacional) {
        case FiltroEstoqueOperacional.todos:
          break;
        case FiltroEstoqueOperacional.abaixoMinimo:
          if (!(p.ativo && p.estoque <= p.quantidadeMinima)) return false;
        case FiltroEstoqueOperacional.ppCritico:
          if (!(_criticoPpPorProdutoId[p.id] ?? false)) return false;
        case FiltroEstoqueOperacional.comReserva:
          if (p.estoqueReservado <= 0) return false;
        case FiltroEstoqueOperacional.estoqueNegativo:
          if (p.estoqueReal >= 0 && p.estoqueLivreParaVenda >= 0) return false;
        case FiltroEstoqueOperacional.semGiro30:
        case FiltroEstoqueOperacional.semGiro60:
        case FiltroEstoqueOperacional.semGiro90:
          final dias = _filtroOperacional.diasSemGiro!;
          if (!_produtoSemGiro(p, dias)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final produtos = _produtos;
    final produtosFiltrados = _aplicarFiltrosLista(produtos);
    final produtosAtivos = produtos.where((p) => p.ativo).length;
    final totalAbaixoMinimo = produtos
        .where((p) => p.ativo && p.estoque <= p.quantidadeMinima)
        .length;
    final valorEstoque = _valorEstoqueTotal(produtos);
    final totalReservado = _totalReservado(produtos);
    final verCusto = UsuarioPermissaoHelper.tem(
      widget.usuarioLogado,
      PermissaoUsuario.verCustoMargem,
    );
    final categorias = _categoriasDisponiveis();
    final fornecedores = _fornecedoresDisponiveis();
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque'),
        actions: [
          if (usuarioPodeReajustePrecoLote(widget.usuarioLogado)) ...[
            IconButton(
              tooltip: 'Historico de reajustes',
              icon: const Icon(Icons.history),
              onPressed: _abrirHistoricoReajustes,
            ),
            IconButton(
              tooltip: 'Reajuste de precos em lote',
              icon: const Icon(Icons.price_change_outlined),
              onPressed: () {
                final escopo = _aplicarFiltrosLista(_produtos);
                _abrirReajustePrecos(escopo);
              },
            ),
          ],
          IconButton(
            tooltip: 'Sugestao de compra',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: _abrirSugestaoCompra,
          ),
          PopupMenuButton<String>(
            tooltip: 'Exportar tabelas',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (value) async {
              if (value == 'precos') {
                await _exportarTabelaProdutos(context, incluirCustos: false);
              } else if (value == 'preco_custo') {
                await _exportarTabelaProdutos(context, incluirCustos: true);
              } else if (value == 'precos_pdf') {
                await _exportarTabelaProdutosPdf(context, incluirCustos: false);
              } else if (value == 'preco_custo_pdf') {
                await _exportarTabelaProdutosPdf(context, incluirCustos: true);
              }
            },
            itemBuilder: (context) {
              final verCusto = UsuarioPermissaoHelper.tem(
                widget.usuarioLogado,
                PermissaoUsuario.verCustoMargem,
              );
              return [
                const PopupMenuItem<String>(
                  value: 'precos',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.sell_outlined),
                    title: Text('Exportar tabela de precos'),
                  ),
                ),
                if (verCusto) ...[
                  const PopupMenuItem<String>(
                    value: 'preco_custo',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.price_change_outlined),
                      title: Text('Exportar tabela de preco e custo'),
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                const PopupMenuItem<String>(
                  value: 'precos_pdf',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Exportar tabela de precos (PDF)'),
                  ),
                ),
                if (verCusto)
                  const PopupMenuItem<String>(
                    value: 'preco_custo_pdf',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.request_quote_outlined),
                      title: Text('Exportar tabela de preco e custo (PDF)'),
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_qtdCriticosPp > 0)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Icon(
                Icons.shopping_bag_outlined,
                color: semantic?.warningFg ?? theme.colorScheme.error,
              ),
              content: Text(
                '$_qtdCriticosPp produto(s) no ou abaixo do ponto de pedido. '
                'Abra a sugestao de compra para repor.',
              ),
              actions: [
                TextButton(
                  onPressed: _abrirSugestaoCompra,
                  child: const Text('Ver sugestao'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _filtroOperacional = FiltroEstoqueOperacional.ppCritico;
                    });
                  },
                  child: const Text('Filtrar lista'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: LayoutBuilder(
              builder: (context, c) {
                final estreito = c.maxWidth < 900;
                final infoBg = semantic?.infoBg ?? const Color(0xFFEAF2FF);
                final infoBorder = semantic?.infoBorder ?? const Color(0xFF9EC0FF);
                final infoFg = semantic?.infoFg ?? const Color(0xFF1E3A8A);
                final errBg = semantic?.errorBg ?? const Color(0xFFFDECEC);
                final errBorder = semantic?.errorBorder ?? const Color(0xFFF1A3A3);
                final errFg = semantic?.errorFg ?? const Color(0xFF9B1C1C);
                final warnBg = semantic?.warningBg ?? const Color(0xFFFFF8E6);
                final warnBorder = semantic?.warningBorder ?? const Color(0xFFF2CC7A);
                final warnFg = semantic?.warningFg ?? const Color(0xFF8A5B00);
                final kpis = [
                  _kpiCard(
                    titulo: 'SKUs ativos',
                    valor: '$produtosAtivos',
                    bg: infoBg,
                    border: infoBorder,
                    fg: infoFg,
                  ),
                  _kpiCard(
                    titulo: 'Abaixo minimo',
                    valor: '$totalAbaixoMinimo',
                    bg: errBg,
                    border: errBorder,
                    fg: errFg,
                    onTap: () => setState(
                      () => _filtroOperacional =
                          FiltroEstoqueOperacional.abaixoMinimo,
                    ),
                  ),
                  _kpiCard(
                    titulo: 'PP critico',
                    valor: '$_qtdCriticosPp',
                    bg: warnBg,
                    border: warnBorder,
                    fg: warnFg,
                    onTap: _qtdCriticosPp > 0
                        ? () => setState(
                              () => _filtroOperacional =
                                  FiltroEstoqueOperacional.ppCritico,
                            )
                        : null,
                  ),
                  if (verCusto)
                    _kpiCard(
                      titulo: 'Valor em estoque',
                      valor: _formatarMoedaBRL(valorEstoque),
                      bg: infoBg,
                      border: infoBorder,
                      fg: infoFg,
                    ),
                  _kpiCard(
                    titulo: 'Total reservado',
                    valor: '$totalReservado un.',
                    bg: warnBg,
                    border: warnBorder,
                    fg: warnFg,
                    onTap: () => setState(
                      () => _filtroOperacional =
                          FiltroEstoqueOperacional.comReserva,
                    ),
                  ),
                ];
                if (estreito) {
                  return Column(
                    children: [
                      for (var i = 0; i < kpis.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        kpis[i],
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in kpis)
                      SizedBox(
                        width: ((c.maxWidth - 8 * (kpis.length - 1)) / kpis.length)
                            .clamp(120.0, 280.0),
                        child: k,
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _buscaController,
                  decoration: produtoBuscaInputDecoration(
                    suffixIcon: _filtroBusca.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar pesquisa',
                            onPressed: () {
                              _buscaController.clear();
                              setState(() => _filtroBusca = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) => setState(() => _filtroBusca = value),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: FiltroEstoqueOperacional.values.map((f) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(f.rotulo),
                          selected: _filtroOperacional == f,
                          onSelected: (_) {
                            setState(() => _filtroOperacional = f);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (categorias.isNotEmpty || fornecedores.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (categorias.isNotEmpty)
                        DropdownMenu<String?>(
                          label: const Text('Categoria'),
                          initialSelection: _filtroCategoria,
                          dropdownMenuEntries: [
                            const DropdownMenuEntry<String?>(
                              value: null,
                              label: 'Todas',
                            ),
                            for (final c in categorias)
                              DropdownMenuEntry<String?>(
                                value: c,
                                label: c,
                              ),
                          ],
                          onSelected: (v) =>
                              setState(() => _filtroCategoria = v),
                        ),
                      if (fornecedores.isNotEmpty)
                        DropdownMenu<String?>(
                          label: const Text('Fornecedor'),
                          initialSelection: _filtroFornecedor,
                          dropdownMenuEntries: [
                            const DropdownMenuEntry<String?>(
                              value: null,
                              label: 'Todos',
                            ),
                            for (final f in fornecedores)
                              DropdownMenuEntry<String?>(
                                value: f,
                                label: f,
                              ),
                          ],
                          onSelected: (v) =>
                              setState(() => _filtroFornecedor = v),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'Itens: ${produtosFiltrados.length}/${produtos.length}',
                      ),
                    ),
                    if (_filtroOperacional != FiltroEstoqueOperacional.todos)
                      ActionChip(
                        avatar: const Icon(Icons.filter_alt_off, size: 18),
                        label: const Text('Limpar filtro'),
                        onPressed: () => setState(
                          () => _filtroOperacional =
                              FiltroEstoqueOperacional.todos,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: produtosFiltrados.length,
              cacheExtent: 800,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final produto = produtosFiltrados[index];
                final abaixoMinimo =
                    produto.estoque <= produto.quantidadeMinima;
                final criticoPp =
                    _criticoPpPorProdutoId[produto.id] ?? false;
                final ppExibicao =
                    _comprasSvc.calcularPontoPedidoExibicao(produto);
                final statusCor = criticoPp
                    ? (semantic?.errorFg ?? theme.colorScheme.error)
                    : abaixoMinimo
                        ? Colors.orange
                        : Colors.green;
                final statusTexto = criticoPp
                    ? 'PP'
                    : abaixoMinimo
                        ? 'Min'
                        : 'OK';

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: criticoPp
                          ? (semantic?.errorFg ?? theme.colorScheme.error)
                              .withValues(alpha: 0.45)
                          : theme.colorScheme.outlineVariant,
                    ),
                    color: criticoPp
                        ? (semantic?.errorBg ?? theme.colorScheme.errorContainer)
                            .withValues(alpha: 0.2)
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              produto.nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Un: ${rotuloUnidadeProdutoLista(produto)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SKU: ${produto.codigoInterno} | Livre: ${produto.estoqueLivreParaVenda} · '
                              'Fis: ${produto.estoqueReal} · Res: ${produto.estoqueReservado} | '
                              'Min: ${produto.quantidadeMinima}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'PP/limiar: ${ppExibicao.toStringAsFixed(1)} · '
                              'Atual: ${produto.estoqueAtual} · '
                              'Media: ${produto.vendaMediaDiaria.toStringAsFixed(2)}/dia',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            if (produto.localizacao.trim().isNotEmpty)
                              Text(
                                'Local: ${produto.localizacao}',
                                style: theme.textTheme.bodySmall,
                              ),
                            Text(
                              verCusto
                                  ? 'Custo: ${_formatarMoedaBRL(produto.precoCusto)} | '
                                        'Medio: ${_formatarMoedaBRL(produto.custoMedio)} | '
                                        'Venda: ${_formatarMoedaBRL(produto.precoVenda)}'
                                  : 'Venda: ${_formatarMoedaBRL(produto.precoVenda)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            statusTexto,
                            style: TextStyle(
                              color: statusCor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Acoes',
                            onSelected: (v) {
                              if (v == 'ajustar') {
                                _abrirAjusteEstoque(produto);
                              } else if (v == 'extrato') {
                                _abrirExtratoEstoque(produto);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'ajustar',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Ajustar estoque'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'extrato',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.receipt_long_outlined),
                                  title: Text('Ver movimentacoes'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
