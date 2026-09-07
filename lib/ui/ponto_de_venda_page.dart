import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../domain/entrega_venda_helper.dart';
import '../domain/pdv_balcao_rapido_helper.dart';
import '../domain/quantidade_venda_util.dart';
import '../domain/troca_com_nota_pdv_intent.dart';
import '../domain/limite_credito_helper.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/pdv_tabela_preco_util.dart';
import '../domain/pdv_consulta_multi_deposito_util.dart';
import '../domain/pdv_consulta_insights_service.dart';
import '../domain/sugestao_venda_metrica_constantes.dart';
import '../domain/sugestao_venda_tipo.dart';
import '../domain/pdv_obra_calculadora_insercao.dart';
import '../domain/pdv_kit_orcamento_insercao.dart';
import '../domain/plano_fiado.dart';
import '../domain/uuid_v4.dart';
import '../domain/vale_credito.dart';
import '../domain/usuario_permissao_helper.dart';
import '../domain/permissao_usuario.dart';
import '../model/usuario_sistema.dart';
import '../domain/produto_embalagem.dart';
import '../domain/produto_limite_desconto_pdv.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/produto_unidade_exibicao.dart';
import '../domain/sessao_operacional_guard.dart';
import '../data/app_config_repository.dart';
import '../data/api/cliente_api_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/sync/estoque_local_refresh_hub.dart';
import '../data/api/lista_compra_api_repository.dart';
import '../data/api/kit_promocao_api_repository.dart';
import '../data/api/produto_api_repository.dart';
import '../data/api/venda_api_repository.dart';
import '../domain/venda_relacao_safe.dart';
import '../data/objectbox.dart';
import '../data/lote_produto_repository.dart';
import '../services/lote_fefo_service.dart';
import '../domain/lista_compra_item_constantes.dart';
import '../data/lista_compra_repository.dart';
import '../data/kit_orcamento_repository.dart';
import '../data/produto_sugestao_venda_repository.dart';
import '../data/sugestao_venda_metrica_repository.dart';
import '../data/promocao_repository.dart';
import '../domain/promocao_cadastro.dart';
import '../domain/promocao_carrinho_service.dart';
import '../domain/promocao_preco_result.dart';
import '../domain/promocao_preco_service.dart';
import '../data/produto_busca_util.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/sync/sync_service.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../data/vale_credito_service.dart';
import '../data/venda_repository.dart';
import 'vales/vale_credito_busca_dialog.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/kit_orcamento.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../services/cupom_pdf_gerado.dart';
import '../services/esc_pos_orcamento_builder.dart';
import '../services/esc_pos_printer_service.dart';
import '../services/orcamento_pdf_service.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'pdv_consulta_preview_panel.dart';
import 'pdv_consulta_produtos_page.dart';
import 'pdv/agenda_carreto_pdv_dialog.dart';
import 'widgets/cadastro_rapido_cliente_dialog.dart';
import 'widgets/anotar_lista_compra_dialog.dart';
import 'pdv_pesquisa_comando.dart';
import 'produto_detalhe_venda_page.dart';
import 'shell/app_shell_aba_visibilidade.dart';
import 'shell/main_menu_deps.dart';
import 'layout/app_layout.dart';
import 'widgets/operacao_feedback.dart';
import 'widgets/lan_api_feedback.dart';
import 'promocao_margem_autorizacao.dart';
import 'pdv_desconto_autorizacao.dart';
import 'pdv_preco_unitario_autorizacao.dart';
import 'pdv_vendedor_bloqueio.dart';
import 'widgets/pdv_atalhos_ajuda.dart';
import 'widgets/pdv_calculadora_panel.dart';
import 'widgets/pdv_obra_calculadora_panel.dart';
import 'widgets/pdv_barcode_scanner_page.dart';
import 'widgets/pdv_barcode_scanner_support.dart';
import 'widgets/pdv_mobile_ui.dart';
import 'widgets/pdv_carrinho_lista_cabecalho.dart';
import 'widgets/pdv_carrinho_linha_colunas.dart';
import 'widgets/pdv_carrinho_linha_compacta.dart';
import 'widgets/quantidade_pdv_input_formatter.dart';
import 'widgets/pdv_tipo_entrega_item.dart';
import 'widgets/plano_fiado_pdv_panel.dart';
import 'widgets/troca_com_nota_pdv_banner.dart';

class _PdvCodigoBarrasResultado {
  const _PdvCodigoBarrasResultado({
    required this.sucesso,
    this.nomeProduto,
    this.mensagemErro,
  });

  final bool sucesso;
  final String? nomeProduto;
  final String? mensagemErro;
}

class _LinhaPagamentoMistoPdV {
  _LinhaPagamentoMistoPdV({
    required this.meio,
    required this.valorController,
    this.parcelas = 1,
  });

  String meio;
  final TextEditingController valorController;
  int parcelas;

  /// Preenchidos quando [meio] e `vale`: sem o id nao daria para dar baixa
  /// no vale certo depois que a venda fecha.
  int valeId = 0;
  String codigoVale = '';
  double saldoVale = 0;

  void limparVale() {
    valeId = 0;
    codigoVale = '';
    saldoVale = 0;
  }

  void dispose() => valorController.dispose();
}

class PontoDeVendaPage extends StatefulWidget {
  const PontoDeVendaPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioLogado,
    this.intentTrocaComNota,
    this.orcamentoIdInicial,
  });

  final dynamic produtoRepository;
  final dynamic clienteRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;

  /// Apos devolucao na listagem: cliente + credito sugerido no desconto (F3).
  final TrocaComNotaPdvIntent? intentTrocaComNota;

  /// Orcamento pendente a carregar automaticamente ao abrir o PDV.
  final int? orcamentoIdInicial;

  @override
  State<PontoDeVendaPage> createState() => _PontoDeVendaPageState();
}

class _PontoDeVendaPageState extends State<PontoDeVendaPage>
    with SafeSyncRefreshMixin {
  bool get _podeVenderFiado => UsuarioPermissaoHelper.tem(
    widget.usuarioLogado,
    PermissaoUsuario.venderFiado,
  );

  bool get _pdvAlvosTouchAmplos =>
      pdvPlataformaCelular ||
      MediaQuery.sizeOf(context).width < AppBreakpoints.desktop;

  bool get _pdvUiCelular => pdvPlataformaCelular;

  void _pdvErro(String mensagem) {
    if (!mounted) return;
    OperacaoFeedback.erro(context, mensagem);
  }

  static const int _validadeOrcamentoDias = 7;
  static const int _selecaoSemClienteValor = -1;
  static const int _selecaoNovoClienteValor = -2;
  static const double _larguraPreviewCarrinhoPdv = 280;
  static const double _breakpointPreviewCarrinhoPdv = 720;

  final _pesquisaController = TextEditingController();
  final _pesquisaFocus = FocusNode(debugLabel: 'pesquisaPdV');
  final _carrinhoFocus = FocusNode(debugLabel: 'carrinhoPdV');

  /// Checkout à direita (F7 / Shift+F7).
  final _focusClientePdV = FocusNode(debugLabel: 'pdvCliente');
  final _focusVendedorPdV = FocusNode(debugLabel: 'pdvVendedor');
  final _focusEntregaPdV = FocusNode(debugLabel: 'pdvEntregaPadrao');
  final _focusPagamentoPdV = FocusNode(debugLabel: 'pdvPagamento');

  /// Botão "Editar dados da entrega" (frete/endereço estão no dialogo).
  final _focusEditarEntregaPdV = FocusNode(debugLabel: 'pdvEditarEntrega');
  final _focusSalvarOrcamentoPdV = FocusNode(debugLabel: 'pdvSalvarOrcamento');
  final _focusDescontoPdV = FocusNode(debugLabel: 'pdvDescontoCheckout');
  final _focusPagamentoMistoSwitchPdV = FocusNode(
    debugLabel: 'pdvMistoSwitchCheckout',
  );
  final _focusCheckoutAcaoPrimaria = FocusNode(
    debugLabel: 'pdvCheckoutAcaoPrimaria',
  );

  /// Dialogo "Dados para enviar ao caixa" aberto (atalhos F10/Esc/1-6).
  bool _checkoutDialogAberto = false;

  /// Dialogo "Orcamento salvo" (imprimir/PDF) — bloqueia F10 do PDV.
  bool _dialogoOrcamentoSalvoAberto = false;

  /// Evita envio duplo (F10 + clique) e corrida com fechamento do dialogo.
  /// Permanece true tambem durante imprimir/PDF pos-save.
  bool _salvandoOrcamento = false;

  /// Overlay "Processando orcamento..." — so durante o save no servidor.
  bool _overlaySalvandoOrcamento = false;

  /// UUID reutilizado em retry apos timeout (so na criacao, nao na edicao).
  String? _idempotencyKeyOrcamentoPendente;
  bool _checkoutDialogFocoInicialAplicado = false;
  StateSetter? _checkoutDialogSetState;
  BuildContext? _checkoutDialogFechamentoContext;
  int _indiceChipPagamentoFocado = 0;
  final _pdvClienteBuscaController = TextEditingController();
  List<Cliente> _pdvClientesSugeridos = [];
  int _pdvIndiceSugestaoCliente = -1;
  final GlobalKey _keySeletorClienteAppBarPdv = GlobalKey();
  OverlayEntry? _overlaySugestoesClientePdv;
  OverlayEntry? _overlayCalculadoraPdv;
  OverlayEntry? _overlayObraCalculadoraPdv;
  Offset _calculadoraPdvOffset = Offset.zero;
  Offset _obraCalculadoraPdvOffset = Offset.zero;
  bool _calculadoraPdvPosicionada = false;
  bool _obraCalculadoraPdvPosicionada = false;
  int _obraCalcTijoloProdutoId = 0;
  int _obraCalcCimentoProdutoId = 0;
  int _obraCalcAreiaProdutoId = 0;
  int _obraCalcPisoProdutoId = 0;
  double _obraCalcPerdaPadraoPct = 10;
  double _obraCalcPerdaRebocoPct = 15;
  double _obraCalcPerdaPisoPct = 10;
  double _obraCalcEspessuraRebocoMm = 20;
  double _obraCalcEspessuraContrapisoMm = 30;
  double _obraCalcM2PorCaixaPiso = 1.44;
  bool _obraCalcGeminiParseAtivo = false;
  String _obraCalcTemplatesJson = '[]';
  int _obraCalcBritaProdutoId = 0;
  int _obraCalcTelhaProdutoId = 0;
  int _obraCalcFerroProdutoId = 0;
  double _obraCalcEspessuraLajeMm = 100;
  double _obraCalcPerdaLajePct = 10;
  double _obraCalcPerdaFundacaoPct = 10;
  double _obraCalcPerdaTelhadoPct = 10;
  double _obraCalcTelhasPorM2 = 16;
  double _obraCalcInclinacaoTelhadoPct = 30;
  bool _obraCalcUsarSubstitutoEstoqueZero = true;

  /// Produtos usados recentemente nesta sessao (consulta vazia).
  final List<int> _produtosRecentesPdv = [];

  Timer? _debounceLeitorBarrasPdv;
  bool _processandoLeitorBarrasPdv = false;
  bool? _apiOnlinePdv;

  /// Ancora o painel direito para saber se o foco realmente esta no checkout (hasFocus dos nos falha).
  final GlobalKey _keyPainelCheckoutPdV = GlobalKey();
  final _valorFreteController = TextEditingController();
  final _enderecoEntregaController = TextEditingController();
  final _observacaoEntregaController = TextEditingController();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  late final dynamic _kitOrcamentoRepo;
  late final ProdutoSugestaoVendaRepository? _sugestaoVendaRepo;
  late final SugestaoVendaMetricaRepository? _sugestaoMetricaRepo;
  late final dynamic _promoRepo;
  late final PromocaoPrecoService? _promoPreco;
  late final PromocaoCarrinhoService? _promoCarrinho;
  late dynamic _usuarioRepository;
  List<Vendedor> _vendedoresAtivos = [];
  final List<_OrcamentoItemDraft> _carrinho = [];

  /// Linha selecionada no carrinho (navegacao com setas).
  int? _indiceLinhaCarrinho;
  int? _indiceLinhaEdicaoQuantidade;
  final _qtdCarrinhoInlineController = TextEditingController(text: '1');
  final _focusQuantidadeCarrinhoInline =
      FocusNode(debugLabel: 'pdvCarrinhoQtdInline');

  /// Epoch do painel carrinho/preview: qty, preco, selecao, etc. sem rebuildar AppBar.
  final ValueNotifier<int> _carrinhoUiEpoch = ValueNotifier(0);

  /// Tabela de preco padrao para novos itens (sempre Preco 1).
  static const String _precoListaPadraoPdv = 'preco1';
  String _precoListaAtivo = _precoListaPadraoPdv;
  String _formaPagamentoSelecionada = 'dinheiro';
  int _parcelasSelecionadas = 1;

  /// Painel "Mais opcoes" removido — pagamento misto fica na secao Pagamento.
  bool _pagamentoMistoPdV = false;
  final List<_LinhaPagamentoMistoPdV> _linhasPagamentoMisto = [];
  List<PlanoFiadoParcela> _planoFiadoParcelas = [];
  static const int _parcelasMaximasCheckoutPdV = 12;
  int? _clienteSelecionadoId;
  int _indiceEnderecoSelecionado = 0;
  int? _vendedorSelecionadoId;

  /// Tipo de entrega do carrinho (Ctrl+F1–F3: padrao; em carrinho uniforme
  /// aplica nas linhas; misto = so padrao — E/Dividir por linha).
  String _tipoEntregaSelecionada = EntregaVendaHelper.tipoRetirada;

  bool get _carrinhoTemItemCarreto => _carrinho.any(
    (i) =>
        EntregaVendaHelper.normalizarTipoItem(i.tipoEntregaItem) ==
        EntregaVendaHelper.tipoEntregaLoja,
  );

  bool get _carrinhoTemItemRetiradaFutura => _carrinho.any(
    (i) =>
        EntregaVendaHelper.normalizarTipoItem(i.tipoEntregaItem) ==
        EntregaVendaHelper.tipoRetiradaFutura,
  );

  bool get _pdvClienteAusente =>
      _clienteSelecionadoId == null || _clienteSelecionadoId! <= 0;

  /// Retirada futura sempre exige cliente (reserva / identificacao).
  bool get _pdvExigeClientePorRetiradaFutura => _carrinhoTemItemRetiradaFutura;

  /// Carreto sempre exige cliente (endereco / entrega).
  bool get _pdvExigeClientePorCarreto => _carrinhoTemItemCarreto;

  bool get _pdvExigeClientePorEntrega =>
      _pdvExigeClientePorCarreto || _pdvExigeClientePorRetiradaFutura;

  String get _motivoClienteObrigatorioPdv {
    final carreto = _carrinhoTemItemCarreto;
    final futura = _carrinhoTemItemRetiradaFutura;
    if (carreto && futura) return 'carreto / retirada futura';
    if (carreto) return 'carreto';
    if (futura) return 'retirada futura';
    return 'entrega';
  }

  String _resolverTipoEntregaVendaCarrinho() {
    return EntregaVendaHelper.resolverTipoEntregaVenda(
      _carrinho.map((e) => e.tipoEntregaItem),
    );
  }

  String get _resumoEntregaItensCarrinho {
    if (_carrinho.isEmpty) return '';
    return EntregaVendaHelper.resumoContagem(
      _carrinho.map((e) => e.tipoEntregaItem),
    );
  }

  bool get _carrinhoEntregaMista =>
      _resolverTipoEntregaVendaCarrinho() == EntregaVendaHelper.tipoMisto;

  bool get _checkoutExibeSecaoEntrega =>
      _carrinhoTemItemCarreto || _carrinhoEntregaMista;

  void _aplicarEnderecoCarretoDoClienteSeVazio() {
    if (!_carrinhoTemItemCarreto) return;
    if (_enderecoEntregaController.text.trim().isNotEmpty) return;
    final cliente = _clienteSelecionado();
    if (cliente == null) return;
    _aplicarEnderecoSelecionadoDoCliente(cliente, _indiceEnderecoSelecionado);
  }

  static const _opcoesEntregaPadraoPdv = <(String, String, String)>[
    (EntregaVendaHelper.tipoRetirada, 'Leva agora', 'Ctrl+F1'),
    (EntregaVendaHelper.tipoRetiradaFutura, 'Retirada futura', 'Ctrl+F2'),
    (EntregaVendaHelper.tipoEntregaLoja, 'Carreto', 'Ctrl+F3'),
  ];

  void _notificarUiCarrinho() {
    _carrinhoUiEpoch.value++;
  }

  void _alternarTipoEntregaLinhaCarrinho(int index) {
    if (index < 0 || index >= _carrinho.length) return;
    final tipoAnterior = EntregaVendaHelper.normalizarTipoItem(
      _carrinho[index].tipoEntregaItem,
    );
    final tipoNovo = EntregaVendaHelper.proximoTipoItem(tipoAnterior);
    _carrinho[index].tipoEntregaItem = tipoNovo;
    _notificarUiCarrinho();
  }

  void _alternarTabelaPrecoLinhaCarrinho(int index) {
    if (index < 0 || index >= _carrinho.length) return;
    final linha = _carrinho[index];
    final proxima = PdvTabelaPrecoUtil.proxima(linha.precoTipo);
    _aplicarTabelaPrecoNaLinha(linha, proxima);
    _promoCarrinho?.aplicarRegrasCarrinho(
      _carrinho,
      dataReferencia: DateTime.now(),
      segmentoCliente: _segmentoClienteAtivo,
    );
    _indiceLinhaCarrinho = index;
    _notificarUiCarrinho();
  }

  int? _indiceLinhaParaMesclar(
    int produtoId,
    String precoTipo,
    String tipoEntregaItem,
    bool quantidadeEmUnidadeCompra,
  ) {
    final idx = _carrinho.indexWhere(
      (e) =>
          e.produto.id == produtoId &&
          e.precoTipo == precoTipo &&
          e.tipoEntregaItem == tipoEntregaItem &&
          e.quantidadeEmUnidadeCompra == quantidadeEmUnidadeCompra,
    );
    return idx >= 0 ? idx : null;
  }

  Future<void> _dividirLinhaCarrinho(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    final orig = _carrinho[index];
    if (orig.quantidade <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para dividir, o item precisa ter pelo menos 2 unidades.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_DividirLinhaCarrinhoResult>(
      context: context,
      builder: (ctx) => _DividirLinhaCarrinhoDialog(
        nomeProduto: orig.produto.nome,
        quantidadeTotal: orig.quantidade,
        tipoAtual: orig.tipoEntregaItem,
      ),
    );
    if (result == null || !mounted) return;

    final qNova = result.quantidadeNovaLinha;
    if (qNova <= 0 || qNova >= orig.quantidade) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quantidade do novo item deve ser entre 1 e o total menos 1.',
          ),
        ),
      );
      return;
    }

    setState(() {
      orig.quantidade -= qNova;
      _carrinho.insert(
        index + 1,
        _OrcamentoItemDraft(
          produto: orig.produto,
          quantidade: qNova,
          precoTipo: orig.precoTipo,
          precoUnitario: orig.precoUnitario,
          tipoEntregaItem: result.tipoEntregaItem,
          quantidadeEmUnidadeCompra: orig.quantidadeEmUnidadeCompra,
          precoUnitarioManual: orig.precoUnitarioManual,
          promocaoId: orig.promocaoId,
          promocaoNome: orig.promocaoNome,
        ),
      );
      _indiceLinhaCarrinho = index + 1;
    });
    _notificarUiCarrinho();
    _carrinhoFocus.requestFocus();
  }

  double _quantidadeUnidadeVendaNoCarrinho(int produtoId) {
    return _carrinho
        .where((e) => e.produto.id == produtoId)
        .fold(0.0, (s, e) => s + e.quantidadeVendaEfetiva);
  }

  Set<int> _idsProdutosNoCarrinho() =>
      _carrinho.map((l) => l.produto.id).toSet();

  String _fonteMetricaDe(PdvConsultaAgregadoVenda agregado) =>
      SugestaoVendaMetricaFonte.deAgregado(
        historico: agregado.historico,
        cadastrado: agregado.cadastrado,
      );

  void _registrarIgnoradosFaixaCarrinho() {
    final origemId = _sugestoesCarrinhoOrigemId;
    if (origemId == null || origemId <= 0) return;
    final login = widget.usuarioLogado.login;
    for (final s in _sugestoesCarrinhoVisiveis) {
      if (_sugestoesCarrinhoAceitasIds.contains(s.produtoId)) continue;
      _sugestaoMetricaRepo?.registrarIgnorou(
        produtoOrigemId: origemId,
        produtoSugeridoId: s.produtoId,
        canal: SugestaoVendaMetricaCanal.faixaCarrinho,
        fonte: _fonteMetricaDe(s),
        usuarioLogin: login,
      );
    }
  }

  void _registrarExibicoesFaixaCarrinho(
    int produtoOrigemId,
    List<PdvConsultaAgregadoVenda> sugestoes,
  ) {
    final login = widget.usuarioLogado.login;
    for (final s in sugestoes) {
      _sugestaoMetricaRepo?.registrarExibiu(
        produtoOrigemId: produtoOrigemId,
        produtoSugeridoId: s.produtoId,
        canal: SugestaoVendaMetricaCanal.faixaCarrinho,
        fonte: _fonteMetricaDe(s),
        usuarioLogin: login,
      );
    }
  }

  void _fecharSugestoesCarrinho() {
    if (_sugestoesCarrinhoVisiveis.isEmpty &&
        _sugestoesCarrinhoOrigemNome.isEmpty) {
      return;
    }
    _registrarIgnoradosFaixaCarrinho();
    setState(() {
      _sugestoesCarrinhoVisiveis = const [];
      _sugestoesCarrinhoOrigemNome = '';
      _sugestoesCarrinhoOrigemId = null;
      _sugestoesCarrinhoAceitasIds.clear();
    });
  }

  void _atualizarSugestoesAposAdicionar(Produto produtoAdicionado) {
    _registrarIgnoradosFaixaCarrinho();
    if (widget.produtoRepository is ProdutoApiRepository) {
      unawaited(_atualizarSugestoesRemotasAposAdicionar(produtoAdicionado));
      return;
    }
    final sugestoes = PdvConsultaInsightsService.listarAgregadosParaPdv(
      referencia: produtoAdicionado,
      sugestaoVendaRepository: _sugestaoVendaRepo,
      vendaRepository: widget.vendaRepository,
      produtoRepository: widget.produtoRepository,
      precoListaAtivo: _precoListaAtivo,
      precoUnitarioDe: (p, t) =>
          _resolverPrecoProduto(p, precoTipoLista: t).precoFinal,
      limite: 3,
      excluirProdutoIds: _idsProdutosNoCarrinho(),
    );
    if (sugestoes.isEmpty) {
      _fecharSugestoesCarrinho();
      return;
    }
    setState(() {
      _sugestoesCarrinhoVisiveis = sugestoes;
      _sugestoesCarrinhoOrigemNome = produtoAdicionado.nome;
      _sugestoesCarrinhoOrigemId = produtoAdicionado.id;
      _sugestoesCarrinhoAceitasIds.clear();
    });
    _registrarExibicoesFaixaCarrinho(produtoAdicionado.id, sugestoes);
  }

  Future<void> _atualizarSugestoesRemotasAposAdicionar(
    Produto produtoAdicionado,
  ) async {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoApiRepository) return;
    try {
      final linhas = await repo.listarSugestoesVendaRemoto(
        produtoAdicionado.id,
        somenteAtivas: true,
      );
      if (!mounted) return;
      final excluir = _idsProdutosNoCarrinho()..add(produtoAdicionado.id);
      final out = <PdvConsultaAgregadoVenda>[];
      for (final linha in linhas) {
        if (out.length >= 3) break;
        if (excluir.contains(linha.produtoSugeridoId)) continue;
        var p = repo.obterPorId(linha.produtoSugeridoId);
        if (p == null) {
          try {
            p = await repo.obterPorIdRemoto(linha.produtoSugeridoId);
          } catch (_) {}
        }
        if (p == null || !p.ativo) continue;
        out.add(
          PdvConsultaAgregadoVenda(
            produtoId: p.id,
            nome: p.nome,
            estoqueDisponivel: p.estoqueLivreParaVenda,
            precoReferencia: _resolverPrecoProduto(
              p,
              precoTipoLista: _precoListaAtivo,
            ).precoFinal,
            tipo: SugestaoVendaTipo.fromCodigo(linha.tipo),
            quantidadeSugerida: linha.quantidadeSugerida,
            observacao: linha.observacao.trim(),
            cadastrado: true,
            historico: false,
          ),
        );
      }
      if (out.isEmpty) {
        _fecharSugestoesCarrinho();
        return;
      }
      setState(() {
        _sugestoesCarrinhoVisiveis = out;
        _sugestoesCarrinhoOrigemNome = produtoAdicionado.nome;
        _sugestoesCarrinhoOrigemId = produtoAdicionado.id;
        _sugestoesCarrinhoAceitasIds.clear();
      });
      _registrarExibicoesFaixaCarrinho(produtoAdicionado.id, out);
    } catch (_) {
      if (mounted) _fecharSugestoesCarrinho();
    }
  }

  Future<void> _adicionarSugestaoAgregadaDoCarrinho(
    PdvConsultaAgregadoVenda agregado,
  ) async {
    final origemId = _sugestoesCarrinhoOrigemId;
    if (origemId != null && origemId > 0) {
      _sugestaoMetricaRepo?.registrarAceite(
        produtoOrigemId: origemId,
        produtoSugeridoId: agregado.produtoId,
        canal: SugestaoVendaMetricaCanal.faixaCarrinho,
        fonte: _fonteMetricaDe(agregado),
        quantidade: agregado.quantidadeSugerida,
        usuarioLogin: widget.usuarioLogado.login,
      );
      _sugestoesCarrinhoAceitasIds.add(agregado.produtoId);
    }
    final produto = widget.produtoRepository.obterPorId(agregado.produtoId);
    if (produto == null) return;
    await _adicionarComQuantidade(
      produto,
      agregado.quantidadeSugerida.toDouble(),
      precoTipo: _precoListaAtivo,
      mostrarSugestoesAgregadas: false,
    );
    if (!mounted) return;
    final restantes = _sugestoesCarrinhoVisiveis
        .where((s) => s.produtoId != agregado.produtoId)
        .where((s) => !_idsProdutosNoCarrinho().contains(s.produtoId))
        .toList();
    setState(() {
      _sugestoesCarrinhoVisiveis = restantes;
      if (restantes.isEmpty) _sugestoesCarrinhoOrigemNome = '';
    });
  }

  double _estoqueDisponivelExibicao(Produto produto) {
    final armazenado = _estoqueDisponivelArmazenadoSync(produto);
    return ProdutoEmbalagem.valorEstoqueExibicao(produto, armazenado);
  }

  int _estoqueDisponivelArmazenadoSync(Produto produto) {
    if (!produto.controlaLoteValidade) {
      return produto.estoqueLivreParaVenda;
    }
    final ob = _objectBoxLocalOuNull();
    if (ob == null) return produto.estoqueLivreParaVenda;
    return LoteFefoService(LoteProdutoRepository(ob))
        .estoqueDisponivelPdv(produto);
  }

  Future<({bool emBotaFora, double percentual})> _resolverBotaFora(
    Produto produto,
  ) async {
    if (!produto.controlaLoteValidade) {
      return (emBotaFora: false, percentual: 0.0);
    }
    final ob = _objectBoxLocalOuNull();
    if (ob != null) {
      final fefo = LoteFefoService(LoteProdutoRepository(ob));
      if (!fefo.loteFefoEmBotaFora(produto)) {
        return (emBotaFora: false, percentual: 0.0);
      }
      return (
        emBotaFora: true,
        percentual: fefo.percentualBotaForaEfetivo(produto),
      );
    }
    final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
    if (client is! LanApiClient) {
      return (emBotaFora: false, percentual: 0.0);
    }
    try {
      final m = await client.obterLoteFefoProduto(produto.id);
      return (
        emBotaFora: m['emBotaFora'] == true,
        percentual: (m['percentualBotaFora'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return (emBotaFora: false, percentual: 0.0);
    }
  }

  String _prioridadeEntregaSelecionada = 'normal';
  String _janelaEntregaSelecionada = 'nao_definida';
  DateTime? _dataEntregaMarcada;
  bool _entregaSemDataCombinada = false;
  bool _permitirVendaSemEstoque = false;
  double _maxDescontoPercentualPdv = 15;
  bool _pdvExigirVendedor = false;
  bool _pdvBloqueioVendedor = false;
  bool _pdvBloqueioVendedorAposOrcamento = false;
  int _pdvBloqueioInatividadeMinutos = 0;
  bool _solicitandoBloqueioVendedorPdv = false;
  Timer? _timerInatividadeVendedorPdv;
  bool _pdvBalcaoRapido = true;
  bool _pdvCheckoutDireto = true;
  bool _pdvPularDialogOrcamentoSalvo = true;

  /// `percentual` | `valor` — desconto sempre limitado ao configurado (% sobre subtotal).
  String _tipoDescontoPdV = 'percentual';
  final _descontoPdVController = TextEditingController();
  bool _descontoAcimaTetoAutorizadoPdv = false;
  String? _descontoAutorizadoPorPdV;
  String _carrinhoSessaoId = '';
  int? _orcamentoEmEdicaoId;
  int? _orcamentoEmEdicaoNumero;

  /// Ultimo orcamento enviado ao caixa (exibido no painel apos salvar).
  int? _ultimoOrcamentoSalvoNumero;
  double? _ultimoOrcamentoSalvoTotal;
  bool _mostrarAjudaAtalhos = false;
  bool _trocaComNotaBannerVisivel = true;
  List<PdvConsultaAgregadoVenda> _sugestoesCarrinhoVisiveis = const [];
  String _sugestoesCarrinhoOrigemNome = '';
  int? _sugestoesCarrinhoOrigemId;
  final Set<int> _sugestoesCarrinhoAceitasIds = {};
  bool _trocaComNotaIntentAplicado = false;
  bool _trocaComNotaDescontoAplicado = false;
  double? _trocaComNotaCreditoAplicadoReais;
  bool _orcamentoInicialAplicado = false;

  /// Agrupa varios KeyDown do F7 no mesmo ciclo (Windows); senao executa dois passos de uma vez.
  int _checkoutF7BurstId = 0;

  void _agendarCheckoutF7Microtask(bool anterior) {
    final querAnterior = anterior;
    final id = ++_checkoutF7BurstId;
    scheduleMicrotask(() {
      if (!mounted || id != _checkoutF7BurstId) return;
      if (querAnterior) {
        _focarCampoCheckoutAnterior();
      } else {
        _focarProximoCampoCheckout();
      }
    });
  }

  ObjectBox? _objectBoxLocalOuNull() {
    try {
      final ob = widget.produtoRepository.objectBox;
      if (ob is ObjectBox) return ob;
    } catch (_) {}
    return null;
  }

  dynamic _listaCompraRepositoryOuNull() {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps?.listaCompraRepository != null) {
      return deps!.listaCompraRepository;
    }
    final client = deps?.lanApiClient;
    if (client != null) {
      return ListaCompraApiRepository(
        client,
        produtoRepository: widget.produtoRepository,
      );
    }
    final objectBox = _objectBoxLocalOuNull();
    return objectBox == null ? null : ListaCompraRepository(objectBox);
  }

  @override
  void initState() {
    super.initState();
    SessaoOperacionalGuard.marcarPdvAberto();
    final ob = _objectBoxLocalOuNull();
    final deps = MainMenuDeps.maybeOf(context);
    if (ob != null) {
      _kitOrcamentoRepo = KitOrcamentoRepository(ob);
      _sugestaoVendaRepo = ProdutoSugestaoVendaRepository(ob);
      _sugestaoMetricaRepo = SugestaoVendaMetricaRepository(ob);
      _promoRepo = PromocaoRepository(ob);
      _promoPreco = PromocaoPrecoService(_promoRepo);
      _promoCarrinho = PromocaoCarrinhoService(_promoRepo);
    } else {
      _kitOrcamentoRepo = deps?.kitOrcamentoRepository;
      _sugestaoVendaRepo = null;
      _sugestaoMetricaRepo = null;
      _promoRepo = deps?.promocaoRepository;
      if (_promoRepo != null) {
        _promoPreco = PromocaoPrecoService(_promoRepo);
        _promoCarrinho = PromocaoCarrinhoService(_promoRepo);
      } else {
        _promoPreco = null;
        _promoCarrinho = null;
      }
    }
    HardwareKeyboard.instance.addHandler(_handlerTeclasHardwarePdv);
    widget.produtoRepository.addListener(_onProdutoRepositoryChanged);
    _usuarioRepository =
        MainMenuDeps.resolverUsuarioRepository(context);
    LanApiEventHub.instance.addListener(_onLanApiStatusChanged);
    EstoqueLocalRefreshHub.instance.addListener(_onEstoqueLocalRefresh);
    initSafeSyncRefresh(
      onReload: _recarregarDadosSync,
      bloquearAtualizacao: _bloquearSyncPdv,
    );
    _carregarDadosIniciais();
    _carregarConfiguracaoVendaSemEstoque();
    _pesquisaController.addListener(_onPesquisaPdvTextoChanged);
    _focusClientePdV.addListener(_onFocoClientePdvChanged);
    _focusQuantidadeCarrinhoInline.onKeyEvent = _onKeyQuantidadeCarrinhoInline;
    _aplicarFocoInicialPdv();
  }

  KeyEventResult _onKeyQuantidadeCarrinhoInline(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _encerrarEdicaoQuantidadeCarrinho(voltarPesquisa: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool? _abaPdvAtivaAnterior;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ativa = AppShellAbaVisibilidade.estaAtiva(context);
    if (_abaPdvAtivaAnterior == false && ativa) {
      unawaited(_sincronizarCatalogoAoFocarAbaPdv());
    }
    _abaPdvAtivaAnterior = ativa;
  }

  Future<void> _sincronizarCatalogoAoFocarAbaPdv() async {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoApiRepository) return;
    try {
      final mudou = await repo.sincronizarSeDesatualizado();
      if (!mounted) return;
      if (mudou) _sincronizarEstoqueVisivelPdv();
    } catch (_) {}
  }

  /// Ao abrir o PDV / apos limpar venda: busca de produto (fluxo sem mouse).
  /// Com bloqueio de vendedor pendente, nao rouba o foco do dialogo de login.
  void _aplicarFocoInicialPdv() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pdvBloqueioVendedor && _vendedorSelecionadoPdv() == null) return;
      _pesquisaFocus.requestFocus();
    });
  }

  void _onFocoClientePdvChanged() {
    if (!_focusClientePdV.hasFocus) {
      _fecharOverlaySugestoesClientePdv();
      if (mounted) setState(_sincronizarTextoBuscaClientePdv);
      return;
    }
    if (mounted) setState(() {});
    if (_pdvClientesSugeridos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _atualizarOverlaySugestoesClientePdv();
      });
    }
  }

  bool _bloquearSyncPdv() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return true;
    return _focoPrimarioDentroDoPainelCheckout();
  }

  void _onProdutoRepositoryChanged() {
    _sincronizarEstoqueVisivelPdv();
  }

  void _onEstoqueLocalRefresh() {
    if (!mounted) return;
    try {
      widget.produtoRepository.atualizarCacheAposMovimentoEstoque();
    } catch (_) {
      _sincronizarEstoqueVisivelPdv();
    }
  }

  /// Atualiza quantidades de estoque na UI do PDV apos baixa (local ou via API).
  void _sincronizarEstoqueVisivelPdv() {
    if (!mounted) return;
    void aplicar(Produto alvo, Produto fresh) {
      alvo.estoqueReal = fresh.estoqueReal;
      alvo.estoqueReservado = fresh.estoqueReservado;
      alvo.estoqueAtual = fresh.estoqueAtual;
      alvo.preco1 = fresh.preco1;
      alvo.preco2 = fresh.preco2;
      alvo.preco3 = fresh.preco3;
      alvo.precoVenda = fresh.precoVenda;
      alvo.precoCusto = fresh.precoCusto;
      alvo.nome = fresh.nome;
      alvo.fotoPath = fresh.fotoPath;
      alvo.ativo = fresh.ativo;
      alvo.controlaLoteValidade = fresh.controlaLoteValidade;
      alvo.percentualBotaFora = fresh.percentualBotaFora;
    }

    for (final item in _carrinho) {
      final fresh = widget.produtoRepository.obterPorId(item.produto.id);
      if (fresh == null) continue;
      aplicar(item.produto, fresh);
    }
    // Copia preco1..3 no Produto nao basta: a linha usa precoUnitario.
    _atualizarPrecosCarrinhoPreservandoTabelas();
    setState(() {});
    _notificarUiCarrinho();
  }

  void _recarregarDadosSync() {
    if (!mounted) return;
    _carregarDadosIniciais();
    _sincronizarEstoqueVisivelPdv();
  }

  @override
  void didUpdateWidget(PontoDeVendaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produtoRepository != widget.produtoRepository) {
      oldWidget.produtoRepository.removeListener(_onProdutoRepositoryChanged);
      widget.produtoRepository.addListener(_onProdutoRepositoryChanged);
    }
  }

  Future<void> _carregarConfiguracaoVendaSemEstoque() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) {
      return;
    }
    setState(() {
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
      _pdvExigirVendedor = config.pdvExigirVendedor;
      _pdvBloqueioVendedor = config.pdvBloqueioVendedor;
      _pdvBloqueioVendedorAposOrcamento =
          config.pdvBloqueioVendedorAposOrcamento;
      _pdvBloqueioInatividadeMinutos =
          config.pdvBloqueioVendedorInatividadeMinutos;
      _pdvBalcaoRapido = config.pdvBalcaoRapido;
      _pdvCheckoutDireto = config.pdvCheckoutDireto;
      _pdvPularDialogOrcamentoSalvo = config.pdvPularDialogOrcamentoSalvo;
      _maxDescontoPercentualPdv = widget.usuarioLogado
          .tetoDescontoPercentualPdv(config.maxDescontoPercentualPdv);
      _obraCalcTijoloProdutoId = config.obraCalcTijoloProdutoId;
      _obraCalcCimentoProdutoId = config.obraCalcCimentoProdutoId;
      _obraCalcAreiaProdutoId = config.obraCalcAreiaProdutoId;
      _obraCalcPisoProdutoId = config.obraCalcPisoProdutoId;
      _obraCalcPerdaPadraoPct = config.obraCalcPerdaPadraoPct;
      _obraCalcPerdaRebocoPct = config.obraCalcPerdaRebocoPct;
      _obraCalcPerdaPisoPct = config.obraCalcPerdaPisoPct;
      _obraCalcEspessuraRebocoMm = config.obraCalcEspessuraRebocoMm;
      _obraCalcEspessuraContrapisoMm = config.obraCalcEspessuraContrapisoMm;
      _obraCalcM2PorCaixaPiso = config.obraCalcM2PorCaixaPiso;
      _obraCalcGeminiParseAtivo = config.obraCalcGeminiParseAtivo;
      _obraCalcTemplatesJson = config.obraCalcTemplatesJson;
      _obraCalcBritaProdutoId = config.obraCalcBritaProdutoId;
      _obraCalcTelhaProdutoId = config.obraCalcTelhaProdutoId;
      _obraCalcFerroProdutoId = config.obraCalcFerroProdutoId;
      _obraCalcEspessuraLajeMm = config.obraCalcEspessuraLajeMm;
      _obraCalcPerdaLajePct = config.obraCalcPerdaLajePct;
      _obraCalcPerdaFundacaoPct = config.obraCalcPerdaFundacaoPct;
      _obraCalcPerdaTelhadoPct = config.obraCalcPerdaTelhadoPct;
      _obraCalcTelhasPorM2 = config.obraCalcTelhasPorM2;
      _obraCalcInclinacaoTelhadoPct = config.obraCalcInclinacaoTelhadoPct;
      _obraCalcUsarSubstitutoEstoqueZero =
          config.obraCalcUsarSubstitutoEstoqueZero;
    });
    await _aplicarIntentTrocaComNotaSeNecessario();
    await _aplicarOrcamentoInicialSeNecessario();
    await _aplicarBloqueioVendedorInicialSeNecessario();
    _registrarAtividadePdvVendedor();
  }

  Future<void> _aplicarBloqueioVendedorInicialSeNecessario() async {
    if (!_pdvBloqueioVendedor || _vendedorSelecionadoPdv() != null) return;
    await _solicitarIdentificacaoVendedorPdvBloqueio(
      permitirCancelar: true,
      sairDoPdvSeCancelar: true,
    );
  }

  Future<bool> _solicitarIdentificacaoVendedorPdvBloqueio({
    bool permitirCancelar = true,
    bool sairDoPdvSeCancelar = false,
  }) async {
    if (!_pdvBloqueioVendedor || _solicitandoBloqueioVendedorPdv) {
      return _vendedorSelecionadoPdv() != null;
    }
    _solicitandoBloqueioVendedorPdv = true;
    try {
      final vendedor = await solicitarIdentificacaoVendedorPdv(
        context: context,
        vendedorRepository: widget.vendedorRepository,
        usuarioRepository: _usuarioRepository,
        permitirCancelar: permitirCancelar,
      );
      if (!mounted) return false;
      if (vendedor == null) {
        if (sairDoPdvSeCancelar && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        return false;
      }
      setState(() => _vendedorSelecionadoId = vendedor.id);
      if (_checkoutDialogAberto) {
        _checkoutDialogSetState?.call(() {});
      }
      _registrarAtividadePdvVendedor();
      _aplicarFocoInicialPdv();
      return true;
    } finally {
      _solicitandoBloqueioVendedorPdv = false;
    }
  }

  Future<void> _trocarVendedorPdvBloqueio() async {
    if (!_pdvBloqueioVendedor) return;
    _timerInatividadeVendedorPdv?.cancel();
    setState(() => _vendedorSelecionadoId = null);
    await _solicitarIdentificacaoVendedorPdvBloqueio(
      permitirCancelar: true,
      sairDoPdvSeCancelar: false,
    );
  }

  void _registrarAtividadePdvVendedor() {
    if (!_pdvBloqueioVendedor ||
        _pdvBloqueioInatividadeMinutos <= 0 ||
        _vendedorSelecionadoPdv() == null) {
      _timerInatividadeVendedorPdv?.cancel();
      return;
    }
    _timerInatividadeVendedorPdv?.cancel();
    _timerInatividadeVendedorPdv = Timer(
      Duration(minutes: _pdvBloqueioInatividadeMinutos),
      () => unawaited(_bloquearVendedorPorInatividadePdv()),
    );
  }

  Future<void> _bloquearVendedorPorInatividadePdv() async {
    if (!mounted || !_pdvBloqueioVendedor) return;
    if (_vendedorSelecionadoPdv() == null) return;
    if (_checkoutDialogAberto ||
        _solicitandoBloqueioVendedorPdv ||
        _dialogoOrcamentoSalvoAberto) {
      _registrarAtividadePdvVendedor();
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _registrarAtividadePdvVendedor();
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          'Terminal ocioso por $_pdvBloqueioInatividadeMinutos min. '
          'Identifique o vendedor novamente.',
        ),
      ),
    );
    setState(() => _vendedorSelecionadoId = null);
    await _solicitarIdentificacaoVendedorPdvBloqueio(
      permitirCancelar: false,
      sairDoPdvSeCancelar: false,
    );
  }

  Future<void> _aplicarOrcamentoInicialSeNecessario() async {
    final id = widget.orcamentoIdInicial;
    if (id == null || _orcamentoInicialAplicado || !mounted) return;
    _orcamentoInicialAplicado = true;

    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        await repo.hidratarOrcamentos();
        await repo.carregarItensRemoto(id);
        final produtoRepo = widget.produtoRepository;
        if (produtoRepo is ProdutoApiRepository) {
          for (final item in repo.listarItensPorVenda(id)) {
            final pid = item.produto.targetId;
            if (pid <= 0 || produtoRepo.obterPorId(pid) != null) continue;
            try {
              await produtoRepo.obterPorIdRemoto(pid);
            } catch (_) {}
          }
        }
        final clienteId = (repo.obterPorId(id) ?? widget.vendaRepository.obterPorId(id))
            ?.cliente
            .targetId;
        if (clienteId != null &&
            clienteId > 0 &&
            widget.clienteRepository is ClienteApiRepository) {
          final cliRepo = widget.clienteRepository as ClienteApiRepository;
          if (cliRepo.obterPorId(clienteId) == null) {
            try {
              await cliRepo.obterPorIdRemoto(clienteId);
            } catch (_) {}
          }
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Falha ao carregar orcamento: ${LanApiFeedback.mensagem(e)}',
            ),
          ),
        );
        return;
      }
    }

    final venda = widget.vendaRepository.obterPorId(id);
    if (venda == null || venda.status != 'orcamento' || venda.cancelada) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Orcamento nao encontrado ou ja foi finalizado/cancelado.',
          ),
        ),
      );
      return;
    }

    final carregou = _aplicarOrcamentoParaEdicao(venda);
    if (!carregou && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel carregar o orcamento no PDV.'),
        ),
      );
    }
  }

  Future<void> _aplicarIntentTrocaComNotaSeNecessario() async {
    final intent = widget.intentTrocaComNota;
    if (intent == null || _trocaComNotaIntentAplicado || !mounted) return;

    final cliente = widget.clienteRepository.obterPorId(intent.clienteId);
    if (cliente == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cliente id ${intent.clienteId} nao encontrado. Selecione o cliente manualmente.',
          ),
        ),
      );
      setState(() => _trocaComNotaIntentAplicado = true);
      return;
    }

    await _selecionarClienteNoOrcamento(cliente.id);
    if (!mounted) return;

    final vendedorId = intent.vendedorId;
    if (vendedorId != null &&
        vendedorId > 0 &&
        _vendedoresAtivos.any((v) => v.id == vendedorId)) {
      setState(() => _vendedorSelecionadoId = vendedorId);
    }

    setState(() => _trocaComNotaIntentAplicado = true);

    if (!mounted) return;
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Troca com nota: cliente ${cliente.nomeRazao}. '
          'Credito sugerido R\$ ${moeda.format(intent.creditoDevolucaoReais)}. '
          'Inclua os produtos novos no carrinho.',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
    _aplicarDescontoCreditoTrocaComNotaSePossivel();
  }

  void _aplicarDescontoCreditoTrocaComNotaSePossivel() {
    final intent = widget.intentTrocaComNota;
    if (intent == null ||
        _trocaComNotaDescontoAplicado ||
        intent.creditoDevolucaoReais <= 0.004) {
      return;
    }
    if (_maxDescontoPercentualPdv <= 0) return;
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0.004) return;

    final maxReais = _valorMaximoDescontoReaisPdV();
    final aplicar = intent.creditoDevolucaoReais
        .clamp(0.0, maxReais)
        .clamp(0.0, sub);
    if (aplicar <= 0.004) return;

    setState(() {
      _tipoDescontoPdV = 'valor';
      _descontoPdVController.text = aplicar
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _trocaComNotaDescontoAplicado = true;
      _trocaComNotaCreditoAplicadoReais = aplicar;
    });
  }

  @override
  void dispose() {
    SessaoOperacionalGuard.marcarPdvFechado();
    disposeSafeSyncRefresh();
    widget.produtoRepository.removeListener(_onProdutoRepositoryChanged);
    LanApiEventHub.instance.removeListener(_onLanApiStatusChanged);
    EstoqueLocalRefreshHub.instance.removeListener(_onEstoqueLocalRefresh);
    HardwareKeyboard.instance.removeHandler(_handlerTeclasHardwarePdv);
    _checkoutF7BurstId = 0;
    _carrinhoFocus.dispose();
    _focusQuantidadeCarrinhoInline.dispose();
    _qtdCarrinhoInlineController.dispose();
    _focusClientePdV.removeListener(_onFocoClientePdvChanged);
    _focusClientePdV.dispose();
    _focusVendedorPdV.dispose();
    _focusEntregaPdV.dispose();
    _focusPagamentoPdV.dispose();
    _focusEditarEntregaPdV.dispose();
    _focusSalvarOrcamentoPdV.dispose();
    _focusDescontoPdV.dispose();
    _focusPagamentoMistoSwitchPdV.dispose();
    _focusCheckoutAcaoPrimaria.dispose();
    _descontoPdVController.dispose();
    _pdvClienteBuscaController.dispose();
    _debouncePesquisaClientePdvApi?.cancel();
    _fecharOverlaySugestoesClientePdv();
    _fecharCalculadoraPdv();
    _fecharObraCalculadoraPdv();
    _debounceLeitorBarrasPdv?.cancel();
    _timerInatividadeVendedorPdv?.cancel();
    _pesquisaController.removeListener(_onPesquisaPdvTextoChanged);
    _pesquisaFocus.dispose();
    _pesquisaController.dispose();
    _valorFreteController.dispose();
    _enderecoEntregaController.dispose();
    _observacaoEntregaController.dispose();
    _disposeLinhasPagamentoMisto();
    _carrinhoUiEpoch.dispose();
    super.dispose();
  }

  void _onLanApiStatusChanged() {
    if (!mounted) return;
    final online = LanApiEventHub.instance.online;
    if (LanApiEventHub.instance.ultimaEntidade == 'produto' ||
        LanApiEventHub.instance.ultimaEntidade == 'estoque' ||
        LanApiEventHub.instance.ultimaEntidade == 'lote_produto') {
      // Nao depender so do main: puxa o produto afetado e recalcula precos.
      unawaited(_aplicarEventoCatalogoNoPdv());
    }
    if (_apiOnlinePdv == online) return;
    _apiOnlinePdv = online;
    if (online && widget.produtoRepository is ProdutoApiRepository) {
      unawaited(
        (widget.produtoRepository as ProdutoApiRepository)
            .sincronizarSeDesatualizado()
            .then((mudou) {
          if (!mounted || !mudou) return;
          _sincronizarEstoqueVisivelPdv();
        }),
      );
    }
    setState(() {});
  }

  /// Aplica evento WS de produto/estoque no cache e na UI do PDV aberto.
  Future<void> _aplicarEventoCatalogoNoPdv() async {
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) {
      final ids = List<int>.from(LanApiEventHub.instance.ultimaEntidadeIds);
      final rev = LanApiEventHub.instance.ultimaCatalogoRevision;
      try {
        await repo.aplicarEventoRede(
          ids: ids,
          revision: rev > 0 ? rev : null,
        );
      } catch (_) {
        try {
          await repo.sincronizarSeDesatualizado();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    _sincronizarEstoqueVisivelPdv();
  }

  Widget _bannerServidorOfflinePdv(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                LanApiEventHub.msgServidorOffline,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _disposeLinhasPagamentoMisto() {
    for (final l in _linhasPagamentoMisto) {
      l.dispose();
    }
    _linhasPagamentoMisto.clear();
  }

  void _inicializarLinhasMistoPadrao() {
    _disposeLinhasPagamentoMisto();
    _linhasPagamentoMisto.addAll([
      _LinhaPagamentoMistoPdV(
        meio: 'dinheiro',
        valorController: TextEditingController(),
      ),
      _LinhaPagamentoMistoPdV(
        meio: 'pix',
        valorController: TextEditingController(),
      ),
    ]);
  }

  double _somaDigitadaMistoPdV() {
    var s = 0.0;
    for (final l in _linhasPagamentoMisto) {
      s += _parseValorMonetario(l.valorController.text);
    }
    return s;
  }

  List<PagamentoOrcamentoLinha>? _montarLinhasMistoParaSalvar(
    double totalEsperado,
  ) {
    if (!_pagamentoMistoPdV) return null;
    final out = <PagamentoOrcamentoLinha>[];
    for (final l in _linhasPagamentoMisto) {
      final v = _parseValorMonetario(l.valorController.text);
      if (v <= 0) continue;
      final par = l.meio == 'cartao_credito' ? l.parcelas.clamp(1, 12) : 1;
      if (l.meio == 'cartao_debito' && par != 1) {
        throw StateError('Cartao de debito so a vista.');
      }
      if (l.meio == 'vale') {
        if (l.valeId <= 0) {
          throw StateError('Escolha o vale de credito da parte em vale.');
        }
        if (v > l.saldoVale + 0.004) {
          throw StateError(
            'O vale ${ValeCreditoCodigo.formatar(l.codigoVale)} tem apenas '
            '${_formatarMoeda(l.saldoVale)} de saldo.',
          );
        }
      }
      out.add(
        PagamentoOrcamentoLinha(
          meio: l.meio,
          valor: v,
          parcelas: par,
          valeId: l.valeId,
          codigoVale: l.codigoVale,
        ),
      );
    }
    if (out.length < 2) {
      throw StateError(
        'Pagamento misto: informe ao menos duas partes com valor.',
      );
    }
    final soma = PagamentoOrcamentoCodec.soma(out);
    if ((soma - totalEsperado).abs() > 0.02) {
      throw StateError(
        'Soma dos meios (${_formatarMoeda(soma)}) deve ser ${_formatarMoeda(totalEsperado)}.',
      );
    }
    final qtdFiado = out.where((p) => p.meio == 'fiado').length;
    if (qtdFiado > 1) {
      throw StateError('Pagamento misto: apenas uma linha pode ser Fiado.');
    }
    return out;
  }

  void _registrarProdutoRecente(Produto produto) {
    _produtosRecentesPdv.remove(produto.id);
    _produtosRecentesPdv.insert(0, produto.id);
    if (_produtosRecentesPdv.length > 20) {
      _produtosRecentesPdv.removeRange(20, _produtosRecentesPdv.length);
    }
  }

  void _onPesquisaPdvTextoChanged() {
    if (_sugestoesCarrinhoVisiveis.isNotEmpty &&
        _pesquisaController.text.trim().isNotEmpty) {
      _fecharSugestoesCarrinho();
    }
    if (!_pesquisaFocus.hasFocus || _processandoLeitorBarrasPdv) return;
    final texto = _pesquisaController.text;
    if (!consultaEanProvavelCompleto(texto)) return;
    _debounceLeitorBarrasPdv?.cancel();
    _debounceLeitorBarrasPdv = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      unawaited(_tentarLeitorBarrasAutomaticoPdv());
    });
  }

  Future<void> _tentarLeitorBarrasAutomaticoPdv() async {
    if (!mounted || _processandoLeitorBarrasPdv) return;
    final texto = _pesquisaController.text.trim();
    if (!consultaEanProvavelCompleto(texto)) return;
    final resultado = await _processarCodigoBarrasPdv(texto);
    if (!mounted || !resultado.sucesso) return;
    _pesquisaController.clear();
    _voltarFocoParaPesquisa();
  }

  Future<_PdvCodigoBarrasResultado> _processarCodigoBarrasPdv(
    String codigoBruto,
  ) async {
    if (!mounted) {
      return const _PdvCodigoBarrasResultado(
        sucesso: false,
        mensagemErro: 'Tela indisponivel.',
      );
    }
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return const _PdvCodigoBarrasResultado(
        sucesso: false,
        mensagemErro: LanApiEventHub.msgServidorOffline,
      );
    }
    if (_processandoLeitorBarrasPdv) {
      return const _PdvCodigoBarrasResultado(
        sucesso: false,
        mensagemErro: 'Aguarde o processamento anterior.',
      );
    }

    final comando = PdvPesquisaComando.parse(codigoBruto);
    final termo = comando.termoBusca.trim();
    if (termo.isEmpty) {
      return const _PdvCodigoBarrasResultado(
        sucesso: false,
        mensagemErro: 'Codigo invalido.',
      );
    }

    _processandoLeitorBarrasPdv = true;
    try {
      var produto = widget.produtoRepository.resolverLeitorCodigoBarras(
        termo,
      ) as Produto?;
      if (produto == null &&
          widget.produtoRepository is ProdutoApiRepository) {
        try {
          produto = await (widget.produtoRepository as ProdutoApiRepository)
              .buscarPorCodigoBarrasRemoto(termo);
        } catch (_) {}
      }
      if (produto != null) {
        _registrarProdutoRecente(produto);
        final qtd = comando.quantidadeDireta ?? 1;
        await _adicionarComQuantidade(
          produto,
          qtd.toDouble(),
          precoTipo: _precoListaAtivo,
          quantidadeEmUnidadeCompra: produto.pdvPodeVenderEmUnidadeCompra,
        );
        return _PdvCodigoBarrasResultado(
          sucesso: true,
          nomeProduto: ProdutoNomeExibicao.paraTela(produto),
        );
      }

      final resolvido = widget.produtoRepository.resolverPesquisaPdv(
        termo,
        clienteId: _clienteSelecionadoId,
      );
      if (resolvido.deveAutoSelecionar && resolvido.produtoAuto != null) {
        await _aplicarProdutoBuscaInteligente(resolvido.produtoAuto!, comando);
        return _PdvCodigoBarrasResultado(
          sucesso: true,
          nomeProduto: ProdutoNomeExibicao.paraTela(resolvido.produtoAuto!),
        );
      }

      return _PdvCodigoBarrasResultado(
        sucesso: false,
        mensagemErro: 'Produto nao encontrado: $termo',
      );
    } finally {
      _processandoLeitorBarrasPdv = false;
    }
  }

  Future<void> _abrirLeitorCameraPdv() async {
    if (!pdvLeitorCameraDisponivel || !mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => PdvBarcodeScannerPage(
          onCodigoLido: (codigo) async {
            final resultado = await _processarCodigoBarrasPdv(codigo);
            return PdvBarcodeScanFeedback(
              sucesso: resultado.sucesso,
              mensagem: resultado.sucesso
                  ? resultado.nomeProduto
                  : resultado.mensagemErro,
            );
          },
        ),
      ),
    );
    if (mounted) _voltarFocoParaPesquisa();
  }

  Future<void> _aplicarProdutoBuscaInteligente(
    Produto produto,
    PdvPesquisaComando comando,
  ) async {
    _registrarProdutoRecente(produto);
    final qtd = (comando.quantidadeDireta ?? 1).toDouble();
    if (comando.quantidadeDireta != null || comando.adicaoDireta) {
      await _adicionarComQuantidade(
        produto,
        qtd,
        precoTipo: _precoListaAtivo,
        tipoEntregaItem: _tipoEntregaSelecionada,
        quantidadeEmUnidadeCompra: produto.pdvPodeVenderEmUnidadeCompra,
      );
      return;
    }
    if (_pdvBalcaoRapido &&
        PdvBalcaoRapidoHelper.podeAdicionarDireto(
          carrinhoTemCarreto: _carrinhoTemItemCarreto,
          tipoEntregaSelecionada: _tipoEntregaSelecionada,
          pagamentoMisto: _pagamentoMistoPdV,
          edicaoOrcamento: _orcamentoEmEdicaoId != null,
        )) {
      await _adicionarComQuantidade(
        produto,
        1,
        precoTipo: _precoListaAtivo,
        tipoEntregaItem: _tipoEntregaSelecionada,
        quantidadeEmUnidadeCompra: produto.pdvPodeVenderEmUnidadeCompra,
        aguardarQuantidadeNoCarrinho: true,
      );
      return;
    }
    await _adicionarAoOrcamento(produto);
  }

  Future<void> _processarEntradaPesquisaPdv() async {
    if (!mounted) return;
    final comando = PdvPesquisaComando.parse(_pesquisaController.text);
    final termo = comando.termoBusca;
    if (termo.isNotEmpty) {
      final resolvido = widget.produtoRepository.resolverPesquisaPdv(
        termo,
        clienteId: _clienteSelecionadoId,
      );
      if (resolvido.deveAutoSelecionar && resolvido.produtoAuto != null) {
        if (comando.quantidadeDireta != null || comando.adicaoDireta) {
          _pesquisaController.clear();
          await _aplicarProdutoBuscaInteligente(resolvido.produtoAuto!, comando);
          return;
        }
        _pesquisaController.clear();
        await _adicionarComQuantidade(
          resolvido.produtoAuto!,
          1,
          precoTipo: _precoListaAtivo,
          tipoEntregaItem: _tipoEntregaSelecionada,
          quantidadeEmUnidadeCompra:
              resolvido.produtoAuto!.pdvPodeVenderEmUnidadeCompra,
          aguardarQuantidadeNoCarrinho: true,
        );
        return;
      }
    }
    await _abrirConsultaProdutos();
  }

  Future<void> _abrirConsultaProdutos() async {
    if (!mounted) return;
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    final texto = _pesquisaController.text;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;

    final result = await Navigator.of(context, rootNavigator: true)
        .push<PdvConsultaProdutoResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (ctx) => PdvConsultaProdutosPage(
              produtoRepository: widget.produtoRepository,
              vendaRepository: widget.vendaRepository,
              termoInicial: texto,
              precoListaAtivoInicial: _precoListaAtivo,
              clienteId: _clienteSelecionadoId,
              produtosRecentesIds: List<int>.from(_produtosRecentesPdv),
              formatarMoeda: _formatarMoeda,
              rotuloPreco: _rotuloPreco,
              precoUnitarioDe: _precoExibicaoConsulta,
              resolverPromocao: (p, t) =>
                  _resolverPrecoProduto(p, precoTipoLista: t),
              campanhasVigentesDe: (p) =>
                  _promoPreco?.listarCampanhasVigentesParaProduto(
                    p,
                    dataReferencia: DateTime.now(),
                    segmentoCliente: _segmentoClienteAtivo,
                  ) ??
                  const [],
              quantidadeNoOrcamentoDe: _quantidadeUnidadeVendaNoCarrinho,
              criadoPorListaCompra: widget.usuarioLogado.login,
              kitOrcamentoRepository: _kitOrcamentoRepo,
              sugestaoVendaRepository: _sugestaoVendaRepo,
              produtosNoOrcamentoIdsDe: _idsProdutosNoCarrinho,
              mostrarMargemGerente: UsuarioPermissaoHelper.tem(
                widget.usuarioLogado,
                PermissaoUsuario.verCustoMargem,
              ),
              margemMinimaPadrao: config.margemMinimaPercentualPadrao,
              rotulosDeposito: const PdvConsultaDepositoRotulos(),
            ),
          ),
        );

    if (!mounted) return;

    if (result == null) {
      _voltarFocoParaPesquisa();
      return;
    }

    _pesquisaController.clear();

    if (result.inserirKit) {
      await _inserirKitPorId(
        result.kitInserirId!,
        result.quantidadeKitsInserir!,
      );
      _voltarFocoParaPesquisa();
      return;
    }

    _registrarProdutoRecente(result.produto);

    if (result.adicaoDireta) {
      await _adicionarComQuantidade(
        result.produto,
        1,
        precoTipo: result.precoListaAtivo,
        quantidadeEmUnidadeCompra: result.quantidadeEmUnidadeCompra,
        aguardarQuantidadeNoCarrinho: result.editarQuantidadeNoCarrinho,
      );
      return;
    }
    if (result.quantidadeDireta != null) {
      await _adicionarComQuantidade(
        result.produto,
        result.quantidadeDireta!.toDouble(),
        precoTipo: result.precoListaAtivo,
        quantidadeEmUnidadeCompra: result.quantidadeEmUnidadeCompra,
      );
      return;
    }
    if (result.abrirDialogoAdicionar) {
      await _adicionarAoOrcamento(result.produto);
    }
  }

  /// Volta o foco ao campo de pesquisa para fluxo continuado sem mouse.
  void _voltarFocoParaPesquisa() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pesquisaFocus.requestFocus();
    });
  }

  bool _ctrlPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  bool _shiftPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  List<FocusNode> _cadeiaFocoCheckout() {
    final nodes = <FocusNode>[_focusClientePdV, _focusVendedorPdV];
    if (_carrinho.isNotEmpty) {
      nodes.add(_carrinhoFocus);
      nodes.add(_focusPagamentoPdV);
      nodes.add(_focusDescontoPdV);
    }
    nodes.add(_focusSalvarOrcamentoPdV);
    return nodes;
  }

  bool _focoPrimarioDentroDoPainelCheckout() {
    final checkoutCtx = _keyPainelCheckoutPdV.currentContext;
    final primaryCtx = FocusManager.instance.primaryFocus?.context;
    if (checkoutCtx == null || primaryCtx == null) return false;
    final checkoutRo = checkoutCtx.findRenderObject();
    final primaryRo = primaryCtx.findRenderObject();
    if (checkoutRo == null || primaryRo == null) return false;
    RenderObject? walk = primaryRo;
    while (walk != null) {
      if (identical(walk, checkoutRo)) return true;
      walk = walk.parent;
    }
    return false;
  }

  int _indiceFocoNaCadeiaCheckout(List<FocusNode> chain) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null) {
      final porPrimario = chain.indexWhere((n) => identical(primary, n));
      if (porPrimario >= 0) return porPrimario;
    }
    return chain.indexWhere((n) => n.hasFocus);
  }

  /// Teclas globais do PDV (F7 checkout; seta baixo na busca entra no carrinho).
  bool _handlerTeclasHardwarePdv(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyDownEvent &&
        _pdvBloqueioVendedor &&
        _pdvBloqueioInatividadeMinutos > 0) {
      _registrarAtividadePdvVendedor();
    }

    if (_dialogoOrcamentoSalvoAberto && event is KeyDownEvent) {
      return true;
    }

    if (_overlayCalculadoraPdv != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _fecharCalculadoraPdv();
      return true;
    }

    if (_overlayObraCalculadoraPdv != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _fecharObraCalculadoraPdv();
      return true;
    }

    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleCalculadoraPdv();
      return true;
    }

    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f12) {
      _toggleObraCalculadoraPdv();
      return true;
    }

    // Checkout modal: rota do PDV deixa de ser "current", mas os atalhos
    // precisam funcionar (F10 enviar, F6/F3, Esc).
    if (_checkoutDialogAberto && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f10) {
        unawaited(_checkoutDialogAcaoF10Async());
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f6) {
        _alternarPagamentoMistoCheckoutDialogoAberto();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        _focarDescontoCheckoutDialogoAberto();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f7) {
        _agendarCheckoutF7Microtask(_shiftPressionado());
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _checkoutDialogFecharOuRetroceder();
        return true;
      }
    }

    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;

    if (event is KeyDownEvent &&
        _pesquisaFocus.hasFocus &&
        event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _carrinho.isNotEmpty) {
      _entrarFocoCarrinhoPdv();
      return true;
    }

    if (!_checkoutDialogAberto && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f2 && _shiftPressionado()) {
        _focusClientePdV.requestFocus();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyN &&
          HardwareKeyboard.instance.isControlPressed) {
        unawaited(_abrirCadastroRapidoClientePdv());
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f4 && _shiftPressionado()) {
        unawaited(_abrirSeletorClienteNoPdv());
        return true;
      }
    }

    if (event.logicalKey != LogicalKeyboardKey.f7) return false;

    if (event is KeyRepeatEvent) {
      return true;
    }

    if (event is! KeyDownEvent) return false;

    _agendarCheckoutF7Microtask(_shiftPressionado());
    return true;
  }

  void _aplicarFocoProximoCheckout() {
    final chain = _cadeiaFocoCheckout();
    if (chain.isEmpty) {
      return;
    }
    if (!_focoPrimarioDentroDoPainelCheckout()) {
      chain.first.requestFocus();
      return;
    }
    final idx = _indiceFocoNaCadeiaCheckout(chain);
    if (idx < 0) {
      chain.first.requestFocus();
      return;
    }
    final next = (idx + 1) % chain.length;
    chain[next].requestFocus();
  }

  void _aplicarFocoCheckoutAnterior() {
    final chain = _cadeiaFocoCheckout();
    if (chain.isEmpty) {
      return;
    }
    if (!_focoPrimarioDentroDoPainelCheckout()) {
      chain.last.requestFocus();
      return;
    }
    final idx = _indiceFocoNaCadeiaCheckout(chain);
    if (idx < 0) {
      chain.last.requestFocus();
      return;
    }
    final prev = (idx - 1 + chain.length) % chain.length;
    chain[prev].requestFocus();
  }

  void _focarProximoCampoCheckout() {
    _aplicarFocoProximoCheckout();
  }

  void _focarCampoCheckoutAnterior() {
    _aplicarFocoCheckoutAnterior();
  }

  void _focarCarrinhoAtalho() {
    _entrarFocoCarrinhoPdv(selecionarUltimaLinha: true);
  }

  void _entrarFocoCarrinhoPdv({bool selecionarUltimaLinha = false}) {
    if (_carrinho.isEmpty) return;
    final novo = selecionarUltimaLinha
        ? (_indiceLinhaCarrinho ?? _carrinho.length - 1).clamp(
            0,
            _carrinho.length - 1,
          )
        : (_indiceLinhaCarrinho ?? 0).clamp(0, _carrinho.length - 1);
    _definirIndiceLinhaCarrinho(novo, isolado: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _carrinhoFocus.requestFocus();
    });
  }

  void _limparPesquisaAtalho() {
    _pesquisaController.clear();
    _voltarFocoParaPesquisa();
  }

  void _irParaPesquisaProdutos() {
    _voltarFocoParaPesquisa();
  }

  /// Carrinho vazio: abre consulta (F4). Com itens: foco no campo de busca do PDV.
  void _atalhoF8Pdv() {
    if (_carrinho.isEmpty) {
      unawaited(_abrirConsultaProdutos());
      return;
    }
    _irParaPesquisaProdutos();
  }

  void _snackbarSemEstoqueComOpcaoCompra(Produto produto) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange.shade800,
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('Sem estoque de ${produto.nome}.')),
          ],
        ),
        action: SnackBarAction(
          label: 'Anotar compra',
          onPressed: () {
            final repo = _listaCompraRepositoryOuNull();
            if (repo == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Use o PC servidor para anotar compras.'),
                ),
              );
              return;
            }
            mostrarAnotarListaCompraDialog(
              context,
              repository: repo,
              produto: produto,
              quantidadeInicial: 1,
              origem: ListaCompraItemOrigem.vendaPerdida,
              criadoPor: widget.usuarioLogado.login,
              urgente: true,
              observacaoInicial: 'Cliente solicitou no PDV',
            );
          },
        ),
      ),
    );
  }

  Future<bool> _adicionarComQuantidade(
    Produto produtoIn,
    double quantidadeVenda, {
    String? precoTipo,
    String? tipoEntregaItem,
    bool quantidadeEmUnidadeCompra = false,
    bool mostrarSugestoesAgregadas = true,
    bool aguardarQuantidadeNoCarrinho = false,
  }) async {
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return false;
    }
    if (quantidadeVenda <= 0) return false;
    final produto = _produtoAtualizadoParaPdv(produtoIn);
    var emEmbalagem =
        quantidadeEmUnidadeCompra && produto.pdvPodeVenderEmUnidadeCompra;
    var qVenda = quantidadeVenda;
    if (emEmbalagem && qVenda != qVenda.roundToDouble()) {
      qVenda = ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
        produto: produto,
        quantidadeComercial: qVenda,
      );
      emEmbalagem = false;
    }
    final fracionada = QuantidadeVendaUtil.pdvArmazenaEmMilesimos(
      emUnidadeCompra: emEmbalagem,
      cadastroFracionado: produto.permiteQuantidadeFracionada,
      quantidadeVenda: qVenda,
    );
    final qArmazenada = QuantidadeVendaUtil.paraArmazenamento(
      qVenda,
      fracionada: fracionada,
    );
    if (qArmazenada <= 0) return false;
    final precoLista = precoTipo ?? _precoListaAtivo;
    final qUnidadeVenda = emEmbalagem
        ? ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
            produto: produto,
            quantidadeComercial: qVenda,
          )
        : QuantidadeVendaUtil.valorExibicao(
            qArmazenada,
            fracionada: fracionada,
          );
    if (qUnidadeVenda <= 0) return false;
    final qEstoquePromo = qUnidadeVenda.ceil();
    final resPreco = _resolverPrecoProduto(
      produto,
      precoTipoLista: precoLista,
      quantidade: qEstoquePromo,
    );
    if (resPreco.emPromocao) {
      if (resPreco.quantidadeMaximaPorVenda > 0 &&
          qEstoquePromo > resPreco.quantidadeMaximaPorVenda) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite da promocao: max. ${resPreco.quantidadeMaximaPorVenda} '
              'un. por venda para ${produto.nome}.',
            ),
          ),
        );
        return false;
      }
      if (resPreco.quantidadeRestanteGlobal > 0 &&
          qEstoquePromo > resPreco.quantidadeRestanteGlobal) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Restam apenas ${resPreco.quantidadeRestanteGlobal} un. '
              'nesta campanha.',
            ),
          ),
        );
        return false;
      }
      if (resPreco.margemMinimaPercentual > 0) {
        final margem = PromocaoCadastro.margemSobrePrecoVenda(
          precoCusto: produto.precoCusto,
          precoVenda: resPreco.precoFinal,
        );
        if (margem + 0.05 < resPreco.margemMinimaPercentual) {
          final ok = await solicitarAutorizacaoMargemPromocao(
            context,
            _usuarioRepository,
            margemAtual: margem,
            margemMinima: resPreco.margemMinimaPercentual,
            nomeProduto: produto.nome,
          );
          if (!ok) return false;
        }
      }
    }
    final preco = resPreco.precoTipo;
    var unit = resPreco.precoFinal;
    var botaForaAplicado = false;
    var percentualBotaFora = 0.0;
    final bota = await _resolverBotaFora(produto);
    if (!mounted) return false;
    if (bota.emBotaFora && bota.percentual > 0) {
      unit = (unit * (100 - bota.percentual) / 100.0 * 100).roundToDouble() /
          100.0;
      botaForaAplicado = true;
      percentualBotaFora = bota.percentual;
    }
    if (!_permitirVendaSemEstoque) {
      final fresh = widget.produtoRepository.obterPorId(produto.id) ?? produto;
      final disp = _estoqueDisponivelExibicao(fresh);
      if (disp <= 0) {
        _snackbarSemEstoqueComOpcaoCompra(produto);
        return false;
      }
      final jaNoCarrinho = _quantidadeUnidadeVendaNoCarrinho(produto.id);
      if (jaNoCarrinho + qUnidadeVenda > disp) {
        final dispTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
          fresh,
          disp,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo para ${produto.nome}: $dispTxt ${ProdutoEmbalagem.normalizarUnidade(fresh.unidade)} (ja ha ${ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(produto, jaNoCarrinho)} no orcamento).',
            ),
          ),
        );
        return false;
      }
    }
    final tipoNovo = EntregaVendaHelper.normalizarTipoItem(
      tipoEntregaItem ?? _tipoEntregaSelecionada,
    );
    final idxExistente = _indiceLinhaParaMesclar(
      produto.id,
      preco,
      tipoNovo,
      emEmbalagem,
    );
    setState(() {
      if (idxExistente != null) {
        _carrinho[idxExistente].quantidade += qArmazenada;
        if (botaForaAplicado) {
          _carrinho[idxExistente].botaForaAplicado = true;
          _carrinho[idxExistente].percentualBotaForaAplicado =
              percentualBotaFora;
          if (!_carrinho[idxExistente].precoUnitarioManual) {
            _carrinho[idxExistente].precoUnitario = unit;
          }
        }
        _indiceLinhaCarrinho = idxExistente;
      } else {
        _carrinho.add(
          _OrcamentoItemDraft(
            produto: produto,
            quantidade: qArmazenada,
            precoTipo: preco,
            precoUnitario: unit,
            tipoEntregaItem: tipoNovo,
            quantidadeEmUnidadeCompra: emEmbalagem,
            promocaoId: resPreco.promocaoId,
            promocaoNome: resPreco.promocaoNome,
            botaForaAplicado: botaForaAplicado,
            percentualBotaForaAplicado: percentualBotaFora,
          ),
        );
        _indiceLinhaCarrinho = _carrinho.length - 1;
      }
      _recalcularPromocoesCarrinho();
    });
    _aplicarDescontoCreditoTrocaComNotaSePossivel();
    _registrarProdutoRecente(produto);
    if (mostrarSugestoesAgregadas) {
      _atualizarSugestoesAposAdicionar(produto);
    }
    if (aguardarQuantidadeNoCarrinho && _indiceLinhaCarrinho != null) {
      _iniciarEdicaoQuantidadeCarrinho(_indiceLinhaCarrinho!);
    } else {
      _voltarFocoParaPesquisa();
    }
    return true;
  }

  void _iniciarEdicaoQuantidadeCarrinho(int index) {
    if (index < 0 || index >= _carrinho.length) {
      _voltarFocoParaPesquisa();
      return;
    }
    final item = _carrinho[index];
    _qtdCarrinhoInlineController.text = item.quantidadeExibicaoTexto;
    setState(() {
      _indiceLinhaEdicaoQuantidade = index;
      _indiceLinhaCarrinho = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusQuantidadeCarrinhoInline.requestFocus();
      final texto = _qtdCarrinhoInlineController.text;
      _qtdCarrinhoInlineController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: texto.length,
      );
    });
  }

  void _encerrarEdicaoQuantidadeCarrinho({required bool voltarPesquisa}) {
    if (_indiceLinhaEdicaoQuantidade == null) return;
    setState(() => _indiceLinhaEdicaoQuantidade = null);
    if (voltarPesquisa) _voltarFocoParaPesquisa();
  }

  void _confirmarQuantidadeCarrinhoInline() {
    final index = _indiceLinhaEdicaoQuantidade;
    if (index == null || index < 0 || index >= _carrinho.length) {
      _encerrarEdicaoQuantidadeCarrinho(voltarPesquisa: true);
      return;
    }
    final item = _carrinho[index];
    final fracionada = !item.quantidadeEmUnidadeCompra;
    final digitada = QuantidadeVendaUtil.parseEntradaPdv(
          _qtdCarrinhoInlineController.text,
          fracionada: fracionada,
        ) ??
        1.0;
    if (digitada <= 0) {
      _encerrarEdicaoQuantidadeCarrinho(voltarPesquisa: true);
      return;
    }
    final novaArmazenada = item.quantidadeEmUnidadeCompra &&
            item.produto.pdvPodeVenderEmUnidadeCompra
        ? digitada.round()
        : QuantidadeVendaUtil.paraArmazenamento(
            digitada,
            fracionada: QuantidadeVendaUtil.pdvArmazenaEmMilesimos(
              emUnidadeCompra: false,
              cadastroFracionado: item.produto.permiteQuantidadeFracionada,
              quantidadeVenda: digitada,
            ),
          );
    if (novaArmazenada <= 0) {
      _encerrarEdicaoQuantidadeCarrinho(voltarPesquisa: true);
      return;
    }
    final delta = novaArmazenada - item.quantidade;
    if (delta == 0) {
      _encerrarEdicaoQuantidadeCarrinho(voltarPesquisa: true);
      return;
    }
    final qtdAntes = item.quantidade;
    _alterarQuantidadeCarrinho(index, delta);
    final falhou = index < _carrinho.length &&
        _carrinho[index].quantidade == qtdAntes;
    if (falhou) return;
    _encerrarEdicaoQuantidadeCarrinho(voltarPesquisa: true);
  }

  bool _quantidadeFracionadaCarrinho(_OrcamentoItemDraft item) =>
      !item.quantidadeEmUnidadeCompra;

  Future<void> _inserirKitPorId(int kitId, int quantidadeKits) async {
    if (kitId <= 0 || quantidadeKits <= 0) return;
    final kitRepo = _kitOrcamentoRepo;
    if (kitRepo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kits indisponiveis neste terminal.')),
      );
      return;
    }

    try {
      final montada = PdvKitOrcamentoInsercaoUtil.montar(
        kitRepository: kitRepo,
        produtoRepository: widget.produtoRepository,
        kitId: kitId,
        quantidadeKits: quantidadeKits,
      );

      if (montada == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kit invalido ou sem itens ativos para inserir.'),
          ),
        );
        return;
      }

      for (final linha in montada.linhas) {
        await _adicionarComQuantidade(
          linha.produto,
          linha.quantidade,
          mostrarSugestoesAgregadas: false,
        );
      }

      if (!mounted) return;
      if (montada.itensIgnorados > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${montada.itensIgnorados} item(ns) do kit '
              '"${montada.nomeKit}" ignorados (produto inativo ou removido).',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kit "${montada.nomeKit}" inserido '
              '(${montada.linhas.length} produto(s)).',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Inserir kit');
    }
  }

  Future<void> _inserirKitNoOrcamento() async {
    final kitRepo = _kitOrcamentoRepo;
    if (kitRepo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kits indisponiveis neste terminal.')),
      );
      return;
    }

    if (kitRepo is KitOrcamentoApiRepository) {
      if (LanApiEventHub.instance.deveBloquearOperacoes) {
        LanApiFeedback.snackAviso(
          context,
          LanApiEventHub.msgServidorOffline,
          prefixo: 'Kits',
        );
        return;
      }
      try {
        await kitRepo.hidratar();
      } catch (e) {
        if (!mounted) return;
        LanApiFeedback.snackErro(context, e, prefixo: 'Kits');
        return;
      }
    }

    final kits = List<KitOrcamento>.from(
      kitRepo.listarPorNome(somenteAtivos: true),
    );
    if (kits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum kit ativo. Cadastre em Menu > Cadastros > Kits de orcamento.',
          ),
        ),
      );
      return;
    }

    final qtdCtrl = TextEditingController(text: '1');
    KitOrcamento escolhido = kits.first;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: const Text('Inserir kit no orcamento'),
              content: AdaptiveDialogPane(
                desktopWidth: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cada produto do kit entra no carrinho com o preco ativo (${_rotuloPreco(_precoListaAtivo)}), '
                        'multiplicado pela quantidade de kits.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Kit selecionado: ${escolhido.nome}',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 220,
                        child: ListView(
                          children: [
                            for (final k in kits)
                              ListTile(
                                dense: true,
                                title: Text(k.nome),
                                selected: escolhido.id == k.id,
                                onTap: () => setDlg(() => escolhido = k),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: qtdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade de kits',
                          hintText: '1',
                        ),
                      ),
                    ],
                  ),
                ),
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

    await _inserirKitPorId(escolhido.id, mult);
  }

  void _ajustarIndiceAposRemoverCarrinho(int removido) {
    if (_carrinho.isEmpty) {
      _indiceLinhaCarrinho = null;
      return;
    }
    final sel = _indiceLinhaCarrinho;
    if (sel == null) return;
    if (removido < sel) {
      _indiceLinhaCarrinho = sel - 1;
    } else if (removido == sel) {
      _indiceLinhaCarrinho = removido.clamp(0, _carrinho.length - 1);
    }
  }

  /// Evita "LayoutBuilder mutated during performLayout" ao remover item
  /// (preview lateral + painel de checkout com LayoutBuilders aninhados).
  void _aplicarMutacaoCarrinhoAposLayout(VoidCallback mutacao) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      mutacao();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      mutacao();
    });
  }

  int _passoQuantidadeCarrinho(_OrcamentoItemDraft item) {
    if (item.quantidadeEmUnidadeCompra || !item.usaArmazenamentoFracionado) {
      return 1;
    }
    return QuantidadeVendaUtil.passoFracionadoArmazenado;
  }

  void _alterarQuantidadeCarrinho(int index, int deltaArmazenado) {
    if (!_permitirVendaSemEstoque && deltaArmazenado > 0) {
      final item = _carrinho[index];
      final fresh =
          widget.produtoRepository.obterPorId(item.produto.id) ?? item.produto;
      final disp = _estoqueDisponivelExibicao(fresh);
      final novaArmazenada = item.quantidade + deltaArmazenado;
      final qNova =
          item.quantidadeEmUnidadeCompra &&
              item.produto.pdvPodeVenderEmUnidadeCompra
          ? ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
              produto: item.produto,
              quantidadeComercial: novaArmazenada.toDouble(),
            )
          : QuantidadeVendaUtil.valorExibicao(
              novaArmazenada,
              fracionada: item.usaArmazenamentoFracionado,
            );
      final jaOutros =
          _quantidadeUnidadeVendaNoCarrinho(item.produto.id) -
          item.quantidadeVendaEfetiva;
      if (jaOutros + qNova > disp) {
        final dispTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
          fresh,
          disp,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo: $dispTxt ${ProdutoEmbalagem.normalizarUnidade(fresh.unidade)} '
              '(no orcamento: ${ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(item.produto, jaOutros + item.quantidadeVendaEfetiva)}).',
            ),
          ),
        );
        return;
      }
    }
    _aplicarMutacaoCarrinhoAposLayout(() {
      if (index < 0 || index >= _carrinho.length) return;
      final item = _carrinho[index];
      final nova = item.quantidade + deltaArmazenado;
      if (nova <= 0) {
        _carrinho.removeAt(index);
        _ajustarIndiceAposRemoverCarrinho(index);
        _notificarUiCarrinho();
        _voltarFocoParaPesquisa();
      } else {
        item.quantidade = nova;
        _recalcularPrecoLinhaCarrinho(item);
        _promoCarrinho?.aplicarRegrasCarrinho(
          _carrinho,
          dataReferencia: DateTime.now(),
          segmentoCliente: _segmentoClienteAtivo,
        );
        _notificarUiCarrinho();
      }
    });
  }

  Future<void> _editarQuantidadeCarrinho(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    final item = _carrinho[index];
    final fracionada = !item.quantidadeEmUnidadeCompra;
    final unidade = item.quantidadeEmUnidadeCompra &&
            item.produto.pdvPodeVenderEmUnidadeCompra
        ? ProdutoEmbalagem.normalizarUnidade(item.produto.unidadeCompraEfetiva)
        : ProdutoEmbalagem.normalizarUnidade(item.produto.unidade);
    final digitada = await showDialog<double>(
      context: context,
      builder: (ctx) => _EditarQuantidadeCarrinhoDialog(
        nomeProduto: item.produto.nome,
        quantidadeInicial: item.quantidadeExibicaoTexto,
        fracionada: fracionada,
        unidade: unidade,
      ),
    );
    if (!mounted || digitada == null) return;
    final novaArmazenada = item.quantidadeEmUnidadeCompra &&
            item.produto.pdvPodeVenderEmUnidadeCompra
        ? digitada.round()
        : QuantidadeVendaUtil.paraArmazenamento(
            digitada,
            fracionada: QuantidadeVendaUtil.pdvArmazenaEmMilesimos(
              emUnidadeCompra: false,
              cadastroFracionado: item.produto.permiteQuantidadeFracionada,
              quantidadeVenda: digitada,
            ),
          );
    if (novaArmazenada <= 0) return;
    _alterarQuantidadeCarrinho(index, novaArmazenada - item.quantidade);
  }

  void _removerItemCarrinho(int index) {
    _aplicarMutacaoCarrinhoAposLayout(() {
      if (index < 0 || index >= _carrinho.length) return;
      _carrinho.removeAt(index);
      _ajustarIndiceAposRemoverCarrinho(index);
      _notificarUiCarrinho();
      _voltarFocoParaPesquisa();
    });
  }

  /// Atualiza a linha selecionada. Com [isolado], so rebuilda carrinho/preview.
  void _definirIndiceLinhaCarrinho(int? index, {bool isolado = false}) {
    if (_indiceLinhaCarrinho == index) return;
    _indiceLinhaCarrinho = index;
    if (isolado) {
      _notificarUiCarrinho();
    }
  }

  /// Setas no carrinho: ↑↓ outra linha (↑ na primeira volta a busca); +/- qtd no teclado numerico.
  KeyEventResult _onKeyCarrinho(FocusNode node, KeyEvent event) {
    if (_indiceLinhaEdicaoQuantidade != null) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_carrinho.isEmpty) return KeyEventResult.ignored;

    final n = _carrinho.length;
    var idx = _indiceLinhaCarrinho ?? 0;
    idx = idx.clamp(0, n - 1);
    final ctrl = _ctrlPressionado();

    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (idx <= 0) {
          _pesquisaFocus.requestFocus();
          return KeyEventResult.handled;
        }
        _definirIndiceLinhaCarrinho(idx - 1, isolado: true);
        return KeyEventResult.handled;
      }
      _definirIndiceLinhaCarrinho((idx + 1).clamp(0, n - 1), isolado: true);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _pesquisaFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _removerItemCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      _alternarTipoEntregaLinhaCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      _alternarTabelaPrecoLinhaCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyD) {
      _dividirLinhaCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyP) {
      unawaited(_alterarPrecoLinhaCarrinhoSelecionada());
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _alterarQuantidadeCarrinho(idx, _passoQuantidadeCarrinho(_carrinho[idx]));
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _alterarQuantidadeCarrinho(
        idx,
        -_passoQuantidadeCarrinho(_carrinho[idx]),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.f9) {
      unawaited(_abrirDetalhesProdutoCarrinho());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _carregarDadosIniciais() {
    final novos = widget.vendedorRepository.listarAtivos();
    if (_mesmaListaVendedoresAtivos(_vendedoresAtivos, novos)) {
      return;
    }
    setState(() => _vendedoresAtivos = novos);
  }

  /// Evita rebuild completo do PDV quando o sync so dispara o listener de produtos
  /// e a lista de vendedores nao mudou.
  static bool _mesmaListaVendedoresAtivos(
    List<Vendedor> atual,
    List<Vendedor> novos,
  ) {
    if (identical(atual, novos)) return true;
    if (atual.length != novos.length) return false;
    for (var i = 0; i < atual.length; i++) {
      if (atual[i].id != novos[i].id) return false;
      if (atual[i].nomeCompleto != novos[i].nomeCompleto) return false;
    }
    return true;
  }

  static const double _larguraSeletorVendedorAppBarPdv = 148;
  static const double _larguraSeletorClienteAppBarPdv = 196;
  static const double _larguraSeletorEntregaAppBarPdv = 124;

  Vendedor? _vendedorSelecionadoPdv() {
    final id = _vendedorSelecionadoId;
    if (id == null) return null;
    return _vendedoresAtivos.where((v) => v.id == id).firstOrNull;
  }

  /// Quando [pdvExigirVendedor] esta ativo, abre dialogo para escolher vendedor.
  /// Retorna `false` se o usuario cancelar ou nao houver vendedores ativos.
  Future<bool> _garantirVendedorPdvObrigatorio() async {
    if (!_pdvExigirVendedor && !_pdvBloqueioVendedor) return true;
    if (_vendedorSelecionadoPdv() != null) return true;

    if (_pdvBloqueioVendedor) {
      return _solicitarIdentificacaoVendedorPdvBloqueio(
        permitirCancelar: true,
        sairDoPdvSeCancelar: false,
      );
    }

    if (!_pdvExigirVendedor) return true;

    if (_vendedoresAtivos.isEmpty) {
      _carregarDadosIniciais();
    }
    final vendedoresAtivos = _vendedoresAtivos;
    if (vendedoresAtivos.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum vendedor ativo cadastrado. Cadastre em Cadastros → Vendedores.',
          ),
        ),
      );
      return false;
    }

    if (vendedoresAtivos.length == 1) {
      _vendedorSelecionadoId = vendedoresAtivos.first.id;
      if (!mounted) return false;
      if (_checkoutDialogAberto) {
        _checkoutDialogSetState?.call(() {});
      } else {
        setState(() {});
      }
      return true;
    }

    int? vendedorSelecionadoId;
    final confirmar = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DialogoSelecionarVendedorPdv(
          vendedoresAtivos: vendedoresAtivos,
          pesquisarVendedores: (termo) => widget.vendedorRepository
              .pesquisar(termo)
              .where((v) => v.ativo)
              .take(60)
              .toList(),
          onConfirmar: (id) {
            vendedorSelecionadoId = id;
            Navigator.pop(dialogContext, true);
          },
          onCancelar: () => Navigator.pop(dialogContext, false),
        );
      },
    );
    if (confirmar != true || vendedorSelecionadoId == null) return false;
    if (!mounted) return false;
    _vendedorSelecionadoId = vendedorSelecionadoId;
    if (_checkoutDialogAberto) {
      _checkoutDialogSetState?.call(() {});
    } else {
      setState(() {});
    }
    return true;
  }

  String _rotuloCurtoVendedorPdV(Vendedor? vendedor) {
    if (vendedor == null) return 'Vendedor';
    final nome = vendedor.apelido.trim().isNotEmpty
        ? vendedor.apelido.trim()
        : vendedor.nomeCompleto.trim();
    if (nome.isEmpty) return 'Vendedor';
    const max = 14;
    if (nome.length <= max) return nome;
    return '${nome.substring(0, max - 1)}…';
  }

  Widget _buildSeletorVendedorAppBarPdv() {
    if (_vendedoresAtivos.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vendedorAtual = _vendedorSelecionadoPdv();
    final semVendedorObrigatorio =
        (_pdvExigirVendedor || _pdvBloqueioVendedor) && vendedorAtual == null;
    final tooltip = vendedorAtual == null
        ? (_pdvBloqueioVendedor
              ? 'Identifique o vendedor com a senha'
              : _pdvExigirVendedor
              ? 'Vendedor (obrigatorio)'
              : 'Vendedor da venda (opcional)')
        : _rotuloItemVendedorPdV(vendedorAtual);

    if (_pdvBloqueioVendedor) {
      final rotulo = vendedorAtual == null
          ? 'Vendedor *'
          : _rotuloCurtoVendedorPdV(vendedorAtual);
      return FocusTraversalOrder(
        order: const NumericFocusOrder(1),
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: SizedBox(
            height: 30,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: semVendedorObrigatorio
                      ? scheme.error.withValues(alpha: 0.75)
                      : scheme.outlineVariant.withValues(alpha: 0.45),
                  width: semVendedorObrigatorio ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: semVendedorObrigatorio
                          ? scheme.error
                          : scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 92),
                      child: Text(
                        rotulo,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: semVendedorObrigatorio ? scheme.error : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: vendedorAtual == null
                          ? 'Identificar vendedor'
                          : 'Trocar vendedor',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => unawaited(_trocarVendedorPdvBloqueio()),
                      icon: Icon(
                        vendedorAtual == null ? Icons.login : Icons.swap_horiz,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final itens = <DropdownMenuItem<int?>>[
      if (!_pdvExigirVendedor)
        const DropdownMenuItem<int?>(value: null, child: Text('Sem vendedor')),
      ..._vendedoresAtivos.map(
        (v) => DropdownMenuItem<int?>(
          value: v.id,
          child: Text(
            _rotuloCurtoVendedorPdV(v),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          width: _larguraSeletorVendedorAppBarPdv,
          height: 30,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: semVendedorObrigatorio
                    ? scheme.error.withValues(alpha: 0.75)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
                width: semVendedorObrigatorio ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  key: ValueKey(
                    'pdv_vnd_${_vendedorSelecionadoId ?? 'nenhum'}',
                  ),
                  isDense: true,
                  isExpanded: true,
                  focusNode: _focusVendedorPdV,
                  value: _vendedorSelecionadoId,
                  icon: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  hint: Text(
                    _pdvExigirVendedor ? 'Vendedor *' : 'Vendedor',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: semVendedorObrigatorio ? scheme.error : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  items: itens,
                  onChanged: (value) {
                    setState(() => _vendedorSelecionadoId = value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeletorEntregaPadraoAppBarPdv() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final itens = _opcoesEntregaPadraoPdv
        .map(
          (opcao) => DropdownMenuItem<String>(
            value: opcao.$1,
            child: Text(
              opcao.$2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: PdvBotaoTipoEntregaItem.corPara(context, opcao.$1),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        )
        .toList();

    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: Tooltip(
        message:
            'Entrega (carrinho e novos itens): '
            '${EntregaVendaHelper.rotuloTipoItem(_tipoEntregaSelecionada)} (Ctrl+F1–F3)',
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          width: _larguraSeletorEntregaAppBarPdv,
          height: 30,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PdvBotaoTipoEntregaItem.fundoPara(
                context,
                _tipoEntregaSelecionada,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: PdvBotaoTipoEntregaItem.bordaPara(
                  context,
                  _tipoEntregaSelecionada,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('pdv_ent_$_tipoEntregaSelecionada'),
                  isDense: true,
                  isExpanded: true,
                  focusNode: _focusEntregaPdV,
                  value: EntregaVendaHelper.normalizarTipoItem(
                    _tipoEntregaSelecionada,
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: PdvBotaoTipoEntregaItem.corPara(
                      context,
                      _tipoEntregaSelecionada,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  items: itens,
                  onChanged: (value) {
                    if (value == null) return;
                    _definirEntregaPadraoPdv(value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _rotuloItemVendedorPdV(Vendedor v) {
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double _parseValorMonetario(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return 0;
    return double.tryParse(normalizado) ?? 0;
  }

  Cliente? _clienteSelecionado() {
    final id = _clienteSelecionadoId;
    if (id == null) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  List<EnderecoCliente> _enderecosClienteSelecionado() {
    final cliente = _clienteSelecionado();
    if (cliente == null) return const [];
    return cliente.listarEnderecos();
  }

  void _aplicarEnderecoSelecionadoDoCliente(Cliente cliente, int indice) {
    final enderecos = cliente.listarEnderecos();
    if (enderecos.isEmpty) {
      _indiceEnderecoSelecionado = 0;
      _enderecoEntregaController.clear();
      _observacaoEntregaController.clear();
      return;
    }
    final indiceSeguro = indice.clamp(0, enderecos.length - 1);
    final endereco = enderecos[indiceSeguro];
    _indiceEnderecoSelecionado = indiceSeguro;
    _enderecoEntregaController.text = endereco.resumo();
    _observacaoEntregaController.text = endereco.referencia.trim();
  }

  String _rotuloCurtoClientePdV(Cliente? cliente) {
    if (cliente == null) return '';
    final nome = cliente.nomeRazao.trim();
    if (nome.isEmpty) return '';
    const max = 14;
    if (nome.length <= max) return nome;
    return '${nome.substring(0, max - 1)}…';
  }

  void _sincronizarTextoBuscaClientePdv() {
    final cliente = _clienteSelecionado();
    _pdvClienteBuscaController.text = _rotuloCurtoClientePdV(cliente);
    _pdvClientesSugeridos = [];
    _pdvIndiceSugestaoCliente = -1;
    _fecharOverlaySugestoesClientePdv();
  }

  static const int _pdvMaxSugestoesCliente = 8;
  Timer? _debouncePesquisaClientePdvApi;

  List<Cliente> _pesquisarClientesPdv(String termo) {
    final t = termo.trim();
    if (t.isEmpty) return const [];
    final encontrados = widget.clienteRepository.pesquisar(t);
    return encontrados
        .where((c) => c.ativo)
        .take(_pdvMaxSugestoesCliente)
        .toList();
  }

  void _atualizarSugestoesClientePdv(String texto) {
    // Nao usa setState: a lista vive no OverlayEntry.
    _pdvClientesSugeridos = _pesquisarClientesPdv(texto);
    _pdvIndiceSugestaoCliente = _pdvClientesSugeridos.isEmpty ? -1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _atualizarOverlaySugestoesClientePdv();
    });
    final repo = widget.clienteRepository;
    _debouncePesquisaClientePdvApi?.cancel();
    if (repo is! ClienteApiRepository) return;
    final termo = texto.trim();
    if (termo.isEmpty) return;
    _debouncePesquisaClientePdvApi = Timer(
      const Duration(milliseconds: 320),
      () async {
        try {
          final remotos = await repo.pesquisarRemoto(
            termo,
            limit: _pdvMaxSugestoesCliente,
          );
          if (!mounted) return;
          _pdvClientesSugeridos = remotos
              .where((c) => c.ativo)
              .take(_pdvMaxSugestoesCliente)
              .toList();
          _pdvIndiceSugestaoCliente =
              _pdvClientesSugeridos.isEmpty ? -1 : 0;
          _atualizarOverlaySugestoesClientePdv();
        } catch (_) {}
      },
    );
  }

  void _fecharOverlaySugestoesClientePdv() {
    final entry = _overlaySugestoesClientePdv;
    if (entry == null) return;
    _overlaySugestoesClientePdv = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.remove());
  }

  void _fecharCalculadoraPdv() {
    final entry = _overlayCalculadoraPdv;
    if (entry == null) return;
    _overlayCalculadoraPdv = null;
    _calculadoraPdvPosicionada = false;
    _calculadoraPdvOffset = Offset.zero;
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.remove());
  }

  void _toggleCalculadoraPdv() {
    if (_overlayCalculadoraPdv != null) {
      _fecharCalculadoraPdv();
      return;
    }
    _fecharObraCalculadoraPdv();
    final overlay = Overlay.of(context);
    _overlayCalculadoraPdv = OverlayEntry(
      builder: (overlayContext) {
        final size = MediaQuery.sizeOf(overlayContext);
        const w = PdvCalculadoraPanel.largura;
        const h = PdvCalculadoraPanel.alturaEstimada;
        if (!_calculadoraPdvPosicionada) {
          _calculadoraPdvOffset = Offset(
            (size.width - w) / 2,
            (size.height - h) / 2,
          );
          _calculadoraPdvPosicionada = true;
        }
        final left = _calculadoraPdvOffset.dx.clamp(0.0, size.width - w);
        final top = _calculadoraPdvOffset.dy.clamp(0.0, size.height - h);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
                child: PdvCalculadoraPanel(
                  onFechar: _fecharCalculadoraPdv,
                  onPanDelta: (delta) {
                    if (!mounted || _overlayCalculadoraPdv == null) return;
                    final area = MediaQuery.sizeOf(overlayContext);
                    _calculadoraPdvOffset = Offset(
                      (_calculadoraPdvOffset.dx + delta.dx).clamp(
                        0.0,
                        area.width - w,
                      ),
                      (_calculadoraPdvOffset.dy + delta.dy).clamp(
                        0.0,
                        area.height - h,
                      ),
                    );
                    _overlayCalculadoraPdv?.markNeedsBuild();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlayCalculadoraPdv!);
  }

  void _fecharObraCalculadoraPdv() {
    final entry = _overlayObraCalculadoraPdv;
    if (entry == null) return;
    _overlayObraCalculadoraPdv = null;
    _obraCalculadoraPdvPosicionada = false;
    _obraCalculadoraPdvOffset = Offset.zero;
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.remove());
  }

  EmpresaConfig _empresaConfigObraCalculadora() {
    return EmpresaConfig(
      obraCalcTijoloProdutoId: _obraCalcTijoloProdutoId,
      obraCalcCimentoProdutoId: _obraCalcCimentoProdutoId,
      obraCalcAreiaProdutoId: _obraCalcAreiaProdutoId,
      obraCalcPisoProdutoId: _obraCalcPisoProdutoId,
      obraCalcPerdaPadraoPct: _obraCalcPerdaPadraoPct,
      obraCalcPerdaRebocoPct: _obraCalcPerdaRebocoPct,
      obraCalcPerdaPisoPct: _obraCalcPerdaPisoPct,
      obraCalcEspessuraRebocoMm: _obraCalcEspessuraRebocoMm,
      obraCalcEspessuraContrapisoMm: _obraCalcEspessuraContrapisoMm,
      obraCalcM2PorCaixaPiso: _obraCalcM2PorCaixaPiso,
      obraCalcGeminiParseAtivo: _obraCalcGeminiParseAtivo,
      obraCalcTemplatesJson: _obraCalcTemplatesJson,
      obraCalcBritaProdutoId: _obraCalcBritaProdutoId,
      obraCalcTelhaProdutoId: _obraCalcTelhaProdutoId,
      obraCalcFerroProdutoId: _obraCalcFerroProdutoId,
      obraCalcEspessuraLajeMm: _obraCalcEspessuraLajeMm,
      obraCalcPerdaLajePct: _obraCalcPerdaLajePct,
      obraCalcPerdaFundacaoPct: _obraCalcPerdaFundacaoPct,
      obraCalcPerdaTelhadoPct: _obraCalcPerdaTelhadoPct,
      obraCalcTelhasPorM2: _obraCalcTelhasPorM2,
      obraCalcInclinacaoTelhadoPct: _obraCalcInclinacaoTelhadoPct,
      obraCalcUsarSubstitutoEstoqueZero: _obraCalcUsarSubstitutoEstoqueZero,
    );
  }

  void _toggleObraCalculadoraPdv() {
    if (_overlayObraCalculadoraPdv != null) {
      _fecharObraCalculadoraPdv();
      return;
    }
    _fecharCalculadoraPdv();
    try {
      final overlay = Overlay.of(context);
      _overlayObraCalculadoraPdv = OverlayEntry(
        builder: (overlayContext) {
          final size = MediaQuery.sizeOf(overlayContext);
          const w = PdvObraCalculadoraPanel.largura;
          const h = PdvObraCalculadoraPanel.alturaEstimada;
          if (!_obraCalculadoraPdvPosicionada) {
            _obraCalculadoraPdvOffset = Offset(
              (size.width - w) / 2,
              (size.height - h) / 2,
            );
            _obraCalculadoraPdvPosicionada = true;
          }
          final left = _obraCalculadoraPdvOffset.dx.clamp(0.0, size.width - w);
          final top = _obraCalculadoraPdvOffset.dy.clamp(0.0, size.height - h);
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                child: PdvObraCalculadoraPanel(
                  config: _empresaConfigObraCalculadora(),
                  produtoRepository: widget.produtoRepository,
                  onFechar: _fecharObraCalculadoraPdv,
                  onAdicionarTudo: _inserirLinhasObraCalculadora,
                  onPanDelta: (delta) {
                    if (!mounted || _overlayObraCalculadoraPdv == null) return;
                    final area = MediaQuery.sizeOf(overlayContext);
                    _obraCalculadoraPdvOffset = Offset(
                      (_obraCalculadoraPdvOffset.dx + delta.dx).clamp(
                        0.0,
                        area.width - w,
                      ),
                      (_obraCalculadoraPdvOffset.dy + delta.dy).clamp(
                        0.0,
                        area.height - h,
                      ),
                    );
                    _overlayObraCalculadoraPdv?.markNeedsBuild();
                  },
                ),
              ),
            ],
          );
        },
      );
      overlay.insert(_overlayObraCalculadoraPdv!);
    } catch (e) {
      _fecharObraCalculadoraPdv();
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Calculadora de obra');
    }
  }

  Future<void> _inserirLinhasObraCalculadora(
    List<PdvObraCalculadoraLinhaInsercao> linhas,
  ) async {
    var inseridos = 0;
    final ignorados = <String>[];
    for (final linha in linhas) {
      final ok = await _adicionarComQuantidade(
        linha.produto,
        linha.quantidade,
        mostrarSugestoesAgregadas: false,
      );
      if (ok) {
        inseridos++;
      } else {
        ignorados.add(linha.produto.nome);
      }
    }
    if (!mounted) return;
    if (inseridos == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ignorados.isEmpty
                ? 'Nenhum material foi adicionado ao orcamento.'
                : 'Nenhum material adicionado. Verifique: '
                      '${ignorados.join(", ")}.',
          ),
        ),
      );
      return;
    }
    final msg = ignorados.isEmpty
        ? '$inseridos material(is) da obra adicionados ao orcamento.'
        : '$inseridos material(is) adicionados. Nao incluidos: '
              '${ignorados.join(", ")}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _atualizarOverlaySugestoesClientePdv() {
    if (_pdvClientesSugeridos.isEmpty || !_focusClientePdV.hasFocus) {
      _fecharOverlaySugestoesClientePdv();
      return;
    }
    // Overlay ja aberto: so redesenha (setas / digitacao) sem rebuild do PDV.
    if (_overlaySugestoesClientePdv != null) {
      _overlaySugestoesClientePdv!.markNeedsBuild();
      return;
    }

    final box =
        _keySeletorClienteAppBarPdv.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return;

    final offset = box.localToGlobal(Offset.zero);
    final overlay = Overlay.of(context);
    final fieldHeight = box.size.height;

    _overlaySugestoesClientePdv = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _fecharOverlaySugestoesClientePdv,
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + fieldHeight + 2,
              width: 300,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _pdvClientesSugeridos.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cliente = _pdvClientesSugeridos[index];
                      final selecionado = index == _pdvIndiceSugestaoCliente;
                      return ListTile(
                        dense: true,
                        selected: selecionado,
                        title: Text(
                          cliente.nomeRazao,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => unawaited(_aplicarClientePdv(cliente)),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlaySugestoesClientePdv!);
  }

  Future<void> _aplicarClientePdv(Cliente? cliente) async {
    await _selecionarClienteNoOrcamento(cliente?.id);
    if (!mounted) return;
    setState(() => _sincronizarTextoBuscaClientePdv());
  }

  Future<void> _confirmarBuscaClientePdv() async {
    if (_pdvIndiceSugestaoCliente >= 0 &&
        _pdvIndiceSugestaoCliente < _pdvClientesSugeridos.length) {
      await _aplicarClientePdv(
        _pdvClientesSugeridos[_pdvIndiceSugestaoCliente],
      );
      return;
    }

    final termo = _pdvClienteBuscaController.text.trim();
    if (termo.isEmpty) {
      await _aplicarClientePdv(null);
      return;
    }

    final lista = _pesquisarClientesPdv(termo);
    if (lista.length == 1) {
      await _aplicarClientePdv(lista.first);
      return;
    }
    if (lista.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nenhum cliente encontrado para "$termo".')),
      );
      _pdvClientesSugeridos = [];
      _pdvIndiceSugestaoCliente = -1;
      _fecharOverlaySugestoesClientePdv();
      return;
    }

    _pdvClientesSugeridos = lista;
    _pdvIndiceSugestaoCliente = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _atualizarOverlaySugestoesClientePdv();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Varios clientes — escolha na lista ou refine a busca.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _abrirCadastroRapidoClientePdv() async {
    final salvo = await mostrarCadastroRapidoClienteDialog(
      context,
      clienteRepository: widget.clienteRepository,
    );
    if (!mounted || salvo == null) return;

    await _aplicarClientePdv(salvo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cliente "${salvo.nomeRazao}" cadastrado.')),
    );
  }

  void _focarDescontoCheckoutDialogoAberto() {
    if (_maxDescontoPercentualPdv <= 0) return;
    _focusDescontoPdV.requestFocus();
  }

  Future<void> _selecionarClienteNoOrcamento(int? value) async {
    if (value == null) {
      setState(() {
        _clienteSelecionadoId = null;
        _indiceEnderecoSelecionado = 0;
        _atualizarEntregaCarrinhoComTipo(EntregaVendaHelper.tipoRetirada);
        _prioridadeEntregaSelecionada = 'normal';
        _janelaEntregaSelecionada = 'nao_definida';
        _dataEntregaMarcada = null;
        _entregaSemDataCombinada = false;
        _valorFreteController.clear();
        _enderecoEntregaController.clear();
        _observacaoEntregaController.clear();
        _precoListaAtivo = _precoListaPadraoPdv;
        _atualizarPrecosCarrinhoPreservandoTabelas();
      });
      return;
    }
    Cliente? cliente = widget.clienteRepository.obterPorId(value) as Cliente?;
    final repo = widget.clienteRepository;
    if (repo is ClienteApiRepository) {
      try {
        cliente = await repo.obterPorIdRemoto(value) ?? cliente;
      } catch (_) {}
    }
    if (cliente == null) return;
    setState(() {
      _clienteSelecionadoId = value;
      if (cliente!.vendedorResponsavelId > 0) {
        _vendedorSelecionadoId = cliente.vendedorResponsavelId;
      }
      _aplicarEnderecoSelecionadoDoCliente(
        cliente,
        cliente.indiceEnderecoPadraoEntrega(),
      );
      _atualizarPrecosCarrinhoPreservandoTabelas();
    });
    if (!cliente.ativo && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cliente "${cliente.nomeRazao}" esta inativo no cadastro.',
          ),
        ),
      );
    }
    if (cliente.bloqueadoFiado && mounted) {
      final motivo = cliente.motivoBloqueio.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            motivo.isEmpty
                ? 'Fiado bloqueado para este cliente.'
                : 'Fiado bloqueado: $motivo',
          ),
        ),
      );
    }
  }

  Future<void> _abrirCadastroNovoClienteNoPdv({
    StateSetter? setDialogState,
  }) async {
    final clienteCriado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientesPage(
          clienteRepository: widget.clienteRepository,
          vendaRepository: widget.vendaRepository,
          vendedorRepository: widget.vendedorRepository,
          retornarClienteAoSalvar: true,
        ),
      ),
    );
    if (!mounted || clienteCriado == null) {
      return;
    }
    await _selecionarClienteNoOrcamento(clienteCriado.id);
    _sincronizarTextoBuscaClientePdv();
    setDialogState?.call(() {});
  }

  KeyEventResult _onKeyClientePdv(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyN &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_abrirCadastroRapidoClientePdv());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.f4 && _shiftPressionado()) {
      unawaited(_abrirSeletorClienteNoPdv());
      return KeyEventResult.handled;
    }

    if (_pdvClientesSugeridos.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        final max = _pdvClientesSugeridos.length - 1;
        _pdvIndiceSugestaoCliente = (_pdvIndiceSugestaoCliente + 1).clamp(
          0,
          max,
        );
        _atualizarOverlaySugestoesClientePdv();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        final max = _pdvClientesSugeridos.length - 1;
        _pdvIndiceSugestaoCliente = _pdvIndiceSugestaoCliente <= 0
            ? max
            : _pdvIndiceSugestaoCliente - 1;
        _atualizarOverlaySugestoesClientePdv();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_confirmarBuscaClientePdv());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape && _pdvClientesSugeridos.isNotEmpty) {
      _pdvClientesSugeridos = [];
      _pdvIndiceSugestaoCliente = -1;
      _fecharOverlaySugestoesClientePdv();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildSeletorClienteAppBarPdv() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clienteAtual = _clienteSelecionado();
    final editandoCliente = _focusClientePdV.hasFocus;
    final faltaClienteFiado =
        _precisaPlanoFiadoPdV() &&
        (_clienteSelecionadoId == null || _clienteSelecionadoId! <= 0);
    final tooltip = clienteAtual == null
        ? 'Consumidor final · Shift+F2 para buscar · Shift+F4 cadastro · Ctrl+N cadastro rapido'
        : clienteAtual.nomeRazao;

    Color fundo;
    Color borda;
    Color corTexto;
    if (faltaClienteFiado) {
      fundo = scheme.errorContainer.withValues(alpha: 0.35);
      borda = scheme.error;
      corTexto = scheme.onErrorContainer;
    } else if (clienteAtual != null) {
      fundo = scheme.primaryContainer.withValues(alpha: 0.72);
      borda = scheme.primary.withValues(alpha: 0.55);
      corTexto = scheme.onPrimaryContainer;
    } else {
      fundo = scheme.surfaceContainerHighest.withValues(alpha: 0.65);
      borda = scheme.outlineVariant.withValues(alpha: 0.55);
      corTexto = scheme.onSurfaceVariant;
    }

    return FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: _keySeletorClienteAppBarPdv,
              width: _larguraSeletorClienteAppBarPdv,
              height: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fundo,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borda,
                    width: faltaClienteFiado ? 1.5 : 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (!editandoCliente) {
                        _focusClientePdV.requestFocus();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: editandoCliente
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Focus(
                                onKeyEvent: _onKeyClientePdv,
                                child: TextField(
                                  controller: _pdvClienteBuscaController,
                                  focusNode: _focusClientePdV,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: corTexto,
                                  ),
                                  textCapitalization:
                                      TextCapitalization.words,
                                  cursorHeight: 16,
                                  decoration: const InputDecoration(
                                    isCollapsed: true,
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: _atualizarSugestoesClientePdv,
                                  onSubmitted: (_) =>
                                      unawaited(_confirmarBuscaClientePdv()),
                                  onTapOutside: (_) =>
                                      _fecharOverlaySugestoesClientePdv(),
                                ),
                              ),
                            )
                          : Row(
                              children: [
                                Icon(
                                  clienteAtual == null
                                      ? Icons.person_outline
                                      : Icons.person,
                                  size: 16,
                                  color: clienteAtual == null
                                      ? corTexto
                                      : scheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    clienteAtual == null
                                        ? 'Consumidor Final (Shift+F2)'
                                        : _rotuloCurtoClientePdV(clienteAtual),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: corTexto,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Focus(
              skipTraversal: true,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Cadastro (Shift+F4)',
                icon: const Icon(Icons.contact_page_outlined, size: 18),
                onPressed: () => unawaited(_abrirSeletorClienteNoPdv()),
              ),
            ),
            Focus(
              skipTraversal: true,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Cadastro rapido (Ctrl+N)',
                icon: const Icon(Icons.flash_on_outlined, size: 18),
                onPressed: () => unawaited(_abrirCadastroRapidoClientePdv()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _garantirClientePdvParaEntrega() async {
    if (!_pdvExigeClientePorEntrega || !_pdvClienteAusente) {
      return true;
    }
    if (!mounted) return false;
    final motivo = _motivoClienteObrigatorioPdv;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${motivo[0].toUpperCase()}${motivo.substring(1)}: '
          'selecione ou cadastre o cliente para continuar.',
        ),
      ),
    );
    await _abrirSeletorClienteNoPdv(
      permitirSemCliente: false,
      motivoObrigatorio: motivo,
    );
    return !_pdvClienteAusente;
  }

  Future<void> _abrirSeletorClienteNoPdv({
    StateSetter? setDialogState,
    bool permitirSemCliente = true,
    String? motivoObrigatorio,
  }) async {
    final pesquisaController = TextEditingController();
    Timer? debounceApi;
    final tituloObrigatorio = motivoObrigatorio == null ||
            motivoObrigatorio.trim().isEmpty
        ? 'Cliente obrigatorio'
        : 'Cliente obrigatorio ($motivoObrigatorio)';
    final resultado = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var filtrados = widget.clienteRepository.listarPaginado(
          limit: 60,
          somenteAtivos: true,
        );
        return StatefulBuilder(
          builder: (context, setDialogStateInner) {
            return AlertDialog(
              title: Text(
                permitirSemCliente
                    ? 'Selecionar cliente'
                    : tituloObrigatorio,
              ),
              content: AdaptiveDialogPane(
                desktopWidth: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nome, documento, telefone...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim();
                        setDialogStateInner(() {
                          filtrados = termo.isEmpty
                              ? widget.clienteRepository.listarPaginado(
                                  limit: 60,
                                  somenteAtivos: true,
                                )
                              : widget.clienteRepository
                                    .pesquisar(termo)
                                    .where((c) => c.ativo)
                                    .take(60)
                                    .toList();
                        });
                        final repo = widget.clienteRepository;
                        if (repo is ClienteApiRepository && termo.isNotEmpty) {
                          debounceApi?.cancel();
                          debounceApi = Timer(
                            const Duration(milliseconds: 320),
                            () async {
                              try {
                                final remotos = await repo.pesquisarRemoto(
                                  termo,
                                  limit: 60,
                                );
                                if (!dialogContext.mounted) return;
                                setDialogStateInner(() {
                                  filtrados = remotos
                                      .where((c) => c.ativo)
                                      .take(60)
                                      .toList();
                                });
                              } catch (_) {}
                            },
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    if (permitirSemCliente)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_off_outlined),
                        title: const Text('Sem cliente'),
                        onTap: () => Navigator.pop(
                          dialogContext,
                          _selecaoSemClienteValor,
                        ),
                      ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.app_registration_outlined),
                      title: const Text('+ Cadastro...'),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        _selecaoNovoClienteValor,
                      ),
                    ),
                    const Divider(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: adaptiveDialogListMaxHeight(
                          context,
                          desktopFactor: 0.45,
                          mobileFactor: 0.38,
                        ),
                      ),
                      child: filtrados.isEmpty
                          ? const Center(
                              child: Text('Nenhum cliente encontrado.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtrados.length,
                              itemBuilder: (context, index) {
                                final c = filtrados[index];
                                final documento = c.documento.trim().isEmpty
                                    ? '-'
                                    : c.documento;
                                return ListTile(
                                  dense: true,
                                  title: Text(c.nomeRazao),
                                  subtitle: Text(
                                    'Doc: $documento | Tel: ${c.telefone.trim().isEmpty ? '-' : c.telefone}',
                                  ),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, c.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
    debounceApi?.cancel();
    pesquisaController.dispose();

    if (!mounted || resultado == null) {
      return;
    }
    if (resultado == _selecaoNovoClienteValor) {
      await _abrirCadastroNovoClienteNoPdv(setDialogState: setDialogState);
      return;
    }
    if (resultado == _selecaoSemClienteValor) {
      await _selecionarClienteNoOrcamento(null);
      _sincronizarTextoBuscaClientePdv();
      setDialogState?.call(() {});
      if (mounted) setState(() {});
      return;
    }
    await _selecionarClienteNoOrcamento(resultado);
    _sincronizarTextoBuscaClientePdv();
    setDialogState?.call(() {});
    if (mounted) setState(() {});
  }

  String _montarEnderecoEntregaCliente(Cliente cliente) {
    final enderecos = cliente.listarEnderecos();
    if (enderecos.isEmpty) return '';
    return enderecos.first.resumo();
  }

  String _montarObservacaoEntregaCliente(Cliente cliente) {
    final enderecos = cliente.listarEnderecos();
    if (enderecos.isEmpty) return '';
    return enderecos.first.referencia.trim();
  }

  String _resumoEntrega() {
    final endereco = _enderecoEntregaController.text.trim();
    final obs = _observacaoEntregaController.text.trim();
    final frete = _valorFreteController.text.trim();
    final partes = <String>[];
    if (endereco.isNotEmpty) {
      partes.add(endereco);
    }
    if (obs.isNotEmpty) {
      partes.add('Obs: $obs');
    }
    if (frete.isNotEmpty && _parseValorMonetario(frete) > 0) {
      partes.add('Frete: ${_formatarMoeda(_parseValorMonetario(frete))}');
    }
    if (_dataEntregaMarcada != null) {
      partes.add(
        'Data marcada: ${DateFormat('dd/MM/yyyy').format(_dataEntregaMarcada!)}',
      );
    } else if (_carrinhoTemItemCarreto && _entregaSemDataCombinada) {
      partes.add('Data: cliente ainda não definiu');
    }
    return partes.isEmpty
        ? 'Sem dados de entrega informados.'
        : partes.join(' | ');
  }

  Future<_EntregaDialogResult?> _abrirDialogEntregaCliente({
    required Cliente cliente,
  }) async {
    final enderecos = cliente.listarEnderecos();
    final enderecoInicial = _enderecoEntregaController.text.trim().isNotEmpty
        ? _enderecoEntregaController.text.trim()
        : _montarEnderecoEntregaCliente(cliente);
    final obsInicial = _observacaoEntregaController.text.trim().isNotEmpty
        ? _observacaoEntregaController.text.trim()
        : _montarObservacaoEntregaCliente(cliente);
    return showDialog<_EntregaDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _EntregaClienteDialog(
          clienteNome: cliente.nomeRazao,
          enderecosDisponiveis: enderecos,
          indiceEnderecoInicial: _indiceEnderecoSelecionado,
          enderecoInicial: enderecoInicial,
          observacaoInicial: obsInicial,
          valorFreteInicial: _valorFreteController.text.trim(),
        );
      },
    );
  }

  _OrcamentoItemDraft? get _linhaCarrinhoSelecionada {
    final i = _indiceLinhaCarrinho;
    if (i == null || i < 0 || i >= _carrinho.length) return null;
    return _carrinho[i];
  }

  Future<void> _alterarPrecoLinhaCarrinhoSelecionada() async {
    final idx = _indiceLinhaCarrinho;
    if (idx == null || idx < 0 || idx >= _carrinho.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um item no carrinho.')),
      );
      return;
    }
    await _alterarPrecoLinhaCarrinho(idx);
  }

  Future<void> _alterarPrecoLinhaCarrinho(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    final linha = _carrinho[index];
    final precoTabela = _resolverPrecoProduto(
      linha.produto,
      precoTipoLista: linha.precoTipo,
      quantidade: linha.quantidadeEstoque,
    ).precoFinal;

    final result = await solicitarAlteracaoPrecoUnitarioPdv(
      context,
      _usuarioRepository,
      usuarioLogado: widget.usuarioLogado,
      produto: linha.produto,
      precoTipo: linha.precoTipo,
      tetoDescontoPercentualEmpresa: _maxDescontoPercentualPdv,
      quantidadeLinha: linha.quantidadeVendaEfetiva,
      nomeProduto: linha.produto.nome,
      precoAtual: linha.precoUnitario,
      precoTabela: precoTabela,
      rotuloTabela: _rotuloPreco(linha.precoTipo),
      formatarMoeda: _formatarMoeda,
    );
    if (result == null || !mounted) return;

    linha.precoUnitario = result.novoPreco;
    linha.precoUnitarioManual = result.manual;
    if (!result.manual) {
      final r = _resolverPrecoProduto(
        linha.produto,
        precoTipoLista: linha.precoTipo,
        quantidade: linha.quantidadeEstoque,
      );
      linha.precoUnitario = r.precoFinal;
      linha.promocaoId = r.promocaoId;
      linha.promocaoNome = r.promocaoNome;
    } else {
      linha.promocaoId = 0;
      linha.promocaoNome = '';
    }
    _notificarUiCarrinho();
    _carrinhoFocus.requestFocus();
  }

  Future<void> _abrirDetalhesProdutoCarrinho() async {
    final linha = _linhaCarrinhoSelecionada;
    if (linha == null) return;
    final campanhas = _promoPreco?.listarCampanhasVigentesParaProduto(
          linha.produto,
          dataReferencia: DateTime.now(),
          segmentoCliente: _segmentoClienteAtivo,
          quantidade: linha.quantidadeEstoque,
        ) ??
        const [];
    await mostrarModalDetalheProdutoVenda(
      context,
      produto: linha.produto,
      campanhasVigentes: campanhas,
      imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
    );
    if (!mounted) return;
    _carrinhoFocus.requestFocus();
  }

  Widget _buildPreviewCarrinhoPdv({required bool compacto}) {
    final linha = _linhaCarrinhoSelecionada;
    if (linha == null) return const SizedBox.shrink();
    final campanhas = _promoPreco?.listarCampanhasVigentesParaProduto(
          linha.produto,
          dataReferencia: DateTime.now(),
          segmentoCliente: _segmentoClienteAtivo,
          quantidade: linha.quantidadeEstoque,
        ) ??
        const [];
    return PdvConsultaPreviewPanel(
      produto: linha.produto,
      formatarMoeda: _formatarMoeda,
      compacto: compacto,
      mostrarDescricaoInline: true,
      tituloPainel: 'Item no carrinho',
      campanhaPromo: campanhas.isNotEmpty ? campanhas.first : null,
      quantidadeNoOrcamento: _quantidadeUnidadeVendaNoCarrinho(
        linha.produto.id,
      ),
      precoUnitarioLinha: linha.precoUnitario,
      precoUnitarioManual: linha.precoUnitarioManual,
      onAlterarPreco: () => unawaited(_alterarPrecoLinhaCarrinhoSelecionada()),
      onDetalhes: () => unawaited(_abrirDetalhesProdutoCarrinho()),
      sugestoesCarrinho: _sugestoesCarrinhoVisiveis,
      sugestoesOrigemNome: _sugestoesCarrinhoOrigemNome,
      onFecharSugestoesCarrinho: _fecharSugestoesCarrinho,
      onAdicionarSugestaoCarrinho: (s) =>
          unawaited(_adicionarSugestaoAgregadaDoCarrinho(s)),
      imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
    );
  }

  Widget _buildAreaCarrinhoComPreviewPdv() {
    // LayoutBuilder sempre presente: trocar a raiz (com/sem LayoutBuilder)
    // ao esvaziar o carrinho mutava o RenderObject no meio do layout.
    return LayoutBuilder(
      builder: (context, constraints) {
        final painel = _buildPainelCheckoutPdv();
        final mostrarPreview =
            _carrinho.isNotEmpty && _linhaCarrinhoSelecionada != null;
        if (!mostrarPreview) {
          return painel;
        }
        final lateral = constraints.maxWidth >= _breakpointPreviewCarrinhoPdv;
        if (lateral) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: painel),
              SizedBox(
                width: _larguraPreviewCarrinhoPdv,
                child: _buildPreviewCarrinhoPdv(compacto: false),
              ),
            ],
          );
        }
        // No celular o preview empilhado (360px) come a tela — so carrinho.
        if (_pdvUiCelular) {
          return painel;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 360,
              child: _buildPreviewCarrinhoPdv(compacto: true),
            ),
            const SizedBox(height: 8),
            Expanded(child: painel),
          ],
        );
      },
    );
  }

  Widget _buildPainelCheckoutPdv() {
    return _PdvPainelCheckout(
      leiauteEmpilhado: true,
      keyPainel: _keyPainelCheckoutPdV,
      painelCheckoutRecolhido: false,
      carrinhoCount: _carrinho.length,
      totalResumoColapsado: _formatarMoeda(_totalGeralComFrete),
      onExpandirPainel: _irParaPesquisaProdutos,
      orcamentoEmEdicao: _orcamentoEmEdicaoId != null,
      orcamentoEmEdicaoNumero: _orcamentoEmEdicaoNumero?.toString(),
      ultimoOrcamentoSalvoNumero: _ultimoOrcamentoSalvoNumero,
      ultimoOrcamentoSalvoTotal: _ultimoOrcamentoSalvoTotal,
      onCancelarEdicaoOrcamento: () {
        setState(() {
          _orcamentoEmEdicaoId = null;
          _orcamentoEmEdicaoNumero = null;
        });
      },
      mostrarDicaAtalhosCarrinho: _mostrarAjudaAtalhos && _carrinho.isNotEmpty,
      resumoEntregaItens: _resumoEntregaItensCarrinho,
        carrinhoBody: _PdvCarrinhoProdutos(
        carrinhoFocus: _carrinhoFocus,
        onKeyCarrinho: _onKeyCarrinho,
        itens: _carrinho,
        indiceLinhaSelecionada: _indiceLinhaCarrinho,
        indiceLinhaEdicaoQuantidade: _indiceLinhaEdicaoQuantidade,
        quantidadeInlineController: _qtdCarrinhoInlineController,
        quantidadeInlineFocus: _focusQuantidadeCarrinhoInline,
        onConfirmarQuantidadeInline: _confirmarQuantidadeCarrinhoInline,
        quantidadeFracionadaDe: _quantidadeFracionadaCarrinho,
        onSelecionarLinha: (index) {
          if (_indiceLinhaEdicaoQuantidade != null) return;
          _definirIndiceLinhaCarrinho(index, isolado: true);
          _carrinhoFocus.requestFocus();
        },
        rotuloPreco: _rotuloPreco,
        formatarMoeda: _formatarMoeda,
        onAlterarQuantidade: _alterarQuantidadeCarrinho,
        onEditarQuantidade: (index) => unawaited(_editarQuantidadeCarrinho(index)),
        passoQuantidadeCarrinho: _passoQuantidadeCarrinho,
        onRemoverItem: _removerItemCarrinho,
        onAlternarTipoEntrega: _alternarTipoEntregaLinhaCarrinho,
        onAlternarTabelaPreco: _alternarTabelaPrecoLinhaCarrinho,
        onDividirLinha: _dividirLinhaCarrinho,
        onAlterarPrecoLinha: _alterarPrecoLinhaCarrinho,
        onIrPesquisaQuandoVazio: () => unawaited(_abrirConsultaProdutos()),
        alvosTouchAmplos: _pdvAlvosTouchAmplos,
      ),
      subtotalProdutos: _totalOrcamento,
      valorFrete: _valorFreteAtual,
      valorDesconto: _valorDescontoReaisPdV(),
      descontoConfigAtivo: _maxDescontoPercentualPdv > 0.004,
      totalDestaqueValor: _maxDescontoPercentualPdv > 0.004
          ? _totalLiquidoPagamentoPdV()
          : _totalGeralComFrete,
      formatarMoeda: _formatarMoeda,
      onIrPesquisaProdutos: _irParaPesquisaProdutos,
      onRecolherCheckout: _irParaPesquisaProdutos,
      focusSalvarOrcamento: _focusSalvarOrcamentoPdV,
      onContinuarFechamento: () {
        unawaited(_abrirPassoFechamentoVenda());
      },
      labelBotaoContinuar: _pdvUiCelular
          ? (_orcamentoEmEdicaoId != null
                ? 'Continuar para atualizar'
                : 'Continuar para salvar')
          : (_orcamentoEmEdicaoId != null
                ? 'Continuar para atualizar (F10)'
                : 'Continuar para salvar (F10)'),
      modoCelular: _pdvUiCelular,
    );
  }

  String? get _segmentoClienteAtivo {
    final id = _clienteSelecionadoId;
    if (id == null || id <= 0) return null;
    return widget.clienteRepository.obterPorId(id)?.segmento;
  }

  String _normalizarTabelaPrecoPdv(String? valor) =>
      PdvTabelaPrecoUtil.normalizar(valor);

  void _aplicarTabelaPrecoNaLinha(
    _OrcamentoItemDraft linha,
    String novaTabela,
  ) {
    final tabela = _normalizarTabelaPrecoPdv(novaTabela);
    if (linha.precoUnitarioManual) {
      linha.precoTipo = tabela;
      return;
    }
    final r = _resolverPrecoProduto(
      linha.produto,
      precoTipoLista: tabela,
      quantidade: linha.quantidadeEstoque,
    );
    linha.precoUnitario = r.precoFinal;
    linha.precoTipo = r.precoTipo;
    linha.promocaoId = r.promocaoId;
    linha.promocaoNome = r.promocaoNome;
  }

  void _recalcularPrecoLinhaCarrinho(_OrcamentoItemDraft linha) {
    if (linha.precoUnitarioManual) return;
    final r = _resolverPrecoProduto(
      linha.produto,
      precoTipoLista: linha.precoTipo,
      quantidade: linha.quantidadeEstoque,
    );
    linha.precoUnitario = r.precoFinal;
    linha.precoTipo = r.precoTipo;
    linha.promocaoId = r.promocaoId;
    linha.promocaoNome = r.promocaoNome;
  }

  /// Recalcula precos linha a linha, preservando a tabela de cada item.
  void _atualizarPrecosCarrinhoPreservandoTabelas() {
    if (_carrinho.isEmpty) return;
    for (final linha in _carrinho) {
      _recalcularPrecoLinhaCarrinho(linha);
    }
    _promoCarrinho?.aplicarRegrasCarrinho(
      _carrinho,
      dataReferencia: DateTime.now(),
      segmentoCliente: _segmentoClienteAtivo,
    );
  }

  String _rotuloFormaPagamentoCheckoutPdV() {
    if (PdvTabelaPrecoUtil.carrinhoMisto(_carrinho.map((l) => l.precoTipo))) {
      return 'tabelas mistas';
    }
    final tabelas = PdvTabelaPrecoUtil.tabelasDistintas(
      _carrinho.map((l) => l.precoTipo),
    );
    final tabela = tabelas.isEmpty ? _precoListaAtivo : tabelas.first;
    return _rotuloPreco(tabela);
  }

  /// F1–F3 com linha selecionada no carrinho: altera a tabela da linha.
  void _aplicarTabelaPrecoAtalhoPdv(String novaTabela) {
    final idx = _indiceLinhaCarrinho;
    if (idx == null || idx < 0 || idx >= _carrinho.length) return;
    final tabela = _normalizarTabelaPrecoPdv(novaTabela);
    final linha = _carrinho[idx];
    if (_normalizarTabelaPrecoPdv(linha.precoTipo) == tabela &&
        !linha.precoUnitarioManual) {
      return;
    }
    setState(() {
      _aplicarTabelaPrecoNaLinha(linha, tabela);
      _promoCarrinho?.aplicarRegrasCarrinho(
        _carrinho,
        dataReferencia: DateTime.now(),
        segmentoCliente: _segmentoClienteAtivo,
      );
    });
    _notificarUiCarrinho();
  }

  void _atualizarEntregaCarrinhoComTipo(String novoTipo) {
    final tipo = EntregaVendaHelper.normalizarTipoItem(novoTipo);
    _tipoEntregaSelecionada = tipo;
    for (final linha in _carrinho) {
      linha.tipoEntregaItem = tipo;
    }
  }

  /// Ctrl+F1–F3: define o padrao para **novos** itens.
  ///
  /// Se o carrinho esta vazio ou todas as linhas ja sao do mesmo tipo, aplica
  /// tambem nas linhas. Se o carrinho e **misto**, nao sobrescreve (use E /
  /// Dividir por linha) — evita transformar "leva agora" em futura/carreto
  /// e reservar estoque sem baixa no caixa.
  void _definirEntregaPadraoPdv(String novoTipo) {
    final tipo = EntregaVendaHelper.normalizarTipoItem(novoTipo);
    if (tipo ==
        EntregaVendaHelper.normalizarTipoItem(_tipoEntregaSelecionada)) {
      return;
    }
    final tiposNoCarrinho = _carrinho
        .map((e) => EntregaVendaHelper.normalizarTipoItem(e.tipoEntregaItem))
        .toSet();
    final carrinhoMisto = tiposNoCarrinho.length > 1;

    if (carrinhoMisto) {
      setState(() => _tipoEntregaSelecionada = tipo);
      _notificarUiCarrinho();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Padrao para novos itens: ${EntregaVendaHelper.rotuloTipoItem(tipo)}. '
              'Carrinho misto: altere linha a linha (tecla E ou Dividir).',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      setState(() => _atualizarEntregaCarrinhoComTipo(tipo));
      _notificarUiCarrinho();
      if (_carrinho.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Entrega do carrinho: ${EntregaVendaHelper.rotuloTipoItem(tipo)}. '
              'Para misturar tipos: tecla E na linha ou Dividir.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _recalcularPromocoesCarrinho() {
    if (_carrinho.isEmpty) return;
    _atualizarPrecosCarrinhoPreservandoTabelas();
  }

  PromocaoPrecoResult _resolverPrecoProduto(
    Produto produto, {
    String? precoTipoLista,
    int quantidade = 1,
    DateTime? dataReferencia,
  }) {
    final tipo = precoTipoLista ?? _precoListaAtivo;
    final svc = _promoPreco;
    if (svc == null) {
      return PromocaoPrecoResult.semPromocao(
        precoFinal: PromocaoPrecoService.precoLista(produto, tipo),
        precoBasePreco1: PromocaoPrecoService.preco1Base(produto),
        precoTipo: tipo,
      );
    }
    return svc.resolver(
      produto,
      dataReferencia: dataReferencia ?? DateTime.now(),
      quantidade: quantidade,
      precoTipoLista: tipo,
      segmentoCliente: _segmentoClienteAtivo,
    );
  }

  double _precoExibicaoConsulta(Produto produto, String precoTipo) {
    return _resolverPrecoProduto(produto, precoTipoLista: precoTipo).precoFinal;
  }

  String _rotuloPreco(String precoTipo) {
    if (precoTipo == PromocaoCadastro.precoTipoPromo) {
      return 'Promocao';
    }
    return PdvTabelaPrecoUtil.rotulo(precoTipo);
  }

  Produto _produtoAtualizadoParaPdv(Produto produto) =>
      widget.produtoRepository.obterPorId(produto.id) ?? produto;

  Future<void> _adicionarAoOrcamento(Produto produto) async {
    final produtoAtual = _produtoAtualizadoParaPdv(produto);
    if (_pdvBalcaoRapido &&
        PdvBalcaoRapidoHelper.podeAdicionarDireto(
          carrinhoTemCarreto: _carrinhoTemItemCarreto,
          tipoEntregaSelecionada: _tipoEntregaSelecionada,
          pagamentoMisto: _pagamentoMistoPdV,
          edicaoOrcamento: _orcamentoEmEdicaoId != null,
        )) {
      await _adicionarComQuantidade(
        produtoAtual,
        1,
        precoTipo: _precoListaAtivo,
        tipoEntregaItem: _tipoEntregaSelecionada,
      );
      return;
    }
    final result = await showDialog<_AdicionarOrcamentoResult>(
      context: context,
      builder: (context) => _AdicionarAoOrcamentoDialog(
        produtoRepository: widget.produtoRepository,
        produto: produtoAtual,
        precoTipoInicial: _precoListaAtivo,
        tipoEntregaInicial: _tipoEntregaSelecionada,
        precoUnitarioDe: (p, t) =>
            _resolverPrecoProduto(p, precoTipoLista: t).precoFinal,
        formatarMoeda: _formatarMoeda,
      ),
    );

    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (result.quantidadeVenda <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade deve ser maior que zero.')),
      );
      return;
    }

    await _adicionarComQuantidade(
      _produtoAtualizadoParaPdv(produto),
      result.quantidadeVenda,
      precoTipo: result.precoTipo,
      tipoEntregaItem: result.tipoEntregaItem,
      quantidadeEmUnidadeCompra: result.quantidadeEmUnidadeCompra,
    );
  }

  static const List<({String id, String rotulo, IconData icone})>
  _opcoesFormaPagamentoPdV = [
    (id: 'dinheiro', rotulo: 'Dinheiro', icone: Icons.payments_outlined),
    (id: 'pix', rotulo: 'PIX', icone: Icons.qr_code_2_outlined),
    (id: 'cartao_debito', rotulo: 'Debito', icone: Icons.credit_card_outlined),
    (
      id: 'cartao_credito',
      rotulo: 'Credito',
      icone: Icons.credit_score_outlined,
    ),
    (
      id: 'transferencia',
      rotulo: 'Transfer.',
      icone: Icons.account_balance_outlined,
    ),
    (id: 'fiado', rotulo: 'Fiado', icone: Icons.receipt_long_outlined),
    (
      id: 'vale',
      rotulo: 'Vale',
      icone: Icons.confirmation_number_outlined,
    ),
  ];

  /// Todas as formas do PDV, independente da tabela de preco do item/venda.
  /// Vale so pelo painel misto: la da para pedir o codigo e saber qual e.
  List<({String id, String rotulo, IconData icone})>
  _opcoesFormaPagamentoPdVAtivas() {
    return [
      for (final op in _opcoesFormaPagamentoPdV)
        if (op.id != 'vale' && (op.id != 'fiado' || _podeVenderFiado)) op,
    ];
  }

  List<({String id, String rotulo, IconData icone})>
  _opcoesFormaPagamentoMistoPdV() {
    return [
      for (final op in _opcoesFormaPagamentoPdV)
        if (op.id != 'fiado' || _podeVenderFiado) op,
    ];
  }

  bool _podeSelecionarMeioMistoFiado(String meioAtualLinha) {
    if (meioAtualLinha == 'fiado') return true;
    return !_linhasPagamentoMisto.any((l) => l.meio == 'fiado');
  }

  void _selecionarMeioPagamentoMisto({
    required _LinhaPagamentoMistoPdV linha,
    required String meio,
    required StateSetter setDialogState,
  }) {
    if (meio == 'fiado' && !_podeVenderFiado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissao para vender a prazo (fiado).'),
        ),
      );
      return;
    }
    if (meio == 'fiado' && !_podeSelecionarMeioMistoFiado(linha.meio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamento misto: use apenas uma linha Fiado.'),
        ),
      );
      return;
    }
    if (meio == 'vale') {
      unawaited(_escolherValeNaLinhaMisto(linha, setDialogState));
      return;
    }
    _atualizarCheckoutFechamento(setDialogState, () {
      linha.meio = meio;
      linha.limparVale();
      if (meio != 'cartao_credito') linha.parcelas = 1;
    });
  }

  /// Pede o codigo do vale antes de marcar a linha: sem vale escolhido a
  /// linha nao teria como ser baixada no fechamento.
  Future<void> _escolherValeNaLinhaMisto(
    _LinhaPagamentoMistoPdV linha,
    StateSetter setDialogState,
  ) async {
    final servico = ValeCreditoService.deVendaRepository(widget.vendaRepository);
    if (!servico.disponivel) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem conexao com o servidor para consultar o vale.'),
        ),
      );
      return;
    }
    final restante =
        _totalLiquidoPagamentoPdV() - _somaDigitadaMistoPdV() +
            _parseValorMonetario(linha.valorController.text);
    final total = _totalLiquidoPagamentoPdV();
    final alvo = restante > 0.004 ? restante : total;

    final vale = await selecionarValeCredito(
      context,
      servico: servico,
      totalAPagar: alvo,
      clienteId: _clienteSelecionadoId ?? 0,
      jaUsados: _linhasPagamentoMisto
          .where((l) => l != linha && l.valeId > 0)
          .map((l) => l.valeId)
          .toSet(),
    );
    if (vale == null || !mounted) return;

    final aplicar = vale.avaliar(alvo).valorAplicavel;
    _atualizarCheckoutFechamento(setDialogState, () {
      linha.meio = 'vale';
      linha.parcelas = 1;
      linha.valeId = vale.id;
      linha.codigoVale = vale.codigo;
      linha.saldoVale = vale.saldo;
      linha.valorController.text = aplicar.toStringAsFixed(2).replaceAll(
            '.',
            ',',
          );
    });
  }

  Widget _buildChipFormaPagamento({
    required String rotulo,
    required IconData icone,
    required bool selecionado,
    required bool destacadoTeclado,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final destaque = selecionado || destacadoTeclado;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icone,
            size: 17,
            color: selecionado ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
          const SizedBox(width: 5),
          Text(
            rotulo,
            style: TextStyle(
              fontWeight: selecionado ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
      showCheckmark: false,
      selected: selecionado,
      selectedColor: scheme.primaryContainer.withValues(alpha: 0.72),
      backgroundColor: scheme.surface,
      side: BorderSide(
        color: destaque ? scheme.primary : scheme.outlineVariant,
        width: destaque ? 1.5 : 1,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: onTap == null ? null : (_) => onTap(),
    );
  }

  Widget _buildChipsParcelasCreditoCheckout(StateSetter setDialogState) {
    final theme = Theme.of(context);
    final valorBase = _totalLiquidoPagamentoPdV();
    final parcelas = _parcelasSelecionadas.clamp(
      1,
      _parcelasMaximasCheckoutPdV,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Parcelas no cartao',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: 156,
          child: DropdownButtonFormField<int>(
            key: ValueKey(parcelas),
            isExpanded: true,
            isDense: true,
            initialValue: parcelas,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: List.generate(_parcelasMaximasCheckoutPdV, (i) {
              final n = i + 1;
              return DropdownMenuItem(
                value: n,
                child: Text(
                  _rotuloParcelaCreditoValor(n, valorBase),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            onChanged: (p) {
              if (p == null) return;
              _atualizarCheckoutFechamento(
                setDialogState,
                () => _parcelasSelecionadas = p,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutBadgeTabelaPreco() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _rotuloFormaPagamentoCheckoutPdV(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildChipsFormaPagamentoCheckout(
    StateSetter setDialogState, {
    bool exibirTituloSecao = true,
  }) {
    final theme = Theme.of(context);
    final pagamentoComFoco = _focusPagamentoPdV.hasFocus;
    final opcoes = _opcoesFormaPagamentoPdVAtivas();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (exibirTituloSecao) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Forma de pagamento',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildCheckoutBadgeTabelaPreco(),
            ],
          ),
          const SizedBox(height: 8),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Meio de pagamento',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _buildCheckoutBadgeTabelaPreco(),
              ],
            ),
          ),
        Focus(
          focusNode: _focusPagamentoPdV,
          onFocusChange: (hasFocus) {
            if (!hasFocus) return;
            final idx = _indiceFormaPagamentoSelecionadaPdV();
            if (_indiceChipPagamentoFocado == idx) return;
            _indiceChipPagamentoFocado = idx;
            _checkoutDialogSetState?.call(() {});
          },
          onKeyEvent: (node, event) =>
              _onKeyPagamentoCheckout(node, event, setDialogState),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < opcoes.length; i++)
                _buildChipFormaPagamento(
                  rotulo: opcoes[i].rotulo,
                  icone: opcoes[i].icone,
                  selecionado: _formaPagamentoSelecionada == opcoes[i].id,
                  destacadoTeclado:
                      pagamentoComFoco && _indiceChipPagamentoFocado == i,
                  onTap: () =>
                      _aplicarFormaPagamentoPorIndice(i, setDialogState),
                ),
            ],
          ),
        ),
        if (_formaPagamentoSelecionada == 'fiado') ...[
          const SizedBox(height: 8),
          Text(
            'O caixa finaliza a venda; o cliente quita as parcelas depois.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_formaPagamentoSelecionada == 'cartao_credito') ...[
          const SizedBox(height: 10),
          _buildChipsParcelasCreditoCheckout(setDialogState),
        ],
      ],
    );
  }

  Widget _buildChipsMeioMistoLinha({
    required _LinhaPagamentoMistoPdV linha,
    required StateSetter setDialogState,
  }) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final op in _opcoesFormaPagamentoMistoPdV())
          _buildChipFormaPagamento(
            rotulo: op.rotulo,
            icone: op.icone,
            selecionado: linha.meio == op.id,
            destacadoTeclado: false,
            onTap:
                (op.id == 'fiado' && !_podeVenderFiado) ||
                    (op.id == 'fiado' &&
                        !_podeSelecionarMeioMistoFiado(linha.meio))
                ? null
                : () => _selecionarMeioPagamentoMisto(
                    linha: linha,
                    meio: op.id,
                    setDialogState: setDialogState,
                  ),
          ),
      ],
    );
  }

  Widget _buildPainelPagamentoMistoPdV(StateSetter setDialogState) {
    final restante = _totalLiquidoPagamentoPdV() - _somaDigitadaMistoPdV();
    final ok = restante.abs() < 0.02;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_linhasPagamentoMisto.length, (i) {
          final linha = _linhasPagamentoMisto[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Parte ${i + 1}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Remover parte',
                        visualDensity: VisualDensity.compact,
                        onPressed: _linhasPagamentoMisto.length <= 2
                            ? null
                            : () {
                                _atualizarCheckoutFechamento(
                                  setDialogState,
                                  () {
                                    final rem = _linhasPagamentoMisto.removeAt(
                                      i,
                                    );
                                    rem.dispose();
                                  },
                                );
                              },
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                    ],
                  ),
                  _buildChipsMeioMistoLinha(
                    linha: linha,
                    setDialogState: setDialogState,
                  ),
                  if (linha.meio == 'vale' && linha.valeId > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${ValeCreditoCodigo.formatar(linha.codigoVale)} · '
                            'saldo ${_formatarMoeda(linha.saldoVale)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => _escolherValeNaLinhaMisto(
                            linha,
                            setDialogState,
                          ),
                          child: const Text('Trocar'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: linha.valorController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor R\$',
                            hintText: '0,00',
                            isDense: true,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      if (linha.meio == 'cartao_credito') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final valorLinha = _parseValorMonetario(
                                linha.valorController.text,
                              );
                              return DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: linha.parcelas.clamp(1, 12),
                                decoration: const InputDecoration(
                                  labelText: 'Parc. credito',
                                  isDense: true,
                                ),
                                selectedItemBuilder: (context) {
                                  return List.generate(12, (k) {
                                    final n = k + 1;
                                    return Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(
                                        _rotuloParcelaCreditoValor(
                                          n,
                                          valorLinha,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                      ),
                                    );
                                  });
                                },
                                items: List.generate(12, (k) {
                                  final n = k + 1;
                                  return DropdownMenuItem(
                                    value: n,
                                    child: Text(
                                      _rotuloParcelaCreditoValor(n, valorLinha),
                                    ),
                                  );
                                }),
                                onChanged: (p) {
                                  if (p != null) {
                                    _atualizarCheckoutFechamento(
                                      setDialogState,
                                      () => linha.parcelas = p,
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              _atualizarCheckoutFechamento(setDialogState, () {
                _linhasPagamentoMisto.add(
                  _LinhaPagamentoMistoPdV(
                    meio: 'cartao_credito',
                    valorController: TextEditingController(),
                    parcelas: 1,
                  ),
                );
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Adicionar meio'),
          ),
        ),
        if (_valorFiadoCheckoutPdV() > 0.001) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Parte fiado: ${_formatarMoeda(_valorFiadoCheckoutPdV())}. '
              'Vincule o cliente e defina as parcelas de quitação abaixo. '
              'No caixa, só entra o que o cliente paga agora (dinheiro, PIX, cartão).',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        Text(
          ok
              ? 'Pagamento fecha com o total geral.'
              : 'Restante: ${_formatarMoeda(restante)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: ok
                ? Colors.green.shade800
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  int _indiceFormaPagamentoSelecionadaPdV() {
    final opcoes = _opcoesFormaPagamentoPdVAtivas();
    final idx = opcoes.indexWhere((o) => o.id == _formaPagamentoSelecionada);
    return idx >= 0 ? idx : 0;
  }

  void _sincronizarIndiceChipPagamentoComSelecao() {
    _indiceChipPagamentoFocado = _indiceFormaPagamentoSelecionadaPdV();
  }

  void _aplicarFormaPagamentoPorIndice(int index, StateSetter setDialogState) {
    final opcoes = _opcoesFormaPagamentoPdVAtivas();
    if (index < 0 || index >= opcoes.length) return;
    final op = opcoes[index];
    if (op.id == 'fiado' && !_podeVenderFiado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissao para vender a prazo (fiado).'),
        ),
      );
      return;
    }
    _atualizarCheckoutFechamento(setDialogState, () {
      _formaPagamentoSelecionada = op.id;
      _indiceChipPagamentoFocado = index;
      if (op.id != 'cartao_credito') {
        _parcelasSelecionadas = 1;
      }
    });
  }

  KeyEventResult _onKeyPagamentoCheckout(
    FocusNode node,
    KeyEvent event,
    StateSetter setDialogState,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_pagamentoMistoPdV) return KeyEventResult.ignored;
    final key = event.logicalKey;

    int? indiceTeclaNumerica;
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      indiceTeclaNumerica = 0;
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      indiceTeclaNumerica = 1;
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      indiceTeclaNumerica = 2;
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      indiceTeclaNumerica = 3;
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      indiceTeclaNumerica = 4;
    } else if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      indiceTeclaNumerica = 5;
    }

    if (indiceTeclaNumerica != null) {
      _aplicarFormaPagamentoPorIndice(indiceTeclaNumerica, setDialogState);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      final opcoes = _opcoesFormaPagamentoPdVAtivas();
      final next = (_indiceChipPagamentoFocado + 1) % opcoes.length;
      _aplicarFormaPagamentoPorIndice(next, setDialogState);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      final opcoes = _opcoesFormaPagamentoPdVAtivas();
      final prev =
          (_indiceChipPagamentoFocado - 1 + opcoes.length) % opcoes.length;
      _aplicarFormaPagamentoPorIndice(prev, setDialogState);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _aplicarFormaPagamentoPorIndice(
        _indiceChipPagamentoFocado,
        setDialogState,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _aplicarFocoInicialCheckoutDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_checkoutDialogAberto || !mounted) return;
      if (_pagamentoMistoPdV) {
        _focusPagamentoMistoSwitchPdV.requestFocus();
        return;
      }
      _sincronizarIndiceChipPagamentoComSelecao();
      _focusPagamentoPdV.requestFocus();
    });
  }

  void _checkoutDialogFecharOuRetroceder() {
    final ctx = _checkoutDialogFechamentoContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  void _alternarPagamentoMistoCheckout(
    StateSetter setDialogState, {
    ScrollController? scrollCheckout,
  }) {
    _atualizarCheckoutFechamento(setDialogState, () {
      _pagamentoMistoPdV = !_pagamentoMistoPdV;
      if (_pagamentoMistoPdV) {
        _inicializarLinhasMistoPadrao();
      } else {
        _disposeLinhasPagamentoMisto();
      }
    }, scrollCheckout: scrollCheckout);
    _aplicarFocoInicialCheckoutDialog();
  }

  void _alternarPagamentoMistoCheckoutDialogoAberto() {
    final setDialogState = _checkoutDialogSetState;
    if (setDialogState == null) return;
    _alternarPagamentoMistoCheckout(setDialogState);
  }

  String? _mensagemErroConfirmarCheckout() {
    if (_descontoPdVUltrapassaTetoSemAutorizacao()) {
      return _mensagemErroDescontoPdVUltrapassaTeto();
    }
    if (_precisaPlanoFiadoPdV() &&
        (_clienteSelecionadoId == null || _clienteSelecionadoId! <= 0)) {
      return 'Selecione o cliente no topo da tela (fiado).';
    }
    if (_pdvExigeClientePorEntrega && _pdvClienteAusente) {
      return '${_motivoClienteObrigatorioPdv[0].toUpperCase()}'
          '${_motivoClienteObrigatorioPdv.substring(1)}: '
          'selecione ou cadastre o cliente no topo da tela.';
    }
    if (_carrinhoTemItemCarreto &&
        _enderecoEntregaController.text.trim().isEmpty) {
      return 'Informe o endereco para carreto.';
    }
    if (_carrinhoTemItemCarreto &&
        _dataEntregaMarcada == null &&
        !_entregaSemDataCombinada) {
      return 'Defina a data da entrega ou marque que o cliente ainda não definiu.';
    }
    if (_carrinhoTemItemCarreto &&
        _prioridadeEntregaSelecionada == 'agendada' &&
        _janelaEntregaSelecionada == 'nao_definida') {
      return 'Para entrega agendada, selecione janela Manha ou Tarde.';
    }
    if (_pdvExigirVendedor && _vendedorSelecionadoPdv() == null) {
      return 'Informe quem esta vendendo (vendedor no topo da tela).';
    }
    return null;
  }

  Future<void> _confirmarCheckoutEEnviar({
    BuildContext? fechamentoDialogContext,
  }) async {
    if (_salvandoOrcamento) return;
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    if (_descontoPdVUltrapassaTetoSemAutorizacao()) {
      final ok = await _solicitarAutorizacaoDescontoAcimaTetoPdV();
      if (!ok || !mounted) return;
      _checkoutDialogSetState?.call(() {});
    }
    if (!await _garantirVendedorPdvObrigatorio()) return;
    final erro = _mensagemErroConfirmarCheckout();
    if (erro != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    await _salvarOrcamento(fechamentoDialogContext: fechamentoDialogContext);
  }

  Future<void> _checkoutDialogAcaoF10Async() async {
    if (!_checkoutDialogAberto || _salvandoOrcamento) return;
    final ctx = _checkoutDialogFechamentoContext;
    if (ctx == null) return;
    await _confirmarCheckoutEEnviar(fechamentoDialogContext: ctx);
  }

  Widget _buildCheckoutAtalhoChip(String rotulo) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Text(
        rotulo,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildCheckoutDicaAtalhosTeclado() {
    if (_pdvUiCelular) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _buildCheckoutAtalhoChip('F10 enviar'),
        _buildCheckoutAtalhoChip('1-6 meio'),
        _buildCheckoutAtalhoChip('F3 desconto'),
        _buildCheckoutAtalhoChip('F6 misto'),
        _buildCheckoutAtalhoChip('Esc fechar'),
      ],
    );
  }

  Widget _buildCheckoutDialogCabecalho(BuildContext dialogContext) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titulo = _orcamentoEmEdicaoId != null
        ? 'Concluir atualizacao da venda'
        : 'Enviar ao caixa';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.point_of_sale_outlined, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Revise pagamento e envie ao operador do caixa',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _pdvUiCelular ? 'Fechar' : 'Fechar (Esc)',
            onPressed: () => Navigator.pop(dialogContext),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutDialogRodape({required BuildContext dialogContext}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final confirmarLabel = _orcamentoEmEdicaoId != null
        ? 'Confirmar atualizacao'
        : 'Enviar ao caixa';
    final celular = _pdvUiCelular;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final botaoConfirmar = Focus(
      focusNode: _focusCheckoutAcaoPrimaria,
      child: FilledButton.icon(
        onPressed: () => unawaited(
          _confirmarCheckoutEEnviar(fechamentoDialogContext: dialogContext),
        ),
        style: celular
            ? FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(vertical: 14),
              )
            : null,
        icon: const Icon(Icons.point_of_sale_outlined),
        label: Text(celular ? confirmarLabel : '$confirmarLabel (F10)'),
      ),
    );
    final botaoFechar = TextButton(
      onPressed: () => Navigator.pop(dialogContext),
      child: Text(celular ? 'Fechar' : 'Fechar (Esc)'),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        celular ? 8 : 10,
        16,
        celular ? 12 + viewInsets.bottom.clamp(0.0, 24.0) : 14,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.55),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!celular) ...[
            _buildCheckoutDicaAtalhosTeclado(),
            const SizedBox(height: 12),
          ],
          if (celular) ...[
            botaoConfirmar,
            const SizedBox(height: 8),
            botaoFechar,
          ] else
            Row(children: [botaoFechar, const Spacer(), botaoConfirmar]),
        ],
      ),
    );
  }

  Future<void> _abrirPassoFechamentoVenda() async {
    _descontoPdVController.clear();
    _tipoDescontoPdV = 'percentual';
    _descontoAcimaTetoAutorizadoPdv = false;
    _descontoAutorizadoPorPdV = null;
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item na venda.')),
      );
      return;
    }
    if (!await _garantirVendedorPdvObrigatorio()) return;
    if (!await _garantirClientePdvParaEntrega()) return;
    _aplicarEnderecoCarretoDoClienteSeVazio();
    if (_pdvCheckoutDireto &&
        PdvBalcaoRapidoHelper.podeCheckoutDireto(
          carrinhoTemCarreto: _carrinhoTemItemCarreto,
          pagamentoMisto: _pagamentoMistoPdV,
          precisaPlanoFiado: _precisaPlanoFiadoPdV(),
          temDescontoInformado: _valorDescontoReaisPdV() > 0.001,
          edicaoOrcamento: _orcamentoEmEdicaoId != null,
        )) {
      final erro = _mensagemErroConfirmarCheckout();
      if (erro != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(erro)));
        return;
      }
      await _salvarOrcamento();
      return;
    }
    final scrollCheckout = ScrollController();
    _checkoutDialogAberto = true;
    _checkoutDialogFocoInicialAplicado = false;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              _checkoutDialogSetState = setDialogState;
              _checkoutDialogFechamentoContext = dialogContext;
              if (!_checkoutDialogFocoInicialAplicado) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_checkoutDialogAberto ||
                      !mounted ||
                      _checkoutDialogFocoInicialAplicado) {
                    return;
                  }
                  _checkoutDialogFocoInicialAplicado = true;
                  _aplicarFocoInicialCheckoutDialog();
                });
              }
              final theme = Theme.of(context);
              final celular = _pdvUiCelular;
              final viewInsets = MediaQuery.viewInsetsOf(context);
              final screen = MediaQuery.sizeOf(context);
              // Dialog amplo no desktop: misto + carreto cabem sem “caixinha”.
              final dialogWidth = celular ? screen.width : 960.0;
              final dialogHeight = celular
                  ? null
                  : (screen.height * 0.88).clamp(560.0, 860.0);
              return Dialog(
                backgroundColor: theme.colorScheme.surface,
                insetPadding: celular
                    ? EdgeInsets.fromLTRB(8, 12, 8, 8 + viewInsets.bottom)
                    : const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(celular ? 10 : 14),
                ),
                child: AdaptiveDialogPane(
                  desktopWidth: dialogWidth,
                  desktopHeight: dialogHeight,
                  mobileHeightFactor: celular ? 0.94 : 0.86,
                  horizontalMargin: celular ? 8 : 28,
                  child: Theme(
                    data: theme.copyWith(
                      visualDensity: VisualDensity.standard,
                      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                        isDense: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCheckoutDialogCabecalho(dialogContext),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            celular ? 14 : 20,
                            14,
                            celular ? 14 : 20,
                            10,
                          ),
                          child: _buildCheckoutResumoFixo(setDialogState),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: celular ? 14 : 20,
                            ),
                            child: Scrollbar(
                              controller: scrollCheckout,
                              thumbVisibility: !celular,
                              interactive: true,
                              child: SingleChildScrollView(
                                controller: scrollCheckout,
                                primary: false,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                  right: 6,
                                  bottom: 12,
                                ),
                                child: FocusTraversalGroup(
                                  policy: OrderedTraversalPolicy(),
                                  child: _buildFormularioFechamentoVenda(
                                    setDialogState: setDialogState,
                                    scrollCheckout: scrollCheckout,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildCheckoutDialogRodape(
                          dialogContext: dialogContext,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _checkoutDialogAberto = false;
      _checkoutDialogFocoInicialAplicado = false;
      _checkoutDialogSetState = null;
      _checkoutDialogFechamentoContext = null;
      scrollCheckout.dispose();
      if (mounted && !_salvandoOrcamento && !_dialogoOrcamentoSalvoAberto) {
        _aplicarFocoInicialPdv();
      }
    }
  }

  /// Atualiza estado do checkout e redesenha apenas o dialog (StatefulBuilder).
  void _atualizarCheckoutFechamento(
    StateSetter setDialogState,
    VoidCallback fn, {
    ScrollController? scrollCheckout,
  }) {
    fn();
    setDialogState(() {});
    if (scrollCheckout != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollCheckout.hasClients) return;
        final max = scrollCheckout.position.maxScrollExtent;
        if (scrollCheckout.offset > max) {
          scrollCheckout.jumpTo(max);
        }
      });
    }
  }

  Widget _buildCheckoutBannerEdicao(StateSetter setDialogState) {
    if (_orcamentoEmEdicaoId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Editando venda ${_orcamentoEmEdicaoNumero ?? '-'}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () {
              _atualizarCheckoutFechamento(setDialogState, () {
                _orcamentoEmEdicaoId = null;
                _orcamentoEmEdicaoNumero = null;
              });
            },
            child: const Text('Cancelar edicao'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutResumoLinhaItens() {
    final theme = Theme.of(context);
    return Text(
      '${_carrinho.length} ${_carrinho.length == 1 ? 'item' : 'itens'}'
      '${_resumoEntregaItensCarrinho.isNotEmpty ? ' · $_resumoEntregaItensCarrinho' : ''}',
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildCheckoutPainelFiado(StateSetter setDialogState) {
    if (!_precisaPlanoFiadoPdV()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanoFiadoPdvPanel(
            key: ValueKey(_valorFiadoCheckoutPdV().toStringAsFixed(2)),
            valorFiado: _valorFiadoCheckoutPdV(),
            parcelasIniciais: _planoFiadoParcelas,
            onChanged: (parcelas) {
              _atualizarCheckoutFechamento(
                setDialogState,
                () => _planoFiadoParcelas = parcelas,
              );
            },
          ),
          _buildResumoLimiteCreditoCheckoutPdV(),
        ],
      ),
    );
  }

  Widget _buildCheckoutSecaoPagamento({
    required StateSetter setDialogState,
    ScrollController? scrollCheckout,
  }) {
    return _buildSecaoCheckoutDialog(
      titulo: 'Pagamento',
      icone: Icons.payments_outlined,
      children: [
        Focus(
          focusNode: _focusPagamentoMistoSwitchPdV,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _pagamentoMistoPdV,
            onChanged: (on) {
              if (on == _pagamentoMistoPdV) return;
              _atualizarCheckoutFechamento(setDialogState, () {
                _pagamentoMistoPdV = on;
                if (on) {
                  _inicializarLinhasMistoPadrao();
                } else {
                  _disposeLinhasPagamentoMisto();
                }
              }, scrollCheckout: scrollCheckout);
            },
            title: Row(
              children: [
                const Expanded(child: Text('Dividir pagamento (misto)')),
                if (_pagamentoMistoPdV)
                  Chip(
                    label: const Text('Ativo'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            subtitle: Text(
              _pagamentoMistoPdV
                  ? 'Combine dinheiro, PIX, cartoes e fiado na mesma venda'
                  : 'Libera todos os meios na mesma venda (F6)',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (_pagamentoMistoPdV) ...[
          const SizedBox(height: 4),
          _buildPainelPagamentoMistoPdV(setDialogState),
        ] else ...[
          const SizedBox(height: 4),
          _buildChipsFormaPagamentoCheckout(
            setDialogState,
            exibirTituloSecao: false,
          ),
        ],
      ],
    );
  }

  Widget _buildCheckoutSecaoDesconto(StateSetter setDialogState) {
    if (_maxDescontoPercentualPdv <= 0) return const SizedBox.shrink();
    return _buildSecaoCheckoutDialog(
      titulo: 'Desconto (F3)',
      icone: Icons.discount_outlined,
      children: [_buildCheckoutCampoDesconto(setDialogState)],
    );
  }

  Widget _buildCheckoutSecaoEntrega({
    required StateSetter setDialogState,
    ScrollController? scrollCheckout,
  }) {
    return _buildSecaoCheckoutDialog(
      titulo: 'Entrega',
      icone: Icons.local_shipping_outlined,
      children: [
        Text(
          _resumoEntregaItensCarrinho.isEmpty
              ? 'Sem itens com entrega definida'
              : _resumoEntregaItensCarrinho,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (_carrinhoEntregaMista) ...[
          const SizedBox(height: 4),
          Text(
            'Venda com tipos de entrega mistos',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_carrinhoTemItemCarreto) ...[
          const SizedBox(height: 10),
          const SizedBox(height: 8),
          if (_clienteSelecionado() != null &&
              _enderecosClienteSelecionado().isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _indiceEnderecoSelecionado.clamp(
                0,
                _enderecosClienteSelecionado().length - 1,
              ),
              decoration: const InputDecoration(
                labelText: 'Endereco para entrega',
              ),
              selectedItemBuilder: (context) {
                final enderecos = _enderecosClienteSelecionado();
                return List.generate(enderecos.length, (index) {
                  final endereco = enderecos[index];
                  final rotulo = endereco.tituloExibicao();
                  final resumo = endereco.resumo();
                  final texto = resumo.isEmpty ? rotulo : '$rotulo — $resumo';
                  return Tooltip(
                    message: texto,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        texto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  );
                });
              },
              items: List.generate(_enderecosClienteSelecionado().length, (
                index,
              ) {
                final endereco = _enderecosClienteSelecionado()[index];
                final rotulo = endereco.tituloExibicao();
                final resumo = endereco.resumo();
                return DropdownMenuItem<int>(
                  value: index,
                  child: Text(
                    resumo.isEmpty ? rotulo : '$rotulo — $resumo',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                );
              }),
              onChanged: (value) {
                if (value == null) return;
                final cliente = _clienteSelecionado();
                if (cliente == null) return;
                _atualizarCheckoutFechamento(setDialogState, () {
                  _aplicarEnderecoSelecionadoDoCliente(cliente, value);
                });
              },
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _prioridadeEntregaSelecionada,
                  decoration: const InputDecoration(
                    labelText: 'Prioridade da entrega',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                    DropdownMenuItem(
                      value: 'agendada',
                      child: Text('Agendada'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _atualizarCheckoutFechamento(setDialogState, () {
                      _prioridadeEntregaSelecionada = value;
                      if (_prioridadeEntregaSelecionada == 'agendada' &&
                          _janelaEntregaSelecionada == 'nao_definida') {
                        _janelaEntregaSelecionada = 'manha';
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _janelaEntregaSelecionada,
                  decoration: const InputDecoration(labelText: 'Janela'),
                  items: const [
                    DropdownMenuItem(
                      value: 'nao_definida',
                      child: Text('Nao definida'),
                    ),
                    DropdownMenuItem(value: 'manha', child: Text('Manha')),
                    DropdownMenuItem(value: 'tarde', child: Text('Tarde')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _atualizarCheckoutFechamento(
                      setDialogState,
                      () => _janelaEntregaSelecionada = value,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final agora = DateTime.now();
                final inicial = _dataEntregaMarcada ?? agora;
                final escolhido = await mostrarAgendaCarretoPdvDialog(
                  context: context,
                  vendaRepository: widget.vendaRepository,
                  dataInicial: inicial,
                  firstDate: DateTime(agora.year, agora.month, agora.day),
                  lastDate: DateTime(agora.year + 3, 12, 31),
                );
                if (!mounted || escolhido == null) return;
                _atualizarCheckoutFechamento(setDialogState, () {
                  _dataEntregaMarcada = escolhido;
                  _entregaSemDataCombinada = false;
                });
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                _dataEntregaMarcada == null
                    ? 'Agenda de carretos — definir data'
                    : 'Data da entrega: ${DateFormat('dd/MM/yyyy').format(_dataEntregaMarcada!)}',
              ),
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              _atualizarCheckoutFechamento(setDialogState, () {
                _entregaSemDataCombinada = !_entregaSemDataCombinada;
                if (_entregaSemDataCombinada) {
                  _dataEntregaMarcada = null;
                }
              });
            },
            child: Row(
              children: [
                SizedBox(
                  height: 28,
                  width: 28,
                  child: Checkbox(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: _entregaSemDataCombinada,
                    onChanged: (v) {
                      _atualizarCheckoutFechamento(setDialogState, () {
                        _entregaSemDataCombinada = v == true;
                        if (_entregaSemDataCombinada) {
                          _dataEntregaMarcada = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Cliente ainda não definiu a data',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entrega configurada',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _resumoEntrega(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Focus(
                    focusNode: _focusEditarEntregaPdV,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final cliente = _clienteSelecionado();
                        if (cliente == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Selecione um cliente para editar a entrega.',
                              ),
                            ),
                          );
                          return;
                        }
                        final entrega = await _abrirDialogEntregaCliente(
                          cliente: cliente,
                        );
                        if (!mounted || entrega == null) return;
                        _atualizarCheckoutFechamento(setDialogState, () {
                          // Nunca sobrescrever tipos por linha em carrinho misto.
                          // Homogeneo sem carreto: ao editar entrega, assume carreto.
                          final tiposNoCarrinho = _carrinho
                              .map(
                                (e) => EntregaVendaHelper.normalizarTipoItem(
                                  e.tipoEntregaItem,
                                ),
                              )
                              .toSet();
                          final carrinhoMisto = tiposNoCarrinho.length > 1;
                          if (!carrinhoMisto && !_carrinhoTemItemCarreto) {
                            _atualizarEntregaCarrinhoComTipo(
                              EntregaVendaHelper.tipoEntregaLoja,
                            );
                          }
                          if (!_entregaSemDataCombinada) {
                            _dataEntregaMarcada ??= DateTime.now();
                          }
                          _valorFreteController.text = entrega.valorFrete;
                          _enderecoEntregaController.text = entrega.endereco;
                          _observacaoEntregaController.text =
                              entrega.observacao;
                          _indiceEnderecoSelecionado =
                              entrega.indiceEnderecoSelecionado;
                        });
                        if (_carrinhoEntregaMista && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Endereco/frete atualizados. Tipos por linha '
                                'preservados (venda mista).',
                              ),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar dados da entrega'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  double _valorEntraCaixaAgoraPdV() {
    final total = _totalLiquidoPagamentoPdV();
    final fiado = _valorFiadoCheckoutPdV();
    return (total - fiado).clamp(0.0, double.infinity).toDouble();
  }

  Widget _buildSecaoCheckoutDialog({
    required String titulo,
    required IconData icone,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCheckoutResumoFixo(StateSetter setDialogState) {
    final theme = Theme.of(context);
    final total = _totalLiquidoPagamentoPdV();
    final fiado = _valorFiadoCheckoutPdV();
    final agora = _valorEntraCaixaAgoraPdV();
    final desconto = _valorDescontoReaisPdV();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total a pagar (caixa)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            _formatarMoeda(total),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Subtotal ${_formatarMoeda(_totalOrcamento)} · '
            'Frete ${_formatarMoeda(_valorFreteAtual)}'
            '${desconto > 0.004 ? ' · Desconto -${_formatarMoeda(desconto)}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          if (fiado > 0.001) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _chipResumoCheckout(
                    rotulo: 'No caixa agora',
                    valor: agora,
                    destaque: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _chipResumoCheckout(
                    rotulo: 'Fiado (a receber)',
                    valor: fiado,
                    destaque: false,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipResumoCheckout({
    required String rotulo,
    required double valor,
    required bool destaque,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: destaque
            ? theme.colorScheme.surface
            : theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: theme.textTheme.labelSmall),
          Text(
            _formatarMoeda(valor),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutCampoDesconto(StateSetter setDialogState) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'percentual', label: Text('%')),
              ButtonSegment<String>(value: 'valor', label: Text('R\$')),
            ],
            selected: {_tipoDescontoPdV},
            onSelectionChanged: (values) {
              _atualizarCheckoutFechamento(setDialogState, () {
                _tipoDescontoPdV = values.first;
                _descontoPdVController.clear();
                _resetarAutorizacaoDescontoAcimaTetoPdV();
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                focusNode: _focusDescontoPdV,
                controller: _descontoPdVController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _tipoDescontoPdV == 'percentual'
                      ? 'Desconto %'
                      : 'Desconto R\$',
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.92),
                  helperText: _descontoAcimaTetoAutorizadoPdv
                      ? 'Autorizado por $_descontoAutorizadoPorPdV'
                      : (_descontoPdVUltrapassaTetoSemAutorizacao()
                            ? 'Autorize um gerente para concluir'
                            : 'F3 · Max. ${_percentualMaximoEfetivoDescontoPdV().toStringAsFixed(1)}% '
                                  '(${_formatarMoeda(_valorMaximoDescontoReaisPdV())})'),
                  errorText: _descontoPdVUltrapassaTetoSemAutorizacao()
                      ? _mensagemErroDescontoPdVUltrapassaTeto()
                      : null,
                  isDense: true,
                ),
                onChanged: (_) =>
                    _atualizarCheckoutFechamento(setDialogState, () {
                      _resetarAutorizacaoDescontoAcimaTetoPdV();
                    }),
              ),
              if (_descontoPdVUltrapassaTetoSemAutorizacao())
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final ok =
                          await _solicitarAutorizacaoDescontoAcimaTetoPdV();
                      if (ok) setDialogState(() {});
                    },
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: const Text('Autorizar gerente'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormularioFechamentoVenda({
    required StateSetter setDialogState,
    ScrollController? scrollCheckout,
  }) {
    final theme = Theme.of(context);
    final duasColunas =
        !_pdvUiCelular &&
        MediaQuery.sizeOf(context).width >= 980 &&
        _checkoutExibeSecaoEntrega;

    final colunaPagamento = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!duasColunas) ...[
          _buildCheckoutBannerEdicao(setDialogState),
          _buildCheckoutResumoLinhaItens(),
          const SizedBox(height: 10),
        ],
        _buildCheckoutSecaoPagamento(
          setDialogState: setDialogState,
          scrollCheckout: scrollCheckout,
        ),
        _buildCheckoutPainelFiado(setDialogState),
        if (_precisaPlanoFiadoPdV() &&
            (_clienteSelecionadoId == null || _clienteSelecionadoId! <= 0)) ...[
          const SizedBox(height: 8),
          Text(
            'Fiado: selecione o cliente no topo da tela (Shift+F2).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        _buildCheckoutSecaoDesconto(setDialogState),
      ],
    );

    final colunaEntrega = _checkoutExibeSecaoEntrega
        ? _buildCheckoutSecaoEntrega(
            setDialogState: setDialogState,
            scrollCheckout: scrollCheckout,
          )
        : const SizedBox.shrink();

    if (duasColunas) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCheckoutBannerEdicao(setDialogState),
          _buildCheckoutResumoLinhaItens(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: colunaPagamento),
              const SizedBox(width: 16),
              Expanded(flex: 10, child: colunaEntrega),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        colunaPagamento,
        if (_checkoutExibeSecaoEntrega) colunaEntrega,
      ],
    );
  }

  Future<bool> _validarLimiteCreditoPdV({
    required int? clienteId,
    required double valorFiado,
  }) async {
    if (valorFiado <= 0.001) return true;
    if (clienteId == null || clienteId <= 0) return true;

    late final dynamic r;
    try {
      if (widget.vendaRepository is VendaApiRepository) {
        r = await (widget.vendaRepository as VendaApiRepository)
            .validarLimiteCreditoRemoto(
          clienteId: clienteId,
          valorFiadoOperacao: valorFiado,
          ignorarVendaId: _orcamentoEmEdicaoId,
        );
      } else {
        r = widget.vendaRepository.validarLimiteCredito(
          clienteId: clienteId,
          valorFiadoOperacao: valorFiado,
          ignorarVendaId: _orcamentoEmEdicaoId,
        );
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Falha ao validar limite de credito: ${LanApiFeedback.mensagem(e)}',
          ),
        ),
      );
      return false;
    }
    if (r.permitido) return true;
    if (!mounted) return false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limite de credito'),
        content: Text(r.mensagem ?? 'Limite de credito excedido.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    return false;
  }

  Widget _buildResumoLimiteCreditoCheckoutPdV() {
    if (!_precisaPlanoFiadoPdV()) return const SizedBox.shrink();
    final clienteId = _clienteSelecionadoId;
    if (clienteId == null || clienteId <= 0) {
      return const SizedBox.shrink();
    }

    final valorFiado = _valorFiadoCheckoutPdV();
    final theme = Theme.of(context);

    if (widget.vendaRepository is VendaApiRepository) {
      final api = widget.vendaRepository as VendaApiRepository;
      return FutureBuilder<ValidacaoLimiteCredito>(
        key: ValueKey('limite-$clienteId-$valorFiado-$_orcamentoEmEdicaoId'),
        future: api.validarLimiteCreditoRemoto(
          clienteId: clienteId,
          valorFiadoOperacao: valorFiado,
          ignorarVendaId: _orcamentoEmEdicaoId,
        ),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.only(top: 6),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final r = snap.data!;
          final saldoAberto = r.saldoEmAberto;
          final limite = r.limite > 0
              ? r.limite
              : (widget.clienteRepository.obterPorId(clienteId)?.limiteCredito ??
                  0);
          if (limite <= 0) return const SizedBox.shrink();
          final disponivelAgora =
              (limite - saldoAberto).clamp(0.0, double.infinity).toDouble();
          if (r.permitido) {
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Credito: fiado em aberto ${LimiteCreditoHelper.formatarMoedaBr(saldoAberto)} '
                '· limite ${LimiteCreditoHelper.formatarMoedaBr(limite)} '
                '· disponivel ${LimiteCreditoHelper.formatarMoedaBr(disponivelAgora)} '
                '(fiado desta venda: ${LimiteCreditoHelper.formatarMoedaBr(valorFiado)})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.error),
            ),
            child: Text(
              r.mensagem ?? 'Limite de credito excedido.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      );
    }

    final saldoAberto = widget.vendaRepository.saldoFiadoEmAbertoCliente(
      clienteId,
      ignorarVendaId: _orcamentoEmEdicaoId,
    );
    final cliente = widget.clienteRepository.obterPorId(clienteId);
    final limite = cliente?.limiteCredito ?? 0;
    if (limite <= 0) return const SizedBox.shrink();

    final disponivelAgora = (limite - saldoAberto)
        .clamp(0.0, double.infinity)
        .toDouble();
    final r = widget.vendaRepository.validarLimiteCredito(
      clienteId: clienteId,
      valorFiadoOperacao: valorFiado,
      ignorarVendaId: _orcamentoEmEdicaoId,
    );

    if (r.permitido) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Credito: fiado em aberto ${LimiteCreditoHelper.formatarMoedaBr(saldoAberto)} '
          '· limite ${LimiteCreditoHelper.formatarMoedaBr(limite)} '
          '· disponivel ${LimiteCreditoHelper.formatarMoedaBr(disponivelAgora)} '
          '(fiado desta venda: ${LimiteCreditoHelper.formatarMoedaBr(valorFiado)})',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Text(
        r.mensagem ?? 'Limite de credito excedido.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  bool _validarClienteParaFiadoPdV({
    required int? clienteId,
    required DadosPagamentoOrcamento pagamento,
    required double totalVendaLiquido,
  }) {
    final valorFiado = LimiteCreditoHelper.valorFiadoNoPagamento(
      formaPagamento: pagamento.formaPagamento,
      totalVendaLiquido: totalVendaLiquido,
      linhasMisto: pagamento.linhasMisto,
    );
    if (valorFiado <= 0.001) return true;
    if (clienteId != null && clienteId > 0) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Vincule um cliente ao orcamento para usar pagamento fiado.',
        ),
      ),
    );
    return false;
  }

  /// Limpa a tela para a proxima venda (vendedor, cliente, carrinho, busca).
  Future<void> _prepararNovaVendaAposEnvioCaixa({
    int? numeroOrcamentoSalvo,
    double? totalOrcamentoSalvo,
  }) async {
    final bloquearVendedorAposEnvio =
        _pdvBloqueioVendedor && _pdvBloqueioVendedorAposOrcamento;
    _registrarIgnoradosFaixaCarrinho();
    setState(() {
      if (numeroOrcamentoSalvo != null && numeroOrcamentoSalvo > 0) {
        _ultimoOrcamentoSalvoNumero = numeroOrcamentoSalvo;
        _ultimoOrcamentoSalvoTotal = totalOrcamentoSalvo;
      }
      _carrinho.clear();
      _carrinhoSessaoId = '';
      _indiceLinhaCarrinho = null;
      _sugestoesCarrinhoVisiveis = const [];
      _sugestoesCarrinhoOrigemNome = '';
      _sugestoesCarrinhoOrigemId = null;
      _sugestoesCarrinhoAceitasIds.clear();
      _pagamentoMistoPdV = false;
      _disposeLinhasPagamentoMisto();
      _formaPagamentoSelecionada = 'dinheiro';
      _parcelasSelecionadas = 1;
      _planoFiadoParcelas = [];
      _clienteSelecionadoId = null;
      _indiceEnderecoSelecionado = 0;
      if (!_pdvBloqueioVendedor || bloquearVendedorAposEnvio) {
        _vendedorSelecionadoId = null;
      }
      _tipoEntregaSelecionada = EntregaVendaHelper.tipoRetirada;
      _prioridadeEntregaSelecionada = 'normal';
      _janelaEntregaSelecionada = 'nao_definida';
      _dataEntregaMarcada = null;
      _entregaSemDataCombinada = false;
      _valorFreteController.clear();
      _enderecoEntregaController.clear();
      _observacaoEntregaController.clear();
      _orcamentoEmEdicaoId = null;
      _orcamentoEmEdicaoNumero = null;
      _idempotencyKeyOrcamentoPendente = null;
      _descontoPdVController.clear();
      _tipoDescontoPdV = 'percentual';
      _resetarAutorizacaoDescontoAcimaTetoPdV();
      _pesquisaController.clear();
      _precoListaAtivo = _precoListaPadraoPdv;
    });
    _sincronizarTextoBuscaClientePdv();
    if (bloquearVendedorAposEnvio) {
      _timerInatividadeVendedorPdv?.cancel();
      await _solicitarIdentificacaoVendedorPdvBloqueio(
        permitirCancelar: false,
        sairDoPdvSeCancelar: false,
      );
      return;
    }
    _aplicarFocoInicialPdv();
    _registrarAtividadePdvVendedor();
  }

  Future<void> _salvarOrcamento({BuildContext? fechamentoDialogContext}) async {
    if (_salvandoOrcamento) return;
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item na venda.')),
      );
      return;
    }
    if (!await _garantirVendedorPdvObrigatorio()) return;
    if (_pdvExigeClientePorEntrega && _pdvClienteAusente) {
      if (!mounted) return;
      final motivo = _motivoClienteObrigatorioPdv;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${motivo[0].toUpperCase()}${motivo.substring(1)}: '
            'selecione ou cadastre o cliente no topo da tela.',
          ),
        ),
      );
      await _abrirSeletorClienteNoPdv(
        permitirSemCliente: false,
        motivoObrigatorio: motivo,
      );
      if (_pdvClienteAusente) return;
    }
    if (_descontoPdVUltrapassaTetoSemAutorizacao()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensagemErroDescontoPdVUltrapassaTeto())),
      );
      return;
    }
    _salvandoOrcamento = true;
    _overlaySalvandoOrcamento = true;
    if (mounted) setState(() {});
    var salvouOk = false;
    Venda? vendaSalvaPos;
    int? numeroOrcamentoSalvoPos;
    try {
      final valorFrete = _carrinhoTemItemCarreto
          ? _parseValorMonetario(_valorFreteController.text)
          : 0.0;
      if (_carrinhoTemItemCarreto &&
          _enderecoEntregaController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o endereco para carreto.')),
        );
        return;
      }
      if (_carrinhoTemItemCarreto &&
          _prioridadeEntregaSelecionada == 'agendada' &&
          _janelaEntregaSelecionada == 'nao_definida') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Para entrega agendada, selecione janela Manha ou Tarde.',
            ),
          ),
        );
        return;
      }
      if (_carrinhoTemItemCarreto &&
          _dataEntregaMarcada == null &&
          !_entregaSemDataCombinada) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Defina a data da entrega ou marque que o cliente ainda não definiu.',
            ),
          ),
        );
        return;
      }
      if (valorFrete < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Valor do frete nao pode ser negativo.'),
          ),
        );
        return;
      }
      if (_carrinhoTemItemCarreto && valorFrete <= 0) {
        if (!mounted) return;
        final aceitaGratis = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Frete zerado'),
            content: const Text(
              'Carreto com frete em R\$ 0,00. Confirma registrar entrega com frete gratuito, '
              'ou volte para informar o valor correto?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Informar frete'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Frete gratuito'),
              ),
            ],
          ),
        );
        if (aceitaGratis != true) {
          return;
        }
      }
      final itens = _carrinho
          .map(
            (item) => ItemVendaInput(
              produtoId: item.produto.id,
              quantidade: item.quantidadeParaPersistir,
              precoUnitario: item.precoUnitario,
              precoTipo: item.precoTipo,
              tipoEntregaItem: item.tipoEntregaItem,
              promocaoId: item.promocaoId,
              promocaoNomeSnapshot: item.promocaoNome,
              precoUnitarioManual: item.precoUnitarioManual,
              botaForaAplicado: item.botaForaAplicado,
              percentualBotaForaAplicado: item.percentualBotaForaAplicado,
            ),
          )
          .toList();
      List<PagamentoOrcamentoLinha>? linhasMisto;
      try {
        linhasMisto = _montarLinhasMistoParaSalvar(_totalLiquidoPagamentoPdV());
      } on StateError catch (e) {
        if (!mounted) return;
        _pdvErro(e.message);
        return;
      }
      var pagamento = DadosPagamentoOrcamento(
        formaPagamento: _pagamentoMistoPdV
            ? 'misto'
            : _formaPagamentoSelecionada,
        quantidadeParcelas: _pagamentoMistoPdV
            ? 1
            : (_formaPagamentoSelecionada == 'cartao_credito'
                  ? _parcelasSelecionadas
                  : 1),
        linhasMisto: linhasMisto,
      );
      final totalLiquido = _totalLiquidoPagamentoPdV();
      if (!_validarClienteParaFiadoPdV(
        clienteId: _clienteSelecionadoId,
        pagamento: pagamento,
        totalVendaLiquido: totalLiquido,
      )) {
        return;
      }
      final valorFiado = LimiteCreditoHelper.valorFiadoNoPagamento(
        formaPagamento: pagamento.formaPagamento,
        totalVendaLiquido: totalLiquido,
        linhasMisto: linhasMisto,
      );
      if (valorFiado > 0.001 &&
          !PlanoFiadoCodec.validarContraValor(
            _planoFiadoParcelas,
            valorFiado,
          )) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Defina o plano de parcelas do fiado (valores e vencimentos) '
              'antes de salvar o orçamento.',
            ),
          ),
        );
        return;
      }
      if (!await _validarLimiteCreditoPdV(
        clienteId: _clienteSelecionadoId,
        valorFiado: valorFiado,
      )) {
        return;
      }
      pagamento = DadosPagamentoOrcamento(
        formaPagamento: pagamento.formaPagamento,
        quantidadeParcelas: pagamento.quantidadeParcelas,
        linhasMisto: pagamento.linhasMisto,
        planoFiado: valorFiado > 0.001 ? List.from(_planoFiadoParcelas) : null,
      );
      final entrega = DadosEntregaOrcamento(
        tipoEntrega: _resolverTipoEntregaVendaCarrinho(),
        valorFrete: valorFrete,
        enderecoEntrega: _enderecoEntregaController.text.trim(),
        observacaoEntrega: _observacaoEntregaController.text.trim(),
        prioridadeEntrega: _carrinhoTemItemCarreto
            ? _prioridadeEntregaSelecionada
            : 'normal',
        janelaEntrega: _carrinhoTemItemCarreto
            ? _janelaEntregaSelecionada
            : 'nao_definida',
        dataEntregaMarcada: _carrinhoTemItemCarreto
            ? _dataEntregaMarcada
            : null,
      );
      final orcamentoEdicaoId = _orcamentoEmEdicaoId;
      int orcamentoId;
      final descontoPdV = _valorDescontoReaisPdV();
      if (orcamentoEdicaoId != null) {
        if (widget.vendaRepository is VendaApiRepository) {
          await (widget.vendaRepository as VendaApiRepository)
              .atualizarOrcamentoRemoto(
                orcamentoEdicaoId,
                itens,
                pagamento: pagamento,
                entrega: entrega,
                clienteId: _clienteSelecionadoId,
                vendedorId: _vendedorSelecionadoId,
                descontoEmReais: descontoPdV,
                permitirVendaSemEstoque: _permitirVendaSemEstoque,
              );
        } else {
          widget.vendaRepository.atualizarOrcamento(
            orcamentoEdicaoId,
            itens,
            pagamento: pagamento,
            entrega: entrega,
            clienteId: _clienteSelecionadoId,
            vendedorId: _vendedorSelecionadoId,
            descontoEmReais: descontoPdV,
            permitirVendaSemEstoque: _permitirVendaSemEstoque,
          );
        }
        orcamentoId = orcamentoEdicaoId;
      } else if (widget.vendaRepository is VendaApiRepository) {
        _idempotencyKeyOrcamentoPendente ??= gerarUuidV4();
        final chave = _idempotencyKeyOrcamentoPendente!;
        Future<int> enviar() =>
            (widget.vendaRepository as VendaApiRepository)
                .registrarOrcamentoRemoto(
                  itens,
                  pagamento: pagamento,
                  entrega: entrega,
                  clienteId: _clienteSelecionadoId,
                  vendedorId: _vendedorSelecionadoId,
                  descontoEmReais: descontoPdV,
                  permitirVendaSemEstoque: _permitirVendaSemEstoque,
                  uuidLocal: chave,
                );
        try {
          orcamentoId = await enviar();
        } catch (e) {
          // Retry automatico 1x com a MESMA chave apos timeout/rede.
          if (!_ehTimeoutSalvarOrcamento(e)) rethrow;
          orcamentoId = await enviar();
        }
        _idempotencyKeyOrcamentoPendente = null;
      } else {
        _idempotencyKeyOrcamentoPendente ??= gerarUuidV4();
        orcamentoId = widget.vendaRepository.registrarOrcamento(
          itens,
          pagamento: pagamento,
          entrega: entrega,
          clienteId: _clienteSelecionadoId,
          vendedorId: _vendedorSelecionadoId,
          descontoEmReais: descontoPdV,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
          uuidLocal: _idempotencyKeyOrcamentoPendente,
        );
        _idempotencyKeyOrcamentoPendente = null;
      }
      if (widget.vendaRepository is! VendaApiRepository) {
        await LanSyncScheduler.solicitarSyncPrioritario();
      }
      if (!mounted) return;
      // Apos o PUSH, o servidor pode ter remapeado o id e/ou renumerado o
      // orcamento (ACK numeroCorrections). Nunca confiar so no id local.
      var vendaSalva = widget.vendaRepository.obterPorId(orcamentoId);
      if (vendaSalva == null) {
        final globalId = SyncService.globalIdVendaAposPush(orcamentoId);
        if (globalId != null && globalId > 0) {
          vendaSalva = widget.vendaRepository.obterPorId(globalId);
        }
      }
      final numeroOrcamentoSalvo =
          vendaSalva?.numeroOrcamento ?? _orcamentoEmEdicaoNumero;
      if (fechamentoDialogContext != null && fechamentoDialogContext.mounted) {
        Navigator.of(fechamentoDialogContext).pop();
      }
      if (!mounted) return;
      final resumoEntrega = _carrinho.isEmpty
          ? ''
          : EntregaVendaHelper.resumoContagem(
              _carrinho.map((e) => e.tipoEntregaItem),
            );
      final temFutura = _carrinho.any(
        (e) =>
            EntregaVendaHelper.normalizarTipoItem(e.tipoEntregaItem) ==
            EntregaVendaHelper.tipoRetiradaFutura,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orcamentoEdicaoId != null
                ? 'Orçamento $numeroOrcamentoSalvo atualizado'
                      '${resumoEntrega.isEmpty ? '' : ' ($resumoEntrega)'}.'
                : 'Orçamento $numeroOrcamentoSalvo salvo'
                      '${resumoEntrega.isEmpty ? '' : ' ($resumoEntrega)'}'
                      ' — finalize no caixa'
                      '${temFutura ? ' para reservar estoque' : ''}.',
          ),
          duration: Duration(seconds: temFutura ? 5 : 3),
        ),
      );
      // Libera o overlay ANTES de imprimir/PDF — senao o "Processando
      // orcamento..." volta a cobrir a tela apos fechar o dialogo de acoes.
      vendaSalvaPos = vendaSalva;
      numeroOrcamentoSalvoPos = numeroOrcamentoSalvo;
      salvouOk = true;
      _overlaySalvandoOrcamento = false;
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      if (_ehTimeoutSalvarOrcamento(e)) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Aguardando servidor'),
            content: const Text(
              'Aguardando resposta do servidor. Nao feche a tela.\n\n'
              'Se tentar de novo, o sistema reusa a mesma chave e nao cria '
              'orcamento duplicado. Se o orcamento ja aparecer no caixa, '
              'nao salve de novo.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      } else {
        _pdvErro(
          'Erro ao salvar orçamento: ${LanApiFeedback.mensagem(e)}',
        );
      }
    } finally {
      _overlaySalvandoOrcamento = false;
      if (!salvouOk) {
        _salvandoOrcamento = false;
      }
      if (mounted) setState(() {});
    }

    if (!salvouOk || !mounted) return;
    try {
      final vendaSalva = vendaSalvaPos;
      if (vendaSalva != null) {
        await _mostrarAcoesPdfOrcamento(vendaSalva);
      }
      if (!mounted) return;
      await _prepararNovaVendaAposEnvioCaixa(
        numeroOrcamentoSalvo: numeroOrcamentoSalvoPos,
        totalOrcamentoSalvo: vendaSalva?.total,
      );
    } finally {
      _salvandoOrcamento = false;
      if (mounted) setState(() {});
    }
  }

  bool _ehTimeoutSalvarOrcamento(Object e) {
    if (e is TimeoutException) return true;
    final m = LanApiFeedback.mensagem(e).toLowerCase();
    return m.contains('tempo esgotado') ||
        m.contains('timeout') ||
        m.contains('timed out');
  }

  Future<bool> _confirmarSubstituirRascunhoAtual() async {
    if (_carrinho.isEmpty) {
      return true;
    }
    final resposta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Carregar outro orcamento'),
        content: const Text(
          'Existe um orcamento em edicao na tela. Deseja descartar este rascunho e carregar outro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Carregar'),
          ),
        ],
      ),
    );
    return resposta == true;
  }

  String _rotuloVendedorUmLinhaOrcamento(Venda venda) {
    final vendedor = _vendedorDaVenda(venda);
    if (vendedor == null) {
      return 'Sem vendedor';
    }
    final nome = vendedor.apelido.trim().isNotEmpty
        ? vendedor.apelido.trim()
        : vendedor.nomeCompleto.trim();
    final codigo = vendedor.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  String _normalizarTextoComparacao(String texto) {
    var t = texto.trim().toLowerCase();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    mapa.forEach((origem, destino) {
      t = t.replaceAll(origem, destino);
    });
    t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return t;
  }

  Produto? _resolverProdutoItemOrcamento(ItemVenda item) {
    // Nao ler .target sem try em entidade detached (Terminal Leve).
    try {
      final porTarget = item.produto.target;
      if (porTarget != null) return porTarget;
    } catch (_) {}
    final produtoId = item.produto.targetId;
    if (produtoId > 0) {
      final porId = widget.produtoRepository.obterPorId(produtoId) as Produto?;
      if (porId != null) return porId;
    }

    final nomeItem = _normalizarTextoComparacao(item.nomeProduto);
    if (nomeItem.isEmpty) {
      return null;
    }

    final candidatos =
        (widget.produtoRepository.pesquisar(
              item.nomeProduto,
              limite: 12,
              somenteAtivos: false,
              excluirProdutosInternos: false,
            )
            as List)
            .cast<Produto>();
    final exato = candidatos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome == nomeItem;
    }).firstOrNull;
    if (exato != null) {
      return exato;
    }

    return candidatos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome.contains(nomeItem) || nomeItem.contains(nome);
    }).firstOrNull;
  }

  /// Itens do orcamento sem depender de ToMany detached (Terminal Leve).
  List<ItemVenda> _itensOrcamentoParaEdicao(Venda orc) {
    final repo = widget.vendaRepository;
    if (repo is VendaRepository) {
      try {
        final via = repo.listarItensDaVendaGarantidos(orc.id);
        if (via.isNotEmpty) return List<ItemVenda>.from(via);
      } catch (_) {}
    }
    try {
      final viaRepo = repo.listarItensPorVenda(orc.id);
      if (viaRepo is List && viaRepo.isNotEmpty) {
        return List<ItemVenda>.from(viaRepo);
      }
    } catch (_) {}
    try {
      final anexos = LanApiClient.itensExtraidos[orc];
      if (anexos != null && anexos.isNotEmpty) {
        return List<ItemVenda>.from(anexos);
      }
    } catch (_) {}
    try {
      final locais = orc.itens;
      if (locais.isNotEmpty) {
        return List<ItemVenda>.from(locais);
      }
    } catch (_) {}
    return const [];
  }

  /// Quantidade de itens sem depender de ToMany ObjectBox (Terminal Leve).
  int _qtdItensOrcamentoSafe(Venda orc) {
    return _itensOrcamentoParaEdicao(orc).length;
  }

  Future<void> _abrirLeitorOrcamento() async {
    final podeSubstituir = await _confirmarSubstituirRascunhoAtual();
    if (!mounted || !podeSubstituir) {
      return;
    }

    // Terminal Leve: rehidrata orcamentos do PC servidor (cache pode estar vazio/stale).
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      if (LanApiEventHub.instance.deveBloquearOperacoes) {
        LanApiFeedback.snackAviso(
          context,
          LanApiEventHub.msgServidorOffline,
          prefixo: 'Ler orcamento',
        );
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
      try {
        await repo.hidratarOrcamentos(limit: 120);
      } catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        LanApiFeedback.snackErro(context, e, prefixo: 'Ler orcamento');
        return;
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
    }

    final pendentes = List<Venda>.from(
      widget.vendaRepository.listarOrcamentosPendentes(),
    );
    if (pendentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha orcamentos pendentes para leitura.'),
        ),
      );
      return;
    }

    final pesquisaController = TextEditingController();
    List<Venda> resultados = List<Venda>.from(pendentes);
    final selecionado = await showDialog<Venda>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ler orcamento'),
              content: AdaptiveDialogPane(
                desktopWidth: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Numero, cliente, vendedor...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim().toLowerCase();
                        setDialogState(() {
                          resultados = pendentes.where((orc) {
                            final cliente =
                                _clienteDaVenda(orc)?.nomeRazao ?? '';
                            final vendedor = _rotuloVendedorUmLinhaOrcamento(
                              orc,
                            );
                            return orc.numeroOrcamento.toString().contains(
                                  termo,
                                ) ||
                                cliente.toLowerCase().contains(termo) ||
                                vendedor.toLowerCase().contains(termo);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: context.isCompactLayout ? 120 : 220,
                        maxHeight: adaptiveDialogListMaxHeight(context),
                      ),
                      child: resultados.isEmpty
                          ? const Center(
                              child: Text('Nenhum orcamento encontrado.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final orc = resultados[index];
                                final cliente =
                                    _clienteDaVenda(orc)?.nomeRazao ??
                                    'Sem cliente';
                                final qtd = _qtdItensOrcamentoSafe(orc);
                                return ListTile(
                                  title: Text(
                                    'Orcamento ${orc.numeroOrcamento}',
                                  ),
                                  subtitle: Text(
                                    '$cliente | Itens: $qtd | Total: ${_formatarMoeda(orc.total)}',
                                  ),
                                  onTap: () => Navigator.pop(context, orc),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
    pesquisaController.dispose();
    if (!mounted || selecionado == null) {
      return;
    }

    if (repo is VendaApiRepository) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
      try {
        await repo.carregarItensRemoto(selecionado.id);
        final produtoRepo = widget.produtoRepository;
        if (produtoRepo is ProdutoApiRepository) {
          for (final item in repo.listarItensPorVenda(selecionado.id)) {
            final pid = item.produto.targetId;
            if (pid <= 0 || produtoRepo.obterPorId(pid) != null) continue;
            try {
              await produtoRepo.obterPorIdRemoto(pid);
            } catch (_) {}
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Falha ao carregar itens: ${LanApiFeedback.mensagem(e)}',
            ),
          ),
        );
        return;
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
    }

    final orcamentoCompleto =
        widget.vendaRepository.obterPorId(selecionado.id) ?? selecionado;
    try {
      final ok = _aplicarOrcamentoParaEdicao(orcamentoCompleto);
      if (!ok && mounted) {
        // Snackbar de falha ja exibido dentro de _aplicarOrcamentoParaEdicao.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Falha ao aplicar orcamento: ${LanApiFeedback.mensagem(e)}',
          ),
        ),
      );
    }
  }

  bool _aplicarOrcamentoParaEdicao(Venda selecionado) {
    final orcamentoCompleto =
        widget.vendaRepository.obterPorId(selecionado.id) ?? selecionado;
    final drafts = <_OrcamentoItemDraft>[];
    final nomesItensSemProduto = <String>[];
    final itensParaCarregar = _itensOrcamentoParaEdicao(orcamentoCompleto);
    for (final item in itensParaCarregar) {
      final produto = _resolverProdutoItemOrcamento(item);
      if (produto == null) {
        nomesItensSemProduto.add(item.nomeProduto);
        continue;
      }
      var tipoItem = EntregaVendaHelper.normalizarTipoItem(
        item.tipoEntregaItem,
      );
      if (tipoItem == EntregaVendaHelper.tipoRetirada &&
          orcamentoCompleto.tipoEntrega != EntregaVendaHelper.tipoRetirada &&
          orcamentoCompleto.tipoEntrega != EntregaVendaHelper.tipoMisto) {
        tipoItem = EntregaVendaHelper.normalizarTipoItem(
          orcamentoCompleto.tipoEntrega,
        );
      }
      final qCarrinho = ProdutoEmbalagem.quantidadeCarrinhoDeItemPersistido(
        produto: produto,
        quantidadeArmazenada: item.quantidade,
      );
      drafts.add(
        _OrcamentoItemDraft(
          produto: produto,
          quantidade: qCarrinho.quantidadeDigitada,
          precoTipo: item.precoTipo,
          precoUnitario: item.precoUnitario,
          precoUnitarioManual: item.precoUnitarioManual,
          tipoEntregaItem: tipoItem,
          quantidadeEmUnidadeCompra: qCarrinho.emUnidadeCompra,
          promocaoId: item.promocaoId,
          promocaoNome: item.promocaoNomeSnapshot,
          botaForaAplicado: item.botaForaAplicado,
          percentualBotaForaAplicado: item.percentualBotaForaAplicado,
        ),
      );
    }
    if (drafts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nomesItensSemProduto.isNotEmpty
                  ? 'Nao foi possivel carregar itens do orcamento. Produtos sem cadastro atual.'
                  : 'Nao foi possivel carregar itens do orcamento selecionado.',
            ),
          ),
        );
      }
      return false;
    }

    final clienteIdCarregado = orcamentoCompleto.cliente.targetId == 0
        ? null
        : orcamentoCompleto.cliente.targetId;
    final vendedorIdCarregado = orcamentoCompleto.vendedor.targetId == 0
        ? null
        : orcamentoCompleto.vendedor.targetId;
    final clienteCarregado = clienteIdCarregado == null
        ? null
        : widget.clienteRepository.obterPorId(clienteIdCarregado);
    final clienteIdValido = clienteCarregado != null && clienteCarregado.ativo
        ? clienteIdCarregado
        : null;
    final vendedorIdValido =
        vendedorIdCarregado != null &&
            _vendedoresAtivos.any((v) => v.id == vendedorIdCarregado)
        ? vendedorIdCarregado
        : null;
    final tipoEntregaValido = switch (orcamentoCompleto.tipoEntrega) {
      'entrega_loja' => EntregaVendaHelper.tipoEntregaLoja,
      'retirada_futura' => EntregaVendaHelper.tipoRetiradaFutura,
      'misto' => EntregaVendaHelper.tipoRetirada,
      _ => EntregaVendaHelper.tipoRetirada,
    };
    final prioridadeValida = switch (orcamentoCompleto.prioridadeEntrega) {
      'urgente' => 'urgente',
      'agendada' => 'agendada',
      _ => 'normal',
    };
    final janelaValida = switch (orcamentoCompleto.janelaEntrega) {
      'manha' => 'manha',
      'tarde' => 'tarde',
      _ => 'nao_definida',
    };
    var indiceEndereco = 0;
    if (clienteIdValido != null) {
      final cliente = widget.clienteRepository.obterPorId(clienteIdValido);
      final enderecos = cliente?.listarEnderecos() ?? const <EnderecoCliente>[];
      if (enderecos.isNotEmpty) {
        final enderecoAtual = orcamentoCompleto.enderecoEntrega.trim();
        final encontrado = enderecos.indexWhere(
          (e) => e.resumo().trim() == enderecoAtual,
        );
        if (encontrado >= 0) {
          indiceEndereco = encontrado;
        }
      }
    }

    setState(() {
      _carrinho
        ..clear()
        ..addAll(drafts);
      _precoListaAtivo = _precoListaPadraoPdv;
      _indiceLinhaCarrinho = _carrinho.isEmpty ? null : 0;
      _clienteSelecionadoId = clienteIdValido;
      _indiceEnderecoSelecionado = indiceEndereco;
      _vendedorSelecionadoId = vendedorIdValido;
      _disposeLinhasPagamentoMisto();
      if (orcamentoCompleto.formaPagamento == 'misto' &&
          orcamentoCompleto.pagamentosJson.trim().isNotEmpty) {
        _pagamentoMistoPdV = true;
        for (final ln in PagamentoOrcamentoCodec.decode(
          orcamentoCompleto.pagamentosJson,
        )) {
          _linhasPagamentoMisto.add(
            _LinhaPagamentoMistoPdV(
              meio: ln.meio,
              valorController: TextEditingController(
                text: ln.valor > 0
                    ? ln.valor.toStringAsFixed(2).replaceAll('.', ',')
                    : '',
              ),
              parcelas: ln.parcelas <= 0 ? 1 : ln.parcelas,
            ),
          );
        }
        _formaPagamentoSelecionada = 'dinheiro';
        _parcelasSelecionadas = 1;
      } else {
        _pagamentoMistoPdV = false;
        _formaPagamentoSelecionada = orcamentoCompleto.formaPagamento;
        _parcelasSelecionadas = orcamentoCompleto.quantidadeParcelas <= 0
            ? 1
            : orcamentoCompleto.quantidadeParcelas;
      }
      _planoFiadoParcelas = PlanoFiadoCodec.decode(
        orcamentoCompleto.planoFiadoJson,
      );
      _tipoEntregaSelecionada = tipoEntregaValido;
      _prioridadeEntregaSelecionada = prioridadeValida;
      _janelaEntregaSelecionada = janelaValida;
      _dataEntregaMarcada = orcamentoCompleto.dataEntregaMarcada;
      _entregaSemDataCombinada = _carrinhoTemItemCarreto &&
          orcamentoCompleto.dataEntregaMarcada == null;
      _valorFreteController.text = orcamentoCompleto.valorFrete
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _enderecoEntregaController.text = orcamentoCompleto.enderecoEntrega;
      _observacaoEntregaController.text = orcamentoCompleto.observacaoEntrega;
      _orcamentoEmEdicaoId = orcamentoCompleto.id;
      _orcamentoEmEdicaoNumero = orcamentoCompleto.numeroOrcamento;
    });
    _sincronizarTextoBuscaClientePdv();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nomesItensSemProduto.isEmpty
                ? 'Orcamento ${orcamentoCompleto.numeroOrcamento} carregado com ${drafts.length} item(ns) para edicao.'
                : 'Orcamento ${orcamentoCompleto.numeroOrcamento} carregado com ${drafts.length} item(ns). ${nomesItensSemProduto.length} item(ns) sem produto cadastrado foram ignorados.',
          ),
        ),
      );
    }
    return true;
  }

  Cliente? _clienteDaVenda(Venda venda) {
    return VendaRelacaoSafe.cliente(
      venda,
      clienteRepository: widget.clienteRepository,
    );
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    return VendaRelacaoSafe.vendedor(
      venda,
      vendedorRepository: widget.vendedorRepository,
    );
  }

  Future<({List<ItemVenda> itens, Map<int, Produto?> produtos})>
  _carregarItensOrcamentoParaImpressao(Venda venda) async {
    var vendaId = venda.id;
    if (vendaId <= 0 && venda.numeroOrcamento > 0) {
      final porNumero = widget.vendaRepository.buscarOrcamentoPendentePorNumero(
        venda.numeroOrcamento,
      );
      vendaId = porNumero?.id ?? vendaId;
    }

    var itensOrcamento = <ItemVenda>[];
    if (vendaId > 0) {
      try {
        final listed = widget.vendaRepository.listarItensPorVenda(vendaId);
        if (listed is List && listed.isNotEmpty) {
          itensOrcamento = List<ItemVenda>.from(listed);
        }
      } catch (_) {}
      if (itensOrcamento.isEmpty) {
        final repo = widget.vendaRepository;
        if (repo is VendaApiRepository) {
          try {
            itensOrcamento = await repo
                .carregarItensRemoto(vendaId)
                .timeout(const Duration(seconds: 12));
          } catch (_) {}
        }
      }
      if (itensOrcamento.isEmpty) {
        try {
          final recarregada = widget.vendaRepository.obterPorId(vendaId);
          if (recarregada != null) {
            try {
              final toMany = recarregada.itens;
              if (toMany.isNotEmpty) {
                itensOrcamento = List<ItemVenda>.from(toMany);
              }
            } catch (_) {
              // ToMany detached (Terminal Leve) — ignore.
            }
          }
        } catch (_) {}
      }
    }

    // Resolve produtos fora do build (ToOne detached estoura no Terminal).
    final produtosPorItem = <int, Produto?>{};
    for (var i = 0; i < itensOrcamento.length; i++) {
      final item = itensOrcamento[i];
      var produto = item.produtoOuNull;
      if (produto == null) {
        produto = _resolverProdutoItemOrcamento(item);
        if (produto != null) {
          try {
            item.produto.target = produto;
          } catch (_) {}
        }
      }
      produtosPorItem[i] = produto;
    }
    return (itens: itensOrcamento, produtos: produtosPorItem);
  }

  Future<CupomPdfGerado> _gerarOrcamentoPdfBytes(Venda venda) async {
    final carregado = await _carregarItensOrcamentoParaImpressao(venda);
    final empresa = await widget.appConfigRepository.carregarEmpresaConfig();
    return OrcamentoPdfService.gerar(
      venda: venda,
      itens: carregado.itens,
      empresa: empresa,
      validadeDias: _validadeOrcamentoDias,
      cliente: _clienteDaVenda(venda),
      vendedor: _vendedorDaVenda(venda),
      produtosPorItem: carregado.produtos,
      formatarMoedaFn: _formatarMoeda,
    );
  }

  Future<String?> _escolherSalvarPdf({
    required Uint8List bytes,
    required String suggestedFileName,
    String? initialDirectory,
  }) async {
    String? dir;
    final rawDir = initialDirectory?.trim() ?? '';
    if (rawDir.isNotEmpty) {
      try {
        if (Directory(rawDir).existsSync()) {
          dir = rawDir;
        }
      } catch (_) {
        dir = null;
      }
    }
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Escolha onde salvar o PDF',
      fileName: suggestedFileName,
      initialDirectory: dir,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) return null;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    final file = File(normalizedPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  KeyEventResult _atalhoDialogoOrcamentoSalvo(
    FocusNode node,
    KeyEvent event,
    void Function(String acao) fechar,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      fechar('fechar');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      fechar('pdf');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      fechar('direto');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      fechar('imprimir');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      fechar('imprimir');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f10) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _mostrarAcoesPdfOrcamento(Venda venda) async {
    final numOrcamento = venda.numeroOrcamento > 0
        ? venda.numeroOrcamento
        : venda.id;
    if (_pdvPularDialogOrcamentoSalvo) {
      return;
    }
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final modoEscPos = config.modoImpressaoBalcao == 'escpos';
    _dialogoOrcamentoSalvoAberto = true;
    String? acao;
    try {
      acao = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          void fechar(String valor) {
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext, valor);
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) =>
                _atalhoDialogoOrcamentoSalvo(node, event, fechar),
            child: AlertDialog(
              title: const Text('Orcamento salvo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Numero para o cliente informar no caixa:',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      child: Text(
                        '$numOrcamento',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Anote no papel ou envie ao cliente. No caixa, informe este numero para pagar.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    modoEscPos
                        ? 'Impressao termica ESC/POS (Epson TM-T20 etc.) '
                            'ou salvar PDF:'
                        : 'Deseja imprimir o orcamento ou mandar em PDF?',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    modoEscPos
                        ? 'Teclado: Esc ou 1 — fechar · 2 — PDF · '
                            '3/4/Enter — termica ESC/POS · F10 ignorado'
                        : 'Teclado: Esc ou 1 — fechar · 2 — PDF · '
                            '3 — impressao direta · 4 ou Enter — imprimir · '
                            'F10 ignorado nesta tela',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'fechar'),
                  child: const Text('Fechar (Esc · 1)'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, 'pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Mandar em PDF (2)'),
                ),
                if (!modoEscPos)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'direto'),
                    icon: const Icon(Icons.print),
                    label: const Text('Impressao direta (3)'),
                  ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    modoEscPos ? 'escpos' : 'imprimir',
                  ),
                  icon: Icon(
                    modoEscPos ? Icons.print : Icons.print_outlined,
                  ),
                  label: Text(
                    modoEscPos
                        ? 'Imprimir termica ESC/POS (3/4 · Enter)'
                        : 'Imprimir (4 · Enter)',
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _dialogoOrcamentoSalvoAberto = false;
      if (mounted) _voltarFocoParaPesquisa();
    }
    if (!mounted || acao == null || acao == 'fechar') return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      final imprimirEscPos = modoEscPos &&
          (acao == 'escpos' || acao == 'imprimir' || acao == 'direto');
      if (imprimirEscPos) {
        final carregado = await _carregarItensOrcamentoParaImpressao(venda);
        if (!mounted) return;
        final r = await EscPosPrinterService.imprimirOrcamentoDireto(
          OrcamentoEscPosDados(
            venda: venda,
            config: config,
            itens: carregado.itens,
            validadeDias: _validadeOrcamentoDias,
            cliente: _clienteDaVenda(venda),
            vendedor: _vendedorDaVenda(venda),
            produtosPorItem: carregado.produtos,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.mensagem)),
        );
        return;
      }

      final pdf = await _gerarOrcamentoPdfBytes(venda);
      if (!mounted) return;
      if (acao == 'imprimir') {
        await Printing.layoutPdf(
          onLayout: (_) async => pdf.bytes,
          name: 'Orcamento ${venda.numeroOrcamento}',
          format: pdf.pageFormat,
        );
        return;
      }
      if (acao == 'direto') {
        final printer = await widget.printService.resolverImpressoraPorNome(
          config.impressoraPadrao,
        );
        if (printer == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impressora padrao nao configurada/encontrada. '
                'Configure em Configuracoes > Impressao.',
              ),
            ),
          );
          return;
        }
        // Usa o mesmo formato finito do PDF gerado (evita altura infinity).
        final formatDireto = config.modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : pdf.pageFormat;
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdf.bytes,
          name: 'Orcamento ${venda.numeroOrcamento}',
          format: formatDireto,
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdf.bytes,
        suggestedFileName: 'orcamento_${venda.numeroOrcamento}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF do orcamento salvo em: $path')),
      );
    } catch (e, st) {
      debugPrint('Erro ao gerar/imprimir orcamento: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nao foi possivel gerar/imprimir orcamento: '
            '${LanApiFeedback.mensagem(e)}',
          ),
        ),
      );
    }
  }

  double get _totalOrcamento =>
      _carrinho.fold(0, (total, item) => total + item.subtotal);

  double get _valorFreteAtual => _carrinhoTemItemCarreto
      ? _parseValorMonetario(_valorFreteController.text)
      : 0.0;

  double get _totalGeralComFrete => _totalOrcamento + _valorFreteAtual;

  /// Subtotal de linhas sem promocao (desconto PDV nao incide em promo).
  double get _subtotalElegivelDescontoPdV => _carrinho
      .where((i) => i.promocaoId <= 0)
      .fold(0.0, (s, i) => s + i.subtotal);

  List<LinhaCalculoLimiteDescontoPdv> get _linhasLimiteDescontoPdV => _carrinho
      .map(
        (i) => LinhaCalculoLimiteDescontoPdv(
          produto: i.produto,
          precoTipo: i.precoTipo,
          subtotal: i.subtotal,
          promocaoId: i.promocaoId,
        ),
      )
      .toList();

  double _percentualMaximoEfetivoDescontoPdV() =>
      ProdutoLimiteDescontoPdv.percentualEquivalenteSobreSubtotal(
        linhas: _linhasLimiteDescontoPdV,
        tetoEmpresaOuUsuario: _maxDescontoPercentualPdv,
      );

  /// Valor maximo de desconto em reais (teto por produto/tabela + config).
  double _valorMaximoDescontoReaisPdV() {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    return ProdutoLimiteDescontoPdv.valorMaximoDescontoReais(
      linhas: _linhasLimiteDescontoPdV,
      tetoEmpresaOuUsuario: _maxDescontoPercentualPdv,
    );
  }

  /// Percentual digitado sem aplicar o teto (para aviso quando ultrapassa).
  double? _percentualDigitadoBrutoSemLimitePdV() {
    if (_tipoDescontoPdV != 'percentual') return null;
    final raw = _descontoPdVController.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    if (v == null || v.isNaN) return null;
    return v;
  }

  bool _descontoPdVDigitadoUltrapassaTeto() {
    if (_maxDescontoPercentualPdv <= 0) return false;
    final maxPct = _percentualMaximoEfetivoDescontoPdV();
    final maxReais = _valorMaximoDescontoReaisPdV();
    const eps = 1e-6;
    if (_tipoDescontoPdV == 'percentual') {
      final bruto = _percentualDigitadoBrutoSemLimitePdV();
      if (bruto == null) return false;
      return bruto > maxPct + eps;
    }
    if (_descontoPdVController.text.trim().isEmpty) return false;
    final brutoReais = _parseValorMonetario(_descontoPdVController.text);
    return brutoReais > maxReais + eps;
  }

  bool _descontoPdVUltrapassaTetoSemAutorizacao() {
    return _descontoPdVDigitadoUltrapassaTeto() &&
        !_descontoAcimaTetoAutorizadoPdv;
  }

  double _descontoSolicitadoReaisBrutoPdV() {
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0) return 0;
    if (_tipoDescontoPdV == 'percentual') {
      final bruto = _percentualDigitadoBrutoSemLimitePdV();
      if (bruto == null) return 0;
      return (sub * bruto / 100).clamp(0.0, sub);
    }
    return _parseValorMonetario(_descontoPdVController.text).clamp(0.0, sub);
  }

  String _idCarrinhoSessaoPdv() {
    if (_carrinhoSessaoId.isEmpty) {
      _carrinhoSessaoId = gerarUuidV4();
    }
    return _carrinhoSessaoId;
  }

  String _descricaoAcaoDescontoPdv() {
    if (_tipoDescontoPdV == 'percentual') {
      final pct = _percentualDigitadoBrutoSemLimitePdV();
      if (pct != null) {
        return 'Desconto de ${pct.toStringAsFixed(1).replaceAll('.', ',')}%';
      }
    }
    return 'Desconto de ${_formatarMoeda(_descontoSolicitadoReaisBrutoPdV())}';
  }

  Future<bool> _solicitarAutorizacaoDescontoAcimaTetoPdV() async {
    if (!_descontoPdVDigitadoUltrapassaTeto()) {
      _descontoAcimaTetoAutorizadoPdv = false;
      _descontoAutorizadoPorPdV = null;
      return true;
    }
    if (_descontoAcimaTetoAutorizadoPdv) return true;

    final autorizadoPor = await solicitarAutorizacaoDescontoAcimaTetoPdv(
      context,
      _usuarioRepository,
      usuarioLogado: widget.usuarioLogado,
      maximoPermitidoReais: _valorMaximoDescontoReaisPdV(),
      descontoSolicitadoReais: _descontoSolicitadoReaisBrutoPdV(),
      formatarMoeda: _formatarMoeda,
      vendaId: _orcamentoEmEdicaoId ?? 0,
      carrinhoId: _idCarrinhoSessaoPdv(),
      descricaoAcao: _descricaoAcaoDescontoPdv(),
      valorOriginal: _subtotalElegivelDescontoPdV,
    );
    if (autorizadoPor == null) return false;
    _descontoAcimaTetoAutorizadoPdv = true;
    _descontoAutorizadoPorPdV = autorizadoPor.login;
    return true;
  }

  void _resetarAutorizacaoDescontoAcimaTetoPdV() {
    _descontoAcimaTetoAutorizadoPdv = false;
    _descontoAutorizadoPorPdV = null;
  }

  String _mensagemErroDescontoPdVUltrapassaTeto() {
    final maxPct = _percentualMaximoEfetivoDescontoPdV();
    final maxReais = _valorMaximoDescontoReaisPdV();
    return 'Acima do permitido. Maximo: ${maxPct.toStringAsFixed(1)}% '
        'do subtotal = ${_formatarMoeda(maxReais)}.';
  }

  /// Desconto apenas sobre o subtotal; frete entra inteiro no total a pagar.
  double _valorDescontoReaisPdV() {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0) return 0;
    final maxReais = _valorMaximoDescontoReaisPdV();
    final acimaAutorizado = _descontoAcimaTetoAutorizadoPdv;
    if (_tipoDescontoPdV == 'percentual') {
      final bruto = _percentualDigitadoBrutoSemLimitePdV() ?? 0;
      final pct = acimaAutorizado
          ? bruto.clamp(0.0, 100.0)
          : bruto.clamp(0.0, _percentualMaximoEfetivoDescontoPdV());
      final valor = sub * pct / 100;
      return acimaAutorizado
          ? valor.clamp(0.0, sub)
          : valor.clamp(0.0, maxReais);
    }
    final digitado = _parseValorMonetario(_descontoPdVController.text);
    if (acimaAutorizado) return digitado.clamp(0.0, sub);
    return digitado.clamp(0.0, maxReais).clamp(0.0, sub);
  }

  double _totalLiquidoPagamentoPdV() =>
      (_totalGeralComFrete - _valorDescontoReaisPdV()).clamp(
        0.0,
        double.infinity,
      );

  double _valorFiadoCheckoutPdV() {
    final total = _totalLiquidoPagamentoPdV();
    if (_pagamentoMistoPdV) {
      try {
        final linhas = _montarLinhasMistoParaSalvar(total);
        if (linhas == null) return 0;
        return PagamentoOrcamentoCodec.somaPorMeio(linhas, 'fiado');
      } on StateError {
        return 0;
      }
    }
    if (_formaPagamentoSelecionada == 'fiado') return total;
    return 0;
  }

  bool _precisaPlanoFiadoPdV() => _valorFiadoCheckoutPdV() > 0.001;

  String _rotuloParcelaCreditoValor(int parcelas, double valorBase) {
    final n = parcelas <= 0 ? 1 : parcelas;
    if (valorBase <= 0.001) {
      return '${n}x';
    }
    final valorParcela = valorBase / n;
    return '${n}x · ${_formatarMoeda(valorParcela)}';
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f1): SelecionarPrecoListaIntent(
          'preco1',
        ),
        SingleActivator(LogicalKeyboardKey.f2): SelecionarPrecoListaIntent(
          'preco2',
        ),
        SingleActivator(LogicalKeyboardKey.f3): SelecionarPrecoListaIntent(
          'preco3',
        ),
        SingleActivator(LogicalKeyboardKey.f1, control: true):
            SelecionarEntregaPadraoIntent('retirada'),
        SingleActivator(LogicalKeyboardKey.f2, control: true):
            SelecionarEntregaPadraoIntent('retirada_futura'),
        SingleActivator(LogicalKeyboardKey.f3, control: true):
            SelecionarEntregaPadraoIntent('entrega_loja'),
        SingleActivator(LogicalKeyboardKey.f4): PdvAbrirConsultaIntent(),
        SingleActivator(LogicalKeyboardKey.f5): PdvRecarregarProdutosIntent(),
        SingleActivator(LogicalKeyboardKey.f6): PdvFocarCarrinhoIntent(),
        SingleActivator(LogicalKeyboardKey.f8):
            PdvFocarPesquisaProdutosIntent(),
        SingleActivator(LogicalKeyboardKey.f10): PdvSalvarOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.f11): PdvToggleCalculadoraIntent(),
        SingleActivator(LogicalKeyboardKey.f12):
            PdvToggleObraCalculadoraIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            PdvSalvarOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyO, control: true):
            PdvLerOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            PdvLimparPesquisaIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SelecionarPrecoListaIntent:
              CallbackAction<SelecionarPrecoListaIntent>(
                onInvoke: (intent) {
                  _aplicarTabelaPrecoAtalhoPdv(intent.precoTipo);
                  return null;
                },
              ),
          SelecionarEntregaPadraoIntent:
              CallbackAction<SelecionarEntregaPadraoIntent>(
                onInvoke: (intent) {
                  _definirEntregaPadraoPdv(intent.tipoEntrega);
                  return null;
                },
              ),
          PdvAbrirConsultaIntent: CallbackAction<PdvAbrirConsultaIntent>(
            onInvoke: (_) {
              unawaited(_abrirConsultaProdutos());
              return null;
            },
          ),
          PdvRecarregarProdutosIntent:
              CallbackAction<PdvRecarregarProdutosIntent>(
                onInvoke: (_) {
                  _carregarDadosIniciais();
                  return null;
                },
              ),
          PdvFocarCarrinhoIntent: CallbackAction<PdvFocarCarrinhoIntent>(
            onInvoke: (_) {
              _focarCarrinhoAtalho();
              return null;
            },
          ),
          PdvFocarPesquisaProdutosIntent:
              CallbackAction<PdvFocarPesquisaProdutosIntent>(
                onInvoke: (_) {
                  _atalhoF8Pdv();
                  return null;
                },
              ),
          PdvSalvarOrcamentoIntent: CallbackAction<PdvSalvarOrcamentoIntent>(
            onInvoke: (_) {
              if (_dialogoOrcamentoSalvoAberto ||
                  _checkoutDialogAberto ||
                  _salvandoOrcamento) {
                return null;
              }
              unawaited(_abrirPassoFechamentoVenda());
              return null;
            },
          ),
          PdvLerOrcamentoIntent: CallbackAction<PdvLerOrcamentoIntent>(
            onInvoke: (_) {
              unawaited(_abrirLeitorOrcamento());
              return null;
            },
          ),
          PdvLimparPesquisaIntent: CallbackAction<PdvLimparPesquisaIntent>(
            onInvoke: (_) {
              _limparPesquisaAtalho();
              return null;
            },
          ),
          PdvToggleCalculadoraIntent:
              CallbackAction<PdvToggleCalculadoraIntent>(
                onInvoke: (_) {
                  _toggleCalculadoraPdv();
                  return null;
                },
              ),
          PdvToggleObraCalculadoraIntent:
              CallbackAction<PdvToggleObraCalculadoraIntent>(
                onInvoke: (_) {
                  _toggleObraCalculadoraPdv();
                  return null;
                },
              ),
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _registrarAtividadePdvVendedor(),
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              appBar: AppBar(
                titleSpacing: _pdvUiCelular ? 8 : 0,
                title: _pdvUiCelular
                    ? const Text('PDV')
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Flexible(
                            child: Text(
                              'Ponto de Venda',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildSeletorVendedorAppBarPdv(),
                          const SizedBox(width: 4),
                          _buildSeletorEntregaPadraoAppBarPdv(),
                          const SizedBox(width: 4),
                          _buildSeletorClienteAppBarPdv(),
                        ],
                      ),
                actions: _pdvUiCelular
                    ? [
                        IconButton(
                          tooltip: 'Consultar produtos',
                          onPressed: () => unawaited(_abrirConsultaProdutos()),
                          icon: const Icon(Icons.search),
                        ),
                        if (pdvLeitorCameraDisponivel)
                          IconButton(
                            tooltip: 'Bipar codigo de barras',
                            onPressed: () => unawaited(_abrirLeitorCameraPdv()),
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Mais acoes',
                          onSelected: (v) {
                            switch (v) {
                              case 'obra':
                                _toggleObraCalculadoraPdv();
                              case 'calc':
                                _toggleCalculadoraPdv();
                              case 'orcamento':
                                _abrirLeitorOrcamento();
                              case 'kit':
                                _inserirKitNoOrcamento();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'obra',
                              child: Text('Calculadora de obra'),
                            ),
                            PopupMenuItem(
                              value: 'calc',
                              child: Text('Calculadora'),
                            ),
                            PopupMenuItem(
                              value: 'orcamento',
                              child: Text('Ler orcamento'),
                            ),
                            PopupMenuItem(
                              value: 'kit',
                              child: Text('Inserir kit'),
                            ),
                          ],
                        ),
                      ]
                    : [
                        IconButton(
                          tooltip: 'Calculadora de obra (F12)',
                          onPressed: _toggleObraCalculadoraPdv,
                          icon: const Icon(Icons.construction_outlined),
                        ),
                        IconButton(
                          tooltip: 'Calculadora (F11)',
                          onPressed: _toggleCalculadoraPdv,
                          icon: const Icon(Icons.calculate_outlined),
                        ),
                        IconButton(
                          tooltip: 'Consultar produtos (F4)',
                          onPressed: () => unawaited(_abrirConsultaProdutos()),
                          icon: const Icon(Icons.search),
                        ),
                        IconButton(
                          tooltip: 'Ler orcamento para editar',
                          onPressed: _abrirLeitorOrcamento,
                          icon: const Icon(Icons.description_outlined),
                        ),
                        IconButton(
                          tooltip: 'Inserir kit de orcamento',
                          onPressed: _inserirKitNoOrcamento,
                          icon: const Icon(Icons.widgets_outlined),
                        ),
                      ],
              ),
              body: Stack(
                children: [
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        _pdvUiCelular ? 10 : 12,
                        _pdvUiCelular ? 8 : 12,
                        _pdvUiCelular ? 10 : 12,
                        _pdvUiCelular ? 8 : 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (LanApiEventHub.instance.deveBloquearOperacoes) ...[
                            _bannerServidorOfflinePdv(context),
                            const SizedBox(height: 8),
                          ],
                          if (_pdvUiCelular) ...[
                            _buildFaixaSeletoresMobilePdv(),
                            const SizedBox(height: 8),
                          ],
                          if (widget.intentTrocaComNota != null &&
                              _trocaComNotaBannerVisivel)
                            TrocaComNotaPdvBanner(
                              intent: widget.intentTrocaComNota!,
                              creditoAplicadoNoDesconto:
                                  _trocaComNotaCreditoAplicadoReais,
                              maxDescontoPermitidoReais:
                                  _valorMaximoDescontoReaisPdV(),
                              onFechar: () {
                                setState(
                                  () => _trocaComNotaBannerVisivel = false,
                                );
                              },
                            ),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(4),
                            child: _PdvHeaderPesquisa(
                              modoBarraCarrinho: true,
                              modoCelular: _pdvUiCelular,
                              pesquisaFocus: _pesquisaFocus,
                              pesquisaController: _pesquisaController,
                              mostrarAjudaAtalhos: _pdvUiCelular
                                  ? false
                                  : _mostrarAjudaAtalhos,
                              mostrarBotaoCamera:
                                  pdvLeitorCameraDisponivel && !_pdvUiCelular,
                              onLimparBusca: _limparPesquisaAtalho,
                              onAbrirConsulta: () =>
                                  unawaited(_abrirConsultaProdutos()),
                              onAbrirCamera: () =>
                                  unawaited(_abrirLeitorCameraPdv()),
                              onSubmitEntrada: () =>
                                  unawaited(_processarEntradaPesquisaPdv()),
                              onRecarregarProdutos: _carregarDadosIniciais,
                              onToggleAjudaAtalhos: () {
                                setState(() {
                                  _mostrarAjudaAtalhos = !_mostrarAjudaAtalhos;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _carrinhoUiEpoch,
                              builder: (context, epoch, child) =>
                                  _buildAreaCarrinhoComPreviewPdv(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_overlaySalvandoOrcamento)
                    const ModalBarrier(
                      dismissible: false,
                      color: Color(0x66000000),
                    ),
                  if (_overlaySalvandoOrcamento)
                    const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 22,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'Processando orcamento...',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Aguardando resposta do servidor.\nNao feche a tela.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Seletores (vendedor, entrega, cliente) em faixa rolavel no celular.
  Widget _buildFaixaSeletoresMobilePdv() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildSeletorVendedorAppBarPdv(),
          const SizedBox(width: 6),
          _buildSeletorEntregaPadraoAppBarPdv(),
          const SizedBox(width: 6),
          _buildSeletorClienteAppBarPdv(),
        ],
      ),
    );
  }
}

/// Barra de pesquisa no topo do carrinho (Enter abre consulta em tela cheia).
class _PdvHeaderPesquisa extends StatelessWidget {
  const _PdvHeaderPesquisa({
    required this.modoBarraCarrinho,
    required this.pesquisaFocus,
    required this.pesquisaController,
    required this.mostrarAjudaAtalhos,
    required this.onLimparBusca,
    required this.onAbrirConsulta,
    required this.onSubmitEntrada,
    required this.onRecarregarProdutos,
    required this.onToggleAjudaAtalhos,
    this.mostrarBotaoCamera = false,
    this.onAbrirCamera,
    this.modoCelular = false,
  });

  final bool modoBarraCarrinho;
  final bool modoCelular;
  final FocusNode pesquisaFocus;
  final TextEditingController pesquisaController;
  final bool mostrarAjudaAtalhos;
  final bool mostrarBotaoCamera;
  final VoidCallback onLimparBusca;
  final VoidCallback onAbrirConsulta;
  final VoidCallback? onAbrirCamera;
  final VoidCallback onSubmitEntrada;
  final VoidCallback onRecarregarProdutos;
  final VoidCallback onToggleAjudaAtalhos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hintCelular = mostrarBotaoCamera
        ? 'Pesquisar ou bipar codigo'
        : 'Pesquisar produto';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          modoCelular ? 8 : (modoBarraCarrinho ? 6 : 10),
          8,
          modoCelular ? 8 : 6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: false,
              focusNode: pesquisaFocus,
              controller: pesquisaController,
              textInputAction: TextInputAction.search,
              style: modoBarraCarrinho
                  ? Theme.of(context).textTheme.bodyMedium
                  : null,
              decoration: InputDecoration(
                isDense: modoBarraCarrinho && !modoCelular,
                filled: true,
                fillColor: scheme.surface.withValues(alpha: 0.92),
                contentPadding: modoBarraCarrinho
                    ? EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: modoCelular ? 14 : 10,
                      )
                    : null,
                hintText: modoBarraCarrinho
                    ? (modoCelular
                          ? hintCelular
                          : (mostrarBotaoCamera
                                ? 'Pesquisar ou bipar com a camera · Enter/F4 consulta'
                                : 'Pesquisar produto · Enter/F4 consulta · Enter confirma qtd no carrinho'))
                    : null,
                labelText: modoBarraCarrinho
                    ? null
                    : 'Pesquisar produto para venda',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mostrarBotaoCamera && onAbrirCamera != null)
                      IconButton(
                        tooltip: 'Bipar codigo de barras',
                        visualDensity: VisualDensity.compact,
                        onPressed: onAbrirCamera,
                        icon: const Icon(Icons.qr_code_scanner, size: 22),
                      ),
                    IconButton(
                      tooltip: 'Limpar busca',
                      visualDensity: VisualDensity.compact,
                      onPressed: onLimparBusca,
                      icon: const Icon(Icons.clear, size: 20),
                    ),
                    IconButton(
                      tooltip: modoCelular
                          ? 'Abrir consulta de produtos'
                          : 'Abrir consulta de produtos (F4)',
                      visualDensity: VisualDensity.compact,
                      onPressed: onAbrirConsulta,
                      icon: const Icon(Icons.search, size: 20),
                    ),
                    if (!modoBarraCarrinho)
                      IconButton(
                        tooltip: 'Recarregar cadastros',
                        onPressed: onRecarregarProdutos,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
              onSubmitted: (_) => onSubmitEntrada(),
            ),
            if (!modoCelular) ...[
              if (!modoBarraCarrinho) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onToggleAjudaAtalhos,
                    icon: Icon(
                      mostrarAjudaAtalhos
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    label: Text(
                      mostrarAjudaAtalhos
                          ? 'Ocultar atalhos'
                          : 'Ajuda de atalhos',
                    ),
                  ),
                ),
              ] else
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onToggleAjudaAtalhos,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      mostrarAjudaAtalhos ? 'Ocultar atalhos' : 'Atalhos',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              AnimatedCrossFade(
                crossFadeState: mostrarAjudaAtalhos
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 180),
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: const PdvAtalhosAjudaPesquisa(),
                ),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lista compacta do carrinho do PDV (foco F6, setas, exclusão).
class _PdvCarrinhoProdutos extends StatefulWidget {
  const _PdvCarrinhoProdutos({
    required this.carrinhoFocus,
    required this.onKeyCarrinho,
    required this.itens,
    required this.indiceLinhaSelecionada,
    required this.indiceLinhaEdicaoQuantidade,
    required this.quantidadeInlineController,
    required this.quantidadeInlineFocus,
    required this.onConfirmarQuantidadeInline,
    required this.quantidadeFracionadaDe,
    required this.onSelecionarLinha,
    required this.rotuloPreco,
    required this.formatarMoeda,
    required this.onAlterarQuantidade,
    required this.onEditarQuantidade,
    required this.passoQuantidadeCarrinho,
    required this.onRemoverItem,
    required this.onAlternarTipoEntrega,
    required this.onAlternarTabelaPreco,
    required this.onDividirLinha,
    required this.onAlterarPrecoLinha,
    required this.onIrPesquisaQuandoVazio,
    this.alvosTouchAmplos = false,
  });

  final FocusNode carrinhoFocus;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyCarrinho;
  final List<_OrcamentoItemDraft> itens;
  final int? indiceLinhaSelecionada;
  final int? indiceLinhaEdicaoQuantidade;
  final TextEditingController quantidadeInlineController;
  final FocusNode quantidadeInlineFocus;
  final VoidCallback onConfirmarQuantidadeInline;
  final bool Function(_OrcamentoItemDraft item) quantidadeFracionadaDe;
  final void Function(int index) onSelecionarLinha;
  final String Function(String) rotuloPreco;
  final String Function(double) formatarMoeda;
  final void Function(int index, int delta) onAlterarQuantidade;
  final void Function(int index) onEditarQuantidade;
  final int Function(_OrcamentoItemDraft item) passoQuantidadeCarrinho;
  final void Function(int index) onRemoverItem;
  final void Function(int index) onAlternarTipoEntrega;
  final void Function(int index) onAlternarTabelaPreco;
  final Future<void> Function(int index) onDividirLinha;
  final Future<void> Function(int index) onAlterarPrecoLinha;
  final VoidCallback onIrPesquisaQuandoVazio;
  final bool alvosTouchAmplos;

  @override
  State<_PdvCarrinhoProdutos> createState() => _PdvCarrinhoProdutosState();
}

class _PdvCarrinhoProdutosState extends State<_PdvCarrinhoProdutos> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PdvCarrinhoProdutos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.indiceLinhaSelecionada != oldWidget.indiceLinhaSelecionada ||
        widget.indiceLinhaEdicaoQuantidade !=
            oldWidget.indiceLinhaEdicaoQuantidade) {
      _rolarParaIndice(
        widget.indiceLinhaEdicaoQuantidade ?? widget.indiceLinhaSelecionada,
      );
    }
  }

  void _rolarParaIndice(int? indice) {
    if (indice == null || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final altura = PdvCarrinhoLinhaCompacta.alturaParaLista(
      alvosTouchAmplos: widget.alvosTouchAmplos,
    );
    final alvo = (indice * altura).clamp(0.0, max);
    _scrollController.jumpTo(alvo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final alturaLinha = PdvCarrinhoLinhaCompacta.alturaParaLista(
      alvosTouchAmplos: widget.alvosTouchAmplos,
    );

    if (widget.itens.isEmpty) {
      return Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 44,
                  color: scheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nenhum item na venda.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onIrPesquisaQuandoVazio,
                  icon: const Icon(Icons.search),
                  label: const Text('Pesquisar produto para venda'),
                ),
                if (!pdvPlataformaCelular) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Atalho: F8 ou F4',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Focus(
      focusNode: widget.carrinhoFocus,
      onKeyEvent: widget.onKeyCarrinho,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final exibirColunaUnitario = !pdvPlataformaCelular &&
              PdvCarrinhoLinhaColunas.cabeColunaUnitario(
                larguraDisponivel: constraints.maxWidth,
                alvosTouchAmplos: widget.alvosTouchAmplos,
              );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!pdvPlataformaCelular)
                PdvCarrinhoListaCabecalho(
                  alvosTouchAmplos: widget.alvosTouchAmplos,
                  exibirColunaUnitario: exibirColunaUnitario,
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemExtent: alturaLinha,
                  itemCount: widget.itens.length,
                  itemBuilder: (context, index) {
                    final item = widget.itens[index];
                    final selecionado = widget.indiceLinhaSelecionada == index;
                    final editandoQuantidade =
                        widget.indiceLinhaEdicaoQuantidade == index;
                    final passo = widget.passoQuantidadeCarrinho(item);
                    return Semantics(
                      container: true,
                      label:
                          '${item.produto.codigoInterno.trim().isNotEmpty ? '${item.produto.codigoInterno.trim()}, ' : ''}'
                          '${item.produto.nome}, ${widget.rotuloPreco(item.precoTipo)}, '
                          'quantidade ${item.quantidadeExibicaoTexto}',
                      child: PdvCarrinhoLinhaCompacta(
                        nomeProduto: item.produto.nome,
                        codigoProduto: item.produto.codigoInterno,
                        unidadeMedida: item.unidadeMedidaExibicao,
                        emPromocao: item.promocaoId > 0,
                        botaFora: item.botaForaAplicado,
                        precoManual: item.precoUnitarioManual,
                        rotuloPreco: widget.rotuloPreco(item.precoTipo),
                        precoUnitarioFormatado:
                            widget.formatarMoeda(item.precoUnitario),
                        subtotalFormatado: widget.formatarMoeda(item.subtotal),
                        quantidadeExibicao: item.quantidadeExibicaoTexto,
                        quantidadeArmazenada: item.quantidade,
                        rotuloQuantidadeLinha: item.rotuloQuantidadeCarrinho,
                        tipoEntregaItem: item.tipoEntregaItem,
                        precoTipo: item.precoTipo,
                        selecionado: selecionado,
                        alvosTouchAmplos: widget.alvosTouchAmplos,
                        exibirColunaUnitario: exibirColunaUnitario,
                        editandoQuantidade: editandoQuantidade,
                        quantidadeFracionada:
                            widget.quantidadeFracionadaDe(item),
                        quantidadeController: editandoQuantidade
                            ? widget.quantidadeInlineController
                            : null,
                        quantidadeFocus: editandoQuantidade
                            ? widget.quantidadeInlineFocus
                            : null,
                        onConfirmarQuantidade:
                            widget.onConfirmarQuantidadeInline,
                        onTap: () => widget.onSelecionarLinha(index),
                        onAlternarTipoEntrega: () =>
                            widget.onAlternarTipoEntrega(index),
                        onAlternarTabelaPreco: () =>
                            widget.onAlternarTabelaPreco(index),
                        onDiminuir: () =>
                            widget.onAlterarQuantidade(index, -passo),
                        onAumentar: () =>
                            widget.onAlterarQuantidade(index, passo),
                        onEditarQuantidade: () =>
                            widget.onEditarQuantidade(index),
                        onDividir: () => widget.onDividirLinha(index),
                        onAlterarPreco: () =>
                            widget.onAlterarPrecoLinha(index),
                        onRemover: () => widget.onRemoverItem(index),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Painel lateral de checkout (colapsável, carrinho, totais na base, continuar).
class _PdvPainelCheckout extends StatelessWidget {
  const _PdvPainelCheckout({
    required this.leiauteEmpilhado,
    required this.keyPainel,
    required this.painelCheckoutRecolhido,
    required this.carrinhoCount,
    required this.totalResumoColapsado,
    required this.onExpandirPainel,
    required this.orcamentoEmEdicao,
    required this.orcamentoEmEdicaoNumero,
    this.ultimoOrcamentoSalvoNumero,
    this.ultimoOrcamentoSalvoTotal,
    required this.onCancelarEdicaoOrcamento,
    required this.mostrarDicaAtalhosCarrinho,
    required this.resumoEntregaItens,
    required this.carrinhoBody,
    required this.subtotalProdutos,
    required this.valorFrete,
    required this.valorDesconto,
    required this.descontoConfigAtivo,
    required this.totalDestaqueValor,
    required this.formatarMoeda,
    required this.onIrPesquisaProdutos,
    required this.onRecolherCheckout,
    required this.focusSalvarOrcamento,
    required this.onContinuarFechamento,
    required this.labelBotaoContinuar,
    this.modoCelular = false,
  });

  /// Em coluna (telas estreitas), o painel ignora recolhimento e usa largura total.
  final bool leiauteEmpilhado;
  final GlobalKey keyPainel;
  final bool painelCheckoutRecolhido;
  final int carrinhoCount;
  final String totalResumoColapsado;
  final VoidCallback onExpandirPainel;
  final bool orcamentoEmEdicao;
  final String? orcamentoEmEdicaoNumero;
  final int? ultimoOrcamentoSalvoNumero;
  final double? ultimoOrcamentoSalvoTotal;
  final VoidCallback onCancelarEdicaoOrcamento;
  final bool mostrarDicaAtalhosCarrinho;
  final String resumoEntregaItens;
  final Widget carrinhoBody;
  final double subtotalProdutos;
  final double valorFrete;
  final double valorDesconto;
  final bool descontoConfigAtivo;
  final double totalDestaqueValor;
  final String Function(double) formatarMoeda;
  final VoidCallback onIrPesquisaProdutos;
  final VoidCallback onRecolherCheckout;
  final FocusNode focusSalvarOrcamento;
  final VoidCallback onContinuarFechamento;
  final String labelBotaoContinuar;
  final bool modoCelular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final efetivamenteRecolhido = painelCheckoutRecolhido && !leiauteEmpilhado;
    return AnimatedContainer(
      key: keyPainel,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: leiauteEmpilhado
          ? double.infinity
          : (efetivamenteRecolhido ? 64 : 470),
      child: efetivamenteRecolhido
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  IconButton(
                    tooltip: 'Expandir checkout',
                    onPressed: onExpandirPainel,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$carrinhoCount',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('itens', style: Theme.of(context).textTheme.bodySmall),
                  Divider(
                    height: 20,
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      totalResumoColapsado,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.045),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  visualDensity: VisualDensity.compact,
                  inputDecorationTheme: Theme.of(context).inputDecorationTheme
                      .copyWith(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                children: [
                                  TextSpan(
                                    text:
                                        'Venda em atendimento · $carrinhoCount itens',
                                  ),
                                  if (resumoEntregaItens.isNotEmpty) ...[
                                    TextSpan(
                                      text: ' · Entrega: $resumoEntregaItens',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                  if (!orcamentoEmEdicao &&
                                      ultimoOrcamentoSalvoNumero != null)
                                    TextSpan(
                                      text:
                                          ' · Ultimo orcamento: $ultimoOrcamentoSalvoNumero'
                                          '${ultimoOrcamentoSalvoTotal != null && ultimoOrcamentoSalvoTotal! > 0.009 ? ' · ${formatarMoeda(ultimoOrcamentoSalvoTotal!)}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Pesquisar produto (Enter abre consulta)',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            onPressed: onIrPesquisaProdutos,
                            icon: const Icon(Icons.search, size: 20),
                          ),
                          if (!leiauteEmpilhado)
                            IconButton(
                              tooltip: 'Recolher checkout',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              onPressed: onRecolherCheckout,
                              icon: const Icon(Icons.chevron_right, size: 20),
                            ),
                        ],
                      ),
                      if (orcamentoEmEdicao)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Editando venda ${orcamentoEmEdicaoNumero ?? '-'}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: scheme.primary,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: onCancelarEdicaoOrcamento,
                                child: const Text('Cancelar edicao'),
                              ),
                            ],
                          ),
                        ),
                      if (mostrarDicaAtalhosCarrinho)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: PdvAtalhosAjudaCarrinho(),
                        ),
                      const SizedBox(height: 2),
                      Expanded(child: carrinhoBody),
                      const SizedBox(height: 8),
                      _PdvCheckoutRodape(
                        scheme: scheme,
                        theme: theme,
                        carrinhoCount: carrinhoCount,
                        descontoConfigAtivo: descontoConfigAtivo,
                        totalDestaque: totalDestaqueValor,
                        formatarMoeda: formatarMoeda,
                        focusSalvarOrcamento: focusSalvarOrcamento,
                        onContinuarFechamento: onContinuarFechamento,
                        labelBotaoContinuar: labelBotaoContinuar,
                        modoCelular: modoCelular,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PdvCheckoutRodape extends StatelessWidget {
  const _PdvCheckoutRodape({
    required this.scheme,
    required this.theme,
    required this.carrinhoCount,
    required this.descontoConfigAtivo,
    required this.totalDestaque,
    required this.formatarMoeda,
    required this.focusSalvarOrcamento,
    required this.onContinuarFechamento,
    required this.labelBotaoContinuar,
    this.modoCelular = false,
  });

  final ColorScheme scheme;
  final ThemeData theme;
  final int carrinhoCount;
  final bool descontoConfigAtivo;
  final double totalDestaque;
  final String Function(double) formatarMoeda;
  final FocusNode focusSalvarOrcamento;
  final VoidCallback onContinuarFechamento;
  final String labelBotaoContinuar;
  final bool modoCelular;

  @override
  Widget build(BuildContext context) {
    final rotuloTotal =
        descontoConfigAtivo ? 'TOTAL A PAGAR' : 'TOTAL GERAL';
    final fundoTotal = Color.lerp(scheme.primary, Colors.black, 0.18)!;
    final corTexto = scheme.onPrimary;
    final itensRotulo = carrinhoCount == 1 ? '1 item' : '$carrinhoCount itens';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: fundoTotal,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            boxShadow: [
              BoxShadow(
                color: fundoTotal.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '$rotuloTotal ($itensRotulo)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: 0.2,
                      color: corTexto.withValues(alpha: 0.92),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatarMoeda(totalDestaque),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -0.4,
                      color: corTexto,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Focus(
          focusNode: focusSalvarOrcamento,
          child: FilledButton.icon(
            onPressed: onContinuarFechamento,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              elevation: 0,
              visualDensity: VisualDensity.standard,
              minimumSize: Size.fromHeight(modoCelular ? 50 : 46),
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: modoCelular ? 13 : 11,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
              ),
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 21),
            label: Text(labelBotaoContinuar),
          ),
        ),
      ],
    );
  }
}

class _AdicionarOrcamentoResult {
  const _AdicionarOrcamentoResult({
    required this.quantidadeVenda,
    required this.precoTipo,
    required this.tipoEntregaItem,
    this.quantidadeEmUnidadeCompra = false,
  });
  final double quantidadeVenda;
  final String precoTipo;
  final String tipoEntregaItem;
  final bool quantidadeEmUnidadeCompra;
}

class _DividirLinhaCarrinhoResult {
  const _DividirLinhaCarrinhoResult({
    required this.quantidadeNovaLinha,
    required this.tipoEntregaItem,
  });

  final int quantidadeNovaLinha;
  final String tipoEntregaItem;
}

class _DividirLinhaCarrinhoDialog extends StatefulWidget {
  const _DividirLinhaCarrinhoDialog({
    required this.nomeProduto,
    required this.quantidadeTotal,
    required this.tipoAtual,
  });

  final String nomeProduto;
  final int quantidadeTotal;
  final String tipoAtual;

  @override
  State<_DividirLinhaCarrinhoDialog> createState() =>
      _DividirLinhaCarrinhoDialogState();
}

class _DividirLinhaCarrinhoDialogState
    extends State<_DividirLinhaCarrinhoDialog> {
  late final TextEditingController _qtdController;
  late String _tipoNovaLinha;
  String? _erroQtd;

  @override
  void initState() {
    super.initState();
    _qtdController = TextEditingController(text: '1');
    _tipoNovaLinha = EntregaVendaHelper.proximoTipoItem(widget.tipoAtual);
  }

  @override
  void dispose() {
    _qtdController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final q = int.tryParse(_qtdController.text.trim());
    if (q == null || q <= 0 || q >= widget.quantidadeTotal) {
      setState(() {
        _erroQtd =
            'Informe de 1 a ${widget.quantidadeTotal - 1} unidades para o novo item.';
      });
      return;
    }
    Navigator.of(context).pop(
      _DividirLinhaCarrinhoResult(
        quantidadeNovaLinha: q,
        tipoEntregaItem: _tipoNovaLinha,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restante =
        widget.quantidadeTotal -
        (int.tryParse(_qtdController.text.trim()) ?? 0);
    return AlertDialog(
      title: const Text('Dividir Item'),
      content: AdaptiveDialogPane(
        desktopWidth: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.nomeProduto,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Neste item: ${widget.quantidadeTotal} un. · '
              'atual: ${EntregaVendaHelper.rotuloTipoItem(widget.tipoAtual)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qtdController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantidade no novo item',
                helperText:
                    'Este item ficara com ${restante.clamp(0, widget.quantidadeTotal)} un.',
                errorText: _erroQtd,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _erroQtd = null),
              onFieldSubmitted: (_) => _confirmar(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_tipoNovaLinha),
              initialValue: _tipoNovaLinha,
              decoration: const InputDecoration(
                labelText: 'Entrega do novo item',
              ),
              items: EntregaVendaHelper.tiposItem
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(EntregaVendaHelper.rotuloTipoItem(t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tipoNovaLinha = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Dividir')),
      ],
    );
  }
}

class _EntregaDialogResult {
  const _EntregaDialogResult({
    required this.valorFrete,
    required this.endereco,
    required this.observacao,
    required this.indiceEnderecoSelecionado,
  });

  final String valorFrete;
  final String endereco;
  final String observacao;
  final int indiceEnderecoSelecionado;
}

class _EntregaClienteDialog extends StatefulWidget {
  const _EntregaClienteDialog({
    required this.clienteNome,
    required this.valorFreteInicial,
    required this.enderecosDisponiveis,
    required this.indiceEnderecoInicial,
    required this.enderecoInicial,
    required this.observacaoInicial,
  });

  final String clienteNome;
  final String valorFreteInicial;
  final List<EnderecoCliente> enderecosDisponiveis;
  final int indiceEnderecoInicial;
  final String enderecoInicial;
  final String observacaoInicial;

  @override
  State<_EntregaClienteDialog> createState() => _EntregaClienteDialogState();
}

class _EntregaClienteDialogState extends State<_EntregaClienteDialog> {
  late final TextEditingController _freteController;
  late final TextEditingController _enderecoController;
  late final TextEditingController _obsController;
  late int _indiceEnderecoSelecionado;
  String? _erroEndereco;
  String? _erroFrete;

  @override
  void initState() {
    super.initState();
    _freteController = TextEditingController(text: widget.valorFreteInicial);
    _enderecoController = TextEditingController(text: widget.enderecoInicial);
    _obsController = TextEditingController(text: widget.observacaoInicial);
    _indiceEnderecoSelecionado = widget.enderecosDisponiveis.isEmpty
        ? 0
        : widget.indiceEnderecoInicial.clamp(
            0,
            widget.enderecosDisponiveis.length - 1,
          );
  }

  @override
  void dispose() {
    _freteController.dispose();
    _enderecoController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final endereco = _enderecoController.text.trim();
    if (endereco.isEmpty) {
      setState(() {
        _erroEndereco = 'Informe o endereco de entrega para continuar.';
      });
      return;
    }
    final freteTxt = _freteController.text.trim();
    if (freteTxt.isNotEmpty) {
      final frete = double.tryParse(
        freteTxt.replaceAll('.', '').replaceAll(',', '.'),
      );
      if (frete == null || frete < 0) {
        setState(() {
          _erroFrete = 'Valor de frete invalido.';
        });
        return;
      }
    }
    Navigator.of(context).pop(
      _EntregaDialogResult(
        valorFrete: freteTxt,
        endereco: endereco,
        observacao: _obsController.text.trim(),
        indiceEnderecoSelecionado: _indiceEnderecoSelecionado,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): _confirmar,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirmar,
      },
      child: AlertDialog(
        title: Text('Entrega de ${widget.clienteNome}'),
        content: AdaptiveDialogPane(
          desktopWidth: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _freteController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Valor do frete',
                    hintText: 'Ex.: 35,00',
                    errorText: _erroFrete,
                  ),
                  onChanged: (_) => setState(() => _erroFrete = null),
                ),
                const SizedBox(height: 8),
                if (widget.enderecosDisponiveis.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _indiceEnderecoSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Endereco do cliente',
                    ),
                    selectedItemBuilder: (context) {
                      return List.generate(widget.enderecosDisponiveis.length, (
                        index,
                      ) {
                        final endereco = widget.enderecosDisponiveis[index];
                        final rotulo = endereco.rotulo.trim().isNotEmpty
                            ? endereco.rotulo.trim()
                            : 'Endereco ${index + 1}';
                        final resumo = endereco.resumo();
                        final texto = resumo.isEmpty
                            ? rotulo
                            : '$rotulo - $resumo';
                        return Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            texto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      });
                    },
                    items: List.generate(widget.enderecosDisponiveis.length, (
                      index,
                    ) {
                      final endereco = widget.enderecosDisponiveis[index];
                      final rotulo = endereco.rotulo.trim().isNotEmpty
                          ? endereco.rotulo.trim()
                          : 'Endereco ${index + 1}';
                      final resumo = endereco.resumo();
                      final texto = resumo.isEmpty
                          ? rotulo
                          : '$rotulo - $resumo';
                      return DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          texto,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _indiceEnderecoSelecionado = value;
                        final endereco = widget.enderecosDisponiveis[value];
                        _enderecoController.text = endereco.resumo();
                        _obsController.text = endereco.referencia.trim();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _enderecoController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: 'Endereco de entrega',
                    errorText: _erroEndereco,
                  ),
                  onChanged: (_) => setState(() => _erroEndereco = null),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _obsController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Observacoes da entrega',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar (Esc)'),
          ),
          ElevatedButton(
            onPressed: _confirmar,
            child: const Text('Confirmar (Enter)'),
          ),
        ],
      ),
    );
  }
}

class _EditarQuantidadeCarrinhoDialog extends StatefulWidget {
  const _EditarQuantidadeCarrinhoDialog({
    required this.nomeProduto,
    required this.quantidadeInicial,
    required this.fracionada,
    required this.unidade,
  });

  final String nomeProduto;
  final String quantidadeInicial;
  final bool fracionada;
  final String unidade;

  @override
  State<_EditarQuantidadeCarrinhoDialog> createState() =>
      _EditarQuantidadeCarrinhoDialogState();
}

class _EditarQuantidadeCarrinhoDialogState
    extends State<_EditarQuantidadeCarrinhoDialog> {
  late final TextEditingController _qtdController;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _qtdController = TextEditingController(text: widget.quantidadeInicial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _qtdController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtdController.text.length,
      );
    });
  }

  @override
  void dispose() {
    _qtdController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final q = QuantidadeVendaUtil.parseEntradaPdv(
      _qtdController.text,
      fracionada: widget.fracionada,
    );
    if (q == null) {
      setState(() {
        _erro = widget.fracionada
            ? 'Informe uma quantidade maior que zero (ex.: 5,75).'
            : 'Informe uma quantidade maior que zero.';
      });
      return;
    }
    Navigator.of(context).pop(q);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quantidade'),
      content: AdaptiveDialogPane(
        desktopWidth: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.nomeProduto,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qtdController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantidade (${widget.unidade})',
                helperText: widget.fracionada
                    ? 'Aceita decimais (ex.: 5,75 ou 4.50).'
                    : 'Quantidade da embalagem.',
                errorText: _erro,
              ),
              keyboardType: widget.fracionada
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              inputFormatters: [
                QuantidadePdvInputFormatter(fracionada: widget.fracionada),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _erro = null),
              onFieldSubmitted: (_) => _confirmar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Aplicar')),
      ],
    );
  }
}

class _AdicionarAoOrcamentoDialog extends StatefulWidget {
  const _AdicionarAoOrcamentoDialog({
    required this.produtoRepository,
    required this.produto,
    required this.precoTipoInicial,
    required this.tipoEntregaInicial,
    required this.precoUnitarioDe,
    required this.formatarMoeda,
  });

  final dynamic produtoRepository;
  final Produto produto;
  final String precoTipoInicial;
  final String tipoEntregaInicial;
  final double Function(Produto produto, String precoTipo) precoUnitarioDe;
  final String Function(double) formatarMoeda;

  @override
  State<_AdicionarAoOrcamentoDialog> createState() =>
      _AdicionarAoOrcamentoDialogState();
}

class _AdicionarAoOrcamentoDialogState
    extends State<_AdicionarAoOrcamentoDialog> {
  late Produto _produto;
  late String _precoTipo;
  late String _tipoEntrega;
  late bool _quantidadeEmUnidadeCompra;
  late final TextEditingController _qtdController;
  final _qtdFocus = FocusNode(debugLabel: 'pdvDialogQtd');
  String? _erroQtd;

  void _recarregarProdutoDoBanco() {
    final fresh = widget.produtoRepository.obterPorId(widget.produto.id);
    if (fresh != null) {
      _produto = fresh;
    }
  }

  @override
  void initState() {
    super.initState();
    _produto = widget.produto;
    _recarregarProdutoDoBanco();
    _precoTipo = widget.precoTipoInicial;
    _tipoEntrega = EntregaVendaHelper.normalizarTipoItem(
      widget.tipoEntregaInicial,
    );
    _quantidadeEmUnidadeCompra = _produto.pdvPodeVenderEmUnidadeCompra;
    _qtdController = TextEditingController(text: '1');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _qtdFocus.requestFocus();
        _qtdController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _qtdController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _qtdController.dispose();
    _qtdFocus.dispose();
    super.dispose();
  }

  void _confirmar() {
    _recarregarProdutoDoBanco();
    final fracionada = QuantidadeVendaUtil.pdvAceitaDecimalDigitacao(
      emUnidadeCompra: _quantidadeEmUnidadeCompra,
    );
    final textoQtd = _qtdController.text;
    final q = QuantidadeVendaUtil.parseEntradaPdv(
      textoQtd,
      fracionada: true,
    );
    if (q == null) {
      setState(
        () => _erroQtd = fracionada
            ? 'Informe uma quantidade maior que zero (ex.: 5,75 ou 1.5).'
            : 'Informe uma quantidade maior que zero.',
      );
      return;
    }
    Navigator.of(context).pop(
      _AdicionarOrcamentoResult(
        quantidadeVenda: q,
        precoTipo: _precoTipo,
        tipoEntregaItem: _tipoEntrega,
        quantidadeEmUnidadeCompra: _quantidadeEmUnidadeCompra,
      ),
    );
  }

  String _previewSubtotalLinha(double precoUnit, bool fracionada) {
    final q = QuantidadeVendaUtil.parseEntradaPdv(
      _qtdController.text,
      fracionada: true,
    );
    if (q == null) return '';
    final qVenda =
        _quantidadeEmUnidadeCompra && _produto.pdvPodeVenderEmUnidadeCompra
        ? ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
            produto: _produto,
            quantidadeComercial: q,
          )
        : q;
    return ' · Subtotal: ${widget.formatarMoeda(qVenda * precoUnit)}';
  }

  String? _previewConversaoEstoque() {
    if (!_quantidadeEmUnidadeCompra || !_produto.pdvPodeVenderEmUnidadeCompra) {
      return null;
    }
    final q = QuantidadeVendaUtil.parseEntradaPdv(
          _qtdController.text,
          fracionada: true,
        ) ??
        0;
    if (q <= 0) return null;
    final qEst = ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
      produto: _produto,
      quantidadeComercial: q,
    );
    final uVenda = ProdutoEmbalagem.normalizarUnidade(_produto.unidade);
    final qEstTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
      _produto,
      qEst,
    );
    return 'Baixa de estoque: $qEstTxt $uVenda';
  }

  @override
  Widget build(BuildContext context) {
    final precoUnit = widget.precoUnitarioDe(_produto, _precoTipo);
    final fracionada = QuantidadeVendaUtil.pdvAceitaDecimalDigitacao(
      emUnidadeCompra: _quantidadeEmUnidadeCompra,
    );
    final podeEmbalagem = _produto.pdvPodeVenderEmUnidadeCompra;
    final uCompra = ProdutoEmbalagem.normalizarUnidade(
      _produto.unidadeCompraEfetiva,
    );
    final uVenda = ProdutoEmbalagem.normalizarUnidade(_produto.unidade);
    final previewEstoque = _previewConversaoEstoque();
    return AlertDialog(
      title: Text('Adicionar: ${_produto.nome}'),
      content: AdaptiveDialogPane(
        desktopWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fracionada)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.straighten, size: 18),
                    label: Text(
                      'Quantidade em $uVenda — aceita 5,75 ou 4.50',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            DropdownButtonFormField<String>(
              key: ValueKey(_precoTipo),
              initialValue: _precoTipo,
              decoration: const InputDecoration(labelText: 'Tipo de preco'),
              items: const [
                DropdownMenuItem(value: 'preco1', child: Text('Preco 1')),
                DropdownMenuItem(value: 'preco2', child: Text('Preco 2')),
                DropdownMenuItem(value: 'preco3', child: Text('Preco 3')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _precoTipo = value);
                }
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_tipoEntrega),
              initialValue: _tipoEntrega,
              decoration: const InputDecoration(
                labelText: 'Entrega deste item',
              ),
              items: EntregaVendaHelper.tiposItem
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(EntregaVendaHelper.rotuloTipoItem(t)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _tipoEntrega = value);
              },
            ),
            if (podeEmbalagem) ...[
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(uVenda)),
                  ButtonSegment(value: true, label: Text(uCompra)),
                ],
                selected: {_quantidadeEmUnidadeCompra},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _quantidadeEmUnidadeCompra = s.first);
                },
              ),
              if (_produto.rotuloConversaoEmbalagem.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _produto.rotuloConversaoEmbalagem,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              controller: _qtdController,
              focusNode: _qtdFocus,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _quantidadeEmUnidadeCompra && podeEmbalagem
                    ? 'Quantidade ($uCompra)'
                    : 'Quantidade ($uVenda)',
                helperText:
                    previewEstoque ??
                    'Permite decimais (ex.: 5,75 ou 4.50).',
                errorText: _erroQtd,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [
                QuantidadePdvInputFormatter(fracionada: true),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _erroQtd = null),
              onFieldSubmitted: (_) => _confirmar(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preco por $uVenda: ${widget.formatarMoeda(precoUnit)}'
                '${_previewSubtotalLinha(precoUnit, fracionada)}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Adicionar')),
      ],
    );
  }
}

/// F1–F3 com linha selecionada no carrinho: altera a tabela da linha.
class SelecionarPrecoListaIntent extends Intent {
  const SelecionarPrecoListaIntent(this.precoTipo);
  final String precoTipo;
}

/// Ctrl+F1/F2/F3: padrao de entrega (carrinho uniforme aplica nas linhas;
/// misto: so padrao — tecla E / Dividir por linha).
class SelecionarEntregaPadraoIntent extends Intent {
  const SelecionarEntregaPadraoIntent(this.tipoEntrega);
  final String tipoEntrega;
}

class PdvAbrirConsultaIntent extends Intent {
  const PdvAbrirConsultaIntent();
}

class PdvFocarPesquisaProdutosIntent extends Intent {
  const PdvFocarPesquisaProdutosIntent();
}

class PdvRecarregarProdutosIntent extends Intent {
  const PdvRecarregarProdutosIntent();
}

class PdvFocarCarrinhoIntent extends Intent {
  const PdvFocarCarrinhoIntent();
}

class PdvSalvarOrcamentoIntent extends Intent {
  const PdvSalvarOrcamentoIntent();
}

class PdvLerOrcamentoIntent extends Intent {
  const PdvLerOrcamentoIntent();
}

class PdvLimparPesquisaIntent extends Intent {
  const PdvLimparPesquisaIntent();
}

class PdvToggleCalculadoraIntent extends Intent {
  const PdvToggleCalculadoraIntent();
}

class PdvToggleObraCalculadoraIntent extends Intent {
  const PdvToggleObraCalculadoraIntent();
}

class _OrcamentoItemDraft implements PromocaoCarrinhoLinha {
  _OrcamentoItemDraft({
    required this.produto,
    required this.quantidade,
    required this.precoTipo,
    required this.precoUnitario,
    this.tipoEntregaItem = EntregaVendaHelper.tipoRetirada,
    this.quantidadeEmUnidadeCompra = false,
    this.promocaoId = 0,
    this.promocaoNome = '',
    this.precoUnitarioManual = false,
    this.botaForaAplicado = false,
    this.percentualBotaForaAplicado = 0,
  });

  @override
  final Produto produto;
  int quantidade;
  @override
  String precoTipo;
  @override
  double precoUnitario;
  String tipoEntregaItem;
  final bool quantidadeEmUnidadeCompra;
  @override
  int promocaoId;
  @override
  String promocaoNome;
  bool precoUnitarioManual;
  bool botaForaAplicado;
  double percentualBotaForaAplicado;

  @override
  bool get precoManual => precoUnitarioManual;

  bool get usaArmazenamentoFracionado {
    if (quantidadeEmUnidadeCompra) return false;
    return QuantidadeVendaUtil.armazenadoEmMilesimos(
      quantidade,
      cadastroFracionado: produto.permiteQuantidadeFracionada,
    );
  }

  double get quantidadeVendaEfetiva {
    if (quantidadeEmUnidadeCompra && produto.pdvPodeVenderEmUnidadeCompra) {
      return ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
        produto: produto,
        quantidadeComercial: quantidade.toDouble(),
      );
    }
    return QuantidadeVendaUtil.valorExibicao(
      quantidade,
      fracionada: usaArmazenamentoFracionado,
    );
  }

  String get quantidadeExibicaoTexto {
    if (quantidadeEmUnidadeCompra && produto.pdvPodeVenderEmUnidadeCompra) {
      return quantidade.toString();
    }
    return QuantidadeVendaUtil.formatarExibicao(
      quantidadeVendaEfetiva,
      fracionada: usaArmazenamentoFracionado,
    );
  }

  int get quantidadeParaPersistir =>
      ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
        produto: produto,
        quantidadeDigitada: quantidade,
        emUnidadeCompra: quantidadeEmUnidadeCompra,
      );

  @override
  int get quantidadeEstoque => quantidadeVendaEfetiva.ceil().clamp(0, 1 << 30);

  String get rotuloQuantidadeCarrinho =>
      ProdutoEmbalagem.rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: quantidade,
        emUnidadeCompra: quantidadeEmUnidadeCompra,
      );

  String get unidadeMedidaExibicao {
    final raw = quantidadeEmUnidadeCompra && produto.pdvPodeVenderEmUnidadeCompra
        ? produto.unidadeCompraEfetiva
        : produto.unidade;
    return rotuloUnidadeProdutoExibicao(raw);
  }

  double get subtotal => quantidadeVendaEfetiva * precoUnitario;
}

class _DialogoSelecionarVendedorPdv extends StatefulWidget {
  const _DialogoSelecionarVendedorPdv({
    required this.vendedoresAtivos,
    required this.pesquisarVendedores,
    required this.onConfirmar,
    required this.onCancelar,
  });

  final List<Vendedor> vendedoresAtivos;
  final List<Vendedor> Function(String termo) pesquisarVendedores;
  final ValueChanged<int> onConfirmar;
  final VoidCallback onCancelar;

  @override
  State<_DialogoSelecionarVendedorPdv> createState() =>
      _DialogoSelecionarVendedorPdvState();
}

class _DialogoSelecionarVendedorPdvState
    extends State<_DialogoSelecionarVendedorPdv> {
  late List<Vendedor> _vendedoresExibidos;
  int? _vendedorSelecionadoId;
  late final TextEditingController _pesquisaController;

  @override
  void initState() {
    super.initState();
    _vendedoresExibidos = widget.vendedoresAtivos.take(60).toList();
    _pesquisaController = TextEditingController();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  void _atualizarBusca(String termo) {
    final t = termo.trim();
    setState(() {
      _vendedoresExibidos = t.isEmpty
          ? widget.vendedoresAtivos.take(60).toList()
          : widget.pesquisarVendedores(t);
    });
  }

  String _nomeVendedor(Vendedor v) {
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    return nome.isEmpty ? 'Vendedor ${v.id}' : nome;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quem esta vendendo?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selecione o vendedor responsavel por esta venda.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pesquisaController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar vendedor',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _atualizarBusca,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: _vendedoresExibidos.isEmpty
                  ? const Center(child: Text('Nenhum vendedor encontrado.'))
                  : ListView.builder(
                      itemCount: _vendedoresExibidos.length,
                      itemBuilder: (context, index) {
                        final v = _vendedoresExibidos[index];
                        final codigo = v.codigoInterno.trim();
                        return ListTile(
                          dense: true,
                          selected: _vendedorSelecionadoId == v.id,
                          title: Text(_nomeVendedor(v)),
                          subtitle: codigo.isEmpty ? null : Text(codigo),
                          onTap: () =>
                              setState(() => _vendedorSelecionadoId = v.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onCancelar, child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _vendedorSelecionadoId == null
              ? null
              : () => widget.onConfirmar(_vendedorSelecionadoId!),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
