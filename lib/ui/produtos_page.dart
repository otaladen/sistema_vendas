import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../data/produto_repository.dart';
import '../domain/permissao_usuario.dart';
import '../domain/produto_unidade_exibicao.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../domain/fiscal/grupo_tributario_produto.dart';
import '../domain/fiscal/fiscal_regime_padrao.dart';
import '../domain/fiscal/produto_fiscal_catalog.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/produto_precificacao.dart';
import '../model/produto.dart';
import '../config/busca_imagem_config.dart';
import '../services/brasil_api_service.dart';
import '../services/gemini_service.dart';
import '../services/print_service.dart';
import '../services/compras_preditivas_service.dart';
import '../services/produto_imagem_busca_service.dart';
import '../services/trusted_http_client.dart';
import '../services/produto_imagem_service.dart';
import 'layout/app_layout.dart';
import 'widgets/abas_historico_produto_widget.dart';
import 'estoque/extrato_movimento_estoque_panel.dart';
import 'widgets/produto_busca_input.dart';

class _CadastroProdutoSalvarIntent extends Intent {
  const _CadastroProdutoSalvarIntent();
}

class _CadastroProdutoCancelarIntent extends Intent {
  const _CadastroProdutoCancelarIntent();
}

enum _BaseCalculoPrecoProduto { custoDigitado, custoMedio }

class ProdutosPage extends StatefulWidget {
  const ProdutosPage({
    super.key,
    required this.produtoRepository,
    required this.printService,
    this.usuarioLogado,
  });

  final ProdutoRepository produtoRepository;
  final PrintService printService;
  final UsuarioSistema? usuarioLogado;

  @override
  State<ProdutosPage> createState() => _ProdutosPageState();
}

class _ProdutosPageState extends State<ProdutosPage>
    with SafeSyncRefreshMixin, SingleTickerProviderStateMixin {
  static const List<String> _subAbasCadastro = [
    'Principal',
    'Precos',
    'Estoque',
    'Fiscal',
  ];
  static ButtonStyle get _estiloBotaoContornoCompacto =>
      OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  bool get _podeEditarPrecoProduto {
    final u = widget.usuarioLogado;
    if (u == null) return true;
    return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.editarPrecoProduto);
  }

  /// Larguras fixas para dados curtos (nao esticar ate metade da tela).
  static const double _wQtdInteira = 158;
  static const double _wNcm = 200;

  /// Área fixa quadrada da pré-visualização da foto no cadastro de produto.
  static const double _erpFotoPreviewSide = 176;

  /// Largura mínima para alinhar a foto à direita do formulário (senão empilha).
  static const double _erpFotoPreviewSideBySideBreakpoint = 680;

  /// Layout inputs à esquerda + painel KPI à direita no card de preços.
  static const double _erpPrecosKpiBreakpoint = 960;

  /// Rodapé fixo: empilha botões abaixo desta largura.
  static const double _erpRodapeAcaoBreakpoint = 520;

  /// Escala de espacamento do cadastro ERP (8 / 16 / 24).
  static const double _erpGap8 = 8;
  static const double _erpGap16 = 16;
  static const double _erpGap24 = 24;

  static const List<String> _unidades = [
    'UN',
    'M',
    'MTS',
    'M2',
    'M3',
    'KG',
    'SC',
    'CX',
    'LT',
  ];
  static const String _categoriaOutros = 'Outros';
  static const Map<String, List<String>> _categoriasMateriaisConstrucao = {
    'Cimento e Argamassas': ['Cimento', 'Argamassa', 'Rejunte', 'Cal'],
    'Telhas e Cobertura': [
      'Telha Ceramica',
      'Telha Fibrocimento',
      'Telha Metalica',
      'Telha PVC',
      'Cumeeira',
      'Rufos e Calhas',
      'Manta Termica',
      'Parafuso para Telha',
    ],
    'Estrutural e Alvenaria': [
      'Tijolo',
      'Bloco de Concreto',
      'Canaleta',
      'Areia',
      'Brita',
      'Pedra',
      'Aco para Construcao',
      'Vergalhao',
    ],
    'Tintas e Acessorios': [
      'Tinta Acrilica',
      'Tinta Esmalte',
      'Selador',
      'Verniz',
      'Rolo e Pincel',
    ],
    'Hidraulica': [
      'Tubos e Conexoes',
      'Registros',
      'Torneiras',
      'Caixa d\'agua',
      'Sifoes e Valvulas',
      'Bombas',
      'Irrigacao',
      'Acessorios para Banheiro',
    ],
    'Eletrica': [
      'Fios e Cabos',
      'Disjuntores',
      'Tomadas e Interruptores',
      'Quadro de Distribuicao',
      'Iluminacao',
      'Eletroduto',
      'Canaleta',
      'Luminaria LED',
    ],
    'Ferragens': [
      'Parafusos e Buchas',
      'Pregos',
      'Dobradiças',
      'Fechaduras',
      'Correntes e Cabos de Aco',
      'Abraçadeiras',
      'Chapas e Cantoneiras',
      'Fixadores',
    ],
    'Madeiras e Chapas': [
      'Compensado',
      'MDF',
      'OSB',
      'Vigas e Ripas',
      'Portas e Batentes',
    ],
    'Pisos e Revestimentos': [
      'Piso Ceramico',
      'Porcelanato',
      'Revestimento de Parede',
      'Rodape',
      'Pastilha',
    ],
    'Loucas e Metais': [
      'Vaso Sanitario',
      'Lavatório',
      'Cuba',
      'Torneira',
      'Chuveiro',
      'Misturador',
      'Assento Sanitario',
    ],
    'Impermeabilizacao e Quimicos': [
      'Impermeabilizante',
      'Vedante',
      'Silicone',
      'Espuma Expansiva',
      'Aditivo para Concreto',
      'Desmoldante',
    ],
    'Ferramentas': [
      'Manuais',
      'Eletricas',
      'Medicao',
      'EPIs',
      'Acessorios de Corte',
    ],
    'Jardinagem e Externo': [
      'Mangueira',
      'Grama Sintetica',
      'Ferramentas de Jardim',
      'Vaso e Cachepot',
      'Pedrisco Decorativo',
    ],
    'Forros e Divisorias': [
      'Forro PVC',
      'Forro Gesso',
      'Perfil para Drywall',
      'Chapa Drywall',
      'Acessorios Drywall',
    ],
    _categoriaOutros: [],
  };

  final _codigoInternoController = TextEditingController();
  final _nomeController = TextEditingController();
  final _nomeImpressaoController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _marcaController = TextEditingController();
  final _fornecedorController = TextEditingController();
  final _fabricanteController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _apelidosBuscaController = TextEditingController();
  final _ncmController = TextEditingController();
  final _cestController = TextEditingController();
  final _cfopVendaController = TextEditingController();
  final _localizacaoController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _preco1Controller = TextEditingController();
  final _preco2Controller = TextEditingController();
  final _preco3Controller = TextEditingController();
  final _estoqueController = TextEditingController();
  final _quantidadeMinimaController = TextEditingController();
  final _leadTimeDiasController = TextEditingController(text: '7');
  final _estoqueSegurancaController = TextEditingController();
  final _subcategoriaLivreController = TextEditingController();
  final _margemAlvoPreco1Controller = TextEditingController();
  final _margemAlvoPreco2Controller = TextEditingController();
  final _margemAlvoPreco3Controller = TextEditingController();
  final _quantidadeEmbalagemController = TextEditingController(text: '1');
  final _unidadeCompraController = TextEditingController();
  final _brasilApiService = BrasilApiService();
  final _geminiService = GeminiService();
  final _produtoImagemBuscaService = ProdutoImagemBuscaService();
  bool _consultandoGtin = false;
  bool _buscandoFoto = false;
  bool _consultandoNcm = false;
  bool _consultandoGemini = false;
  String _infoNcmBrasilApi = '';
  String _unidadeSelecionada = 'UN';
  String _grupoTributarioSelecionado = GrupoTributarioProduto.tributado.codigo;
  String _icmsOrigemSelecionado = kFiscalValorAutomatico;
  String _icmsCstSelecionado = kFiscalValorAutomatico;
  String _pisCofinsCstSelecionado = kFiscalValorAutomatico;
  _BaseCalculoPrecoProduto _baseCalculoPreco = _BaseCalculoPrecoProduto.custoDigitado;
  bool _embalagemMultiplica = true;
  bool _permiteQuantidadeFracionada = false;
  DateTime? _ultimaVendaEmCadastro;
  String? _categoriaSelecionada;
  String? _subcategoriaSelecionada;
  int? _produtoEmEdicaoId;
  bool _produtoAtivo = true;
  bool _gerarSkuAutomatico = true;
  bool _nomeImpressaoVinculadoAoNome = true;
  final _formKey = GlobalKey<FormState>();
  bool _tentouSalvar = false;
  late final ProdutoImagemService _produtoImagemService;
  String _fotoPathAtual = '';
  String? _fotoOrigemLocalPath;
  bool _fotoFoiRemovida = false;
  final ScrollController _scrollController = ScrollController();
  late final TabController _subAbaCadastroController;
  final FocusNode _codigoBarrasFocus =
      FocusNode(debugLabel: 'produtoCadastroBarras');
  int _historicoVersao = 0;
  final FocusNode _cadastroKeyboardFocusNode =
      FocusNode(debugLabel: 'produtosCadastroTeclado');

  String _status = '';
  bool _statusEhErro = false;
  final NumberFormat _moedaBrFormatter = NumberFormat('#,##0.00', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _subAbaCadastroController = TabController(
      length: _subAbasCadastro.length,
      vsync: this,
    );
    _produtoImagemService = ProdutoImagemService(
      imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
    );
    initSafeSyncRefresh(
      onReload: _atualizarAposSyncRede,
      bloquearAtualizacao: _bloquearSyncProdutos,
      aoConcluir: _snackbarDadosAtualizados,
    );
    _subAbaCadastroController.addListener(_onSubAbaCadastroChanged);
    _nomeController.addListener(_sincronizarNomeImpressaoSeVinculado);
    _nomeImpressaoController.addListener(_atualizarVinculoNomeImpressao);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focarBarrasSeNovoCadastro();
    });
  }

  void _onSubAbaCadastroChanged() {
    if (_subAbaCadastroController.indexIsChanging) return;
    if (!mounted) return;
    setState(() {});
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _sincronizarNomeImpressaoSeVinculado() {
    if (!_nomeImpressaoVinculadoAoNome) return;
    final nome = _nomeController.text;
    if (_nomeImpressaoController.text == nome) return;
    _nomeImpressaoController.text = nome;
  }

  void _atualizarVinculoNomeImpressao() {
    final nome = _nomeController.text.trim();
    final imp = _nomeImpressaoController.text.trim();
    final vinculado = imp.isEmpty || imp == nome;
    if (vinculado != _nomeImpressaoVinculadoAoNome) {
      setState(() => _nomeImpressaoVinculadoAoNome = vinculado);
    }
  }

  String _nomeImpressaoParaSalvar(String nomeCadastro) {
    if (_nomeImpressaoVinculadoAoNome) {
      return ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
        nome: nomeCadastro,
        nomeImpressao: '',
      );
    }
    return ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
      nome: nomeCadastro,
      nomeImpressao: _nomeImpressaoController.text,
    );
  }

  void _focarBarrasSeNovoCadastro() {
    if (_produtoEmEdicaoId != null) return;
    _codigoBarrasFocus.requestFocus();
  }

  bool _bloquearSyncProdutos() =>
      _temDadosNoFormulario() || SafeSyncRefreshMixin.focoEmCampoDeTexto();

  void _atualizarAposSyncRede() {
    if (!mounted || _bloquearSyncProdutos()) return;
    setState(() {});
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

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    _codigoInternoController.dispose();
    _nomeController.removeListener(_sincronizarNomeImpressaoSeVinculado);
    _nomeImpressaoController.removeListener(_atualizarVinculoNomeImpressao);
    _nomeController.dispose();
    _nomeImpressaoController.dispose();
    _descricaoController.dispose();
    _marcaController.dispose();
    _fornecedorController.dispose();
    _fabricanteController.dispose();
    _codigoBarrasController.dispose();
    _apelidosBuscaController.dispose();
    _ncmController.dispose();
    _cestController.dispose();
    _cfopVendaController.dispose();
    _localizacaoController.dispose();
    _precoCustoController.dispose();
    _preco1Controller.dispose();
    _preco2Controller.dispose();
    _preco3Controller.dispose();
    _estoqueController.dispose();
    _quantidadeMinimaController.dispose();
    _leadTimeDiasController.dispose();
    _estoqueSegurancaController.dispose();
    _subcategoriaLivreController.dispose();
    _margemAlvoPreco1Controller.dispose();
    _margemAlvoPreco2Controller.dispose();
    _margemAlvoPreco3Controller.dispose();
    _quantidadeEmbalagemController.dispose();
    _unidadeCompraController.dispose();
    _scrollController.dispose();
    _subAbaCadastroController.removeListener(_onSubAbaCadastroChanged);
    _subAbaCadastroController.dispose();
    _codigoBarrasFocus.dispose();
    _cadastroKeyboardFocusNode.dispose();
    super.dispose();
  }

  String _gerarSkuAutomaticamente() {
    return 'SKU-${DateTime.now().millisecondsSinceEpoch}';
  }

  bool _skuJaExiste(String skuNormalizado) {
    final produtos = widget.produtoRepository.listarTodos();
    for (final produto in produtos) {
      final mesmoSku =
          produto.codigoInterno.trim().toLowerCase() == skuNormalizado;
      final emEdicao =
          _produtoEmEdicaoId != null && produto.id == _produtoEmEdicaoId;
      if (mesmoSku && !emEdicao) {
        return true;
      }
    }
    return false;
  }

  bool _temDadosNoFormulario() {
    final controllers = [
      _codigoInternoController,
      _nomeController,
      _descricaoController,
      _marcaController,
      _fornecedorController,
      _fabricanteController,
      _codigoBarrasController,
      _apelidosBuscaController,
      _ncmController,
      _cestController,
      _cfopVendaController,
      _localizacaoController,
      _precoCustoController,
      _preco1Controller,
      _preco2Controller,
      _preco3Controller,
      _estoqueController,
      _quantidadeMinimaController,
      _leadTimeDiasController,
      _estoqueSegurancaController,
    ];
    final existeTexto = controllers.any(
      (controller) => controller.text.trim().isNotEmpty,
    );
    return existeTexto ||
        _produtoEmEdicaoId != null ||
        _unidadeSelecionada != 'UN' ||
        _categoriaSelecionada != null ||
        _subcategoriaSelecionada != null ||
        !_produtoAtivo ||
        _fotoPathAtual.trim().isNotEmpty ||
        (_fotoOrigemLocalPath?.trim().isNotEmpty ?? false) ||
        _subcategoriaLivreController.text.trim().isNotEmpty;
  }

  String? _fotoPreviewPath() {
    if (_fotoOrigemLocalPath != null &&
        _fotoOrigemLocalPath!.trim().isNotEmpty) {
      return _fotoOrigemLocalPath;
    }
    if (_fotoPathAtual.trim().isNotEmpty) {
      return _fotoPathAtual;
    }
    return null;
  }

  // --- Layout ERP (cadastro de produtos) ---

  TextStyle _erpLabelStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: cs.onSurface.withValues(alpha: 0.72),
    );
  }

  Widget _erpFieldLabel(String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _erpGap8),
      child: Text(text, style: _erpLabelStyle(context)),
    );
  }

  Widget _buildPainelPontoPedido(BuildContext context) {
    final estoqueAtual = int.tryParse(_estoqueController.text) ?? 0;
    final leadTime = int.tryParse(_leadTimeDiasController.text) ?? 7;
    final seguranca = int.tryParse(_estoqueSegurancaController.text) ?? 0;
    final minimo = int.tryParse(_quantidadeMinimaController.text) ?? 0;
    final produto = _produtoEmEdicaoId != null
        ? widget.produtoRepository.obterPorId(_produtoEmEdicaoId!)
        : null;
    final comprasSvc = ComprasPreditivasService(
      widget.produtoRepository.objectBox,
    );

    double media = 0;
    double pp;
    bool critico;
    bool semGiroConfiavel;

    if (produto != null) {
      produto.leadTimeDias = leadTime > 0 ? leadTime : 7;
      produto.estoqueSeguranca = seguranca;
      produto.estoqueAtual = estoqueAtual;
      media = produto.vendaMediaDiaria;
      semGiroConfiavel = !comprasSvc.temGiroVendaConfiavel(produto);
      pp = comprasSvc.calcularPontoPedidoExibicao(produto);
      critico = comprasSvc.verificarEstoqueCritico(produto);
    } else {
      media = 0;
      semGiroConfiavel = true;
      pp = (seguranca > 0 ? seguranca : minimo).toDouble();
      critico = estoqueAtual <= pp;
    }

    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_erpGap8),
      decoration: BoxDecoration(
        color: critico
            ? (semantic?.errorBg ?? theme.colorScheme.errorContainer)
                .withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: critico
              ? theme.colorScheme.error.withValues(alpha: 0.4)
              : theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compras preditivas (ponto de pedido)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            semGiroConfiavel
                ? 'Produto novo ou sem giro: alerta pelo estoque de seguranca '
                    '(min. ${comprasSvc.diasMinimosCadastroParaGiro} dias de cadastro + vendas).'
                : 'PP = (media diaria x lead time) + estoque seguranca',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            semGiroConfiavel
                ? 'Limiar seguranca: ${pp.toStringAsFixed(0)} un · '
                    'Atual: $estoqueAtual un'
                : 'Media diaria: ${media.toStringAsFixed(2)} un/dia · '
                    'PP: ${pp.toStringAsFixed(1)} un · Atual: $estoqueAtual un',
            style: theme.textTheme.bodyMedium,
          ),
          if (critico)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                semGiroConfiavel
                    ? 'Alerta: estoque no ou abaixo do limiar de seguranca.'
                    : 'Alerta: estoque no ou abaixo do ponto de pedido.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic?.errorFg ?? theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _erpInputDecoration(
    BuildContext context, {
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final subtle = cs.outline.withValues(alpha: 0.5);
    return InputDecoration(
      isDense: true,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: subtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
    );
  }

  Widget _erpSurfaceCard({
    required BuildContext context,
    required String title,
    IconData? icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: _erpGap16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(_erpGap24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: cs.primary),
                const SizedBox(width: _erpGap8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _erpGap16),
          ...children,
        ],
      ),
    );
  }

  Widget _erpResponsiveGrid(BuildContext context, List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW >= 1200
            ? 4
            : maxW >= 960
            ? 3
            : maxW >= 640
            ? 2
            : 1;
        const gap = _erpGap16;
        final usable = maxW - gap * (cols - 1);
        final cellW = cols > 0 ? usable / cols : maxW;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: fields
              .map((w) => SizedBox(width: cols <= 1 ? maxW : cellW, child: w))
              .toList(),
        );
      },
    );
  }

  Widget _erpFinancialMetricChip(
    BuildContext context,
    String metricName,
    double pct,
  ) {
    final theme = Theme.of(context);
    final positive = pct > 0;
    final bg = positive
        ? Colors.green.shade50
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85);
    final fg = positive
        ? Colors.green.shade800
        : theme.colorScheme.onSurface.withValues(alpha: 0.52);
    final bd = positive
        ? Colors.green.shade200
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$metricName: ${pct.toStringAsFixed(2)}%',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: fg,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _erpKpiLinhaTabelaPreco(
    BuildContext context, {
    required String titulo,
    required double margem,
    required double markup,
    bool isLast = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : _erpGap8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(_erpGap16),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: _erpGap8),
            Wrap(
              spacing: _erpGap8,
              runSpacing: _erpGap8,
              children: [
                _erpFinancialMetricChip(context, 'Margem', margem),
                _erpFinancialMetricChip(context, 'Markup', markup),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _erpPainelResumoFinanceiroKpis(
    BuildContext context, {
    required double margem1,
    required double markup1,
    required double margem2,
    required double markup2,
    required double margem3,
    required double markup3,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(_erpGap16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest.withValues(alpha: 0.5),
            cs.surfaceContainerHighest.withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 22, color: cs.primary),
              const SizedBox(width: _erpGap8),
              Expanded(
                child: Text(
                  'Indicadores de rentabilidade',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _erpGap16),
          _erpKpiLinhaTabelaPreco(
            context,
            titulo: 'A prazo (Preco 1)',
            margem: margem1,
            markup: markup1,
          ),
          _erpKpiLinhaTabelaPreco(
            context,
            titulo: 'A vista (Preco 2)',
            margem: margem2,
            markup: markup2,
          ),
          _erpKpiLinhaTabelaPreco(
            context,
            titulo: 'Atacado (Preco 3)',
            margem: margem3,
            markup: markup3,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCabecalhoFixoCadastro(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sku = _codigoInternoController.text.trim();
    final skuRotulo = _gerarSkuAutomatico
        ? 'SKU automatico ao salvar'
        : (sku.isEmpty ? 'SKU manual pendente' : 'SKU $sku');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _erpGap16,
          _erpGap8,
          _erpGap16,
          _erpGap8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final empilhar = constraints.maxWidth < 720;
                final campoBarras = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _erpFieldLabel('Codigo de barras (EAN)', context),
                    TextField(
                      focusNode: _codigoBarrasFocus,
                      controller: _codigoBarrasController,
                      textInputAction: TextInputAction.next,
                      decoration: _erpInputDecoration(
                        context,
                        hint: 'Leia ou digite o GTIN',
                        suffixIcon: _suffixConsultaBrasilApi(
                          carregando: _consultandoGtin,
                          tooltip: 'Buscar produto na Brasil API',
                          onPressed: _consultandoGtin
                              ? null
                              : _consultarGtinBrasilApi,
                        ),
                      ),
                    ),
                  ],
                );
                final campoNome = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _erpFieldLabel('Nome do produto', context),
                    TextFormField(
                      controller: _nomeController,
                      validator: _validarNome,
                      textInputAction: TextInputAction.next,
                      decoration: _erpInputDecoration(
                        context,
                        helper: 'Nome + Marca + Volume (ex.: Tinta Coral 18L)',
                        suffixIcon: _suffixAcaoCampo(
                          carregando: _consultandoGemini,
                          tooltip:
                              'Padronizar nome, categoria e unidade com IA',
                          icon: Icons.auto_awesome_outlined,
                          onPressed: _consultandoGemini
                              ? null
                              : _padronizarProdutoComGemini,
                        ),
                      ),
                    ),
                  ],
                );
                final campoNomeImpressao = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _erpFieldLabel('Nome impressao', context),
                    TextFormField(
                      controller: _nomeImpressaoController,
                      textInputAction: TextInputAction.next,
                      decoration: _erpInputDecoration(
                        context,
                        helper:
                            'Cupom, orcamento e NF-e. Inicia igual ao nome; '
                            'edite aqui para texto diferente na impressao.',
                      ),
                    ),
                  ],
                );
                if (empilhar) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      campoBarras,
                      const SizedBox(height: _erpGap8),
                      campoNome,
                      const SizedBox(height: _erpGap8),
                      campoNomeImpressao,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: campoBarras),
                        const SizedBox(width: _erpGap16),
                        Expanded(flex: 3, child: campoNome),
                      ],
                    ),
                    const SizedBox(height: _erpGap8),
                    campoNomeImpressao,
                  ],
                );
              },
            ),
            const SizedBox(height: _erpGap8),
            Wrap(
              spacing: _erpGap8,
              runSpacing: _erpGap8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(skuRotulo),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    _produtoAtivo ? 'Ativo no PDV' : 'Inativo no PDV',
                  ),
                  backgroundColor: _produtoAtivo
                      ? scheme.primaryContainer.withValues(alpha: 0.55)
                      : scheme.errorContainer.withValues(alpha: 0.4),
                ),
                if (_produtoEmEdicaoId != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Edicao #${_produtoEmEdicaoId!}'),
                  ),
                if (_ultimaVendaEmCadastro != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'Ultima venda: ${DateFormat('dd/MM/yy HH:mm').format(_ultimaVendaEmCadastro!.toLocal())}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: _erpGap8),
            _erpFieldLabel('Apelidos e codigos de busca', context),
            TextField(
              controller: _apelidosBuscaController,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.next,
              decoration: _erpInputDecoration(
                context,
                hint: 'Ex.: bacia sabara; cod fornecedor 8821; 7891234567890',
                helper:
                    'Nomes de balcao, SKU fornecedor ou EAN alternativo. Separe com ; ou quebra de linha.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCamposNcmCadastro(BuildContext context) {
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _erpFieldLabel('NCM', context),
          SizedBox(
            width: _wNcm,
            child: TextFormField(
              controller: _ncmController,
              keyboardType: TextInputType.number,
              maxLength: 10,
              validator: _validarNcm,
              onChanged: (_) {
                if (_infoNcmBrasilApi.isNotEmpty) {
                  setState(() => _infoNcmBrasilApi = '');
                }
              },
              decoration: _erpInputDecoration(
                context,
                helper: '8 digitos — obrigatorio p/ NFC-e',
                suffixIcon: _suffixConsultaBrasilApi(
                  carregando: _consultandoNcm,
                  tooltip: 'Conferir descricao oficial do NCM',
                  onPressed:
                      _consultandoNcm ? null : _consultarNcmBrasilApi,
                ),
              ),
            ),
          ),
          if (_infoNcmBrasilApi.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _infoNcmBrasilApi,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
        ],
      ),
    ];
  }

  Widget _erpRodapeAcaoCadastroProduto(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final saveStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    );

    final cancelStyle = OutlinedButton.styleFrom(
      foregroundColor: Color.lerp(cs.onSurface, cs.error, 0.35)!,
      side: BorderSide(color: cs.outline.withValues(alpha: 0.42)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    );

    final etiquetaStyle = OutlinedButton.styleFrom(
      foregroundColor: cs.onSurfaceVariant,
      side: BorderSide(color: cs.outline.withValues(alpha: 0.55)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _erpRodapeAcaoBreakpoint;

        Widget salvar = Tooltip(
          message: 'Salvar cadastro (F5 ou F10)',
          child: ElevatedButton.icon(
            style: saveStyle,
            onPressed: _salvarProduto,
            icon: const Icon(Icons.save_rounded),
            label: const Text(
              'Salvar (F5 · F10)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );

        Widget cancelar = Tooltip(
          message: 'Cancelar / limpar (Esc)',
          child: OutlinedButton(
            style: cancelStyle,
            onPressed: _limparFormularioComConfirmacao,
            child: const Text('Cancelar (Esc)'),
          ),
        );

        Widget etiqueta = Tooltip(
          message: 'Imprimir etiqueta de teste (F11)',
          child: OutlinedButton.icon(
            style: etiquetaStyle,
            onPressed: _imprimirEtiquetaProduto,
            icon: const Icon(Icons.print_rounded),
            label: const Text('Imprimir Etiqueta (F11)'),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: double.infinity, child: cancelar),
              const SizedBox(height: _erpGap8),
              SizedBox(width: double.infinity, child: etiqueta),
              const SizedBox(height: _erpGap8),
              SizedBox(width: double.infinity, child: salvar),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            cancelar,
            const SizedBox(width: _erpGap16),
            etiqueta,
            const SizedBox(width: _erpGap16),
            salvar,
          ],
        );
      },
    );
  }

  /// Quadrado dedicado à pré-visualização (sempre visível; estado vazio elegante).
  Widget _erpProdutoFotoPreviewSquare(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final path = _fotoPreviewPath();
    final side = _erpFotoPreviewSide;

    Widget child;
    if (path != null) {
      child = ColoredBox(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          width: side,
          height: side,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(_erpGap16),
                child: Text(
                  'Nao foi possivel carregar a imagem.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } else {
      child = DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.85)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 42,
              color: cs.outline.withValues(alpha: 0.9),
            ),
            const SizedBox(height: _erpGap8),
            Text(
              'Sem imagem',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: side,
      height: side,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }

  String _normalizarNomeProduto(String nome) {
    final texto = nome.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (texto.isEmpty) {
      return '';
    }
    const conectores = {
      'de',
      'da',
      'do',
      'das',
      'dos',
      'e',
      'em',
      'com',
      'para',
      'por',
    };
    const siglas = {
      'pvc',
      'uv',
      'led',
      'mdf',
      'osb',
      'ac',
      'cp',
      'kg',
      'g',
      'mg',
      'mm',
      'cm',
      'm',
      'm2',
      'm3',
      'l',
      'lt',
      'ml',
      'w',
      'v',
      'a',
      'un',
      'cx',
      'sc',
    };

    final tokens = texto.split(' ').where((parte) => parte.isNotEmpty).toList();
    final normalizados = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final tokenOriginal = tokens[i];
      final token = tokenOriginal.toLowerCase();
      if (siglas.contains(token)) {
        normalizados.add(token.toUpperCase());
        continue;
      }
      if (token.contains('/')) {
        final partes = token.split('/');
        final frac = partes
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .join('/');
        normalizados.add(frac);
        continue;
      }
      if (i > 0 && conectores.contains(token)) {
        normalizados.add(token);
        continue;
      }
      final inicial = token[0].toUpperCase();
      final restante = token.length > 1 ? token.substring(1).toLowerCase() : '';
      normalizados.add('$inicial$restante');
    }
    return normalizados.join(' ');
  }

  void _definirStatus(String mensagem, {required bool erro}) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    setState(() {
      _status = mensagem;
      _statusEhErro = erro;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro
            ? semantic?.errorFg ?? Colors.red.shade700
            : semantic?.successFg ?? Colors.green.shade700,
      ),
    );
  }

  void _resetarFormulario() {
    setState(() {
      _codigoInternoController.clear();
      _nomeController.clear();
      _nomeImpressaoController.clear();
      _nomeImpressaoVinculadoAoNome = true;
      _descricaoController.clear();
      _marcaController.clear();
      _fornecedorController.clear();
      _fabricanteController.clear();
      _codigoBarrasController.clear();
      _apelidosBuscaController.clear();
      _ncmController.clear();
      _cestController.clear();
      _cfopVendaController.clear();
      _localizacaoController.clear();
      _grupoTributarioSelecionado = GrupoTributarioProduto.tributado.codigo;
      _icmsOrigemSelecionado = kFiscalValorAutomatico;
      _icmsCstSelecionado = kFiscalValorAutomatico;
      _pisCofinsCstSelecionado = kFiscalValorAutomatico;
      _precoCustoController.clear();
      _preco1Controller.clear();
      _preco2Controller.clear();
      _preco3Controller.clear();
      _estoqueController.clear();
      _quantidadeMinimaController.clear();
      _leadTimeDiasController.text = '7';
      _estoqueSegurancaController.clear();
      _subcategoriaLivreController.clear();
      _unidadeSelecionada = 'UN';
      _categoriaSelecionada = null;
      _subcategoriaSelecionada = null;
      _produtoEmEdicaoId = null;
      _produtoAtivo = true;
      _gerarSkuAutomatico = true;
      _tentouSalvar = false;
      _fotoPathAtual = '';
      _fotoOrigemLocalPath = null;
      _fotoFoiRemovida = false;
      _consultandoGtin = false;
      _consultandoNcm = false;
      _consultandoGemini = false;
      _buscandoFoto = false;
      _infoNcmBrasilApi = '';
      _subAbaCadastroController.index = 0;
      _baseCalculoPreco = _BaseCalculoPrecoProduto.custoDigitado;
      _embalagemMultiplica = true;
      _permiteQuantidadeFracionada = false;
      _ultimaVendaEmCadastro = null;
      _margemAlvoPreco1Controller.clear();
      _margemAlvoPreco2Controller.clear();
      _margemAlvoPreco3Controller.clear();
      _quantidadeEmbalagemController.text = '1';
      _unidadeCompraController.clear();
    });
    _formKey.currentState?.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focarBarrasSeNovoCadastro();
    });
  }

  Future<void> _importarFotoProduto() async {
    final pathSelecionado = await _produtoImagemService.selecionarImagemLocal();
    if (pathSelecionado == null) {
      return;
    }
    setState(() {
      _fotoOrigemLocalPath = pathSelecionado;
      _fotoFoiRemovida = false;
    });
  }

  void _removerFotoProduto() {
    setState(() {
      _fotoOrigemLocalPath = null;
      if (_fotoPathAtual.trim().isNotEmpty) {
        _fotoFoiRemovida = true;
      }
      _fotoPathAtual = '';
    });
  }

  Future<void> _excluirArquivoTemporarioSeExistir(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<void> _abrirUrlExterna(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri);
      }
    } catch (_) {
      if (mounted) {
        _snackbarBrasilApi('Nao foi possivel abrir: $url', erro: true);
      }
    }
  }

  Future<void> _mostrarDialogoErroGemini(GeminiServiceException erro) async {
    final passos = erro.instrucoesCorrecao ?? const <String>[];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API Gemini indisponivel'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(erro.message),
              if (passos.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (var i = 0; i < passos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${i + 1}. ${passos[i]}'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          if (erro.chaveBloqueadaParaApi)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _abrirUrlExterna('https://aistudio.google.com/apikey');
              },
              child: const Text('Criar chave Gemini'),
            ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoConfigurarGemini() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chave Gemini nao configurada'),
        content: const SingleChildScrollView(
          child: Text(
            'Para padronizar nome, categoria e unidade com IA:\n\n'
            '1. Abra o menu principal > Configuracoes > aba Empresa.\n'
            '2. Na secao "IA — padronizar produtos", clique em '
            '"Criar chave no AI Studio" e gere uma chave gratuita.\n'
            '3. Cole a chave (AIza...) e clique em "Salvar chave Gemini".\n'
            '4. Volte ao cadastro de produtos e use o botao de IA novamente.\n\n'
            'Alternativa avancada: variavel de ambiente GEMINI_API_KEY ou '
            'flutter run --dart-define=GEMINI_API_KEY=sua_chave',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _abrirUrlExterna('https://aistudio.google.com/apikey');
            },
            child: const Text('Criar chave no AI Studio'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoErroBuscaImagem(BuscaImagemException erro) async {
    final passos = erro.instrucoesCorrecao ?? const <String>[];
    final url = erro.urlAtivacao;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Busca de foto indisponivel'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(erro.message),
              if (passos.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (var i = 0; i < passos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${i + 1}. ${passos[i]}'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          if (url != null && url.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _abrirUrlExterna(url);
              },
              child: const Text('Abrir ajuda'),
            ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoConfigBuscaImagem() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Busca de foto'),
        content: const Text(
          'A busca usa DuckDuckGo (gratuita, sem cadastro). '
          'Confira sua conexao com a internet e tente de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _buscarFotoProdutoNaWeb() async {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      _snackbarBrasilApi(
        'Informe o nome do produto (ou padronize com IA) antes de buscar foto.',
        erro: true,
      );
      return;
    }

    if (!BuscaImagemConfig.configurado) {
      await _mostrarDialogoConfigBuscaImagem();
      return;
    }

    final termo = ProdutoImagemBuscaService.montarTermoBusca(
      nome: nome,
      marca: _marcaController.text,
    );

    final pathAnterior = _fotoOrigemLocalPath;
    setState(() => _buscandoFoto = true);

    try {
      final pathLocal = await _produtoImagemBuscaService
          .buscarEBaixarPrimeiraImagem(termo);
      if (!mounted) return;

      if (pathLocal == null) {
        _snackbarBrasilApi(
          'Nenhuma imagem encontrada ou baixavel para "$termo".',
          erro: true,
        );
        return;
      }

      await _excluirArquivoTemporarioSeExistir(pathAnterior);
      if (!mounted) return;

      setState(() {
        _fotoOrigemLocalPath = pathLocal;
        _fotoFoiRemovida = false;
      });

      final semantic = Theme.of(context).extension<AppSemanticColors>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Foto carregada na pre-visualizacao. Salve o produto para gravar.',
          ),
          duration: const Duration(seconds: 4),
          backgroundColor: semantic?.successFg ?? Colors.green.shade700,
        ),
      );
    } on BuscaImagemConfigException catch (e) {
      if (e.instrucoesCorrecao != null && e.instrucoesCorrecao!.isNotEmpty) {
        await _mostrarDialogoErroBuscaImagem(
          BuscaImagemException(
            e.message,
            instrucoesCorrecao: e.instrucoesCorrecao,
            urlAtivacao: BuscaImagemConfig.urlCadastroBraveApi,
            codigoErro: 'CONFIG_MISSING',
          ),
        );
      } else {
        _snackbarBrasilApi(e.message, erro: true);
      }
    } on BuscaImagemException catch (e) {
      if (e.instrucoesCorrecao != null && e.instrucoesCorrecao!.isNotEmpty) {
        await _mostrarDialogoErroBuscaImagem(e);
      } else {
        _snackbarBrasilApi(e.message, erro: true);
      }
    } catch (e) {
      final msg = isFalhaSslHandshake(e)
          ? mensagemErroSslAmigavel()
          : 'Erro ao buscar foto: $e';
      _snackbarBrasilApi(msg, erro: true);
    } finally {
      if (mounted) setState(() => _buscandoFoto = false);
    }
  }

  Future<void> _limparFormularioComConfirmacao() async {
    if (!_temDadosNoFormulario()) {
      _resetarFormulario();
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Limpar formulario'),
          content: const Text(
            'Existem dados preenchidos. Deseja limpar os campos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Limpar'),
            ),
          ],
        );
      },
    );
    if (confirmar == true) {
      _resetarFormulario();
      _definirStatus('Formulario limpo com sucesso.', erro: false);
    }
  }

  Future<void> _excluirProdutoEmEdicao() async {
    final produtoId = _produtoEmEdicaoId;
    if (produtoId == null) {
      _definirStatus('Selecione um produto para excluir.', erro: true);
      return;
    }
    final produto = widget.produtoRepository.obterPorId(produtoId);
    if (produto == null) {
      _definirStatus('Produto nao encontrado para exclusao.', erro: true);
      _resetarFormulario();
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir produto'),
          content: Text(
            'Deseja realmente excluir o produto "${produto.nome}"?\n'
            'Essa acao nao pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) return;

    final removido = widget.produtoRepository.remover(produtoId);
    if (!removido) {
      _definirStatus('Nao foi possivel excluir o produto.', erro: true);
      return;
    }
    if (produto.fotoPath.trim().isNotEmpty) {
      await _produtoImagemService.removerImagemProduto(produto.fotoPath);
    }
    _resetarFormulario();
    _definirStatus('Produto excluido com sucesso.', erro: false);
  }

  /// Custo medio para exibicao: ponderado pelas entradas de NF-e; senao acompanha o preco de custo.
  double _custoMedioInteligenteParaExibicao() {
    final precoDigitado =
        _parseValorMonetario(_precoCustoController.text) ?? 0.0;
    final id = _produtoEmEdicaoId;
    if (id != null && id > 0) {
      final cm = widget.produtoRepository
          .calcularCustoMedioPonderadoPorEntradasNfe(id);
      if (cm != null) {
        return cm;
      }
    }
    return precoDigitado < 0 ? 0 : precoDigitado;
  }

  bool _custoMedioDerivadoDeHistoricoNfe() {
    final id = _produtoEmEdicaoId;
    if (id == null || id <= 0) return false;
    return widget.produtoRepository.calcularCustoMedioPonderadoPorEntradasNfe(
          id,
        ) !=
        null;
  }

  double _custoBaseParaCalculoPrecos() {
    if (_baseCalculoPreco == _BaseCalculoPrecoProduto.custoMedio) {
      return _custoMedioInteligenteParaExibicao();
    }
    final digitado = _parseValorMonetario(_precoCustoController.text) ?? 0;
    return digitado < 0 ? 0 : digitado;
  }

  double _margemCalculadaPorController(TextEditingController precoController) {
    final custo = _custoBaseParaCalculoPrecos();
    final venda = _parseValorMonetario(precoController.text) ?? 0;
    return ProdutoPrecificacao.margemSobrePrecoVenda(
      custo: custo,
      precoVenda: venda,
    );
  }

  double _markupCalculadoPorController(TextEditingController precoController) {
    final custo = _custoBaseParaCalculoPrecos();
    final venda = _parseValorMonetario(precoController.text) ?? 0;
    if (custo <= 0) {
      return 0;
    }
    return ((venda - custo) / custo) * 100;
  }

  double _margemAlvoOuAtual(
    TextEditingController alvo,
    TextEditingController preco,
  ) {
    final texto = alvo.text.trim().replaceAll(',', '.');
    if (texto.isNotEmpty) {
      final v = double.tryParse(texto);
      if (v != null) return v.clamp(0, 95);
    }
    return _margemCalculadaPorController(preco);
  }

  void _aplicarMargemNosTresPrecos() {
    final custo = _custoBaseParaCalculoPrecos();
    if (custo <= 0) {
      _definirStatus(
        'Informe o preco de custo ou use custo medio (NF-e) como base.',
        erro: true,
      );
      return;
    }
    final m1 = _margemAlvoOuAtual(_margemAlvoPreco1Controller, _preco1Controller);
    final m2 = _margemAlvoOuAtual(_margemAlvoPreco2Controller, _preco2Controller);
    final m3 = _margemAlvoOuAtual(_margemAlvoPreco3Controller, _preco3Controller);
    setState(() {
      _preco1Controller.text = _formatarValorMonetario(
        ProdutoPrecificacao.precoComMargemSobreVenda(
          custo: custo,
          margemPercentual: m1,
        ),
      );
      _preco2Controller.text = _formatarValorMonetario(
        ProdutoPrecificacao.precoComMargemSobreVenda(
          custo: custo,
          margemPercentual: m2,
        ),
      );
      _preco3Controller.text = _formatarValorMonetario(
        ProdutoPrecificacao.precoComMargemSobreVenda(
          custo: custo,
          margemPercentual: m3,
        ),
      );
      _margemAlvoPreco1Controller.text = m1.toStringAsFixed(1);
      _margemAlvoPreco2Controller.text = m2.toStringAsFixed(1);
      _margemAlvoPreco3Controller.text = m3.toStringAsFixed(1);
    });
    final base = _baseCalculoPreco == _BaseCalculoPrecoProduto.custoMedio
        ? 'custo medio'
        : 'custo digitado';
    _definirStatus(
      'Precos calculados com margem sobre $base (${_formatarValorMonetario(custo)}).',
      erro: false,
    );
  }

  double _lerQuantidadeEmbalagem() {
    final t = _quantidadeEmbalagemController.text.trim().replaceAll(',', '.');
    final v = double.tryParse(t);
    if (v == null || v <= 0) return 1;
    return v;
  }

  Widget _buildPainelCalcularMargemPrecos(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(_erpGap16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Calcular precos pela margem',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: _erpGap8),
          Text(
            'Base: ${_formatarValorMonetario(_custoBaseParaCalculoPrecos())} '
            '(${_baseCalculoPreco == _BaseCalculoPrecoProduto.custoMedio ? 'custo medio' : 'custo digitado'})',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: _erpGap8),
          SegmentedButton<_BaseCalculoPrecoProduto>(
            segments: const [
              ButtonSegment(
                value: _BaseCalculoPrecoProduto.custoDigitado,
                label: Text('Custo digitado'),
              ),
              ButtonSegment(
                value: _BaseCalculoPrecoProduto.custoMedio,
                label: Text('Custo medio'),
              ),
            ],
            selected: {_baseCalculoPreco},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              setState(() => _baseCalculoPreco = s.first);
            },
          ),
          const SizedBox(height: _erpGap8),
          _erpResponsiveGrid(context, [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _erpFieldLabel('Margem alvo Preco 1 (%)', context),
                TextField(
                  controller: _margemAlvoPreco1Controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _erpInputDecoration(
                    context,
                    hint: 'Ex.: 35 — vazio usa margem atual',
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _erpFieldLabel('Margem alvo Preco 2 (%)', context),
                TextField(
                  controller: _margemAlvoPreco2Controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _erpInputDecoration(context),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _erpFieldLabel('Margem alvo Preco 3 (%)', context),
                TextField(
                  controller: _margemAlvoPreco3Controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _erpInputDecoration(context),
                ),
              ],
            ),
          ]),
          const SizedBox(height: _erpGap8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _aplicarMargemNosTresPrecos,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Aplicar margem nos 3 precos'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardEmbalagemUnidade(BuildContext context) {
    final uVenda = _normalizarUnidade(_unidadeSelecionada);
    final fator = _lerQuantidadeEmbalagem();
    final uCompra = _unidadeCompraController.text.trim().isEmpty
        ? uVenda
        : _unidadeCompraController.text.trim().toUpperCase();
    final preview = fator <= 1 || (fator - 1).abs() < 0.0001
        ? 'Sem conversao (1:1).'
        : (_embalagemMultiplica
            ? '1 $uCompra = ${fator == fator.roundToDouble() ? fator.toInt() : fator} $uVenda no estoque.'
            : '1 $uCompra entra como 1 $uVenda (estoque ÷ $fator).');

    return _erpSurfaceCard(
      context: context,
      title: 'Embalagem e unidade',
      icon: Icons.inventory_outlined,
      children: [
        _erpResponsiveGrid(context, [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _erpFieldLabel('Unidade de compra (opcional)', context),
              TextField(
                controller: _unidadeCompraController,
                textCapitalization: TextCapitalization.characters,
                decoration: _erpInputDecoration(
                  context,
                  hint: 'CX, FD, SC — vazio = $uVenda',
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _erpFieldLabel('Qtd. por embalagem', context),
              TextField(
                controller: _quantidadeEmbalagemController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _erpInputDecoration(
                  context,
                  helper: 'Ex.: 12 (unidades por caixa)',
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: _erpGap8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Multiplica'),
              icon: Icon(Icons.close, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('Divide'),
              icon: Icon(Icons.percent, size: 16),
            ),
          ],
          selected: {_embalagemMultiplica},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() => _embalagemMultiplica = s.first);
          },
        ),
        const SizedBox(height: _erpGap8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Permite venda fracionada'),
          subtitle: const Text(
            'Ex.: metro, m², kg — quantidade decimal no PDV.',
          ),
          value: _permiteQuantidadeFracionada,
          onChanged: (v) => setState(() => _permiteQuantidadeFracionada = v),
        ),
        Text(
          preview,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  String _normalizarUnidade(String? unidade) {
    if (unidade == null || unidade.trim().isEmpty) {
      return 'UN';
    }
    final u = unidade.trim().toUpperCase();
    if (u == 'METRO') return 'M';
    return _unidades.contains(u) ? u : 'UN';
  }

  String? _validarNcm(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return 'NCM obrigatorio para NFC-e (8 digitos).';
    }
    if (digits.length != 8) {
      return 'NCM deve ter exatamente 8 digitos.';
    }
    return null;
  }

  String _formatarNcmExibicao(String digitos) {
    final d = digitos.replaceAll(RegExp(r'\D'), '');
    if (d.length != 8) return digitos.trim();
    return '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6, 8)}';
  }

  Widget? _suffixAcaoCampo({
    required bool carregando,
    required VoidCallback? onPressed,
    required String tooltip,
    IconData icon = Icons.cloud_download_outlined,
  }) {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget? _suffixConsultaBrasilApi({
    required bool carregando,
    required VoidCallback? onPressed,
    required String tooltip,
  }) =>
      _suffixAcaoCampo(
        carregando: carregando,
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icons.cloud_download_outlined,
      );

  String? _mapearCategoriaGeminiParaSistema(String categoriaGemini) {
    const mapa = <String, String>{
      'Hidráulica': 'Hidraulica',
      'Elétrica': 'Eletrica',
      'Ferramentas': 'Ferramentas',
      'Tintas': 'Tintas e Acessorios',
      'Ferragens': 'Ferragens',
      'Outros': _categoriaOutros,
    };
    final chave = mapa[categoriaGemini.trim()] ?? _categoriaOutros;
    if (_categoriasMateriaisConstrucao.containsKey(chave)) {
      return chave;
    }
    return _categoriaOutros;
  }

  String _montarCatalogoSubcategoriasParaGemini() {
    const mapaGemini = <String, String>{
      'Hidráulica': 'Hidraulica',
      'Elétrica': 'Eletrica',
      'Ferramentas': 'Ferramentas',
      'Tintas': 'Tintas e Acessorios',
      'Ferragens': 'Ferragens',
      'Outros': _categoriaOutros,
    };
    final buf = StringBuffer(
      'Catalogo da loja — use subcategoria_sugerida com o texto EXATO de uma opcao abaixo:\n',
    );
    for (final entry in mapaGemini.entries) {
      final categoriaSistema = entry.value;
      if (categoriaSistema == _categoriaOutros) continue;
      final subs = _categoriasMateriaisConstrucao[categoriaSistema] ?? [];
      if (subs.isEmpty) continue;
      buf.writeln(
        '- ${entry.key} ($categoriaSistema): ${subs.join(' | ')}',
      );
    }
    return buf.toString();
  }

  String? _resolverSubcategoriaGemini({
    required String categoriaSistema,
    required String subcategoriaGemini,
  }) {
    final sugestao = subcategoriaGemini.trim();
    if (categoriaSistema == _categoriaOutros) {
      return null;
    }
    if (sugestao.isEmpty) {
      return null;
    }

    final lista = _categoriasMateriaisConstrucao[categoriaSistema] ?? [];
    if (lista.isEmpty) {
      return null;
    }

    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final alvo = norm(sugestao);
    for (final sub in lista) {
      if (norm(sub) == alvo) {
        return sub;
      }
    }
    for (final sub in lista) {
      final ns = norm(sub);
      if (ns.contains(alvo) || alvo.contains(ns)) {
        return sub;
      }
    }

    if (categoriaSistema == 'Hidraulica') {
      final t = sugestao.toLowerCase();
      if (t.contains('tubo') ||
          t.contains('conex') ||
          t.contains('pvc') ||
          t.contains('esgoto') ||
          t.contains('cano')) {
        return 'Tubos e Conexoes';
      }
      if (t.contains('torneira') || t.contains('misturador')) {
        return 'Torneiras';
      }
    }

    if (categoriaSistema == 'Tintas e Acessorios') {
      final t = sugestao.toLowerCase();
      if (t.contains('tinta')) {
        if (t.contains('esmalte')) return 'Tinta Esmalte';
        return 'Tinta Acrilica';
      }
    }

    if (categoriaSistema == 'Cimento e Argamassas') {
      final t = sugestao.toLowerCase();
      if (t.contains('argamassa')) return 'Argamassa';
      if (t.contains('cimento')) return 'Cimento';
    }

    return null;
  }

  String _extrairCodigoBarrasDoTexto(String texto) {
    for (final match in RegExp(r'\b\d{8,14}\b').allMatches(texto)) {
      final d = match.group(0)!;
      if (d.length == 8 ||
          d.length == 12 ||
          d.length == 13 ||
          d.length == 14) {
        return d;
      }
    }
    return '';
  }

  Future<void> _enriquecerNcmAposGemini(String ncm8) async {
    if (ncm8.length != 8) return;
    try {
      final dados = await _brasilApiService.consultarNcm(ncm8);
      if (!mounted || dados == null) return;
      setState(() {
        _ncmController.text = _formatarNcmExibicao(dados.codigoDigitos);
        _infoNcmBrasilApi = dados.descricao.trim().isEmpty
            ? 'NCM valido: ${_formatarNcmExibicao(ncm8)}'
            : 'NCM valido: ${dados.descricao.trim()}';
        if (dados.cest.length == 7 && _cestController.text.trim().isEmpty) {
          _cestController.text = dados.cest;
        }
      });
    } catch (_) {
      // Falha na Brasil API nao invalida sugestao da IA.
    }
  }

  String _mapearUnidadeGeminiParaSistema(String unidadeGemini) {
    var u = unidadeGemini.trim().toUpperCase();
    if (u == 'MT') u = 'M';
    final normalizada = _normalizarUnidade(u);
    if (_unidades.contains(normalizada)) {
      return normalizada;
    }
    return 'UN';
  }

  Future<void> _padronizarProdutoComGemini() async {
    final texto = _nomeController.text.trim();
    if (texto.isEmpty) {
      _snackbarBrasilApi(
        'Digite o nome ou descricao do produto antes de padronizar com a IA.',
        erro: true,
      );
      return;
    }

    if (!await _geminiService.configurado) {
      await _mostrarDialogoConfigurarGemini();
      return;
    }

    setState(() => _consultandoGemini = true);
    try {
      final model = await _geminiService.padronizarProdutoModel(
        texto,
        catalogoSubcategorias: _montarCatalogoSubcategoriasParaGemini(),
      );
      if (!mounted) return;

      if (model == null) {
        _snackbarBrasilApi(
          'A IA nao retornou sugestao para este produto.',
          erro: true,
        );
        return;
      }

      final categoriaSistema = _mapearCategoriaGeminiParaSistema(
        model.categoriaSugerida,
      );
      final subcategoriaSistema = _resolverSubcategoriaGemini(
        categoriaSistema: categoriaSistema ?? _categoriaOutros,
        subcategoriaGemini: model.subcategoriaSugerida,
      );
      final unidadeSistema = _mapearUnidadeGeminiParaSistema(
        model.unidadeMedida,
      );

      var codigoBarras = model.codigoBarras;
      if (codigoBarras.isEmpty) {
        codigoBarras = _extrairCodigoBarrasDoTexto(texto);
      }

      setState(() {
        _nomeController.text = model.nomePadronizado;
        _categoriaSelecionada = categoriaSistema;
        if (categoriaSistema == _categoriaOutros) {
          _subcategoriaSelecionada = null;
          if (model.subcategoriaSugerida.trim().isNotEmpty) {
            _subcategoriaLivreController.text = model.subcategoriaSugerida.trim();
          }
        } else if (subcategoriaSistema != null) {
          _subcategoriaSelecionada = subcategoriaSistema;
          _subcategoriaLivreController.clear();
        } else {
          _subcategoriaSelecionada = null;
        }
        _unidadeSelecionada = unidadeSistema;

        if (codigoBarras.isNotEmpty) {
          _codigoBarrasController.text = codigoBarras;
        }
        if (model.ncm.length == 8) {
          _ncmController.text = _formatarNcmExibicao(model.ncm);
        }
        if (model.cest.length == 7) {
          _cestController.text = model.cest;
        }
        _grupoTributarioSelecionado = model.grupoTributario;
      });

      if (model.ncm.length == 8) {
        await _enriquecerNcmAposGemini(model.ncm);
      }

      if (!mounted) return;
      final semantic = Theme.of(context).extension<AppSemanticColors>();
      final extras = <String>[
        if (codigoBarras.isNotEmpty) 'cod. barras',
        if (model.ncm.length == 8) 'NCM',
        if (model.cest.length == 7) 'CEST',
        'grupo tributario',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            extras.isEmpty
                ? 'Produto padronizado pela IA!'
                : 'Produto padronizado pela IA (${extras.join(', ')})!',
          ),
          duration: const Duration(seconds: 4),
          backgroundColor: semantic?.successFg ?? Colors.green.shade700,
        ),
      );
    } on GeminiConfigException catch (e) {
      _snackbarBrasilApi(e.message, erro: true);
    } on GeminiServiceException catch (e) {
      if (e.instrucoesCorrecao != null && e.instrucoesCorrecao!.isNotEmpty) {
        await _mostrarDialogoErroGemini(e);
      } else {
        _snackbarBrasilApi(e.message, erro: true);
      }
    } catch (e) {
      _snackbarBrasilApi('Erro ao padronizar com IA: $e', erro: true);
    } finally {
      if (mounted) setState(() => _consultandoGemini = false);
    }
  }

  void _snackbarBrasilApi(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        duration: Duration(seconds: erro ? 8 : 5),
        backgroundColor: erro
            ? semantic?.errorFg ?? Colors.red.shade700
            : null,
      ),
    );
  }

  Future<void> _consultarGtinBrasilApi() async {
    final codigo = _codigoBarrasController.text.trim();
    if (codigo.isEmpty) {
      _snackbarBrasilApi('Informe o codigo de barras ou GTIN para consultar.', erro: true);
      return;
    }

    setState(() => _consultandoGtin = true);
    try {
      final dados = await _brasilApiService.consultarGtin(codigo);
      if (!mounted) return;

      if (dados == null) {
        _snackbarBrasilApi(
          'Produto nao encontrado na Brasil API para o codigo informado.',
          erro: true,
        );
        return;
      }

      final nomeAtual = _nomeController.text.trim();
      final descricaoApi = dados.descricao.trim();

      setState(() {
        if (nomeAtual.isEmpty && descricaoApi.isNotEmpty) {
          _nomeController.text = descricaoApi;
        }
        if (dados.ncm.length == 8) {
          _ncmController.text = _formatarNcmExibicao(dados.ncm);
        }
      });

      if (nomeAtual.isNotEmpty &&
          descricaoApi.isNotEmpty &&
          nomeAtual != descricaoApi) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Encontrado: $descricaoApi'),
            action: SnackBarAction(
              label: 'Usar nome',
              onPressed: () {
                _nomeController.text = descricaoApi;
              },
            ),
          ),
        );
      } else {
        final partes = <String>[
          if (descricaoApi.isNotEmpty) 'Dados do codigo importados.',
          if (dados.ncm.length == 8) 'NCM preenchido.',
        ];
        if (partes.isNotEmpty) {
          _snackbarBrasilApi(partes.join(' '));
        }
      }
    } on BrasilApiException catch (e) {
      _snackbarBrasilApi(e.message, erro: true);
    } catch (e) {
      _snackbarBrasilApi('Erro ao consultar codigo de barras: $e', erro: true);
    } finally {
      if (mounted) setState(() => _consultandoGtin = false);
    }
  }

  Future<void> _consultarNcmBrasilApi() async {
    final digitos = _ncmController.text.replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 8) {
      _snackbarBrasilApi(
        'Informe um NCM com 8 digitos antes de consultar.',
        erro: true,
      );
      return;
    }

    setState(() {
      _consultandoNcm = true;
      _infoNcmBrasilApi = '';
    });

    try {
      final dados = await _brasilApiService.consultarNcm(digitos);
      if (!mounted) return;

      if (dados == null) {
        setState(() => _infoNcmBrasilApi = '');
        _snackbarBrasilApi(
          'NCM nao encontrado na tabela oficial.',
          erro: true,
        );
        return;
      }

      final descricaoOficial = dados.descricao.trim();
      final codigoFmt = _formatarNcmExibicao(
        dados.codigoDigitos.isNotEmpty ? dados.codigoDigitos : digitos,
      );

      setState(() {
        _ncmController.text = codigoFmt;
        _infoNcmBrasilApi = descricaoOficial.isEmpty
            ? 'NCM valido: $codigoFmt'
            : 'NCM valido: $descricaoOficial';
        if (dados.cest.length == 7 && _cestController.text.trim().isEmpty) {
          _cestController.text = dados.cest;
        }
      });
    } on BrasilApiException catch (e) {
      if (mounted) setState(() => _infoNcmBrasilApi = '');
      _snackbarBrasilApi(e.message, erro: true);
    } catch (e) {
      if (mounted) setState(() => _infoNcmBrasilApi = '');
      _snackbarBrasilApi('Erro ao consultar NCM: $e', erro: true);
    } finally {
      if (mounted) setState(() => _consultandoNcm = false);
    }
  }

  String? _validarCest(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    return ProdutoFiscalCatalog.validarCestParaGrupo(
      cestDigitos: digits,
      grupoTributarioCodigo: _grupoTributarioSelecionado,
    );
  }

  String? _validarCfopVenda(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(v)) {
      return 'CFOP deve ter 4 digitos ou deixe vazio (automatico).';
    }
    return null;
  }

  double? _parseValorMonetario(String texto) {
    var valor = texto.trim();
    if (valor.isEmpty) {
      return null;
    }
    valor = valor
        .replaceAll('\u00A0', '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(RegExp('r\$', caseSensitive: false), '');
    if (valor.isEmpty) {
      return null;
    }
    // Export Python/Paradox costuma usar ponto decimal (12.5, 0.99). Antes removiamos TODOS os pontos
    // pensando em milhar BR — isso quebrava esses valores e gerava fallback 0,01 em massa.
    final direto = double.tryParse(valor);
    if (direto != null) {
      return direto;
    }
    final limpo = valor.replaceAll(RegExp(r'[^\d.,+\-eE]'), '');
    if (limpo.isEmpty) {
      return null;
    }
    final ultVirg = limpo.lastIndexOf(',');
    final ultPonto = limpo.lastIndexOf('.');
    if (ultVirg > ultPonto) {
      final br = limpo.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(br);
    }
    return double.tryParse(limpo.replaceAll(',', '.'));
  }

  /// Quando [PrecoVenda] vem vazio no CSV (comum no TabEst), o sistema antigo as vezes
  /// guardava valores em [Obs] como texto, ex.: `MARCA 60,00 PDEDIDO 58,00`.
  /// Retorna o primeiro valor monetario plausivel encontrado da esquerda para a direita.
  double? _extrairPrecoVendaDeTextoLivre(String texto) {
    final raw = texto.trim();
    if (raw.isEmpty) {
      return null;
    }
    final re = RegExp(r'\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d+\.\d{2}');
    for (final m in re.allMatches(raw)) {
      final s = m.group(0);
      if (s == null) {
        continue;
      }
      final v = _parseValorMonetario(s);
      if (v != null && v > 0 && v < 1e7) {
        return v;
      }
    }
    // Ex.: "MARCA 60 PDEDIDO" sem centavos escritos
    final soNumeros = RegExp(r'\b(\d{2,6})\b');
    for (final m in soNumeros.allMatches(raw)) {
      final s = m.group(1);
      if (s == null) {
        continue;
      }
      final v = double.tryParse(s);
      if (v != null && v >= 10 && v <= 999999) {
        return v;
      }
    }
    return null;
  }

  /// Colunas que nao devem ser escolhidas pela heuristica de "preco de venda".
  Set<int> _indicesExcluidosHeuristicaPreco(List<String> headers) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    final ex = <int>{};
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (k == 'codigo' ||
          k == 'codinterno' ||
          k == 'codex' ||
          k == 'controle' ||
          k == 'produto' ||
          k == 'nome' ||
          k.contains('quantidade') ||
          k == 'estoque' ||
          k.contains('estminimo') ||
          k.contains('fabricante') ||
          k == 'unidade' ||
          k.startsWith('lk') ||
          k == 'lucro' ||
          k == 'comissao' ||
          k.contains('ncm') ||
          k.contains('barras') ||
          k.contains('descricao') ||
          k.contains('observ') ||
          k.contains('peso') ||
          k.contains('icms') ||
          k.contains('ipi') ||
          k.contains('iva') ||
          k.contains('cst') ||
          k.contains('basecalculo') ||
          k.contains('ean') ||
          k.contains('modulo') ||
          k.contains('armazen') ||
          k.contains('embal') ||
          k.contains('previs') ||
          k.contains('data') ||
          k == 'moeda' ||
          k.contains('pf') ||
          k.contains('ippt') ||
          k.contains('iat')) {
        ex.add(i);
      }
    }
    return ex;
  }

  /// Evita escolher coluna errada (peso, imposto) como "preco de venda" na heuristica.
  bool _cabecalhoPermiteHeuristicaPrecoVenda(String rawHeader) {
    final k = _chaveCabecalhoCsv(rawHeader);
    if (k.contains('custo')) {
      return false;
    }
    if (k.contains('peso')) {
      return false;
    }
    if (k.contains('icms') ||
        k.contains('ipi') ||
        k.contains('iva') ||
        k.contains('cst')) {
      return false;
    }
    if (k.contains('basecalculo') || k.contains('ean') || k.startsWith('lk')) {
      return false;
    }
    if (k.contains('quantidade') || k == 'moeda') {
      return false;
    }
    return k.contains('preco') ||
        k.contains('venda') ||
        k.contains('valor') ||
        k.startsWith('vr');
  }

  int _contarPrecoValidoAmostra(
    List<List<String>> linhas,
    int col,
    int maxLinhas,
  ) {
    var n = 0;
    final lim = math.min(linhas.length - 1, maxLinhas);
    for (var r = 1; r <= lim; r++) {
      final row = linhas[r];
      if (col >= row.length) continue;
      final v = _parseValorMonetario(row[col].trim());
      if (v != null && v > 0 && v <= 1e7) {
        n++;
      }
    }
    return n;
  }

  /// Se a coluna encontrada por nome vier vazia nos dados, escolhe a coluna
  /// numerica com mais precos validos na amostra (ex.: CSV desalinhado).
  int _refinarIndicePrecoVenda(
    List<List<String>> linhas,
    List<String> headers,
    int indiceSugerido,
    Set<int> excluir,
  ) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    if (indiceSugerido >= 0 && indiceSugerido < keys.length) {
      final k = keys[indiceSugerido];
      // TabEst: PrecoVenda costuma estar certo no nome mas raro nas linhas; nao trocar por
      // outra coluna "mais preenchida" (ICMS, peso, flags 0/1) senao vira 0,01 em massa.
      if (k == 'precovenda' ||
          k == 'valorvenda' ||
          k == 'valor_venda' ||
          k == 'vrvenda' ||
          k == 'vr_venda') {
        return indiceSugerido;
      }
    }

    final amostra = math.max(1, linhas.length - 1);
    final limite = math.max(40, (amostra * 0.12).round());
    final hitsSug = _contarPrecoValidoAmostra(linhas, indiceSugerido, 500);
    if (hitsSug >= limite) {
      return indiceSugerido;
    }
    var bestJ = indiceSugerido;
    var bestHits = hitsSug;
    final ncol = linhas.first.length;
    for (var j = 0; j < ncol; j++) {
      if (excluir.contains(j)) {
        continue;
      }
      if (j != indiceSugerido &&
          !_cabecalhoPermiteHeuristicaPrecoVenda(headers[j])) {
        continue;
      }
      final h = _contarPrecoValidoAmostra(linhas, j, 500);
      if (h > bestHits) {
        bestHits = h;
        bestJ = j;
      }
    }
    return bestJ;
  }

  /// Cabecalhos TabEst / exportacoes: prioriza igualdade exata, depois nomes com "venda".
  int? _indiceColunaPrecoVenda(List<String> headers) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    const exatas = <String>[
      'precovenda',
      'valorvenda',
      'valor_venda',
      'vrvenda',
      'vr_venda',
      'preco1',
      'preco2',
      'preco3',
    ];
    for (final e in exatas) {
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == e) {
          return i;
        }
      }
    }
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (k.contains('custo')) {
        continue;
      }
      if (k == 'precovenda' || k == 'valorvenda') {
        return i;
      }
      if (k.contains('venda') &&
          (k.contains('preco') || k.contains('valor') || k.startsWith('vr'))) {
        return i;
      }
    }
    return null;
  }

  String _resumoTiposErroImportacaoCsv(List<String> erros) {
    var nPreco = 0;
    var nCodigo = 0;
    var nNome = 0;
    var nOutro = 0;
    for (final e in erros) {
      if (e.contains('preco invalido')) {
        nPreco++;
      } else if (e.contains('codigo vazio')) {
        nCodigo++;
      } else if (e.contains('nome/descricao vazio')) {
        nNome++;
      } else {
        nOutro++;
      }
    }
    final p = <String>[
      if (nPreco > 0) 'preco invalido: $nPreco',
      if (nCodigo > 0) 'codigo vazio: $nCodigo',
      if (nNome > 0) 'nome vazio: $nNome',
      if (nOutro > 0) 'outros: $nOutro',
    ];
    return p.isEmpty ? '' : 'Resumo: ${p.join(' | ')}.';
  }

  String _formatarValorMonetario(double valor) {
    return _moedaBrFormatter.format(valor);
  }

  String? _validarSku(String? value) {
    if (_gerarSkuAutomatico) {
      return null;
    }
    final sku = (value ?? '').trim();
    if (sku.isEmpty) {
      return 'Informe o SKU ou habilite geracao automatica.';
    }
    if (_skuJaExiste(sku.toLowerCase())) {
      return 'SKU ja cadastrado.';
    }
    return null;
  }

  String? _validarNome(String? value) {
    final nome = (value ?? '').trim();
    if (nome.isEmpty) {
      return 'Nome do produto e obrigatorio.';
    }
    return null;
  }

  String? _validarCategoria(String? value) {
    if (_categoriaSelecionada == null ||
        _categoriaSelecionada!.trim().isEmpty) {
      return 'Categoria e obrigatoria.';
    }
    return null;
  }

  String? _validarSubcategoria(String? value) {
    if (_categoriaSelecionada == null) {
      return 'Escolha uma categoria primeiro.';
    }
    if (_categoriaSelecionada == _categoriaOutros) {
      if (_subcategoriaLivreController.text.trim().isEmpty) {
        return 'Informe a subcategoria personalizada.';
      }
      return null;
    }
    if (_subcategoriaSelecionada == null ||
        _subcategoriaSelecionada!.trim().isEmpty) {
      return 'Subcategoria obrigatoria.';
    }
    final subcategorias =
        _categoriasMateriaisConstrucao[_categoriaSelecionada] ?? [];
    if (!subcategorias.contains(_subcategoriaSelecionada)) {
      return 'Subcategoria invalida para a categoria.';
    }
    return null;
  }

  String? _validarPrecoCusto(String? value) {
    final texto = (value ?? '').trim();
    final precoCusto = _parseValorMonetario(texto);
    if (precoCusto == null) {
      return 'Preco de custo invalido.';
    }
    if (precoCusto < 0) {
      return 'Preco de custo nao pode ser negativo.';
    }
    return null;
  }

  String? _validarPrecoTabela(String? value) {
    final texto = (value ?? '').trim();
    final preco = _parseValorMonetario(texto);
    if (preco == null || preco <= 0) {
      return 'Preco deve ser maior que zero.';
    }
    return null;
  }

  Future<void> _imprimirEtiquetaProduto() async {
    final tc = DefaultTabController.maybeOf(context);
    if (tc != null && tc.index != 0) {
      return;
    }
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o nome do produto para imprimir a etiqueta de teste.',
          ),
        ),
      );
      return;
    }
    final codigoBarras = _codigoBarrasController.text.trim();
    final sku = _codigoInternoController.text.trim();
    final codigo = codigoBarras.isNotEmpty ? codigoBarras : sku;
    final preco2 = _parseValorMonetario(_preco2Controller.text) ?? 0;
    final precoFmt = NumberFormat('#,##0.00', 'pt_BR').format(preco2);
    try {
      await widget.printService.imprimirEtiquetaProdutoTeste(
        nomeProduto: nome,
        codigoBarrasOuSku: codigo,
        precoAVistaFormatado: 'R\$ $precoFmt',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel imprimir a etiqueta: $e')),
      );
    }
  }

  Future<void> _salvarProduto() async {
    setState(() {
      _tentouSalvar = true;
    });
    final formValido = _formKey.currentState?.validate() ?? false;
    if (!formValido) {
      _definirStatus('Revise os campos destacados em vermelho.', erro: true);
      return;
    }

    final codigoInternoDigitado = _codigoInternoController.text.trim();
    final nomePadrao = _normalizarNomeProduto(_nomeController.text);
    final descricao = _descricaoController.text.trim();
    final categoria = _categoriaSelecionada?.trim() ?? '';
    final subcategoria = _categoriaSelecionada == _categoriaOutros
        ? _subcategoriaLivreController.text.trim()
        : (_subcategoriaSelecionada?.trim() ?? '');
    final marca = _marcaController.text.trim();
    final fornecedor = _fornecedorController.text.trim();
    final fabricante = _fabricanteController.text.trim();
    final codigoBarras = _codigoBarrasController.text.trim();
    final apelidosBusca = _apelidosBuscaController.text.trim();
    final ncm = _ncmController.text.replaceAll(RegExp(r'\D'), '');
    final cest = _cestController.text.replaceAll(RegExp(r'\D'), '');
    final cfopVenda = _cfopVendaController.text.trim();
    final localizacao = _localizacaoController.text.trim();
    final precoCusto = _parseValorMonetario(_precoCustoController.text);
    final produtoExistente = _produtoEmEdicaoId == null
        ? null
        : widget.produtoRepository.obterPorId(_produtoEmEdicaoId!);
    final pc = precoCusto!;
    final double custoMedioPersistido = produtoExistente != null
        ? (widget.produtoRepository.calcularCustoMedioPonderadoPorEntradasNfe(
                produtoExistente.id,
              ) ??
              (pc < 0 ? 0.0 : pc))
        : (pc < 0 ? 0.0 : pc);
    final preco1 = _parseValorMonetario(_preco1Controller.text);
    final preco2 = _parseValorMonetario(_preco2Controller.text);
    final preco3 = _parseValorMonetario(_preco3Controller.text);
    final estoque = int.tryParse(_estoqueController.text) ?? 0;
    final quantidadeMinima =
        int.tryParse(_quantidadeMinimaController.text) ?? 0;
    final leadTimeDias = int.tryParse(_leadTimeDiasController.text) ?? 7;
    final estoqueSeguranca =
        int.tryParse(_estoqueSegurancaController.text) ?? 0;
    final codigoInternoFinal = _gerarSkuAutomatico
        ? _gerarSkuAutomaticamente()
        : codigoInternoDigitado;

    _nomeController.text = nomePadrao;

    final fotoPathExistente = produtoExistente?.fotoPath ?? '';
    final identificadorFoto = codigoInternoFinal.isNotEmpty
        ? codigoInternoFinal
        : 'produto_${DateTime.now().millisecondsSinceEpoch}';
    var fotoPathFinal = fotoPathExistente;

    if (_fotoOrigemLocalPath != null &&
        _fotoOrigemLocalPath!.trim().isNotEmpty) {
      final fotoProcessada = await _produtoImagemService
          .processarESalvarImagemProduto(
            sourceImagePath: _fotoOrigemLocalPath!,
            productIdentifier: identificadorFoto,
          );
      if (fotoProcessada == null) {
        _definirStatus(
          'Nao foi possivel processar a foto selecionada.',
          erro: true,
        );
        return;
      }
      if (fotoPathExistente.trim().isNotEmpty &&
          fotoPathExistente != fotoProcessada) {
        await _produtoImagemService.removerImagemProduto(fotoPathExistente);
      }
      fotoPathFinal = fotoProcessada;
    } else if (_fotoFoiRemovida && fotoPathExistente.trim().isNotEmpty) {
      await _produtoImagemService.removerImagemProduto(fotoPathExistente);
      fotoPathFinal = '';
    }

    final produto = Produto(
      id: produtoExistente?.id ?? 0,
      codigoInterno: codigoInternoFinal,
      nome: nomePadrao,
      nomeImpressao: _nomeImpressaoParaSalvar(nomePadrao),
      descricao: descricao,
      unidade: _normalizarUnidade(_unidadeSelecionada),
      categoria: categoria,
      subcategoria: subcategoria,
      marca: marca,
      fornecedor: fornecedor,
      fabricante: fabricante,
      codigoBarras: codigoBarras,
      apelidosBusca: apelidosBusca,
      fotoPath: fotoPathFinal,
      localizacao: localizacao,
      ncm: ncm,
      cest: cest,
      grupoTributario: _grupoTributarioSelecionado,
      cfopVenda: cfopVenda,
      icmsOrigem: _icmsOrigemSelecionado,
      icmsSituacaoTributaria: _icmsCstSelecionado,
      pisCofinsSituacaoTributaria: _pisCofinsCstSelecionado,
      estoque: estoque,
      quantidadeMinima: quantidadeMinima,
      leadTimeDias: leadTimeDias > 0 ? leadTimeDias : 7,
      estoqueSeguranca: estoqueSeguranca,
      vendaMediaDiaria: produtoExistente?.vendaMediaDiaria ?? 0,
      ativo: _produtoAtivo,
      precoCusto: pc,
      custoMedio: custoMedioPersistido < 0 ? 0.0 : custoMedioPersistido,
      preco1: preco1!,
      preco2: preco2!,
      preco3: preco3!,
      precoVenda: preco1,
      unidadeCompra: _unidadeCompraController.text.trim(),
      quantidadePorEmbalagem: _lerQuantidadeEmbalagem(),
      embalagemMultiplica: _embalagemMultiplica,
      permiteQuantidadeFracionada: _permiteQuantidadeFracionada,
      ultimaVendaEm: produtoExistente?.ultimaVendaEm,
      criadoEm: produtoExistente?.criadoEm,
    );
    final estavaEditando = _produtoEmEdicaoId != null;
    final idSalvo = widget.produtoRepository.salvar(produto);
    final salvoPosGravacao = widget.produtoRepository.obterPorId(idSalvo);
    if (salvoPosGravacao != null) {
      ComprasPreditivasService(widget.produtoRepository.objectBox)
          .atualizarVendaMediaDiaria(salvoPosGravacao);
      widget.produtoRepository.salvar(salvoPosGravacao);
    }
    if (!estavaEditando) {
      final salvo = widget.produtoRepository.obterPorId(idSalvo);
      if (salvo != null) {
        _editarProdutoNoCabecalho(salvo);
      } else {
        _resetarFormulario();
      }
    } else {
      _resetarFormulario();
      setState(() => _historicoVersao++);
    }
    _definirStatus(
      !estavaEditando
          ? 'Produto incluido com sucesso.'
          : 'Produto atualizado com sucesso.',
      erro: false,
    );
  }

  void _editarProdutoNoCabecalho(Produto produto) {
    setState(() {
      _historicoVersao++;
      _produtoEmEdicaoId = produto.id;
      _codigoInternoController.text = produto.codigoInterno;
      _nomeController.text = produto.nome;
      _nomeImpressaoVinculadoAoNome =
          ProdutoNomeExibicao.nomeImpressaoVinculadoAoNome(produto);
      _nomeImpressaoController.text = _nomeImpressaoVinculadoAoNome
          ? produto.nome
          : produto.nomeImpressao;
      _descricaoController.text = produto.descricao;
      if (_categoriasMateriaisConstrucao.containsKey(produto.categoria)) {
        _categoriaSelecionada = produto.categoria;
        if (produto.categoria == _categoriaOutros) {
          _subcategoriaSelecionada = null;
          _subcategoriaLivreController.text = produto.subcategoria;
        } else {
          _subcategoriaLivreController.clear();
          final subcategorias =
              _categoriasMateriaisConstrucao[produto.categoria] ?? [];
          _subcategoriaSelecionada =
              subcategorias.contains(produto.subcategoria)
              ? produto.subcategoria
              : null;
        }
      } else {
        _categoriaSelecionada = null;
        _subcategoriaSelecionada = null;
        _subcategoriaLivreController.clear();
      }
      _marcaController.text = produto.marca;
      _fornecedorController.text = produto.fornecedor;
      _fabricanteController.text = produto.fabricante;
      _codigoBarrasController.text = produto.codigoBarras;
      _apelidosBuscaController.text = produto.apelidosBusca;
      _fotoPathAtual = produto.fotoPath;
      _fotoOrigemLocalPath = null;
      _fotoFoiRemovida = false;
      _ncmController.text = produto.ncm;
      _cestController.text = produto.cest;
      _cfopVendaController.text = produto.cfopVenda;
      _grupoTributarioSelecionado =
          grupoTributarioProdutoDeString(produto.grupoTributario).codigo;
      _icmsOrigemSelecionado = produto.icmsOrigem;
      _icmsCstSelecionado = produto.icmsSituacaoTributaria;
      _pisCofinsCstSelecionado = produto.pisCofinsSituacaoTributaria;
      _localizacaoController.text = produto.localizacao;
      _precoCustoController.text = _formatarValorMonetario(produto.precoCusto);
      _preco1Controller.text = _formatarValorMonetario(
        produto.preco1 > 0 ? produto.preco1 : produto.precoVenda,
      );
      _preco2Controller.text = _formatarValorMonetario(
        produto.preco2 > 0 ? produto.preco2 : produto.precoVenda,
      );
      _preco3Controller.text = _formatarValorMonetario(
        produto.preco3 > 0 ? produto.preco3 : produto.precoVenda,
      );
      _estoqueController.text = produto.estoque.toString();
      _quantidadeMinimaController.text = produto.quantidadeMinima.toString();
      _leadTimeDiasController.text =
          produto.leadTimeDias > 0 ? produto.leadTimeDias.toString() : '7';
      _estoqueSegurancaController.text = produto.estoqueSeguranca.toString();
      _unidadeSelecionada = _normalizarUnidade(produto.unidade);
      _unidadeCompraController.text = produto.unidadeCompra;
      _quantidadeEmbalagemController.text =
          produto.quantidadePorEmbalagem.toString();
      _embalagemMultiplica = produto.embalagemMultiplica;
      _permiteQuantidadeFracionada = produto.permiteQuantidadeFracionada;
      _ultimaVendaEmCadastro = produto.ultimaVendaEm;
      _margemAlvoPreco1Controller.text = ProdutoPrecificacao.margemSobrePrecoVenda(
        custo: produto.precoCusto,
        precoVenda: produto.preco1 > 0 ? produto.preco1 : produto.precoVenda,
      ).toStringAsFixed(1);
      _margemAlvoPreco2Controller.text = ProdutoPrecificacao.margemSobrePrecoVenda(
        custo: produto.precoCusto,
        precoVenda: produto.preco2 > 0 ? produto.preco2 : produto.precoVenda,
      ).toStringAsFixed(1);
      _margemAlvoPreco3Controller.text = ProdutoPrecificacao.margemSobrePrecoVenda(
        custo: produto.precoCusto,
        precoVenda: produto.preco3 > 0 ? produto.preco3 : produto.precoVenda,
      ).toStringAsFixed(1);
      _produtoAtivo = produto.ativo;
      _status = 'Editando produto: ${produto.nome}';
      _statusEhErro = false;
      _gerarSkuAutomatico = false;
    });
  }

  List<Produto> _produtosOrdenadosPorCadastro() {
    final produtos = widget.produtoRepository.listarTodos();
    produtos.sort((a, b) => a.id.compareTo(b.id));
    return produtos;
  }

  int _indiceProdutoAtual(List<Produto> produtos) {
    final atualId = _produtoEmEdicaoId;
    if (atualId == null) return -1;
    return produtos.indexWhere((p) => p.id == atualId);
  }

  void _abrirProdutoPorIndice(int indice) {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    final indexValido = indice.clamp(0, produtos.length - 1);
    _editarProdutoNoCabecalho(produtos[indexValido]);
  }

  void _irParaPrimeiroProduto() {
    _abrirProdutoPorIndice(0);
  }

  void _irParaUltimoProduto() {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    _abrirProdutoPorIndice(produtos.length - 1);
  }

  void _irParaProdutoAnterior() {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    final indiceAtual = _indiceProdutoAtual(produtos);
    if (indiceAtual <= 0) {
      _abrirProdutoPorIndice(0);
      return;
    }
    _abrirProdutoPorIndice(indiceAtual - 1);
  }

  void _irParaProximoProduto() {
    final produtos = _produtosOrdenadosPorCadastro();
    if (produtos.isEmpty) {
      _definirStatus('Nao ha produtos cadastrados para navegar.', erro: true);
      return;
    }
    final indiceAtual = _indiceProdutoAtual(produtos);
    if (indiceAtual < 0) {
      _abrirProdutoPorIndice(0);
      return;
    }
    if (indiceAtual >= produtos.length - 1) {
      _abrirProdutoPorIndice(produtos.length - 1);
      return;
    }
    _abrirProdutoPorIndice(indiceAtual + 1);
  }

  String _lerTextoArquivoUtf8OuLatin1(List<int> bytes) {
    var slice = bytes;
    if (slice.length >= 3 &&
        slice[0] == 0xEF &&
        slice[1] == 0xBB &&
        slice[2] == 0xBF) {
      slice = slice.sublist(3);
    }
    try {
      return utf8.decode(slice, allowMalformed: false);
    } catch (_) {
      return latin1.decode(slice, allowInvalid: true);
    }
  }

  String _detectarSeparadorCsv(String primeiraLinha) {
    final pv = ';'.allMatches(primeiraLinha).length;
    final pc = ','.allMatches(primeiraLinha).length;
    return pv >= pc ? ';' : ',';
  }

  List<String> _dividirLinhaCsv(String linha, String sep) {
    return linha.split(sep).map((c) => c.trim().replaceAll('"', '')).toList();
  }

  /// Normaliza cabecalho para casar CSV do Paradox (TabEst1) e exportacoes genericas.
  String _chaveCabecalhoCsv(String raw) {
    var s = raw.toLowerCase().trim().replaceAll('\ufeff', '');
    const acentos = <String, String>{
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
      'ñ': 'n',
    };
    for (final e in acentos.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'[\s_\.\-]'), '');
  }

  int? _indiceColunaPorAliases(List<String> headers, List<String> aliases) {
    final keys = headers.map(_chaveCabecalhoCsv).toList();
    for (final alias in aliases) {
      final a = _chaveCabecalhoCsv(alias);
      if (a.isEmpty) continue;
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == a) {
          return i;
        }
      }
    }
    for (final alias in aliases) {
      final a = _chaveCabecalhoCsv(alias);
      if (a.length < 5) {
        continue;
      }
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].contains(a)) {
          return i;
        }
      }
    }
    for (final alias in aliases) {
      final a = _chaveCabecalhoCsv(alias);
      if (a.length < 2) {
        continue;
      }
      for (var i = 0; i < keys.length; i++) {
        if (keys[i] == a) {
          return i;
        }
      }
    }
    return null;
  }

  int _parseQuantidadeCsv(String texto) {
    final t = texto.trim();
    if (t.isEmpty) {
      return 0;
    }
    final semMilhar = t.replaceAll('.', '').replaceAll(',', '.');
    final d = double.tryParse(semMilhar);
    if (d == null) {
      return int.tryParse(t.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;
    }
    final arred = d.round();
    return arred < 0 ? 0 : arred;
  }

  Produto? _produtoPorCodigoInterno(String codigo) {
    final alvo = codigo.trim().toLowerCase();
    if (alvo.isEmpty) return null;
    for (final p in widget.produtoRepository.listarTodos()) {
      if (p.codigoInterno.trim().toLowerCase() == alvo) {
        return p;
      }
    }
    return null;
  }

  Future<void> _importarProdutosCsv() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (!mounted) return;
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _definirStatus('Arquivo CSV vazio ou nao foi possivel ler.', erro: true);
      return;
    }
    final texto = _lerTextoArquivoUtf8OuLatin1(bytes);
    final textoN = texto.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    List<List<String>> linhas;
    var leituraCsv = 'CSV padrao (delimitador automatico, aspas suportadas)';
    try {
      final raw = Csv(dynamicTyping: false).decode(textoN);
      linhas = raw
          .map((row) => row.map((e) => e.toString().trim()).toList())
          .toList();
    } catch (_) {
      leituraCsv = 'CSV simples (fallback)';
      final linhasBrutas = textoN
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (linhasBrutas.length < 2) {
        _definirStatus(
          'CSV precisa ter cabecalho e ao menos uma linha de dados.',
          erro: true,
        );
        return;
      }
      final sep = _detectarSeparadorCsv(linhasBrutas.first);
      linhas = linhasBrutas.map((l) => _dividirLinhaCsv(l, sep)).toList();
    }

    if (linhas.length < 2) {
      _definirStatus(
        'CSV precisa ter cabecalho e ao menos uma linha de dados.',
        erro: true,
      );
      return;
    }
    final headers = linhas.first;
    final maxCols = headers.length;
    for (var i = 1; i < linhas.length; i++) {
      while (linhas[i].length < maxCols) {
        linhas[i].add('');
      }
    }

    final idxCodigo = _indiceColunaPorAliases(headers, [
      'codigo',
      'codigo interno',
      'codigo_interno',
      'sku',
      'ref',
      'cod',
    ]);
    final idxCodInterno = _indiceColunaPorAliases(headers, [
      'codinterno',
      'codigo_interno',
      'cod_interno',
      'codigointerno',
    ]);
    final idxCodEx = _indiceColunaPorAliases(headers, [
      'codex',
      'cod_ex',
      'cod ex',
    ]);
    var idxNome = _indiceColunaPorAliases(headers, [
      'nome',
      'produto',
      'item',
      'mercadoria',
    ]);
    final idxDescricao = _indiceColunaPorAliases(headers, [
      'descricao tecnica',
      'descricao_tecnica',
      'observacao',
      'observacoes',
      'obs',
      'complemento',
    ]);
    final idxObsCol = _indiceColunaPorAliases(headers, [
      'obs',
      'observacoes',
      'observacao',
    ]);
    idxNome ??= _indiceColunaPorAliases(headers, [
      'descricao',
      'descrição',
      'desc',
    ]);
    var idxPreco =
        _indiceColunaPrecoVenda(headers) ??
        _indiceColunaPorAliases(headers, [
          'precovenda',
          'preco venda',
          'preco_venda',
          'valor venda',
          'valorvenda',
          'vr venda',
          'vrvenda',
          'preco unitario',
          'preco_unitario',
          'preco1',
          'preco2',
          'preco3',
        ]);
    final idxPreco1 = _indiceColunaPorAliases(headers, ['preco1', 'preco_1']);
    final idxPreco2 = _indiceColunaPorAliases(headers, ['preco2', 'preco_2']);
    final idxPreco3 = _indiceColunaPorAliases(headers, ['preco3', 'preco_3']);
    final idxPrecoCusto = _indiceColunaPorAliases(headers, [
      'precocusto',
      'preco custo',
      'preco_custo',
    ]);
    final idxCustoMedio = _indiceColunaPorAliases(headers, [
      'customedio',
      'custo medio',
      'custo_medio',
      'cust_medio',
      'mediocusto',
    ]);
    final idxEstoque = _indiceColunaPorAliases(headers, [
      'quantidade',
      'estoque',
      'qtd',
      'saldo',
    ]);
    final idxEstMinimo = _indiceColunaPorAliases(headers, [
      'estminimo',
      'estoque minimo',
      'estoque_minimo',
      'quantidade minima',
      'qtd minima',
    ]);
    final idxFabricante = _indiceColunaPorAliases(headers, [
      'fabricante',
      'marca',
    ]);
    final idxUnidade = _indiceColunaPorAliases(headers, [
      'unidade',
      'und',
      'um',
    ]);

    if (idxCodigo == null && idxCodInterno == null && idxCodEx == null) {
      _definirStatus(
        'CSV sem coluna de codigo. Inclua Codigo, CodInterno ou CodEx (ex.: export TabEst1).',
        erro: true,
      );
      return;
    }
    if (idxNome == null) {
      _definirStatus(
        'CSV sem coluna de nome/descricao. Inclua: Nome, Produto ou Descricao.',
        erro: true,
      );
      return;
    }
    if (idxPreco == null) {
      _definirStatus(
        'CSV sem coluna de preco de venda. Inclua: PrecoVenda, Preco venda, Valor venda ou Preco1.',
        erro: true,
      );
      return;
    }

    final exclHeur = _indicesExcluidosHeuristicaPreco(headers);
    void excluirCol(int? i) {
      if (i != null) {
        exclHeur.add(i);
      }
    }

    excluirCol(idxCodigo);
    excluirCol(idxCodInterno);
    excluirCol(idxCodEx);
    excluirCol(idxNome);
    excluirCol(idxDescricao);
    excluirCol(idxEstoque);
    excluirCol(idxEstMinimo);
    excluirCol(idxPrecoCusto);
    excluirCol(idxCustoMedio);
    final idxPrecoRefinado = _refinarIndicePrecoVenda(
      linhas,
      headers,
      idxPreco,
      exclHeur,
    );

    var atualizarExistentes = true;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return AlertDialog(
              title: const Text('Importar produtos (CSV)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arquivo: ${file.name}'),
                    Text(leituraCsv),
                    Text('Colunas no cabecalho: ${linhas.first.length}'),
                    Text('Linhas de dados: ${linhas.length - 1}'),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Atualizar produto se o codigo ja existir',
                      ),
                      value: atualizarExistentes,
                      onChanged: (v) {
                        setSt(() => atualizarExistentes = v ?? true);
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Paradox TabEst1: Codigo, CodInterno ou CodEx, Produto, PrecoVenda, Quantidade, '
                      'PrecoCusto, CustoMedio, EstMinimo, Fabricante, Unidade, Obs (opcionais).\n'
                      'Categoria fixa: Outros / Importacao CSV. PrecoVenda do CSV = apenas A Prazo (preco1); '
                      'a Vista e Atacado ficam 0 em produtos novos ou mantidos na atualizacao.\n'
                      'Quantidade negativa ou decimal: arredonda e nao deixa estoque < 0.\n'
                      'PrecoVenda vazio ou "000": tenta PrecoCusto; depois valores em Obs/descricao '
                      '(ex.: 60,00 no texto); se ainda zero, grava venda R\$ 0,01.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Importar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmar != true || !mounted) return;

    var inseridos = 0;
    var atualizados = 0;
    var ignorados = 0;
    var precosExtraidosDeTexto = 0;
    final erros = <String>[];

    for (var r = 1; r < linhas.length; r++) {
      final row = linhas[r];
      var codigo = idxCodigo != null && idxCodigo < row.length
          ? row[idxCodigo].trim()
          : '';
      if (codigo.isEmpty &&
          idxCodInterno != null &&
          idxCodInterno < row.length) {
        codigo = row[idxCodInterno].trim();
      }
      if (codigo.isEmpty && idxCodEx != null && idxCodEx < row.length) {
        codigo = row[idxCodEx].trim();
      }
      final nome = row[idxNome].trim();
      final descExtra = idxDescricao != null && idxDescricao < row.length
          ? row[idxDescricao].trim()
          : '';
      var precoTxt = row[idxPrecoRefinado].trim();
      if (precoTxt.isEmpty || (_parseValorMonetario(precoTxt) ?? 0) <= 0) {
        for (final j in [idxPreco1, idxPreco2, idxPreco3]) {
          if (j == null || j >= row.length) continue;
          final t = row[j].trim();
          if (t.isNotEmpty && (_parseValorMonetario(t) ?? 0) > 0) {
            precoTxt = t;
            break;
          }
        }
      }
      if (precoTxt.isEmpty || (_parseValorMonetario(precoTxt) ?? 0) <= 0) {
        if (idxPrecoCusto != null && idxPrecoCusto < row.length) {
          final t = row[idxPrecoCusto].trim();
          if (t.isNotEmpty && (_parseValorMonetario(t) ?? 0) > 0) {
            precoTxt = t;
          }
        }
      }
      var precoVeioDeTextoLivre = false;
      if (precoTxt.isEmpty || (_parseValorMonetario(precoTxt) ?? 0) <= 0) {
        final obsCell = idxObsCol != null && idxObsCol < row.length
            ? row[idxObsCol].trim()
            : '';
        double? doTexto;
        if (obsCell.isNotEmpty) {
          doTexto = _extrairPrecoVendaDeTextoLivre(obsCell);
        }
        doTexto ??= _extrairPrecoVendaDeTextoLivre(descExtra);
        if (doTexto != null && doTexto > 0) {
          precoTxt = doTexto.toString();
          precoVeioDeTextoLivre = true;
        }
      }
      final estoqueTxt = idxEstoque != null && idxEstoque < row.length
          ? row[idxEstoque].trim()
          : '';
      final custoTxt = idxPrecoCusto != null && idxPrecoCusto < row.length
          ? row[idxPrecoCusto].trim()
          : '';
      final custoMedioTxt = idxCustoMedio != null && idxCustoMedio < row.length
          ? row[idxCustoMedio].trim()
          : '';
      final estMinTxt = idxEstMinimo != null && idxEstMinimo < row.length
          ? row[idxEstMinimo].trim()
          : '';
      final fabricanteTxt = idxFabricante != null && idxFabricante < row.length
          ? row[idxFabricante].trim()
          : '';
      final unidadeTxt = idxUnidade != null && idxUnidade < row.length
          ? row[idxUnidade].trim()
          : '';

      if (codigo.isEmpty && nome.isEmpty) {
        ignorados++;
        continue;
      }
      if (codigo.isEmpty) {
        erros.add('Linha ${r + 1}: codigo vazio.');
        continue;
      }
      if (nome.isEmpty) {
        erros.add('Linha ${r + 1}: nome/descricao vazio.');
        continue;
      }
      // Paradox/TabEst: PrecoVenda "000" ou 0 e comum; usa custo e, se ainda zero, 0.01 (sistema exige venda > 0).
      var preco = _parseValorMonetario(precoTxt);
      if (preco == null || preco <= 0) {
        final pc = _parseValorMonetario(custoTxt);
        if (pc != null && pc > 0) {
          preco = pc;
        }
      }
      if (preco == null || preco <= 0) {
        preco = 0.01;
      } else if (precoVeioDeTextoLivre) {
        precosExtraidosDeTexto++;
      }
      final estoque = _parseQuantidadeCsv(estoqueTxt);
      final precoCustoVal = _parseValorMonetario(custoTxt) ?? 0;
      final precoCusto = precoCustoVal < 0 ? 0.0 : precoCustoVal;
      final qtdMin = _parseQuantidadeCsv(estMinTxt);
      final descricao = descExtra.isEmpty ? '' : descExtra;
      final existente = _produtoPorCodigoInterno(codigo);
      double custoMedioVal;
      if (custoMedioTxt.isNotEmpty) {
        custoMedioVal = _parseValorMonetario(custoMedioTxt) ?? 0;
        if (custoMedioVal < 0) {
          custoMedioVal = 0;
        }
      } else {
        custoMedioVal = existente?.custoMedio ?? 0;
      }

      if (existente != null && !atualizarExistentes) {
        ignorados++;
        continue;
      }

      // Import antigo copiava PrecoVenda para preco2/preco3: se os tres eram iguais, zera vista/atacado na reimportacao.
      var preco2Imp = existente?.preco2 ?? 0;
      var preco3Imp = existente?.preco3 ?? 0;
      if (existente != null) {
        final p1a = existente.preco1;
        if (p1a > 0 &&
            (existente.preco2 - p1a).abs() < 0.0001 &&
            (existente.preco3 - p1a).abs() < 0.0001) {
          preco2Imp = 0;
          preco3Imp = 0;
        }
      }

      final produto = Produto(
        id: existente?.id ?? 0,
        codigoInterno: codigo,
        nome: _normalizarNomeProduto(nome),
        descricao: descricao,
        unidade: _normalizarUnidade(unidadeTxt.isEmpty ? 'UN' : unidadeTxt),
        categoria: _categoriaOutros,
        subcategoria: 'Importacao CSV',
        marca: '',
        fornecedor: '',
        fabricante: fabricanteTxt,
        codigoBarras: '',
        fotoPath: existente?.fotoPath ?? '',
        localizacao: '',
        ncm: '',
        estoque: estoque,
        quantidadeMinima: qtdMin > 0
            ? qtdMin
            : (existente?.quantidadeMinima ?? 0),
        precoCusto: precoCusto,
        custoMedio: custoMedioVal,
        // PrecoVenda do TabEst1 = "a prazo" no sistema antigo -> so preco1 e precoVenda (como no salvar manual).
        preco1: preco,
        preco2: preco2Imp,
        preco3: preco3Imp,
        precoVenda: preco,
        criadoEm: existente?.criadoEm,
        ativo: existente?.ativo ?? true,
      );
      final idSalvo = widget.produtoRepository.salvar(produto);
      widget.produtoRepository.sincronizarCustoMedioInteligenteParaProduto(
        idSalvo,
        legadoImportacao: custoMedioVal > 0 ? custoMedioVal : null,
      );
      if (existente != null) {
        atualizados++;
      } else {
        inseridos++;
      }
    }

    if (!mounted) return;
    final buf = StringBuffer()
      ..write('Importacao CSV: $inseridos novos, $atualizados atualizados');
    if (precosExtraidosDeTexto > 0) {
      buf.write(
        '; preco de venda obtido do texto Obs/descricao em $precosExtraidosDeTexto linha(s)',
      );
    }
    if (ignorados > 0) {
      buf.write(', $ignorados ignorados');
    }
    if (erros.isNotEmpty) {
      buf.write('. ${erros.length} erro(s). ');
      buf.write(_resumoTiposErroImportacaoCsv(erros));
    }
    _definirStatus(buf.toString(), erro: erros.isNotEmpty);
    if (erros.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          final preview = erros.take(25).join('\n');
          final resumo = _resumoTiposErroImportacaoCsv(erros);
          return AlertDialog(
            title: const Text('Erros na importacao'),
            content: SingleChildScrollView(
              child: SelectableText(
                erros.length > 25
                    ? '$resumo\n\n$preview\n... e mais ${erros.length - 25} linha(s).'
                    : '$resumo\n\n$preview',
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
    }
  }

  Future<void> _abrirPesquisaProduto() async {
    final pesquisaController = TextEditingController();
    final resultadosScrollController = ScrollController();
    final pesquisaFocusNode = FocusNode();
    var somenteInativosLista = false;
    List<Produto> resultados = widget.produtoRepository.pesquisarPadraoPdv(
      '',
      limite: 80,
      somenteAtivos: !somenteInativosLista,
      somenteInativos: somenteInativosLista,
    );
    int indiceSelecionado = resultados.isEmpty ? -1 : 0;

    final produtoSelecionado = await showDialog<Produto>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            TextSpan spanComDestaque(
              String texto,
              String termo,
              TextStyle estiloBase,
            ) {
              final busca = termo.trim().toLowerCase();
              if (busca.isEmpty) {
                return TextSpan(text: texto, style: estiloBase);
              }
              final textoMinusculo = texto.toLowerCase();
              final spans = <TextSpan>[];
              var cursor = 0;

              while (cursor < texto.length) {
                final indice = textoMinusculo.indexOf(busca, cursor);
                if (indice < 0) {
                  spans.add(TextSpan(text: texto.substring(cursor)));
                  break;
                }
                if (indice > cursor) {
                  spans.add(TextSpan(text: texto.substring(cursor, indice)));
                }
                spans.add(
                  TextSpan(
                    text: texto.substring(indice, indice + busca.length),
                    style: estiloBase.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
                cursor = indice + busca.length;
              }

              return TextSpan(style: estiloBase, children: spans);
            }

            void rolarParaIndiceSelecionado() {
              if (!resultadosScrollController.hasClients ||
                  indiceSelecionado < 0) {
                return;
              }
              const alturaEstimadaLinha = 64.0;
              final posicaoDesejada = (indiceSelecionado * alturaEstimadaLinha)
                  .clamp(
                    0.0,
                    resultadosScrollController.position.maxScrollExtent,
                  );
              resultadosScrollController.animateTo(
                posicaoDesejada,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
              );
            }

            return Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent || resultados.isEmpty) {
                  return KeyEventResult.ignored;
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setDialogState(() {
                    indiceSelecionado = math.min(
                      indiceSelecionado + 1,
                      resultados.length - 1,
                    );
                  });
                  rolarParaIndiceSelecionado();
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setDialogState(() {
                    indiceSelecionado = math.max(indiceSelecionado - 1, 0);
                  });
                  rolarParaIndiceSelecionado();
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                  final indice = indiceSelecionado >= 0 ? indiceSelecionado : 0;
                  Navigator.pop(context, resultados[indice]);
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.pop(context);
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                title: const Text('Pesquisar produto'),
                content: AdaptiveDialogPane(
                  desktopWidth: 760,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 28,
                              width: 28,
                              child: Checkbox(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                value: somenteInativosLista,
                                onChanged: (v) {
                                  if (v == null) return;
                                  setDialogState(() {
                                    somenteInativosLista = v;
                                    resultados = widget.produtoRepository
                                        .pesquisarPadraoPdv(
                                          pesquisaController.text,
                                          limite: 80,
                                          somenteAtivos: !somenteInativosLista,
                                          somenteInativos: somenteInativosLista,
                                        );
                                    indiceSelecionado = resultados.isEmpty
                                        ? -1
                                        : 0;
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (resultadosScrollController.hasClients) {
                                      resultadosScrollController.jumpTo(0);
                                    }
                                  });
                                },
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'Somente inativos',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: pesquisaController,
                        focusNode: pesquisaFocusNode,
                        autofocus: true,
                        decoration: produtoBuscaInputDecoration(),
                        onChanged: (value) {
                          setDialogState(() {
                            resultados = widget.produtoRepository.pesquisarPadraoPdv(
                              value,
                              limite: 80,
                              somenteAtivos: !somenteInativosLista,
                              somenteInativos: somenteInativosLista,
                            );
                            indiceSelecionado = resultados.isEmpty ? -1 : 0;
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (resultadosScrollController.hasClients) {
                              resultadosScrollController.jumpTo(0);
                            }
                            if (pesquisaFocusNode.canRequestFocus) {
                              pesquisaFocusNode.requestFocus();
                            }
                          });
                        },
                        onSubmitted: (_) {
                          if (resultados.isEmpty) {
                            return;
                          }
                          final indice = indiceSelecionado >= 0
                              ? indiceSelecionado
                              : 0;
                          Navigator.pop(context, resultados[indice]);
                        },
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: 220,
                          maxHeight: adaptiveDialogListMaxHeight(context),
                        ),
                        child: resultados.isEmpty
                            ? const Center(
                                child: Text('Nenhum produto encontrado.'),
                              )
                            : ListView.builder(
                                controller: resultadosScrollController,
                                shrinkWrap: true,
                                itemCount: resultados.length,
                                itemBuilder: (context, index) {
                                  final produto = resultados[index];
                                  final consulta = pesquisaController.text
                                      .trim();
                                  final estiloTitulo =
                                      Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ) ??
                                      const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      );
                                  final estiloSubtitulo =
                                      Theme.of(context).textTheme.bodyMedium ??
                                      const TextStyle();
                                  final selecionado =
                                      index == indiceSelecionado;

                                  return MouseRegion(
                                    onEnter: (_) {
                                      if (indiceSelecionado == index) {
                                        return;
                                      }
                                      setDialogState(() {
                                        indiceSelecionado = index;
                                      });
                                    },
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                      selected: selecionado,
                                      selectedTileColor: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.08),
                                      title: RichText(
                                        text: spanComDestaque(
                                          produto.nome,
                                          consulta,
                                          estiloTitulo,
                                        ),
                                      ),
                                      subtitle: RichText(
                                        text: spanComDestaque(
                                          'SKU: ${produto.codigoInterno} | '
                                          'Un: ${rotuloUnidadeProdutoLista(produto)} | '
                                          'Categoria: ${produto.categoria.isEmpty ? '-' : produto.categoria}'
                                          '${produto.ativo ? '' : ' · Inativo'}',
                                          consulta,
                                          estiloSubtitulo,
                                        ),
                                      ),
                                      onTap: () =>
                                          Navigator.pop(context, produto),
                                    ),
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
              ),
            );
          },
        );
      },
    );

    pesquisaController.dispose();
    resultadosScrollController.dispose();
    pesquisaFocusNode.dispose();

    if (produtoSelecionado != null) {
      _editarProdutoNoCabecalho(produtoSelecionado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margem1 = _margemCalculadaPorController(_preco1Controller);
    final margem2 = _margemCalculadaPorController(_preco2Controller);
    final margem3 = _margemCalculadaPorController(_preco3Controller);
    final markup1 = _markupCalculadoPorController(_preco1Controller);
    final markup2 = _markupCalculadoPorController(_preco2Controller);
    final markup3 = _markupCalculadoPorController(_preco3Controller);
    final semantic = theme.extension<AppSemanticColors>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro de Produtos'),
        actions: [
          IconButton(
            tooltip: 'Importar produtos (CSV)',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _importarProdutosCsv,
          ),
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: Builder(
          builder: (tabCtx) {
            return Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.f5):
                    _CadastroProdutoSalvarIntent(),
                SingleActivator(LogicalKeyboardKey.f10):
                    _CadastroProdutoSalvarIntent(),
                SingleActivator(LogicalKeyboardKey.escape):
                    _CadastroProdutoCancelarIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _CadastroProdutoSalvarIntent:
                      CallbackAction<_CadastroProdutoSalvarIntent>(
                        onInvoke: (_) {
                          final tc = DefaultTabController.maybeOf(tabCtx);
                          if (tc != null && tc.index != 0) return null;
                          _salvarProduto();
                          return null;
                        },
                      ),
                  _CadastroProdutoCancelarIntent:
                      CallbackAction<_CadastroProdutoCancelarIntent>(
                        onInvoke: (_) {
                          final tc = DefaultTabController.maybeOf(tabCtx);
                          if (tc != null && tc.index != 0) return null;
                          _limparFormularioComConfirmacao();
                          return null;
                        },
                      ),
                },
                child: KeyboardListener(
                  focusNode: _cadastroKeyboardFocusNode,
                  onKeyEvent: (KeyEvent event) {
                    if (event is! KeyDownEvent) {
                      return;
                    }
                    if (event.logicalKey != LogicalKeyboardKey.f11) {
                      return;
                    }
                    final tc = DefaultTabController.maybeOf(tabCtx);
                    if (tc != null && tc.index != 0) {
                      return;
                    }
                    _imprimirEtiquetaProduto();
                  },
                  child: Column(
                    children: [
                      Material(
                        color: theme.colorScheme.surface,
                        child: TabBar(
                          labelColor: theme.colorScheme.primary,
                          tabs: const [
                            Tab(text: 'Dados do produto'),
                            Tab(text: 'Historico de compras'),
                            Tab(text: 'Movimentacoes estoque'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            Form(
                              key: _formKey,
                              autovalidateMode: _tentouSalvar
                                  ? AutovalidateMode.always
                                  : AutovalidateMode.disabled,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        _erpGap24,
                                        _erpGap16,
                                        _erpGap24,
                                        0,
                                      ),
                                      child: RawScrollbar(
                                        controller: _scrollController,
                                        thumbVisibility: true,
                                        trackVisibility: true,
                                        thickness: 8,
                                        radius: const Radius.circular(8),
                                        crossAxisMargin: 2,
                                        mainAxisMargin: 4,
                                        child: SingleChildScrollView(
                                          controller: _scrollController,
                                          padding: const EdgeInsets.only(
                                            bottom: _erpGap24,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Material(
                                                color: Colors.transparent,
                                                child: context.isCompactLayout
                                                    ? Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          OutlinedButton.icon(
                                                            style: OutlinedButton
                                                                .styleFrom(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal:
                                                                    _erpGap16,
                                                                vertical: 12,
                                                              ),
                                                            ),
                                                            onPressed:
                                                                _abrirPesquisaProduto,
                                                            icon: const Icon(
                                                              Icons.search,
                                                              size: 20,
                                                            ),
                                                            label: const Text(
                                                              'Pesquisar produto',
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: _erpGap8,
                                                          ),
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              IconButton(
                                                                tooltip:
                                                                    'Primeiro',
                                                                onPressed:
                                                                    _irParaPrimeiroProduto,
                                                                icon: const Icon(
                                                                  Icons
                                                                      .first_page_outlined,
                                                                ),
                                                              ),
                                                              IconButton(
                                                                tooltip:
                                                                    'Anterior',
                                                                onPressed:
                                                                    _irParaProdutoAnterior,
                                                                icon: const Icon(
                                                                  Icons
                                                                      .navigate_before_outlined,
                                                                ),
                                                              ),
                                                              IconButton(
                                                                tooltip:
                                                                    'Proximo',
                                                                onPressed:
                                                                    _irParaProximoProduto,
                                                                icon: const Icon(
                                                                  Icons
                                                                      .navigate_next_outlined,
                                                                ),
                                                              ),
                                                              IconButton(
                                                                tooltip: 'Ultimo',
                                                                onPressed:
                                                                    _irParaUltimoProduto,
                                                                icon: const Icon(
                                                                  Icons
                                                                      .last_page_outlined,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      )
                                                    : Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Expanded(
                                                            child: OutlinedButton
                                                                .icon(
                                                              style: OutlinedButton
                                                                  .styleFrom(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      _erpGap16,
                                                                  vertical: 12,
                                                                ),
                                                              ),
                                                              onPressed:
                                                                  _abrirPesquisaProduto,
                                                              icon: const Icon(
                                                                Icons.search,
                                                                size: 20,
                                                              ),
                                                              label: const Text(
                                                                'Pesquisar produto',
                                                              ),
                                                            ),
                                                          ),
                                                          IconButton(
                                                            tooltip: 'Primeiro',
                                                            onPressed:
                                                                _irParaPrimeiroProduto,
                                                            icon: const Icon(
                                                              Icons
                                                                  .first_page_outlined,
                                                            ),
                                                          ),
                                                          IconButton(
                                                            tooltip: 'Anterior',
                                                            onPressed:
                                                                _irParaProdutoAnterior,
                                                            icon: const Icon(
                                                              Icons
                                                                  .navigate_before_outlined,
                                                            ),
                                                          ),
                                                          IconButton(
                                                            tooltip: 'Proximo',
                                                            onPressed:
                                                                _irParaProximoProduto,
                                                            icon: const Icon(
                                                              Icons
                                                                  .navigate_next_outlined,
                                                            ),
                                                          ),
                                                          IconButton(
                                                            tooltip: 'Ultimo',
                                                            onPressed:
                                                                _irParaUltimoProduto,
                                                            icon: const Icon(
                                                              Icons
                                                                  .last_page_outlined,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                              const SizedBox(height: _erpGap16),
                                              Text(
                                                _produtoEmEdicaoId == null
                                                    ? 'Novo cadastro — use as abas abaixo (F5 salva · setas na busca do PDV).'
                                                    : 'Edicao — revise as abas e salve (F5 ou F10).',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: 0.65,
                                                          ),
                                                    ),
                                              ),
                                              const SizedBox(height: _erpGap8),
                                              _buildCabecalhoFixoCadastro(
                                                context,
                                              ),
                                              Material(
                                                color: theme
                                                    .colorScheme.surface,
                                                child: TabBar(
                                                  controller:
                                                      _subAbaCadastroController,
                                                  isScrollable: true,
                                                  tabAlignment:
                                                      TabAlignment.start,
                                                  tabs: [
                                                    for (final t
                                                        in _subAbasCadastro)
                                                      Tab(text: t),
                                                  ],
                                                ),
                                              ),
                                              if (_subAbaCadastroController
                                                      .index ==
                                                  0) ...[
                                              _erpSurfaceCard(
                                                context: context,
                                                title: 'Informacoes basicas',
                                                icon:
                                                    Icons.inventory_2_outlined,
                                                children: [
                                                  LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final sideBySide =
                                                          constraints
                                                              .maxWidth >=
                                                          _erpFotoPreviewSideBySideBreakpoint;
                                                      final preview =
                                                          _erpProdutoFotoPreviewSquare(
                                                            context,
                                                          );

                                                      final camposEBotoesFoto = Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          _erpResponsiveGrid(context, [
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                _erpFieldLabel(
                                                                  'Codigo interno (SKU)',
                                                                  context,
                                                                ),
                                                                TextFormField(
                                                                  controller:
                                                                      _codigoInternoController,
                                                                  enabled:
                                                                      !_gerarSkuAutomatico,
                                                                  validator:
                                                                      _validarSku,
                                                                  decoration:
                                                                      _erpInputDecoration(
                                                                        context,
                                                                        helper:
                                                                            'Manual ou geracao automatica ao salvar',
                                                                      ),
                                                                ),
                                                                CheckboxListTile(
                                                                  dense: true,
                                                                  visualDensity: const VisualDensity(
                                                                    horizontal:
                                                                        VisualDensity
                                                                            .minimumDensity,
                                                                    vertical:
                                                                        VisualDensity
                                                                            .minimumDensity,
                                                                  ),
                                                                  value:
                                                                      _gerarSkuAutomatico,
                                                                  onChanged: (value) {
                                                                    setState(() {
                                                                      _gerarSkuAutomatico =
                                                                          value ??
                                                                          true;
                                                                      if (_gerarSkuAutomatico) {
                                                                        _codigoInternoController
                                                                            .clear();
                                                                      }
                                                                    });
                                                                  },
                                                                  contentPadding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                  title: Text(
                                                                    'Gerar SKU automaticamente',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w400,
                                                                      height:
                                                                          1.2,
                                                                      color: Theme.of(context)
                                                                          .colorScheme
                                                                          .onSurface
                                                                          .withValues(
                                                                            alpha:
                                                                                0.62,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  controlAffinity:
                                                                      ListTileControlAffinity
                                                                          .leading,
                                                                ),
                                                              ],
                                                            ),
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                _erpFieldLabel(
                                                                  'Marca',
                                                                  context,
                                                                ),
                                                                TextField(
                                                                  controller:
                                                                      _marcaController,
                                                                  decoration:
                                                                      _erpInputDecoration(
                                                                        context,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                _erpFieldLabel(
                                                                  'Fabricante',
                                                                  context,
                                                                ),
                                                                TextField(
                                                                  controller:
                                                                      _fabricanteController,
                                                                  decoration:
                                                                      _erpInputDecoration(
                                                                        context,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                _erpFieldLabel(
                                                                  'Fornecedor',
                                                                  context,
                                                                ),
                                                                TextField(
                                                                  controller:
                                                                      _fornecedorController,
                                                                  decoration:
                                                                      _erpInputDecoration(
                                                                        context,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                          ]),
                                                          const SizedBox(
                                                            height: _erpGap16,
                                                          ),
                                                          Wrap(
                                                            spacing: _erpGap8,
                                                            runSpacing: _erpGap8,
                                                            children: [
                                                              OutlinedButton.icon(
                                                                style:
                                                                    _estiloBotaoContornoCompacto,
                                                                onPressed:
                                                                    _buscandoFoto
                                                                        ? null
                                                                        : _importarFotoProduto,
                                                                icon: const Icon(
                                                                  Icons
                                                                      .add_a_photo_outlined,
                                                                  size: 18,
                                                                ),
                                                                label: Text(
                                                                  _fotoPreviewPath() ==
                                                                          null
                                                                      ? 'Importar foto'
                                                                      : 'Trocar foto',
                                                                ),
                                                              ),
                                                              OutlinedButton.icon(
                                                                style:
                                                                    _estiloBotaoContornoCompacto,
                                                                onPressed:
                                                                    _buscandoFoto
                                                                        ? null
                                                                        : _buscarFotoProdutoNaWeb,
                                                                icon: _buscandoFoto
                                                                    ? const SizedBox(
                                                                        width: 18,
                                                                        height: 18,
                                                                        child: CircularProgressIndicator(
                                                                          strokeWidth: 2,
                                                                        ),
                                                                      )
                                                                    : const Icon(
                                                                        Icons
                                                                            .image_search_outlined,
                                                                        size: 18,
                                                                      ),
                                                                label: const Text(
                                                                  'Buscar foto',
                                                                ),
                                                              ),
                                                              if (_fotoPreviewPath() !=
                                                                  null)
                                                                OutlinedButton.icon(
                                                                  style:
                                                                      _estiloBotaoContornoCompacto,
                                                                  onPressed:
                                                                      _removerFotoProduto,
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .delete_outline,
                                                                    size: 18,
                                                                  ),
                                                                  label:
                                                                      const Text(
                                                                        'Remover',
                                                                      ),
                                                                ),
                                                            ],
                                                          ),
                                                        ],
                                                      );

                                                      if (sideBySide) {
                                                        return Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Expanded(
                                                              child:
                                                                  camposEBotoesFoto,
                                                            ),
                                                            const SizedBox(
                                                              width: _erpGap16,
                                                            ),
                                                            preview,
                                                          ],
                                                        );
                                                      }

                                                      return Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          camposEBotoesFoto,
                                                          const SizedBox(
                                                            height: _erpGap16,
                                                          ),
                                                          Center(
                                                            child: preview,
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                              _erpSurfaceCard(
                                                context: context,
                                                title:
                                                    'Classificacao e codigos',
                                                icon: Icons.category_outlined,
                                                children: [
                                                  _erpResponsiveGrid(context, [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'Categoria',
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          initialValue:
                                                              _categoriaSelecionada,
                                                          validator:
                                                              _validarCategoria,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                hint:
                                                                    'Selecione',
                                                              ),
                                                          items: _categoriasMateriaisConstrucao
                                                              .keys
                                                              .map(
                                                                (categoria) =>
                                                                    DropdownMenuItem<
                                                                      String
                                                                    >(
                                                                      value:
                                                                          categoria,
                                                                      child: Text(
                                                                        categoria,
                                                                      ),
                                                                    ),
                                                              )
                                                              .toList(),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _categoriaSelecionada =
                                                                  value;
                                                              _subcategoriaSelecionada =
                                                                  null;
                                                              _subcategoriaLivreController
                                                                  .clear();
                                                            });
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'Subcategoria',
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          key: ValueKey(
                                                            'subcategoria_${_categoriaSelecionada ?? 'vazio'}_${_subcategoriaSelecionada ?? 'vazio'}',
                                                          ),
                                                          initialValue:
                                                              _subcategoriaSelecionada,
                                                          validator:
                                                              _validarSubcategoria,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                hint:
                                                                    'Selecione',
                                                              ),
                                                          items:
                                                              (_categoriasMateriaisConstrucao[_categoriaSelecionada] ??
                                                                      [])
                                                                  .map(
                                                                    (
                                                                      subcategoria,
                                                                    ) => DropdownMenuItem<String>(
                                                                      value:
                                                                          subcategoria,
                                                                      child: Text(
                                                                        subcategoria,
                                                                      ),
                                                                    ),
                                                                  )
                                                                  .toList(),
                                                          onChanged:
                                                              _categoriaSelecionada ==
                                                                      null ||
                                                                  _categoriaSelecionada ==
                                                                      _categoriaOutros
                                                              ? null
                                                              : (value) {
                                                                  setState(() {
                                                                    _subcategoriaSelecionada =
                                                                        value;
                                                                  });
                                                                },
                                                        ),
                                                      ],
                                                    ),
                                                  ]),
                                                  if (_categoriaSelecionada ==
                                                      _categoriaOutros) ...[
                                                    const SizedBox(
                                                      height: _erpGap16,
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'Subcategoria personalizada',
                                                          context,
                                                        ),
                                                        TextFormField(
                                                          controller:
                                                              _subcategoriaLivreController,
                                                          validator:
                                                              _validarSubcategoria,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                helper:
                                                                    'Para itens fora do padrao',
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                  const SizedBox(
                                                    height: _erpGap16,
                                                  ),
                                                  _erpResponsiveGrid(context, [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'Unidade',
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          isDense: true,
                                                          isExpanded: true,
                                                          initialValue:
                                                              _unidadeSelecionada,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                              ),
                                                          items: const [
                                                            DropdownMenuItem(
                                                              value: 'UN',
                                                              child: Text(
                                                                'UN - Unidade',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'M',
                                                              child: Text(
                                                                'M - Metro',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'MTS',
                                                              child: Text(
                                                                'MTS - Metros',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'M2',
                                                              child: Text(
                                                                'M2 - Metro quadrado',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'M3',
                                                              child: Text(
                                                                'M3 - Metro cubico',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'KG',
                                                              child: Text(
                                                                'KG - Quilograma',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'SC',
                                                              child: Text(
                                                                'SC - Saco',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'CX',
                                                              child: Text(
                                                                'CX - Caixa',
                                                              ),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: 'LT',
                                                              child: Text(
                                                                'LT - Litro',
                                                              ),
                                                            ),
                                                          ],
                                                          onChanged: (value) {
                                                            if (value != null) {
                                                              setState(() {
                                                                _unidadeSelecionada =
                                                                    _normalizarUnidade(
                                                                      value,
                                                                    );
                                                              });
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ]),
                                                ],
                                              ),
                                              _buildCardEmbalagemUnidade(
                                                context,
                                              ),
                                              const SizedBox(
                                                height: _erpGap16,
                                              ),
                                              ],
                                              if (_subAbaCadastroController
                                                      .index ==
                                                  1)
                                              _erpSurfaceCard(
                                                context: context,
                                                title:
                                                    'Precos, custos e margem de lucro',
                                                icon: Icons.payments_outlined,
                                                children: [
                                                  _buildPainelCalcularMargemPrecos(
                                                    context,
                                                  ),
                                                  const SizedBox(
                                                    height: _erpGap16,
                                                  ),
                                                  LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final wideKpi =
                                                          constraints
                                                              .maxWidth >=
                                                          _erpPrecosKpiBreakpoint;

                                                      final painelKpi =
                                                          _erpPainelResumoFinanceiroKpis(
                                                            context,
                                                            margem1: margem1,
                                                            markup1: markup1,
                                                            margem2: margem2,
                                                            markup2: markup2,
                                                            margem3: margem3,
                                                            markup3: markup3,
                                                          );

                                                      final colunaInputs = LayoutBuilder(
                                                        builder: (context, cIn) {
                                                          final wIn =
                                                              cIn.maxWidth;
                                                          final custosLadoALado =
                                                              wIn >= 440;
                                                          final precosLadoALado =
                                                              wIn >= 600;

                                                          final campoPrecoCusto = Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              _erpFieldLabel(
                                                                'Preco de custo',
                                                                context,
                                                              ),
                                                              TextFormField(
                                                                controller:
                                                                    _precoCustoController,
                                                                keyboardType:
                                                                    const TextInputType.numberWithOptions(
                                                                      decimal:
                                                                          true,
                                                                    ),
                                                                inputFormatters: [
                                                                  RealInputFormatter(),
                                                                ],
                                                                validator:
                                                                    _validarPrecoCusto,
                                                                decoration:
                                                                    _erpInputDecoration(
                                                                      context,
                                                                      helper:
                                                                          'Nao pode ser negativo',
                                                                    ),
                                                                onChanged: (_) =>
                                                                    setState(
                                                                      () {},
                                                                    ),
                                                              ),
                                                            ],
                                                          );

                                                          final campoCustoMedio = Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              _erpFieldLabel(
                                                                'Custo medio',
                                                                context,
                                                              ),
                                                              Builder(
                                                                builder: (ctx) {
                                                                  final cs =
                                                                      Theme.of(
                                                                        ctx,
                                                                      ).colorScheme;
                                                                  final valor =
                                                                      _custoMedioInteligenteParaExibicao();
                                                                  final deNfe =
                                                                      _custoMedioDerivadoDeHistoricoNfe();
                                                                  return Container(
                                                                    width: double
                                                                        .infinity,
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          14,
                                                                      vertical:
                                                                          14,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: cs
                                                                          .surfaceContainerHighest
                                                                          .withValues(
                                                                            alpha:
                                                                                0.4,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            8,
                                                                          ),
                                                                      border: Border.all(
                                                                        color: cs
                                                                            .outline
                                                                            .withValues(
                                                                              alpha: 0.45,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    child: Column(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        Text(
                                                                          _formatarValorMonetario(
                                                                            valor,
                                                                          ),
                                                                          style: Theme.of(ctx)
                                                                              .textTheme
                                                                              .titleMedium
                                                                              ?.copyWith(
                                                                                fontWeight: FontWeight.w700,
                                                                              ),
                                                                        ),
                                                                        const SizedBox(
                                                                          height:
                                                                              _erpGap8,
                                                                        ),
                                                                        Text(
                                                                          deNfe
                                                                              ? 'Calculado automaticamente pela media ponderada das entradas de NF-e.'
                                                                              : 'Sem entradas de NF-e: acompanha o preco de custo acima.',
                                                                          style: TextStyle(
                                                                            fontSize:
                                                                                11.5,
                                                                            height:
                                                                                1.35,
                                                                            color: cs.onSurface.withValues(
                                                                              alpha: 0.62,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                            ],
                                                          );

                                                          final blocoCustos =
                                                              custosLadoALado
                                                              ? Row(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Expanded(
                                                                      child:
                                                                          campoPrecoCusto,
                                                                    ),
                                                                    const SizedBox(
                                                                      width:
                                                                          _erpGap16,
                                                                    ),
                                                                    Expanded(
                                                                      child:
                                                                          campoCustoMedio,
                                                                    ),
                                                                  ],
                                                                )
                                                              : Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .stretch,
                                                                  children: [
                                                                    campoPrecoCusto,
                                                                    const SizedBox(
                                                                      height:
                                                                          _erpGap16,
                                                                    ),
                                                                    campoCustoMedio,
                                                                  ],
                                                                );

                                                          Widget colPrecoVenda(
                                                            String label,
                                                            TextEditingController
                                                            ctrl,
                                                          ) {
                                                            return Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .stretch,
                                                              children: [
                                                                _erpFieldLabel(
                                                                  label,
                                                                  context,
                                                                ),
                                                                TextFormField(
                                                                  controller:
                                                                      ctrl,
                                                                  readOnly:
                                                                      !_podeEditarPrecoProduto,
                                                                  keyboardType:
                                                                      const TextInputType.numberWithOptions(
                                                                        decimal:
                                                                            true,
                                                                      ),
                                                                  inputFormatters: [
                                                                    RealInputFormatter(),
                                                                  ],
                                                                  validator:
                                                                      _validarPrecoTabela,
                                                                  decoration:
                                                                      _erpInputDecoration(
                                                                        context,
                                                                      ).copyWith(
                                                                        helperText: !_podeEditarPrecoProduto
                                                                            ? 'Sem permissao para editar precos'
                                                                            : null,
                                                                      ),
                                                                  onChanged: (_) =>
                                                                      setState(
                                                                        () {},
                                                                      ),
                                                                ),
                                                              ],
                                                            );
                                                          }

                                                          final blocoPrecosVenda =
                                                              precosLadoALado
                                                              ? Row(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Expanded(
                                                                      child: colPrecoVenda(
                                                                        'A prazo (Preco 1)',
                                                                        _preco1Controller,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width:
                                                                          _erpGap16,
                                                                    ),
                                                                    Expanded(
                                                                      child: colPrecoVenda(
                                                                        'A vista (Preco 2)',
                                                                        _preco2Controller,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width:
                                                                          _erpGap16,
                                                                    ),
                                                                    Expanded(
                                                                      child: colPrecoVenda(
                                                                        'Atacado (Preco 3)',
                                                                        _preco3Controller,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                )
                                                              : Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .stretch,
                                                                  children: [
                                                                    colPrecoVenda(
                                                                      'A prazo (Preco 1)',
                                                                      _preco1Controller,
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          _erpGap16,
                                                                    ),
                                                                    colPrecoVenda(
                                                                      'A vista (Preco 2)',
                                                                      _preco2Controller,
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          _erpGap16,
                                                                    ),
                                                                    colPrecoVenda(
                                                                      'Atacado (Preco 3)',
                                                                      _preco3Controller,
                                                                    ),
                                                                  ],
                                                                );

                                                          return Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets.all(
                                                                      _erpGap16,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: theme
                                                                      .colorScheme
                                                                      .surfaceContainerHighest
                                                                      .withValues(
                                                                        alpha:
                                                                            0.38,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        8,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .outlineVariant
                                                                        .withValues(
                                                                          alpha:
                                                                              0.55,
                                                                        ),
                                                                  ),
                                                                ),
                                                                child:
                                                                    blocoCustos,
                                                              ),
                                                              const SizedBox(
                                                                height:
                                                                    _erpGap16,
                                                              ),
                                                              blocoPrecosVenda,
                                                            ],
                                                          );
                                                        },
                                                      );

                                                      if (wideKpi) {
                                                        return Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Expanded(
                                                              flex: 5,
                                                              child:
                                                                  colunaInputs,
                                                            ),
                                                            const SizedBox(
                                                              width: _erpGap16,
                                                            ),
                                                            Expanded(
                                                              flex: 3,
                                                              child: painelKpi,
                                                            ),
                                                          ],
                                                        );
                                                      }

                                                      return Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          colunaInputs,
                                                          const SizedBox(
                                                            height: _erpGap16,
                                                          ),
                                                          painelKpi,
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                              if (_subAbaCadastroController
                                                      .index ==
                                                  3) ...[
                                              _erpSurfaceCard(
                                                context: context,
                                                title: 'NCM (NFC-e)',
                                                icon: Icons.numbers_outlined,
                                                children: _buildCamposNcmCadastro(
                                                  context,
                                                ),
                                              ),
                                              _erpSurfaceCard(
                                                context: context,
                                                title: 'Dados fiscais (NFC-e)',
                                                icon: Icons.receipt_long_outlined,
                                                children: [
                                                  _erpResponsiveGrid(context, [
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'CEST',
                                                          context,
                                                        ),
                                                        TextFormField(
                                                          controller:
                                                              _cestController,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          maxLength: 9,
                                                          validator:
                                                              _validarCest,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                helper:
                                                                    grupoTributarioProdutoDeString(
                                                                          _grupoTributarioSelecionado,
                                                                        ) ==
                                                                        GrupoTributarioProduto
                                                                            .substituicaoTributaria
                                                                    ? 'Obrigatorio para ST (7 digitos)'
                                                                    : '7 digitos — ST / construcao',
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'Grupo tributario',
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          isDense: true,
                                                          isExpanded: true,
                                                          initialValue:
                                                              _grupoTributarioSelecionado,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                              ),
                                                          items: todosGruposTributariosProduto
                                                              .map(
                                                                (g) =>
                                                                    DropdownMenuItem(
                                                                  value: g.codigo,
                                                                  child: Text(
                                                                    g.rotulo,
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(),
                                                          onChanged: (value) {
                                                            if (value != null) {
                                                              setState(() {
                                                                _grupoTributarioSelecionado =
                                                                    value;
                                                              });
                                                              _formKey
                                                                  .currentState
                                                                  ?.validate();
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'Origem da mercadoria',
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          isDense: true,
                                                          isExpanded: true,
                                                          initialValue:
                                                              _icmsOrigemSelecionado,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                helper:
                                                                    'Vazio = nacional (0)',
                                                              ),
                                                          items: ProdutoFiscalCatalog
                                                              .icmsOrigens
                                                              .map(
                                                                (o) =>
                                                                    DropdownMenuItem(
                                                                  value: o.codigo,
                                                                  child: Text(
                                                                    o.rotulo,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(),
                                                          onChanged: (value) {
                                                            if (value != null) {
                                                              setState(() {
                                                                _icmsOrigemSelecionado =
                                                                    value;
                                                              });
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          FiscalRegimePadrao
                                                              .rotuloIcmsCampo(),
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          isDense: true,
                                                          isExpanded: true,
                                                          initialValue:
                                                              _icmsCstSelecionado,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                helper: FiscalRegimePadrao
                                                                        .ehSimplesNacional()
                                                                    ? 'Automatico: CSOSN pelo grupo (102/400/500)'
                                                                    : 'Automatico: CST 00 / 40 / 60 pelo grupo',
                                                              ),
                                                          items: ProdutoFiscalCatalog
                                                              .icmsOpcoesCadastro(
                                                                ehSimplesNacional:
                                                                    FiscalRegimePadrao
                                                                        .ehSimplesNacional(),
                                                              )
                                                              .map(
                                                                (o) =>
                                                                    DropdownMenuItem(
                                                                  value: o.codigo,
                                                                  child: Text(
                                                                    o.rotulo,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(),
                                                          onChanged: (value) {
                                                            if (value != null) {
                                                              setState(() {
                                                                _icmsCstSelecionado =
                                                                    value;
                                                              });
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'CST PIS/COFINS',
                                                          context,
                                                        ),
                                                        DropdownButtonFormField<
                                                          String
                                                        >(
                                                          isDense: true,
                                                          isExpanded: true,
                                                          initialValue:
                                                              _pisCofinsCstSelecionado,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                helper:
                                                                    'Vazio = ${FiscalRegimePadrao.pisCofinsSituacaoTributariaPadrao()} (padrao loja)',
                                                              ),
                                                          items: ProdutoFiscalCatalog
                                                              .pisCofinsCst
                                                              .map(
                                                                (o) =>
                                                                    DropdownMenuItem(
                                                                  value: o.codigo,
                                                                  child: Text(
                                                                    o.rotulo,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(),
                                                          onChanged: (value) {
                                                            if (value != null) {
                                                              setState(() {
                                                                _pisCofinsCstSelecionado =
                                                                    value;
                                                              });
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        _erpFieldLabel(
                                                          'CFOP na venda (opcional)',
                                                          context,
                                                        ),
                                                        TextFormField(
                                                          controller:
                                                              _cfopVendaController,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          maxLength: 4,
                                                          validator:
                                                              _validarCfopVenda,
                                                          decoration:
                                                              _erpInputDecoration(
                                                                context,
                                                                helper:
                                                                    'Vazio = automatico (ex.: 5102 / 5405 na BA)',
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ]),
                                                  Text(
                                                    'CFOP automatico na BA: Tributado/Isento 5102, ST 5405. '
                                                    'CST ICMS automatico pelo grupo se nao escolher acima.',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                                ],
                                              ),
                                              ],
                                              if (_subAbaCadastroController
                                                      .index ==
                                                  2) ...[
                                              _erpSurfaceCard(
                                                context: context,
                                                title: 'Logistica e descricao',
                                                icon: Icons
                                                    .local_shipping_outlined,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      _erpFieldLabel(
                                                        'Localizacao no deposito',
                                                        context,
                                                      ),
                                                      TextField(
                                                        controller:
                                                            _localizacaoController,
                                                        decoration:
                                                            _erpInputDecoration(
                                                              context,
                                                              hint:
                                                                  'Corredor, prateleira, nivel',
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(
                                                    height: _erpGap16,
                                                  ),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      _erpFieldLabel(
                                                        'Descricao tecnica',
                                                        context,
                                                      ),
                                                      TextField(
                                                        controller:
                                                            _descricaoController,
                                                        maxLines: 4,
                                                        decoration:
                                                            _erpInputDecoration(
                                                              context,
                                                              helper:
                                                                  'Beneficios, aplicacao e diferenciais para o vendedor',
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              _erpSurfaceCard(
                                                context: context,
                                                title:
                                                    'Estoque e disponibilidade',
                                                icon: Icons.warehouse_outlined,
                                                children: [
                                                  Wrap(
                                                    spacing: _erpGap16,
                                                    runSpacing: _erpGap16,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .start,
                                                    children: [
                                                      SizedBox(
                                                        width: _wQtdInteira,
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            _erpFieldLabel(
                                                              'Quantidade em estoque',
                                                              context,
                                                            ),
                                                            TextField(
                                                              controller:
                                                                  _estoqueController,
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              onChanged: (_) =>
                                                                  setState(() {}),
                                                              decoration:
                                                                  _erpInputDecoration(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: _wQtdInteira,
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            _erpFieldLabel(
                                                              'Quantidade minima',
                                                              context,
                                                            ),
                                                            TextField(
                                                              controller:
                                                                  _quantidadeMinimaController,
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              decoration:
                                                                  _erpInputDecoration(
                                                                    context,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: _wQtdInteira,
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            _erpFieldLabel(
                                                              'Lead time (dias)',
                                                              context,
                                                            ),
                                                            TextField(
                                                              controller:
                                                                  _leadTimeDiasController,
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              onChanged: (_) =>
                                                                  setState(() {}),
                                                              decoration:
                                                                  _erpInputDecoration(
                                                                    context,
                                                                    hint:
                                                                        '7',
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: _wQtdInteira,
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            _erpFieldLabel(
                                                              'Estoque seguranca',
                                                              context,
                                                            ),
                                                            TextField(
                                                              controller:
                                                                  _estoqueSegurancaController,
                                                              keyboardType:
                                                                  TextInputType
                                                                      .number,
                                                              onChanged: (_) =>
                                                                  setState(() {}),
                                                              decoration:
                                                                  _erpInputDecoration(
                                                                    context,
                                                                    hint:
                                                                        '0',
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(
                                                    height: _erpGap8,
                                                  ),
                                                  _buildPainelPontoPedido(
                                                    context,
                                                  ),
                                                  const SizedBox(
                                                    height: _erpGap16,
                                                  ),
                                                  SwitchListTile(
                                                    dense: true,
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    title: const Text(
                                                      'Produto ativo na venda',
                                                    ),
                                                    subtitle: const Text(
                                                      'Inativo permanece no cadastro e no historico, mas nao aparece no PDV.',
                                                    ),
                                                    value: _produtoAtivo,
                                                    onChanged: (v) => setState(
                                                      () => _produtoAtivo = v,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (_produtoEmEdicaoId !=
                                                  null) ...[
                                                const SizedBox(
                                                  height: _erpGap16,
                                                ),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: OutlinedButton.icon(
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Theme.of(
                                                        context,
                                                      ).colorScheme.error,
                                                      side: BorderSide(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                      ),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 8,
                                                          ),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                    onPressed:
                                                        _excluirProdutoEmEdicao,
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      size: 18,
                                                    ),
                                                    label: const Text(
                                                      'Excluir produto',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_status.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        _erpGap24,
                                        _erpGap8,
                                        _erpGap24,
                                        _erpGap8,
                                      ),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: _erpGap16,
                                          vertical: _erpGap16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusEhErro
                                              ? semantic?.errorBg ??
                                                    const Color(0xFFFDECEC)
                                              : semantic?.successBg ??
                                                    const Color(0xFFEAF8EF),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: _statusEhErro
                                                ? semantic?.errorBorder ??
                                                      const Color(0xFFF1A3A3)
                                                : semantic?.successBorder ??
                                                      const Color(0xFF8FD1A8),
                                          ),
                                        ),
                                        child: Text(
                                          _status,
                                          style: TextStyle(
                                            color: _statusEhErro
                                                ? semantic?.errorFg ??
                                                      const Color(0xFF9B1C1C)
                                                : semantic?.successFg ??
                                                      const Color(0xFF166534),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface,
                                      border: Border(
                                        top: BorderSide(
                                          color: theme
                                              .colorScheme
                                              .outlineVariant
                                              .withValues(alpha: 0.42),
                                          width: 1,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.07,
                                          ),
                                          offset: const Offset(0, -3),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      _erpGap24,
                                      _erpGap16,
                                      _erpGap24,
                                      _erpGap16,
                                    ),
                                    child: SafeArea(
                                      top: false,
                                      maintainBottomViewPadding: true,
                                      child: _erpRodapeAcaoCadastroProduto(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AbasHistoricoProdutoWidget(
                              key: ValueKey(_historicoVersao),
                              produtoRepository: widget.produtoRepository,
                              produtoId: _produtoEmEdicaoId,
                            ),
                            ExtratoMovimentoEstoquePanel(
                              key: ValueKey('mov_${_historicoVersao}_$_produtoEmEdicaoId'),
                              produtoRepository: widget.produtoRepository,
                              produtoId: _produtoEmEdicaoId,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class RealInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final apenasNumeros = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (apenasNumeros.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final valorCentavos = int.parse(apenasNumeros);
    final valor = valorCentavos / 100;
    final formatador = NumberFormat('#,##0.00', 'pt_BR');
    final textoFormatado = formatador.format(valor);

    return TextEditingValue(
      text: textoFormatado,
      selection: TextSelection.collapsed(offset: textoFormatado.length),
    );
  }
}
