import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/pdv_consulta_detalhe_linha.dart';
import '../domain/pdv_estoque_semaforo_util.dart';
import '../domain/pdv_consulta_insights_service.dart';
import '../domain/pdv_consulta_multi_deposito_util.dart';
import '../domain/pdv_busca_inteligente.dart';
import '../domain/lista_compra_item_constantes.dart';
import '../domain/pdv_tabela_preco_util.dart';
import '../data/kit_orcamento_repository.dart';
import '../data/lista_compra_repository.dart';
import '../data/produto_busca_util.dart';
import '../data/produto_repository.dart';
import '../data/produto_sugestao_venda_repository.dart';
import '../data/sugestao_venda_metrica_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../domain/sugestao_venda_metrica_constantes.dart';
import '../data/venda_repository.dart';
import '../domain/promocao_info_vigente.dart';
import '../domain/promocao_preco_result.dart';
import '../model/produto.dart';
import 'pdv_consulta_preview_panel.dart';
import 'pdv_pesquisa_comando.dart';
import 'produto_detalhe_venda_page.dart';
import 'widgets/anotar_lista_compra_dialog.dart';
import 'widgets/consulta_lista_vazia.dart';
import 'widgets/pdv_atalhos_ajuda.dart';
import 'widgets/pdv_barcode_scanner_page.dart';
import 'widgets/pdv_barcode_scanner_support.dart';
import 'widgets/pdv_consulta_filtros_chips.dart';
import 'widgets/pdv_consulta_linha_produto.dart';
import 'widgets/pdv_consulta_lista_cabecalho.dart';
import 'widgets/pdv_consulta_tabela_preco_chips.dart';
import 'widgets/operacao_feedback.dart';

/// Resultado ao escolher (ou atalho rapido) na consulta de produtos do PDV.
class PdvConsultaProdutoResult {
  const PdvConsultaProdutoResult({
    required this.produto,
    required this.precoListaAtivo,
    this.quantidadeDireta,
    this.adicaoDireta = false,
    this.abrirDialogoAdicionar = true,
    this.quantidadeEmUnidadeCompra = false,
    this.kitInserirId,
    this.quantidadeKitsInserir,
  });

  final Produto produto;
  final String precoListaAtivo;
  final int? quantidadeDireta;
  final bool adicaoDireta;
  final bool abrirDialogoAdicionar;
  final bool quantidadeEmUnidadeCompra;
  final int? kitInserirId;
  final int? quantidadeKitsInserir;

  bool get inserirKit =>
      (kitInserirId ?? 0) > 0 && (quantidadeKitsInserir ?? 0) > 0;
}

/// Tela cheia de consulta (lista + teclado). Aberta a partir do carrinho.
class PdvConsultaProdutosPage extends StatefulWidget {
  const PdvConsultaProdutosPage({
    super.key,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.termoInicial,
    required this.precoListaAtivoInicial,
    required this.clienteId,
    required this.produtosRecentesIds,
    required this.formatarMoeda,
    required this.rotuloPreco,
    required this.precoUnitarioDe,
    this.resolverPromocao,
    this.campanhasVigentesDe,
    this.quantidadeNoOrcamentoDe,
    this.criadoPorListaCompra = '',
    this.kitOrcamentoRepository,
    this.sugestaoVendaRepository,
    this.mostrarMargemGerente = false,
    this.margemMinimaPadrao = 20,
    this.rotulosDeposito = const PdvConsultaDepositoRotulos(),
    this.produtosNoOrcamentoIdsDe,
  });

  final ProdutoRepository produtoRepository;
  final VendaRepository vendaRepository;
  final String termoInicial;
  final String precoListaAtivoInicial;
  final int? clienteId;
  final List<int> produtosRecentesIds;
  final String Function(double) formatarMoeda;
  final String Function(String) rotuloPreco;
  final double Function(Produto produto, String precoTipo) precoUnitarioDe;
  final PromocaoPrecoResult Function(Produto produto, String precoTipo)?
      resolverPromocao;
  final List<PromocaoInfoVigente> Function(Produto produto)?
      campanhasVigentesDe;
  final num Function(int produtoId)? quantidadeNoOrcamentoDe;
  final String criadoPorListaCompra;
  final KitOrcamentoRepository? kitOrcamentoRepository;
  final ProdutoSugestaoVendaRepository? sugestaoVendaRepository;
  final bool mostrarMargemGerente;
  final double margemMinimaPadrao;
  final PdvConsultaDepositoRotulos rotulosDeposito;
  final Set<int> Function()? produtosNoOrcamentoIdsDe;

  @override
  State<PdvConsultaProdutosPage> createState() =>
      _PdvConsultaProdutosPageState();
}

class _PdvConsultaProdutosPageState extends State<PdvConsultaProdutosPage> {
  static const double _larguraPainelPreview = 360;
  static const double _breakpointPainelLateral = 720;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TextEditingController _pesquisaController;
  late final FocusNode _pesquisaFocus;
  late final FocusNode _listaFocus;
  late final ScrollController _scrollController;
  Timer? _debounce;
  Timer? _debouncePreview;
  late final SugestaoVendaMetricaRepository _sugestaoMetricaRepo;

  late String _precoListaAtivo;
  int _quantidadeAdicionar = 1;
  final GlobalKey<PdvConsultaControlesAdicionarState> _controlesQuantidadeKey =
      GlobalKey<PdvConsultaControlesAdicionarState>();
  List<Produto> _produtosBase = [];
  List<Produto> _produtos = [];
  /// Preco/promo/estoque precalculados por linha (evita trabalho no itemBuilder).
  List<_PdvConsultaLinhaVm> _linhasVm = const [];
  int? _indiceSelecionado;
  /// Painel lateral atualizado com debounce no teclado (evita piscar foto/layout).
  Produto? _produtoPreviewPainel;
  bool _painelPreviewVisivel = true;
  bool _filtrosExpandidos = false;
  bool _atalhosVisiveis = false;
  String _subtituloLista = '';
  String _termoBuscaAtual = '';
  bool _filtroSomenteComEstoque = false;
  bool _filtroSomentePromocao = false;
  bool _filtroSomenteAplicacao = false;
  PdvConsultaModoSugestao _modoSugestao = PdvConsultaModoSugestao.misto;

  /// Montada uma vez (recentes + ranking); evita travar ao apagar o texto.
  List<Produto>? _cacheSugestoes;

  @override
  void initState() {
    super.initState();
    _precoListaAtivo = PdvTabelaPrecoUtil.normalizar(widget.precoListaAtivoInicial);
    _pesquisaController = TextEditingController(text: widget.termoInicial);
    _pesquisaFocus = FocusNode(debugLabel: 'pdvConsultaPesquisa');
    _listaFocus = FocusNode(debugLabel: 'pdvConsultaLista');
    _scrollController = ScrollController();
    _sugestaoMetricaRepo =
        SugestaoVendaMetricaRepository(widget.produtoRepository.objectBox);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_produtos.isEmpty) {
      _atualizarLista(
        forcarAutoSeUnico: widget.termoInicial.trim().isNotEmpty,
        focarListaSeTiverItens: widget.termoInicial.trim().isNotEmpty,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debouncePreview?.cancel();
    _pesquisaController.dispose();
    _pesquisaFocus.dispose();
    _listaFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _agendarBuscaDigitacao() {
    _debounce?.cancel();
    final comando = PdvPesquisaComando.parse(_pesquisaController.text);
    final termo = comando.termoBusca;
    if (consultaEanProvavelCompleto(termo)) {
      _debounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _atualizarLista(
          forcarAutoSeUnico: true,
          manterFocoNaPesquisa: true,
        );
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _atualizarLista(
        manterFocoNaPesquisa: true,
        autoSeUnicoEnquantoDigita: true,
      );
    });
  }

  Future<void> _abrirLeitorCameraConsulta() async {
    if (!pdvLeitorCameraDisponivel || !mounted) return;

    String? codigoLido;
    Produto? produtoEncontrado;
    PdvPesquisaComando? comandoLido;
    String? mensagemErro;

    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => PdvBarcodeScannerPage(
          titulo: 'Consultar produto',
          modoContinuoInicial: false,
          mostrarToggleContinuo: false,
          instrucaoUnico:
              'Aponte para o codigo. O produto sera selecionado na consulta.',
          onCodigoLido: (codigo) async {
            final comando = PdvPesquisaComando.parse(codigo);
            final termo = comando.termoBusca.trim();
            if (termo.isEmpty) {
              return const PdvBarcodeScanFeedback(
                sucesso: false,
                mensagem: 'Codigo invalido.',
              );
            }

            codigoLido = termo;
            comandoLido = comando;

            final porBarras =
                widget.produtoRepository.resolverLeitorCodigoBarras(termo);
            if (porBarras != null) {
              produtoEncontrado = porBarras;
              return PdvBarcodeScanFeedback(
                sucesso: true,
                mensagem: porBarras.nome.trim().isEmpty
                    ? termo
                    : porBarras.nome.trim(),
              );
            }

            final resolvido = widget.produtoRepository.resolverPesquisaPdv(
              termo,
              clienteId: widget.clienteId,
            );
            if (resolvido.deveAutoSelecionar &&
                resolvido.produtoAuto != null) {
              produtoEncontrado = resolvido.produtoAuto;
              return PdvBarcodeScanFeedback(
                sucesso: true,
                mensagem: resolvido.produtoAuto!.nome.trim().isEmpty
                    ? termo
                    : resolvido.produtoAuto!.nome.trim(),
              );
            }

            mensagemErro = 'Produto nao encontrado: $termo';
            return PdvBarcodeScanFeedback(
              sucesso: false,
              mensagem: mensagemErro,
            );
          },
        ),
      ),
    );
    if (!mounted) return;

    final produto = produtoEncontrado;
    if (produto != null) {
      _pesquisaController.text = codigoLido ?? '';
      _confirmarProduto(produto, comando: comandoLido);
      return;
    }

    final termo = codigoLido?.trim() ?? '';
    if (termo.isEmpty) {
      _focarCampoBusca();
      return;
    }

    _pesquisaController.text = termo;
    if (mensagemErro != null) {
      OperacaoFeedback.erro(context, mensagemErro!);
    }
    _atualizarLista(
      forcarAutoSeUnico: true,
      focarListaSeTiverItens: true,
    );
  }

  bool _deveAutoConfirmarResolvido(
    PdvPesquisaResolvida resolvido, {
    required bool forcarAutoSeUnico,
    required bool autoSeUnicoEnquantoDigita,
    required String termo,
  }) {
    if (!resolvido.deveAutoSelecionar) return false;
    if (forcarAutoSeUnico) return true;
    if (!autoSeUnicoEnquantoDigita) return false;
    return PdvBuscaInteligenteHelper.permiteAutoEnquantoDigita(
      termo,
      matchCodigoBarras:
          resolvido.motivoAuto == PdvBuscaAutoMotivo.codigoBarras,
    );
  }

  List<Produto> _produtosPorIds(Iterable<int> ids) {
    final vistos = <int>{};
    final out = <Produto>[];
    for (final id in ids) {
      if (id <= 0 || vistos.contains(id)) continue;
      final p = widget.produtoRepository.obterPorId(id);
      if (p == null || !p.ativo || produtoEhCadastroInternoSistema(p)) continue;
      vistos.add(id);
      out.add(p);
      if (out.length >= 50) break;
    }
    return out;
  }

  List<Produto> _filtrarProdutos(List<Produto> base) {
    var out = base;
    if (_filtroSomenteComEstoque) {
      out = out.where((p) => p.estoqueLivreParaVenda > 0).toList();
    }
    if (_filtroSomentePromocao && widget.resolverPromocao != null) {
      out = out
          .where(
            (p) => widget.resolverPromocao!(p, _precoListaAtivo).emPromocao,
          )
          .toList();
    }
    if (_filtroSomenteAplicacao && _termoBuscaAtual.trim().length >= 3) {
      out = out
          .where(
            (p) => PdvConsultaInsightsService.produtoCombinaAplicacao(
              p,
              _termoBuscaAtual,
            ),
          )
          .toList();
    }
    return out;
  }

  String _montarSubtituloLista(List<Produto> base, String termo) {
    late final String nucleo;
    if (termo.isEmpty) {
      nucleo = switch (_modoSugestao) {
        PdvConsultaModoSugestao.recentes => 'Produtos recentes nesta sessao',
        PdvConsultaModoSugestao.maisVendidos => 'Mais vendidos (30 dias)',
        PdvConsultaModoSugestao.misto => base.isEmpty
            ? 'Nenhum produto ativo cadastrado'
            : 'Recentes e mais vendidos (30 dias)',
      };
    } else if (base.isEmpty) {
      nucleo = 'Nenhum resultado para "$termo"';
    } else {
      nucleo = '${base.length} resultado(s) para "$termo"';
    }

    final partes = <String>[nucleo];
    if (base.isNotEmpty && _produtos.length != base.length) {
      partes.insert(0, '${_produtos.length} de ${base.length}');
    } else if (base.isEmpty && _produtos.isEmpty && _temFiltroAtivo()) {
      partes.add('nenhum item passou nos filtros');
    }
    final filtros = <String>[];
    if (_filtroSomenteComEstoque) filtros.add('com estoque');
    if (_filtroSomentePromocao) filtros.add('promocao');
    if (_filtroSomenteAplicacao) filtros.add('aplicacao');
    if (filtros.isNotEmpty) partes.add(filtros.join(' · '));
    return partes.join(' · ');
  }

  bool _temFiltroAtivo() =>
      _filtroSomenteComEstoque ||
      _filtroSomentePromocao ||
      _filtroSomenteAplicacao;

  void _reaplicarFiltrosLocais() {
    setState(() {
      _produtos = _filtrarProdutos(_produtosBase);
      _remontarLinhasVm();
      _subtituloLista = _montarSubtituloLista(_produtosBase, _termoBuscaAtual);
      if (_produtos.isEmpty) {
        _indiceSelecionado = null;
        _produtoPreviewPainel = null;
      } else {
        final atual = _indiceSelecionado ?? 0;
        _indiceSelecionado = atual.clamp(0, _produtos.length - 1);
        _produtoPreviewPainel = _produtos[_indiceSelecionado!];
      }
    });
    _debouncePreview?.cancel();
    if (_produtos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaIndice());
    }
  }

  void _remontarLinhasVm() {
    final tabela = _precoListaAtivo;
    final lista = _produtos;
    _linhasVm = List<_PdvConsultaLinhaVm>.generate(lista.length, (i) {
      final item = lista[i];
      final res = widget.resolverPromocao?.call(item, tabela);
      final preco = res?.precoFinal ?? widget.precoUnitarioDe(item, tabela);
      final emPromo = res?.emPromocao ?? false;
      return _PdvConsultaLinhaVm(
        produto: item,
        precoFormatado: widget.formatarMoeda(preco),
        emPromocao: emPromo,
        precoDeFormatado:
            emPromo ? widget.formatarMoeda(res!.precoBasePreco1) : null,
        estoqueNivel: PdvEstoqueSemaforoUtil.nivelDe(item),
      );
    }, growable: false);
  }

  void _onFiltroSomenteComEstoqueChanged(bool value) {
    _filtroSomenteComEstoque = value;
    _reaplicarFiltrosLocais();
  }

  void _onFiltroSomentePromocaoChanged(bool value) {
    _filtroSomentePromocao = value;
    _reaplicarFiltrosLocais();
  }

  void _onFiltroSomenteAplicacaoChanged(bool value) {
    _filtroSomenteAplicacao = value;
    _reaplicarFiltrosLocais();
  }

  void _onModoSugestaoChanged(PdvConsultaModoSugestao modo) {
    _modoSugestao = modo;
    if (_termoBuscaAtual.isEmpty) {
      _atualizarLista();
    }
  }

  static const double _alturaLinhaConsulta =
      PdvConsultaLinhaProduto.alturaLinhaExpandida;

  double _alturaItemLista(int index) {
    // Altura fixa para itemExtent / scroll O(1).
    return _alturaLinhaConsulta;
  }

  double _offsetAcumuladoItemLista(int index) {
    if (index <= 0) return 0;
    return index * _alturaLinhaConsulta;
  }

  Future<void> _puxarProdutosDaRede() async {
    final erro = await LanSyncScheduler.solicitarSyncCompleto();
    if (!mounted) return;
    widget.produtoRepository.invalidarCacheBusca();
    _atualizarLista(manterFocoNaPesquisa: true);
    if (erro != null && erro.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync: $erro')),
      );
    }
  }

  void _atualizarLista({
    bool forcarAutoSeUnico = false,
    bool autoSeUnicoEnquantoDigita = false,
    bool manterFocoNaPesquisa = false,
    bool focarListaSeTiverItens = false,
  }) {
    final comando = PdvPesquisaComando.parse(_pesquisaController.text);
    final termo = comando.termoBusca;
    late final List<Produto> lista;

    if (termo.isEmpty) {
      lista = _listaSugestoes();
    } else {
      final resolvido = widget.produtoRepository.resolverPesquisaPdv(
        termo,
        clienteId: widget.clienteId,
      );
      lista = resolvido.produtos;

      if (_deveAutoConfirmarResolvido(
        resolvido,
        forcarAutoSeUnico: forcarAutoSeUnico,
        autoSeUnicoEnquantoDigita: autoSeUnicoEnquantoDigita,
        termo: termo,
      )) {
        _confirmarProduto(resolvido.produtoAuto!, comando: comando);
        return;
      }
    }

    if (!mounted) return;
    final filtrada = _filtrarProdutos(lista);
    setState(() {
      _produtosBase = lista;
      _produtos = filtrada;
      _remontarLinhasVm();
      _termoBuscaAtual = termo;
      _subtituloLista = _montarSubtituloLista(lista, termo);
      _indiceSelecionado = filtrada.isEmpty ? null : 0;
      _produtoPreviewPainel = filtrada.isEmpty ? null : filtrada.first;
      _quantidadeAdicionar = 1;
    });
    _debouncePreview?.cancel();

    if (_produtos.isNotEmpty) {
      _reposicionarListaAposBusca();
    }

    if (manterFocoNaPesquisa) return;

    if (focarListaSeTiverItens && _produtos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _listaFocus.requestFocus();
      });
    }
  }

  List<Produto> _listaSugestoes() {
    switch (_modoSugestao) {
      case PdvConsultaModoSugestao.recentes:
        return _produtosPorIds(widget.produtosRecentesIds);
      case PdvConsultaModoSugestao.maisVendidos:
        return _produtosPorIds(
          widget.vendaRepository.listarProdutoIdsMaisVendidos(
            dias: 30,
            limite: 50,
          ),
        );
      case PdvConsultaModoSugestao.misto:
        if (_cacheSugestoes != null) return _cacheSugestoes!;
    }

    final vistos = <int>{};
    final out = <Produto>[];

    void addId(int id) {
      if (id <= 0 || vistos.contains(id)) return;
      final p = widget.produtoRepository.obterPorId(id);
      if (p == null || !p.ativo || produtoEhCadastroInternoSistema(p)) return;
      vistos.add(id);
      out.add(p);
    }

    for (final id in widget.produtosRecentesIds) {
      addId(id);
      if (out.length >= 50) break;
    }

    if (out.length < 50) {
      final ranking = widget.vendaRepository.listarProdutoIdsMaisVendidos(
        dias: 30,
        limite: 50,
      );
      for (final id in ranking) {
        addId(id);
        if (out.length >= 50) break;
      }
    }

    if (out.length < 20) {
      for (final p in widget.produtoRepository.listarPaginado(
        limit: 50,
        somenteAtivos: true,
      )) {
        addId(p.id);
        if (out.length >= 50) break;
      }
    }

    _cacheSugestoes = out;
    return out;
  }

  void _scrollParaIndice({bool forcarTopo = false}) {
    final i = _indiceSelecionado;
    if (i == null) return;
    _garantirIndiceVisivel(i, forcarTopo: forcarTopo);
  }

  /// So rola se o item estiver fora da area visivel (setas). Em busca nova,
  /// [forcarTopo] alinha o 1º resultado no topo.
  void _garantirIndiceVisivel(int indice, {bool forcarTopo = false}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final itemTop = _offsetAcumuladoItemLista(indice);
    final itemBottom = itemTop + _alturaItemLista(indice);
    final max = position.maxScrollExtent;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;

    double? target;
    if (forcarTopo) {
      target = itemTop.clamp(0.0, max);
    } else if (itemTop < viewTop) {
      target = itemTop.clamp(0.0, max);
    } else if (itemBottom > viewBottom) {
      target = (itemBottom - position.viewportDimension).clamp(0.0, max);
    }
    if (target != null && (position.pixels - target).abs() > 0.5) {
      _scrollController.jumpTo(target);
    }
  }

  /// Apos nova busca, garante que o 1º resultado fique visivel (lista nao fica
  /// com o scroll da pesquisa anterior).
  void _reposicionarListaAposBusca() {
    var tentativas = 0;
    void tentar() {
      if (!mounted) return;
      tentativas++;
      if (_scrollController.hasClients) {
        _garantirIndiceVisivel(_indiceSelecionado ?? 0, forcarTopo: true);
        return;
      }
      if (tentativas < 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) => tentar());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tentar());
  }

  bool _estoqueCritico(Produto p) =>
      PdvEstoqueSemaforoUtil.nivelDe(p) == PdvEstoqueSemaforoNivel.amarelo ||
      PdvEstoqueSemaforoUtil.nivelDe(p) == PdvEstoqueSemaforoNivel.vermelho;

  bool get _temFiltrosAtivos =>
      _filtroSomenteComEstoque ||
      _filtroSomentePromocao ||
      _filtroSomenteAplicacao ||
      _modoSugestao != PdvConsultaModoSugestao.misto;

  String? get _dicaBuscaContextual =>
      dicaBuscaContextual(_pesquisaController.text);

  Widget _buildCabecalhoConsulta() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final faixaUnica = constraints.maxWidth >= 760;
              final campoBusca = CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.f8):
                      _focarCampoBusca,
                  const SingleActivator(LogicalKeyboardKey.arrowDown):
                      _focarListaPrimeiroItem,
                },
                child: ListenableBuilder(
                  listenable: _pesquisaController,
                  builder: (context, _) {
                    return TextField(
                      controller: _pesquisaController,
                      focusNode: _pesquisaFocus,
                      autofocus: widget.termoInicial.isEmpty,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Filtrar na consulta',
                        helperText: _dicaBuscaContextual,
                        helperMaxLines: 1,
                        isDense: true,
                        hintText: 'Nome, codigo ou codigo de barras',
                        suffixIcon: SizedBox(
                          width: pdvLeitorCameraDisponivel ? 96 : 48,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (pdvLeitorCameraDisponivel)
                                IconButton(
                                  tooltip: 'Bipar codigo de barras',
                                  icon: const Icon(Icons.qr_code_scanner),
                                  onPressed: () =>
                                      unawaited(_abrirLeitorCameraConsulta()),
                                ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                onPressed: () => _atualizarLista(
                                  forcarAutoSeUnico: true,
                                  focarListaSeTiverItens: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      onChanged: (_) => _agendarBuscaDigitacao(),
                      onSubmitted: (_) => _atualizarLista(
                        forcarAutoSeUnico: true,
                        focarListaSeTiverItens: true,
                      ),
                    );
                  },
                ),
              );
              final chips = PdvConsultaTabelaPrecoChips(
                precoListaAtivo: _precoListaAtivo,
                rotuloPreco: widget.rotuloPreco,
                onSelecionar: _selecionarTabelaPreco,
                inline: faixaUnica,
              );

              if (faixaUnica) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: campoBusca),
                    const SizedBox(width: 10),
                    Expanded(flex: 4, child: chips),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  campoBusca,
                  const SizedBox(height: 4),
                  chips,
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    setState(() => _filtrosExpandidos = !_filtrosExpandidos),
                icon: Icon(
                  _filtrosExpandidos ? Icons.expand_less : Icons.tune,
                  size: 18,
                ),
                label: Text(_filtrosExpandidos ? 'Ocultar filtros' : 'Filtros'),
              ),
              if (!_filtrosExpandidos && _temFiltrosAtivos)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.filter_alt, size: 16, color: scheme.primary),
                ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _atalhosVisiveis = !_atalhosVisiveis),
                child: Text(_atalhosVisiveis ? 'Ocultar atalhos' : 'Atalhos'),
              ),
            ],
          ),
        ),
        if (_filtrosExpandidos)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: PdvConsultaFiltrosChips(
              somenteComEstoque: _filtroSomenteComEstoque,
              somentePromocao: _filtroSomentePromocao,
              modoSugestao: _modoSugestao,
              mostrarModosSugestao: _termoBuscaAtual.isEmpty,
              mostrarFiltroPromocao: widget.resolverPromocao != null,
              mostrarFiltroAplicacao: _termoBuscaAtual.trim().length >= 3,
              somenteAplicacao: _filtroSomenteAplicacao,
              onSomenteComEstoqueChanged: _onFiltroSomenteComEstoqueChanged,
              onSomentePromocaoChanged: _onFiltroSomentePromocaoChanged,
              onSomenteAplicacaoChanged: _onFiltroSomenteAplicacaoChanged,
              onModoSugestaoChanged: _onModoSugestaoChanged,
            ),
          ),
        if (_atalhosVisiveis)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: PdvAtalhosAjudaConsulta(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            _subtituloLista,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }

  Produto? get _produtoSelecionado {
    final i = _indiceSelecionado;
    if (i == null || i < 0 || i >= _produtos.length) return null;
    return _produtos[i];
  }

  Produto? get _produtoParaPainel =>
      _produtoPreviewPainel ?? _produtoSelecionado;

  void _sincronizarPainelPreview({required bool imediato}) {
    final atual = _produtoSelecionado;
    if (imediato) {
      _debouncePreview?.cancel();
      if (_produtoPreviewPainel?.id == atual?.id) {
        _produtoPreviewPainel = atual;
        return;
      }
      _produtoPreviewPainel = atual;
      return;
    }
    _debouncePreview?.cancel();
    _debouncePreview = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final p = _produtoSelecionado;
      if (_produtoPreviewPainel?.id == p?.id) return;
      setState(() => _produtoPreviewPainel = p);
    });
  }

  void _selecionarIndice(int index) {
    if (index < 0 || index >= _produtos.length) return;
    setState(() {
      _indiceSelecionado = index;
      _quantidadeAdicionar = 1;
      _sincronizarPainelPreview(imediato: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollParaIndice();
      _listaFocus.requestFocus();
    });
  }

  void _selecionarTabelaPreco(String novaTabela) {
    final tabela = PdvTabelaPrecoUtil.normalizar(novaTabela);
    if (tabela == _precoListaAtivo) return;
    setState(() {
      _precoListaAtivo = tabela;
      _remontarLinhasVm();
    });
    if (_filtroSomentePromocao) {
      _reaplicarFiltrosLocais();
    }
  }

  void _atualizarQuantidadeAdicionar(int quantidade) {
    _quantidadeAdicionar = quantidade;
  }

  /// Fecha a consulta uma unica vez (Esc nao deve dar pop duplo).
  void _fecharConsulta() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _adicionarSelecionadoAoOrcamento() {
    final p = _produtoSelecionado;
    if (p == null) return;
    _confirmarProduto(p, adicionarDireto: true);
  }

  Future<void> _anotarSelecionadoParaCompra() async {
    final p = _produtoSelecionado;
    if (p == null) return;
    final repo = ListaCompraRepository(widget.produtoRepository.objectBox);
    await mostrarAnotarListaCompraDialog(
      context,
      repository: repo,
      produto: p,
      quantidadeInicial: p.quantidadeMinima > p.estoqueAtual
          ? (p.quantidadeMinima - p.estoqueAtual).clamp(1, 99999)
          : 1,
      origem: ListaCompraItemOrigem.manual,
      criadoPor: widget.criadoPorListaCompra,
      urgente: p.estoqueAtual <= 0,
    );
    if (!mounted) return;
    _listaFocus.requestFocus();
  }

  Future<void> _abrirDetalhesProduto() async {
    final p = _produtoSelecionado;
    if (p == null) return;
    await mostrarModalDetalheProdutoVenda(
      context,
      produto: p,
      campanhasVigentes: widget.campanhasVigentesDe?.call(p) ?? const [],
      imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
    );
    if (!mounted) return;
    _listaFocus.requestFocus();
  }

  void _focarCampoBusca() {
    _pesquisaFocus.requestFocus();
    final texto = _pesquisaController.text;
    _pesquisaController.selection = TextSelection.collapsed(offset: texto.length);
  }

  void _focarListaPrimeiroItem() {
    if (_produtos.isEmpty) return;
    setState(() => _indiceSelecionado = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollParaIndice();
      _listaFocus.requestFocus();
    });
  }

  bool _shiftPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool _ehTeclaMais(KeyDownEvent event) =>
      event.logicalKey == LogicalKeyboardKey.numpadAdd ||
      (_shiftPressionado() && event.logicalKey == LogicalKeyboardKey.equal);

  bool _ehTeclaMenos(KeyDownEvent event) =>
      event.logicalKey == LogicalKeyboardKey.numpadSubtract ||
      event.logicalKey == LogicalKeyboardKey.minus;

  void _deltaQuantidadePainel(int delta) {
    _controlesQuantidadeKey.currentState?.aplicarDelta(delta);
  }

  void _confirmarProduto(
    Produto produto, {
    PdvPesquisaComando? comando,
    bool adicionarDireto = true,
  }) {
    final emUnidadeCompra = produto.pdvPodeVenderEmUnidadeCompra;
    final cmd = comando ?? PdvPesquisaComando.parse(_pesquisaController.text);
    if (cmd.adicaoDireta) {
      Navigator.of(context).pop(
        PdvConsultaProdutoResult(
          produto: produto,
          precoListaAtivo: _precoListaAtivo,
          adicaoDireta: true,
          abrirDialogoAdicionar: false,
          quantidadeEmUnidadeCompra: emUnidadeCompra,
        ),
      );
      return;
    }
    if (cmd.quantidadeDireta != null) {
      Navigator.of(context).pop(
        PdvConsultaProdutoResult(
          produto: produto,
          precoListaAtivo: _precoListaAtivo,
          quantidadeDireta: cmd.quantidadeDireta,
          abrirDialogoAdicionar: false,
          quantidadeEmUnidadeCompra: emUnidadeCompra,
        ),
      );
      return;
    }
    if (adicionarDireto) {
      final qtd = _quantidadeAdicionar;
      if (qtd <= 1) {
        Navigator.of(context).pop(
          PdvConsultaProdutoResult(
            produto: produto,
            precoListaAtivo: _precoListaAtivo,
            adicaoDireta: true,
            abrirDialogoAdicionar: false,
            quantidadeEmUnidadeCompra: emUnidadeCompra,
          ),
        );
      } else {
        Navigator.of(context).pop(
          PdvConsultaProdutoResult(
            produto: produto,
            precoListaAtivo: _precoListaAtivo,
            quantidadeDireta: qtd,
            abrirDialogoAdicionar: false,
            quantidadeEmUnidadeCompra: emUnidadeCompra,
          ),
        );
      }
      return;
    }
    Navigator.of(context).pop(
      PdvConsultaProdutoResult(
        produto: produto,
        precoListaAtivo: _precoListaAtivo,
        abrirDialogoAdicionar: true,
        quantidadeEmUnidadeCompra: emUnidadeCompra,
      ),
    );
  }

  KeyEventResult _onKeyLista(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_produtos.isEmpty) return KeyEventResult.ignored;

    final n = _produtos.length;
    var i = _indiceSelecionado ?? 0;
    i = i.clamp(0, n - 1);

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final novo = (i + 1).clamp(0, n - 1);
      if (novo == (_indiceSelecionado ?? i)) {
        return KeyEventResult.handled;
      }
      setState(() {
        _produtoPreviewPainel ??= _produtos[i];
        _indiceSelecionado = novo;
      });
      _sincronizarPainelPreview(imediato: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaIndice());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        if (event is KeyDownEvent) _focarCampoBusca();
        return KeyEventResult.handled;
      }
      setState(() {
        _produtoPreviewPainel ??= _produtos[i];
        _indiceSelecionado = i - 1;
      });
      _sincronizarPainelPreview(imediato: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaIndice());
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f8) {
      _focarCampoBusca();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f7) {
      _togglePainelPreview();
      return KeyEventResult.handled;
    }
    if (_ehTeclaMais(event)) {
      _deltaQuantidadePainel(1);
      return KeyEventResult.handled;
    }
    if (_ehTeclaMenos(event)) {
      _deltaQuantidadePainel(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _confirmarProduto(_produtos[i]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.f9) {
      _abrirDetalhesProduto();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selecionarProdutoPorId(int produtoId) {
    if (produtoId <= 0) return;
    final idx = _produtos.indexWhere((p) => p.id == produtoId);
    if (idx >= 0) {
      _selecionarIndice(idx);
      return;
    }
    final produto = widget.produtoRepository.obterPorId(produtoId);
    if (produto == null) return;
    _pesquisaController.text = produto.nome;
    _atualizarLista(focarListaSeTiverItens: true);
  }

  void _togglePainelPreview() {
    final produto = _produtoSelecionado;
    if (produto == null) return;

    final largura = MediaQuery.sizeOf(context).width;
    if (largura < _breakpointPainelLateral) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold == null) return;
      if (scaffold.isEndDrawerOpen) {
        scaffold.closeEndDrawer();
      } else {
        scaffold.openEndDrawer();
      }
      return;
    }

    setState(() => _painelPreviewVisivel = !_painelPreviewVisivel);
  }

  Future<void> _inserirKitSugerido(PdvConsultaKitResumo kit) async {
    final produto = _produtoSelecionado;
    if (produto == null || widget.kitOrcamentoRepository == null) return;

    final qtdCtrl = TextEditingController(text: '1');
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Inserir kit — ${kit.nome}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${kit.quantidadeItens} produto(s) entram no orcamento com '
                '${widget.rotuloPreco(_precoListaAtivo)}.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtdCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantidade de kits',
                  hintText: '1',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Inserir'),
            ),
          ],
        );
      },
    );

    final mult = int.tryParse(qtdCtrl.text.trim()) ?? 0;
    qtdCtrl.dispose();

    if (confirmou != true || mult <= 0) {
      if (confirmou == true && mult <= 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantidade de kits invalida.')),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      PdvConsultaProdutoResult(
        produto: produto,
        precoListaAtivo: _precoListaAtivo,
        abrirDialogoAdicionar: false,
        kitInserirId: kit.kitId,
        quantidadeKitsInserir: mult,
      ),
    );
  }

  void _adicionarAgregadoSugerido(PdvConsultaAgregadoVenda agregado) {
    final origem = _produtoSelecionado;
    if (origem != null && origem.id > 0) {
      _sugestaoMetricaRepo.registrarAceite(
        produtoOrigemId: origem.id,
        produtoSugeridoId: agregado.produtoId,
        canal: SugestaoVendaMetricaCanal.insights,
        fonte: SugestaoVendaMetricaFonte.deAgregado(
          historico: agregado.historico,
          cadastrado: agregado.cadastrado,
        ),
        quantidade: agregado.quantidadeSugerida,
        usuarioLogin: widget.criadoPorListaCompra,
      );
    }
    final produto = widget.produtoRepository.obterPorId(agregado.produtoId);
    if (produto == null) return;
    Navigator.of(context).pop(
      PdvConsultaProdutoResult(
        produto: produto,
        precoListaAtivo: _precoListaAtivo,
        quantidadeDireta: agregado.quantidadeSugerida,
        abrirDialogoAdicionar: false,
      ),
    );
  }

  PdvConsultaInsightsPacote _montarInsights(Produto produto) {
    final promo = widget.resolverPromocao?.call(produto, _precoListaAtivo);
    return PdvConsultaInsightsService.montar(
      produto: produto,
      produtoRepository: widget.produtoRepository,
      vendaRepository: widget.vendaRepository,
      kitOrcamentoRepository: widget.kitOrcamentoRepository,
      sugestaoVendaRepository: widget.sugestaoVendaRepository,
      clienteId: widget.clienteId,
      precoListaAtivo: _precoListaAtivo,
      precoUnitarioDe: widget.precoUnitarioDe,
      margemMinimaPadrao: widget.margemMinimaPadrao,
      margemMinimaPromocao: promo?.margemMinimaPercentual ?? 0,
      mostrarMargemGerente: widget.mostrarMargemGerente,
      termoBusca: _termoBuscaAtual,
      rotulosDeposito: widget.rotulosDeposito,
      excluirProdutoIdsAgregados:
          widget.produtosNoOrcamentoIdsDe?.call() ?? const {},
    );
  }

  Widget _buildPainelPreview(Produto produto, {required bool compacto}) {
    final campanhas = widget.campanhasVigentesDe?.call(produto) ?? const [];
    return PdvConsultaPreviewPanel(
      key: ValueKey<int>(produto.id),
      produto: produto,
      precoListaAtivo: _precoListaAtivo,
      precoUnitarioDe: widget.precoUnitarioDe,
      rotuloPreco: widget.rotuloPreco,
      formatarMoeda: widget.formatarMoeda,
      campanhaPromo: campanhas.isNotEmpty ? campanhas.first : null,
      promocaoAtiva: widget.resolverPromocao?.call(produto, _precoListaAtivo),
      estoqueCritico: _estoqueCritico(produto),
      compacto: compacto,
      quantidadeNoOrcamento:
          widget.quantidadeNoOrcamentoDe?.call(produto.id) ?? 0,
      onDetalhes: _abrirDetalhesProduto,
      onSelecionarTabela: _selecionarTabelaPreco,
      mostrarAdicionarAoOrcamento: true,
      onQuantidadeChanged: _atualizarQuantidadeAdicionar,
      onAdicionar: _adicionarSelecionadoAoOrcamento,
      controlesQuantidadeKey: _controlesQuantidadeKey,
      insights: _montarInsights(produto),
      onSelecionarSimilar: _selecionarProdutoPorId,
      onInserirKit: widget.kitOrcamentoRepository != null
          ? _inserirKitSugerido
          : null,
      onAdicionarAgregado: widget.sugestaoVendaRepository != null
          ? _adicionarAgregadoSugerido
          : null,
      rotulosDeposito: widget.rotulosDeposito,
      imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
    );
  }

  Widget _buildBarraProdutoSelecionado(Produto produto) {
    final scheme = Theme.of(context).colorScheme;
    final res = widget.resolverPromocao?.call(produto, _precoListaAtivo);
    final preco = res?.precoFinal ??
        widget.precoUnitarioDe(produto, _precoListaAtivo);

    return Material(
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      produto.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '${widget.rotuloPreco(_precoListaAtivo)} · '
                      '${widget.formatarMoeda(preco)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _togglePainelPreview,
                icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                label: const Text('Painel (F7)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaProdutos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PdvConsultaListaCabecalho(
          rotuloColunaPreco: widget.rotuloPreco(_precoListaAtivo),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _puxarProdutosDaRede,
            child: Focus(
              focusNode: _listaFocus,
              onKeyEvent: _onKeyLista,
              child: ListView.builder(
                key: const ValueKey<String>('pdv-consulta-lista'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemExtent: _alturaLinhaConsulta,
                cacheExtent: 280,
                itemCount: _linhasVm.length,
                itemBuilder: (context, index) {
                final vm = _linhasVm[index];
                final item = vm.produto;
                final selecionado = _indiceSelecionado == index;
                final qtdOrcamento =
                    widget.quantidadeNoOrcamentoDe?.call(item.id) ?? 0;
                final scheme = Theme.of(context).colorScheme;
                return Material(
                  key: ValueKey<int>(item.id),
                  color: selecionado
                      ? scheme.primaryContainer.withValues(alpha: 0.55)
                      : (index.isOdd
                          ? scheme.surfaceContainerLow
                          : scheme.surface),
                  child: InkWell(
                    onTap: () => _selecionarIndice(index),
                    onDoubleTap: () =>
                        _confirmarProduto(item, adicionarDireto: true),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      child: PdvConsultaLinhaProduto(
                        produto: item,
                        termoBusca: _termoBuscaAtual,
                        precoFormatado: vm.precoFormatado,
                        emPromocao: vm.emPromocao,
                        precoDeFormatado: vm.precoDeFormatado,
                        estoqueNivel: vm.estoqueNivel,
                        selecionado: selecionado,
                        quantidadeNoOrcamento: qtdOrcamento,
                        tooltipAdicionar:
                            'Adicionar 1 (${widget.rotuloPreco(_precoListaAtivo)})',
                        onAdicionar: () {
                          Navigator.of(context).pop(
                            PdvConsultaProdutoResult(
                              produto: item,
                              precoListaAtivo: _precoListaAtivo,
                              adicaoDireta: true,
                              abrirDialogoAdicionar: false,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        ),
      ],
    );
  }

  Widget _buildAreaListaComPreview() {
    final selecionado = _produtoSelecionado;
    final painel = _produtoParaPainel;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painelLateral = constraints.maxWidth >= _breakpointPainelLateral;
        if (selecionado == null || painel == null) {
          return _buildListaProdutos();
        }
        if (painelLateral) {
          if (!_painelPreviewVisivel) {
            return _buildListaProdutos();
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildListaProdutos()),
              SizedBox(
                width: _larguraPainelPreview,
                child: _buildPainelPreview(painel, compacto: false),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildListaProdutos()),
            _buildBarraProdutoSelecionado(selecionado),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f1): _PdvConsultaPrecoIntent('preco1'),
        SingleActivator(LogicalKeyboardKey.f2): _PdvConsultaPrecoIntent('preco2'),
        SingleActivator(LogicalKeyboardKey.f3): _PdvConsultaPrecoIntent('preco3'),
        SingleActivator(LogicalKeyboardKey.f7): _PdvConsultaTogglePainelIntent(),
        SingleActivator(LogicalKeyboardKey.f8): _PdvConsultaFocoBuscaIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _PdvConsultaFecharIntent(),
      },
      child: Actions(
        actions: {
          _PdvConsultaFocoBuscaIntent: CallbackAction<_PdvConsultaFocoBuscaIntent>(
            onInvoke: (_) {
              _focarCampoBusca();
              return null;
            },
          ),
          _PdvConsultaPrecoIntent: CallbackAction<_PdvConsultaPrecoIntent>(
            onInvoke: (intent) {
              _selecionarTabelaPreco(intent.precoTipo);
              return null;
            },
          ),
          _PdvConsultaFecharIntent: CallbackAction<_PdvConsultaFecharIntent>(
            onInvoke: (_) {
              _fecharConsulta();
              return null;
            },
          ),
          _PdvConsultaTogglePainelIntent:
              CallbackAction<_PdvConsultaTogglePainelIntent>(
            onInvoke: (_) {
              _togglePainelPreview();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (context) {
            final selecionado = _produtoSelecionado;
            final painel = _produtoParaPainel;
            final usarDrawer =
                selecionado != null &&
                MediaQuery.sizeOf(context).width < _breakpointPainelLateral;

            return Scaffold(
              key: _scaffoldKey,
              endDrawer: usarDrawer && painel != null
                  ? Drawer(
                      width: _larguraPainelPreview,
                      child: _buildPainelPreview(painel, compacto: true),
                    )
                  : null,
              onEndDrawerChanged: (aberto) {
                if (!aberto) _listaFocus.requestFocus();
              },
              appBar: AppBar(
            leading: IconButton(
              tooltip: 'Voltar ao carrinho (Esc)',
              icon: const Icon(Icons.arrow_back),
              onPressed: _fecharConsulta,
            ),
            title: const Text('Consulta de produtos'),
            actions: [
              if (selecionado != null)
                IconButton(
                  tooltip: 'Painel do produto (F7)',
                  onPressed: _togglePainelPreview,
                  icon: Icon(
                    usarDrawer && (_scaffoldKey.currentState?.isEndDrawerOpen ?? false)
                        ? Icons.view_sidebar
                        : Icons.view_sidebar_outlined,
                  ),
                ),
              IconButton(
                tooltip: 'Anotar para comprar',
                onPressed: _produtoSelecionado == null
                    ? null
                    : _anotarSelecionadoParaCompra,
                icon: const Icon(Icons.playlist_add_outlined),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCabecalhoConsulta(),
              Expanded(
                child: _produtos.isEmpty
                    ? ConsultaListaVazia(
                        mensagem: _subtituloLista,
                        dica: _termoBuscaAtual.trim().isEmpty
                            ? 'Digite para buscar ou use F4 no PDV.'
                            : 'Ajuste os filtros ou o termo de busca.',
                      )
                    : _buildAreaListaComPreview(),
              ),
            ],
          ),
            );
          },
        ),
      ),
    );
  }
}

class _PdvConsultaTogglePainelIntent extends Intent {
  const _PdvConsultaTogglePainelIntent();
}

class _PdvConsultaPrecoIntent extends Intent {
  const _PdvConsultaPrecoIntent(this.precoTipo);
  final String precoTipo;
}

class _PdvConsultaFocoBuscaIntent extends Intent {
  const _PdvConsultaFocoBuscaIntent();
}

class _PdvConsultaFecharIntent extends Intent {
  const _PdvConsultaFecharIntent();
}

/// Dados de linha precalculados (preco/promo/estoque) fora do [itemBuilder].
class _PdvConsultaLinhaVm {
  const _PdvConsultaLinhaVm({
    required this.produto,
    required this.precoFormatado,
    required this.emPromocao,
    required this.estoqueNivel,
    this.precoDeFormatado,
  });

  final Produto produto;
  final String precoFormatado;
  final bool emPromocao;
  final String? precoDeFormatado;
  final PdvEstoqueSemaforoNivel estoqueNivel;
}
