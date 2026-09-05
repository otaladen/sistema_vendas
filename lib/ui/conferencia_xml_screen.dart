import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/api/nfe_entrada_api_repository.dart';
import '../data/api/produto_api_repository.dart';
import '../data/app_config_repository.dart';
import '../data/nfe_entrada_repository.dart';
import '../domain/conferencia_nfe_opcoes.dart';
import '../domain/nfe_entrada_conversao_util.dart';
import '../domain/produto_embalagem.dart';
import '../model/item_nota_temporario.dart';
import '../model/produto.dart';
import 'layout/app_layout.dart';
import 'fiscal/widgets/conferencia_nfe_cabecalho.dart';
import 'fiscal/widgets/conferencia_nfe_financeiro_painel.dart';
import 'fiscal/widgets/conferencia_nfe_opcoes_painel.dart';
import 'fiscal/widgets/conferencia_nfe_rodape.dart';
import 'fiscal/widgets/conferencia_nfe_tabela_itens.dart';
import 'produtos/produto_pesquisa_dialog.dart';
import 'widgets/lan_api_feedback.dart';
import 'widgets/operacao_feedback.dart';
import 'theme/app_semantic_helper.dart';

enum _ConferenciaNfeFiltro { todos, vinculados, novos, atencao }

enum _ConferenciaNfeModoExibicao { cards, tabela }

/// Conferencia de itens da NF-e antes de gravar estoque e vinculos.
class ConferenciaXmlScreen extends StatefulWidget {
  const ConferenciaXmlScreen({
    super.key,
    required this.nfe,
    required this.nfeRepository,
    required this.produtoRepository,
    this.appConfigRepository,
    this.xmlOriginal = '',
    this.sugestoesIniciais,
  });

  final NfeXmlParseResult nfe;
  final dynamic nfeRepository;
  final dynamic produtoRepository;
  final AppConfigRepository? appConfigRepository;
  final String xmlOriginal;

  /// Quando ja veio do `POST /api/nfe/ler-xml` (evita segundo parse no terminal).
  final List<SugestaoLinhaConferencia>? sugestoesIniciais;

  @override
  State<ConferenciaXmlScreen> createState() => _ConferenciaXmlScreenState();
}

class _LinhaEdicao {
  _LinhaEdicao({
    required this.sugestao,
    required this.fatorCtrl,
    required this.unidade,
    required this.embalagemMultiplica,
    this.confirmarConversaoEmbalagem = false,
    required this.loteCtrl,
    this.dataValidade,
  });

  final SugestaoLinhaConferencia sugestao;
  final TextEditingController fatorCtrl;
  final TextEditingController loteCtrl;
  String unidade;
  bool embalagemMultiplica;
  bool confirmarConversaoEmbalagem;
  DateTime? dataValidade;

  /// Quando preenchido, substitui a sugestao automatica (ex.: vincular item "novo" a um cadastro).
  int? vinculoManualProdutoId;
  String? vinculoManualProdutoNome;

  /// Usuario rejeitou o casamento automatico (EAN / fornecedor); item fica como novo cadastro.
  bool vinculoAutomaticoIgnorado = false;
  String? erroValidacao;

  int? produtoDestinoId() {
    if (vinculoManualProdutoId != null) {
      return vinculoManualProdutoId;
    }
    if (vinculoAutomaticoIgnorado) {
      return null;
    }
    if (!sugestao.produtoNovo) {
      return sugestao.produtoExistenteId;
    }
    return null;
  }

  bool get temVinculoAtivo => produtoDestinoId() != null;
}

class _ConferenciaXmlScreenState extends State<ConferenciaXmlScreen> {
  List<_LinhaEdicao> _linhas = [];
  String? _initError;
  String? _erroConfirmacaoGlobal;
  bool _confirmando = false;
  double _margemMinimaPadrao = 20;
  _ConferenciaNfeFiltro _filtro = _ConferenciaNfeFiltro.todos;
  _ConferenciaNfeModoExibicao _modoExibicao = _ConferenciaNfeModoExibicao.cards;
  ConferenciaNfeOpcoes _opcoes = const ConferenciaNfeOpcoes();
  final Set<int> _custoExpandido = {};
  bool _rebuildAgendado = false;

  void _agendarRebuild() {
    if (!mounted || _rebuildAgendado) return;
    _rebuildAgendado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildAgendado = false;
      if (mounted) setState(() {});
    });
  }

  void _atualizarUi({VoidCallback? aoAtualizar}) {
    if (aoAtualizar != null) {
      aoAtualizar();
    } else {
      _agendarRebuild();
    }
  }

  static final NumberFormat _nfQtd = NumberFormat('#,##0.###', 'pt_BR');
  static final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');

  /// Mesmos gaps usados em telas ERP (ex.: produtos_page).
  static const double _erpGap8 = 8;
  static const double _erpGap16 = 16;

  /// Largura minima para dispor "Custo atual" e bloco XML em duas colunas.
  static const double _custoPainelBreakpoint2Col = 640;

  @override
  void initState() {
    super.initState();
    _iniciarSugestoes();
    _carregarMargemMinima();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.isDesktopLayout) {
        setState(() => _modoExibicao = _ConferenciaNfeModoExibicao.tabela);
      }
    });
  }

  Future<void> _iniciarSugestoes() async {
    try {
      List<SugestaoLinhaConferencia> sugestoes =
          widget.sugestoesIniciais ?? const [];
      if (sugestoes.isEmpty) {
        final repo = widget.nfeRepository;
        final xml = widget.xmlOriginal.trim();
        if (repo is NfeEntradaApiRepository && xml.isNotEmpty) {
          sugestoes = await repo.prepararSugestoesConferenciaRemoto(xml);
        } else {
          sugestoes = repo.prepararSugestoesConferencia(widget.nfe)
              as List<SugestaoLinhaConferencia>;
        }
      }
      await _hidratarProdutosVinculados(sugestoes);
      if (!mounted) return;
      setState(() {
        _linhas = sugestoes.map((s) {
          final c = TextEditingController(text: _formatarFator(s.fatorInicial));
          final lote = TextEditingController(text: s.item.numeroLote);
          return _LinhaEdicao(
            sugestao: s,
            fatorCtrl: c,
            unidade: s.unidadeInternaInicial,
            embalagemMultiplica: s.embalagemMultiplicaInicial,
            confirmarConversaoEmbalagem: s.produtoNovo,
            loteCtrl: lote,
            dataValidade: s.item.dataValidade,
          );
        }).toList();
        _initError = null;
      });
    } catch (e, st) {
      debugPrint('ConferenciaXml init: $e\n$st');
      if (!mounted) return;
      setState(() {
        _initError = e is FormatException || e is StateError
            ? e.toString()
            : 'Nao foi possivel montar a conferencia da nota.';
      });
    }
  }

  /// Terminal leve: IDs vindos do PC1 precisam estar no cache local.
  Future<void> _hidratarProdutosVinculados(
    List<SugestaoLinhaConferencia> sugestoes,
  ) async {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoApiRepository) return;
    final ids = <int>{
      for (final s in sugestoes)
        if ((s.produtoExistenteId ?? 0) > 0) s.produtoExistenteId!,
    };
    if (ids.isEmpty) return;
    final faltando = ids.where((id) => repo.obterPorId(id) == null).toList();
    if (faltando.isEmpty) return;
    try {
      await repo.atualizarEstoquePorIds(faltando);
    } catch (e) {
      debugPrint('ConferenciaXml hidratar produtos: $e');
    }
  }

  void _alterarOpcoes(ConferenciaNfeOpcoes opcoes) {
    setState(() {
      _opcoes = opcoes.atualizarPrecoCusto
          ? opcoes
          : opcoes.copyWith(atualizarPrecosVenda: false);
    });
  }

  Future<void> _carregarMargemMinima() async {
    final repo = widget.appConfigRepository;
    if (repo == null) return;
    final config = await repo.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _margemMinimaPadrao = config.margemMinimaPercentualPadrao.clamp(0, 99);
    });
  }

  static double _margemSobreVenda(double precoVenda, double custo) {
    if (precoVenda <= 0) return 0;
    return ((precoVenda - custo) / precoVenda) * 100;
  }

  static double? _precoVendaSugerido(double custo, double margemMinPercent) {
    if (custo <= 0 || margemMinPercent <= 0 || margemMinPercent >= 99.9) {
      return null;
    }
    return custo / (1 - margemMinPercent / 100);
  }

  Future<void> _aplicarCustoXmlNoCadastro(_LinhaEdicao linha) async {
    final id = linha.produtoDestinoId();
    final custoXml = _custoUnitarioXmlConvertidoInterno(linha);
    if (id == null || custoXml == null) return;
    final p = await _obterProdutoDestino(id);
    if (p == null) return;
    p.precoCusto = custoXml;
    try {
      final repo = widget.produtoRepository;
      if (repo is ProdutoApiRepository) {
        await repo.salvarRemoto(p);
      } else {
        repo.salvar(p);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel atualizar custo: $e')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Custo atualizado para ${_formatarReais(custoXml)} / ${linha.unidade.trim()}.',
        ),
      ),
    );
  }

  Future<void> _aplicarPrecoSugeridoMargem(
    _LinhaEdicao linha,
    double precoSugerido,
  ) async {
    final id = linha.produtoDestinoId();
    if (id == null) return;
    final p = await _obterProdutoDestino(id);
    if (p == null) return;
    p.precoVenda = precoSugerido;
    try {
      final repo = widget.produtoRepository;
      if (repo is ProdutoApiRepository) {
        await repo.salvarRemoto(p);
      } else {
        repo.salvar(p);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel atualizar preco: $e')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Preco de venda ajustado para ${_formatarReais(precoSugerido)}.',
        ),
      ),
    );
  }

  static String _formatarFator(double v) {
    if (v == v.roundToDouble()) {
      return v.round().toString();
    }
    return v
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static double _lerFator(String texto) {
    final v = double.tryParse(texto.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite) {
      return 0;
    }
    return v;
  }

  Produto? _produtoDestinoLinha(_LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) return null;
    return widget.produtoRepository.obterPorId(id);
  }

  /// Campos de lote so quando o produto destino controla validade, ou o XML ja trouxe rastro.
  bool _linhaMostraCamposLote(_LinhaEdicao linha) {
    final p = _produtoDestinoLinha(linha);
    if (p != null && p.controlaLoteValidade) return true;
    final item = linha.sugestao.item;
    return item.numeroLote.trim().isNotEmpty || item.dataValidade != null;
  }

  Future<Produto?> _obterProdutoDestino(int id) async {
    final local = widget.produtoRepository.obterPorId(id);
    if (local != null) return local;
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) {
      try {
        return await repo.obterPorIdRemoto(id);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  ({int armazenado, double unidadeVenda}) _entradaNotaCalculada(
    _LinhaEdicao linha,
  ) {
    final f = _lerFator(linha.fatorCtrl.text);
    final q = linha.sugestao.item.quantidadeComercial;
    final multiplica = linha.embalagemMultiplica;
    final produto = _produtoDestinoLinha(linha);
    final unidadeEstoque = produto != null
        ? NfeEntradaConversaoUtil.unidadeEstoqueProdutoExistente(
            produto: produto,
            unidadeConferencia: linha.unidade,
          )
        : linha.unidade;
    final unidadeVenda = ProdutoEmbalagem.quantidadeNotaParaUnidadeVenda(
      quantidadeComercial: q,
      fator: f,
      embalagemMultiplica: multiplica,
    );
    final armazenado = ProdutoEmbalagem.quantidadeNotaParaEstoque(
      quantidadeComercial: q,
      fator: f,
      embalagemMultiplica: multiplica,
      produto: produto,
      unidadeComercial: linha.sugestao.item.unidadeComercial,
      unidadeInterna: unidadeEstoque,
    );
    return (armazenado: armazenado, unidadeVenda: unidadeVenda);
  }

  double _quantidadeEntrada(_LinhaEdicao linha) {
    return _entradaNotaCalculada(linha).unidadeVenda;
  }

  double? _estoqueTotalAposConfirmar(_LinhaEdicao linha) {
    final produto = _produtoDestinoLinha(linha);
    if (produto == null) return null;
    return produto.estoqueExibicao + _quantidadeEntrada(linha);
  }

  String _rotuloEntradaEstoque(_LinhaEdicao linha) {
    final calc = _entradaNotaCalculada(linha);
    final produto = _produtoDestinoLinha(linha);
    return ProdutoEmbalagem.formatarQuantidadeNotaEstoque(
      estoqueArmazenado: calc.armazenado,
      quantidadeUnidadeVenda: calc.unidadeVenda,
      produto: produto,
      unidadeInterna: linha.unidade,
      comUnidade: true,
    );
  }
  double? _custoUnitarioXmlConvertidoInterno(_LinhaEdicao linha) {
    final f = _lerFator(linha.fatorCtrl.text);
    if (f <= 0) return null;
    return NfeEntradaConversaoUtil.custoUnitarioInterno(
      item: linha.sugestao.item,
      fator: f,
      embalagemMultiplica: linha.embalagemMultiplica,
    );
  }

  String _unidadeEstoqueLinha(_LinhaEdicao linha) {
    final produto = _produtoDestinoLinha(linha);
    if (produto != null) {
      return NfeEntradaConversaoUtil.unidadeEstoqueProdutoExistente(
        produto: produto,
        unidadeConferencia: linha.unidade,
      );
    }
    return linha.unidade;
  }

  bool _linhaUnidadeCadastroTravada(_LinhaEdicao linha) {
    final produto = _produtoDestinoLinha(linha);
    if (produto == null) return false;
    return produto.unidade.trim().isNotEmpty;
  }

  bool _linhaOfereceConfirmarConversaoEmbalagem(_LinhaEdicao linha) {
    final produto = _produtoDestinoLinha(linha);
    if (produto == null) return false;
    final f = _lerFator(linha.fatorCtrl.text);
    return NfeEntradaConversaoUtil.precisaConfirmarConversaoEmbalagem(
      item: linha.sugestao.item,
      produto: produto,
      fator: f,
    );
  }

  void _aplicarPadraoNovoProduto(_LinhaEdicao linha) {
    if (linha.sugestao.produtoNovo && !linha.vinculoAutomaticoIgnorado) {
      linha.unidade = linha.sugestao.unidadeInternaInicial;
      linha.fatorCtrl.text = _formatarFator(linha.sugestao.fatorInicial);
      linha.embalagemMultiplica = true;
      linha.confirmarConversaoEmbalagem = true;
      return;
    }
    linha.unidade = 'UN';
    linha.fatorCtrl.text = _formatarFator(1);
    linha.embalagemMultiplica = true;
    linha.confirmarConversaoEmbalagem = true;
  }

  void _restaurarSugestaoAutomatica(_LinhaEdicao linha) {
    linha.unidade = linha.sugestao.unidadeInternaInicial;
    linha.fatorCtrl.text = _formatarFator(linha.sugestao.fatorInicial);
    linha.embalagemMultiplica = linha.sugestao.embalagemMultiplicaInicial;
    linha.confirmarConversaoEmbalagem = false;
  }

  void _desfazerVinculoLinha(_LinhaEdicao linha) {
    if (linha.vinculoManualProdutoId != null) {
      linha.vinculoManualProdutoId = null;
      linha.vinculoManualProdutoNome = null;
      if (linha.vinculoAutomaticoIgnorado || linha.sugestao.produtoNovo) {
        _aplicarPadraoNovoProduto(linha);
      } else {
        _restaurarSugestaoAutomatica(linha);
      }
      return;
    }
    if (!linha.sugestao.produtoNovo && linha.sugestao.produtoExistenteId != null) {
      linha.vinculoAutomaticoIgnorado = true;
      _aplicarPadraoNovoProduto(linha);
    }
  }


  static String _formatarReais(double v) => 'R\$ ${_nfMoeda.format(v)}';

  bool _linhaEhNovo(_LinhaEdicao linha) => linha.produtoDestinoId() == null;

  bool _linhaEhVinculada(_LinhaEdicao linha) => linha.produtoDestinoId() != null;

  bool _linhaFatorValido(_LinhaEdicao linha) =>
      _lerFator(linha.fatorCtrl.text) > 0;

  bool _linhaMargemAbaixoMinimo(_LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) return false;
    final p = widget.produtoRepository.obterPorId(id);
    final custoXml = _custoUnitarioXmlConvertidoInterno(linha);
    if (p == null || custoXml == null || p.precoVenda <= 1e-9) return false;
    final margemApos = _margemSobreVenda(p.precoVenda, custoXml);
    return margemApos + 0.05 < _margemMinimaPadrao;
  }

  bool _linhaCustoAumentou(_LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) return false;
    final p = widget.produtoRepository.obterPorId(id);
    final custoXml = _custoUnitarioXmlConvertidoInterno(linha);
    if (p == null || custoXml == null || p.precoCusto <= 1e-9) return false;
    return (custoXml - p.precoCusto) / p.precoCusto > 0.05;
  }

  bool _linhaPrecisaAtencao(_LinhaEdicao linha) =>
      _linhaEhNovo(linha) ||
      !_linhaFatorValido(linha) ||
      _linhaMargemAbaixoMinimo(linha) ||
      _linhaCustoAumentou(linha);

  bool _linhaPronta(_LinhaEdicao linha) =>
      _linhaFatorValido(linha) &&
      NfeEntradaRepository.unidadesInternasValidas.contains(linha.unidade);

  int get _countVinculados =>
      _linhas.where(_linhaEhVinculada).length;

  int get _countNovos => _linhas.where(_linhaEhNovo).length;

  int get _countAtencao => _linhas.where(_linhaPrecisaAtencao).length;

  int get _countProntos => _linhas.where(_linhaPronta).length;

  List<int> get _indicesFiltrados {
    final out = <int>[];
    for (var i = 0; i < _linhas.length; i++) {
      final linha = _linhas[i];
      final ok = switch (_filtro) {
        _ConferenciaNfeFiltro.todos => true,
        _ConferenciaNfeFiltro.vinculados => _linhaEhVinculada(linha),
        _ConferenciaNfeFiltro.novos => _linhaEhNovo(linha),
        _ConferenciaNfeFiltro.atencao => _linhaPrecisaAtencao(linha),
      };
      if (ok) out.add(i);
    }
    return out;
  }

  Widget _buildPassoConferencia(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget passo(String n, String rotulo, bool ativo) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: ativo ? cs.primary : cs.surfaceContainerHighest,
            child: Text(
              n,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ativo ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            rotulo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
              color: ativo ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          passo('1', 'XML lido', false),
          Icon(Icons.chevron_right, size: 18, color: cs.outline),
          passo('2', 'Conferir itens', true),
          Icon(Icons.chevron_right, size: 18, color: cs.outline),
          passo('3', 'Lançar estoque', false),
        ],
      ),
    );
  }

  Widget _buildFiltros(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ChoiceChip chip(
      _ConferenciaNfeFiltro f,
      String label,
      int? count,
    ) {
      final sel = _filtro == f;
      return ChoiceChip(
        label: Text(count == null ? label : '$label ($count)'),
        selected: sel,
        onSelected: (_) => setState(() => _filtro = f),
        selectedColor: cs.primaryContainer,
        labelStyle: TextStyle(
          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12.5,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            'Filtrar:',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          chip(_ConferenciaNfeFiltro.todos, 'Todos', _linhas.length),
          chip(_ConferenciaNfeFiltro.vinculados, 'Vinculados', _countVinculados),
          chip(_ConferenciaNfeFiltro.novos, 'Novos', _countNovos),
          if (_countAtencao > 0)
            chip(_ConferenciaNfeFiltro.atencao, 'Atenção', _countAtencao),
        ],
      ),
    );
  }

  Widget _buildMetaCelula(
    BuildContext context, {
    required String rotulo,
    required String valor,
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              Text(
                rotulo,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  /// Painel custo cadastro vs XML; so quando ja existe produto destino.
  Widget _buildComparativoCustoPainel(BuildContext context, _LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) {
      return const SizedBox.shrink();
    }
    final p = widget.produtoRepository.obterPorId(id);
    if (p == null) {
      return const SizedBox.shrink();
    }
    final custoXml = _custoUnitarioXmlConvertidoInterno(linha);
    final atual = p.precoCusto;
    final uInt = linha.unidade.trim();

    if (custoXml == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Informe uma qtd. na embalagem valida para comparar o custo unitario do XML com o cadastro.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final textoCustoCadastro = Text(
      'Custo cadastro (precoCusto): ${_formatarReais(atual)} / $uInt',
      style: Theme.of(context).textTheme.bodySmall,
      softWrap: true,
    );

    final bm = Theme.of(context).textTheme.bodyMedium;
    final xmlPrecoRich = Text.rich(
      TextSpan(
        style: bm?.copyWith(fontWeight: FontWeight.w700),
        children: [
          const TextSpan(text: 'XML convertido: '),
          TextSpan(
            text: _formatarReais(custoXml),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: ' / $uInt',
            style: bm?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    Widget? indicadorVariacao;
    const eps = 1e-9;
    if (atual > eps) {
      final pct = (custoXml - atual) / atual * 100;
      if (pct > 5 + 1e-9) {
        final pctTxt =
            pct >= 10 ? pct.round().toString() : pct.toStringAsFixed(1);
        indicadorVariacao = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '⚠️',
              style: TextStyle(
                color: semantic.errorFg,
                fontSize: 18,
                height: 1,
              ),
            ),
            Text(
              '+$pctTxt% de aumento',
              style: TextStyle(
                color: semantic.errorFg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              softWrap: true,
            ),
          ],
        );
      } else if (custoXml < atual - eps) {
        final pctAbs = ((atual - custoXml) / atual * 100).abs();
        final pctTxt = pctAbs >= 10
            ? pctAbs.round().toString()
            : pctAbs.toStringAsFixed(1);
        indicadorVariacao = Text(
          '$pctTxt% menor que o cadastro',
          style: TextStyle(
            color: semantic.successFg,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          softWrap: true,
        );
      }
    } else if (custoXml > eps) {
      indicadorVariacao = Text(
        'Custo cadastro era zero; apos confirmar sera ${_formatarReais(custoXml)} / $uInt',
        style: TextStyle(
          color: cs.tertiary,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        softWrap: true,
      );
    }

    Widget blocoXmlEIndicador(double larguraMaxBloco) {
      return Wrap(
        spacing: _erpGap8,
        runSpacing: _erpGap8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: larguraMaxBloco),
            child: xmlPrecoRich,
          ),
          if (indicadorVariacao != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: larguraMaxBloco),
              child: indicadorVariacao,
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final maxW = c.maxWidth;
                  final titulo = Text(
                    'Custo vs cadastro',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                  );

                  if (maxW >= _custoPainelBreakpoint2Col) {
                    final colW = (maxW - _erpGap16) / 2;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        titulo,
                        const SizedBox(height: _erpGap8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: colW,
                              child: textoCustoCadastro,
                            ),
                            const SizedBox(width: _erpGap16),
                            SizedBox(
                              width: colW,
                              child: blocoXmlEIndicador(colW),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titulo,
                      const SizedBox(height: _erpGap8),
                      textoCustoCadastro,
                      const SizedBox(height: _erpGap8),
                      blocoXmlEIndicador(maxW),
                    ],
                  );
                },
              ),
              _buildMargemCustoSection(context, p, custoXml, linha),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMargemCustoSection(
    BuildContext context,
    Produto produto,
    double custoXml,
    _LinhaEdicao linha,
  ) {
    final cs = Theme.of(context).colorScheme;
    final precoVenda = produto.precoVenda;
    if (precoVenda <= 1e-9) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'Cadastre preco de venda para avaliar margem. '
          'O custo do XML sera aplicado ao confirmar a entrada.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
        ),
      );
    }

    final margemAtual = _margemSobreVenda(precoVenda, produto.precoCusto);
    final margemApos = _margemSobreVenda(precoVenda, custoXml);
    final abaixoMin = margemApos + 0.05 < _margemMinimaPadrao;
    final sugerido = _precoVendaSugerido(custoXml, _margemMinimaPadrao);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 20),
          Text(
            'Margem sobre venda (${_formatarReais(precoVenda)})',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Atual: ${margemAtual.toStringAsFixed(1)}% · '
            'Apos XML: ${margemApos.toStringAsFixed(1)}% '
            '(min. ${_margemMinimaPadrao.toStringAsFixed(0)}%)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (abaixoMin) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Margem apos o custo do XML ficaria abaixo do minimo configurado.',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            if (sugerido != null) ...[
              const SizedBox(height: 6),
              Text(
                'Preco sugerido para ${_margemMinimaPadrao.toStringAsFixed(0)}%: '
                '${_formatarReais(sugerido)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
          const SizedBox(height: 4),
          Text(
            _opcoes.atualizarPrecoCusto
                ? 'Ao confirmar, o preco de custo sera atualizado conforme as opcoes. '
                  'Use o botao abaixo para aplicar antes, se preferir.'
                : 'O preco de custo do cadastro nao sera alterado ao confirmar. '
                  'O custo medio so muda se "Lancar estoque" estiver marcado.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => _aplicarCustoXmlNoCadastro(linha),
                icon: const Icon(Icons.price_change_outlined, size: 18),
                label: const Text('Aplicar custo do XML'),
              ),
              if (abaixoMin && sugerido != null)
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _aplicarPrecoSugeridoMargem(linha, sugerido),
                  icon: const Icon(Icons.trending_up, size: 18),
                  label: const Text('Aplicar preco sugerido'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _mensagemFatorConversao(_LinhaEdicao linha) {
    final item = linha.sugestao.item;
    final uCom = item.unidadeComercial.trim();
    final uInt = _unidadeEstoqueLinha(linha).trim();
    final q = item.quantidadeComercial;
    final f = _lerFator(linha.fatorCtrl.text);
    final uComLabel = uCom.isEmpty ? '(unid. na nota)' : uCom;
    final uIntLabel = uInt.isEmpty ? '?' : uInt;
    if (f <= 0) {
      return 'Informe a qtd. na embalagem maior que zero. Ex.: se a nota vem em CX '
          'e voce controla em UN, digite quantas UN existem em 1 CX.';
    }
    if (!q.isFinite || q < 0) {
      return 'Quantidade da nota invalida; confira o XML.';
    }
    final multiplica = linha.embalagemMultiplica;
    final calc = _entradaNotaCalculada(linha);
    final produto = _produtoDestinoLinha(linha);
    final qtdTxt = ProdutoEmbalagem.formatarQuantidadeNotaEstoque(
      estoqueArmazenado: calc.armazenado,
      quantidadeUnidadeVenda: calc.unidadeVenda,
      produto: produto,
      unidadeInterna: uIntLabel,
      comUnidade: true,
    );
    final qFmt = _nfQtd.format(q);
    final fFmt = _formatarFator(f);
    final op = multiplica ? '×' : '÷';
    return '$qFmt $uComLabel $op $fFmt = $qtdTxt';
  }

  Widget _buildToggleEmbalagemModo(
    _LinhaEdicao linha, {
    VoidCallback? aoAtualizar,
    bool compacto = false,
  }) {
    return SegmentedButton<bool>(
      style: SegmentedButton.styleFrom(
        visualDensity:
            compacto ? VisualDensity.compact : VisualDensity.standard,
        padding: compacto
            ? const EdgeInsets.symmetric(horizontal: 2)
            : const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: compacto ? const Size(28, 32) : null,
      ),
      segments: const [
        ButtonSegment(
          value: true,
          label: Text('×', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        ButtonSegment(
          value: false,
          label: Text('÷', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
      selected: {linha.embalagemMultiplica},
      onSelectionChanged: (s) {
        if (s.isEmpty) return;
        linha.embalagemMultiplica = s.first;
        _atualizarUi(aoAtualizar: aoAtualizar);
      },
    );
  }

  ({Color bg, Color fg, String label}) _coresStatusChip(
    BuildContext context,
    _LinhaEdicao linha,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    if (linha.produtoDestinoId() == null) {
      final desfeito = linha.vinculoAutomaticoIgnorado;
      return (
        bg: semantic.warningBg,
        fg: semantic.warningFg,
        label: desfeito
            ? 'Novo produto (vinculo automatico desfeito)'
            : 'Novo produto (sera cadastrado)',
      );
    }
    final manual = linha.vinculoManualProdutoId != null;
    final tipo = linha.sugestao.tipoMatch;
    if (manual &&
        (tipo == ConferenciaNfeMatchTipo.produtoNovo ||
            linha.vinculoAutomaticoIgnorado)) {
      return (
        bg: scheme.secondaryContainer,
        fg: scheme.onSecondaryContainer,
        label: 'Vinculo manual - produto cadastrado',
      );
    }
    if (manual) {
      return (
        bg: scheme.secondaryContainer,
        fg: scheme.onSecondaryContainer,
        label: 'Vinculo manual - produto trocado',
      );
    }
    switch (tipo) {
      case ConferenciaNfeMatchTipo.vinculadoPorEan:
        return (
          bg: semantic.successBg,
          fg: semantic.successFg,
          label: 'Produto vinculado por EAN',
        );
      case ConferenciaNfeMatchTipo.vinculoFornecedor:
        return (
          bg: semantic.infoBg,
          fg: semantic.infoFg,
          label: 'Vinculo por fornecedor encontrado',
        );
      case ConferenciaNfeMatchTipo.produtoNovo:
        return (
          bg: semantic.warningBg,
          fg: semantic.warningFg,
          label: 'Novo produto (sera cadastrado)',
        );
    }
  }

  Widget _buildStatusChip(BuildContext context, _LinhaEdicao linha) {
    final s = _coresStatusChip(context, linha);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.fg.withValues(alpha: 0.38)),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          color: s.fg,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildModoExibicaoToggle(BuildContext context) {
    if (!context.isDesktopLayout) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<_ConferenciaNfeModoExibicao>(
          segments: const [
            ButtonSegment(
              value: _ConferenciaNfeModoExibicao.tabela,
              icon: Icon(Icons.table_rows_outlined, size: 18),
              label: Text('Tabela'),
            ),
            ButtonSegment(
              value: _ConferenciaNfeModoExibicao.cards,
              icon: Icon(Icons.view_agenda_outlined, size: 18),
              label: Text('Cards'),
            ),
          ],
          selected: {_modoExibicao},
          onSelectionChanged: (s) =>
              setState(() => _modoExibicao = s.first),
        ),
      ),
    );
  }

  List<ConferenciaNfeTabelaLinha> _montarLinhasTabela(BuildContext context) {
    return [
      for (final index in _indicesFiltrados)
        _linhaParaTabela(context, index),
    ];
  }

  ConferenciaNfeTabelaLinha _linhaParaTabela(BuildContext context, int index) {
    final linha = _linhas[index];
    final item = linha.sugestao.item;
    final status = _coresStatusChip(context, linha);
    return ConferenciaNfeTabelaLinha(
      indice: index,
      numeroItem: item.numeroItem,
      descricao: item.descricao,
      unidadeXml: item.unidadeComercial.isEmpty ? '—' : item.unidadeComercial,
      quantidadeXml: item.quantidadeComercial,
      valorUnitarioXml: item.valorUnitarioComercial,
      destinoRotulo: _rotuloProdutoVinculado(linha),
      statusRotulo: status.label,
      statusCor: status.bg,
      statusCorTexto: status.fg,
      entradaRotulo: _rotuloEntradaEstoque(linha),
      unidadeInterna: _unidadeEstoqueLinha(linha),
      unidadeTravada: _linhaUnidadeCadastroTravada(linha),
      fatorController: linha.fatorCtrl,
      embalagemMultiplica: linha.embalagemMultiplica,
      erroFator: linha.erroValidacao,
      precisaAtencao: _linhaPrecisaAtencao(linha),
      temDestino: linha.produtoDestinoId() != null,
      temVinculoAtivo: linha.temVinculoAtivo,
    );
  }

  Future<void> _abrirDetalheItem(int index) async {
    if (!mounted) return;
    // Adia a navegacao para fora do evento de clique do mouse (evita mouse_tracker no Windows).
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ConferenciaItemDetalhePage(
          screenState: this,
          index: index,
        ),
      ),
    );
    _agendarRebuild();
  }

  Widget _buildListaItens(BuildContext context) {
    if (_indicesFiltrados.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Nenhum item neste filtro.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    if (_modoExibicao == _ConferenciaNfeModoExibicao.tabela &&
        context.isDesktopLayout) {
      return ConferenciaNfeTabelaItens(
        linhas: _montarLinhasTabela(context),
        onUnidadeChanged: (i, u) {
          _linhas[i].unidade = u;
          _agendarRebuild();
        },
        onFatorChanged: (i) {
          if (_linhas[i].erroValidacao != null) {
            _linhas[i].erroValidacao = null;
          }
          _agendarRebuild();
        },
        onEmbalagemModoChanged: (i, multiplica) {
          _linhas[i].embalagemMultiplica = multiplica;
          _agendarRebuild();
        },
        onVincular: (i) => _abrirDialogVincularProduto(_linhas[i]),
        onDesfazerVinculo: (i) {
          _desfazerVinculoLinha(_linhas[i]);
          _agendarRebuild();
        },
        onAbrirDetalhe: _abrirDetalheItem,
      );
    }
    return Column(
      children: [
        for (final index in _indicesFiltrados)
          _buildLinhaCard(context, index),
      ],
    );
  }

  Widget _buildLinhaCard(
    BuildContext context,
    int index, {
    VoidCallback? aoAtualizar,
    bool modoDetalhe = false,
  }) {
    final linha = _linhas[index];
    final s = linha.sugestao;
    final item = s.item;
    final destinoId = linha.produtoDestinoId();
    final rotuloVinculo = _rotuloProdutoVinculado(linha);
    final cs = Theme.of(context).colorScheme;
    final avisoConversao = _mensagemFatorConversao(linha);
    final status = _coresStatusChip(context, linha);
    final atencao = _linhaPrecisaAtencao(linha);
    final custoAberto = _custoExpandido.contains(index) || atencao;

    int colsMetaGrid(double largura) {
      if (largura >= 520) return 3;
      if (largura >= 280) return 2;
      return 1;
    }

    Widget secaoDestino() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Produto no sistema',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (rotuloVinculo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rotuloVinculo,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cs.tertiary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.fiber_new_outlined, size: 20, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Novo cadastro sera criado ao confirmar a entrada.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => _abrirDialogVincularProduto(linha),
                icon: const Icon(Icons.link, size: 18),
                label: Text(
                  destinoId == null
                      ? 'Vincular produto'
                      : 'Trocar vinculo',
                ),
              ),
              if (linha.temVinculoAtivo)
                TextButton.icon(
                  onPressed: () {
                    _desfazerVinculoLinha(linha);
                    _atualizarUi(aoAtualizar: aoAtualizar);
                  },
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Desvincular produto'),
                ),
            ],
          ),
        ],
      );
    }

    Widget secaoXml() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dados do XML',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final cols = colsMetaGrid(c.maxWidth);
              final gap = 8.0;
              final cellW =
                  ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
              final cells = <Widget>[
                _buildMetaCelula(
                  context,
                  rotulo: 'Unidade nota',
                  valor: item.unidadeComercial.isEmpty ? '—' : item.unidadeComercial,
                  icon: Icons.straighten,
                ),
                _buildMetaCelula(
                  context,
                  rotulo: 'Quantidade',
                  valor: _nfQtd.format(item.quantidadeComercial),
                  icon: Icons.numbers,
                ),
                _buildMetaCelula(
                  context,
                  rotulo: 'cProd',
                  valor: item.codigo.isEmpty ? '—' : item.codigo,
                  icon: Icons.tag,
                ),
                _buildMetaCelula(
                  context,
                  rotulo: 'Valor unit.',
                  valor: _formatarReais(item.valorUnitarioComercial),
                  icon: Icons.payments_outlined,
                ),
                if (item.ncm.isNotEmpty)
                  _buildMetaCelula(
                    context,
                    rotulo: 'NCM',
                    valor: item.ncm,
                    icon: Icons.category_outlined,
                  ),
                if (item.codigoBarras.isNotEmpty)
                  _buildMetaCelula(
                    context,
                    rotulo: 'EAN',
                    valor: item.codigoBarras,
                    icon: Icons.qr_code_2,
                  ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cell in cells)
                    SizedBox(width: cellW, child: cell),
                ],
              );
            },
          ),
        ],
      );
    }

    Widget secaoConversao() {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Conversao para estoque',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ajuste unidade, qtd. na embalagem e o modo x ou / quando a nota difere do cadastro.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _linhaUnidadeCadastroTravada(linha)
                      ? InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Unidade cadastro',
                            isDense: true,
                          ),
                          child: Text(
                            _unidadeEstoqueLinha(linha),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          key: ValueKey('${index}_${linha.unidade}'),
                          decoration: const InputDecoration(
                            labelText: 'Unidade cadastro',
                            isDense: true,
                          ),
                          initialValue: linha.unidade,
                          items: NfeEntradaRepository.unidadesInternasValidas
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            linha.unidade = v;
                            _atualizarUi(aoAtualizar: aoAtualizar);
                          },
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: linha.fatorCtrl,
                    onChanged: (_) {
                      if (linha.erroValidacao != null) {
                        linha.erroValidacao = null;
                      }
                      _atualizarUi(aoAtualizar: aoAtualizar);
                    },
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Qtd. na embalagem',
                      hintText: 'Ex.: 6',
                      isDense: true,
                      errorText: linha.erroValidacao,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildToggleEmbalagemModo(
                    linha,
                    aoAtualizar: aoAtualizar,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_linhaMostraCamposLote(linha)) ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: linha.loteCtrl,
                      onChanged: (_) =>
                          _atualizarUi(aoAtualizar: aoAtualizar),
                      decoration: const InputDecoration(
                        labelText: 'Lote',
                        hintText: 'Nº do lote',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Validade',
                        isDense: true,
                      ),
                      child: InkWell(
                        onTap: () async {
                          final inicial =
                              linha.dataValidade?.toLocal() ?? DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: inicial,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked == null) return;
                          linha.dataValidade = DateTime.utc(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                          _atualizarUi(aoAtualizar: aoAtualizar);
                        },
                        child: Text(
                          linha.dataValidade == null
                              ? 'Selecionar'
                              : DateFormat('dd/MM/yyyy')
                                  .format(linha.dataValidade!.toLocal()),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (_linhaOfereceConfirmarConversaoEmbalagem(linha))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Gravar conversao de embalagem no cadastro do produto',
                ),
                subtitle: const Text(
                  'Desmarcado: o fator vale so nesta nota, sem alterar venda/PDV.',
                ),
                value: linha.confirmarConversaoEmbalagem,
                onChanged: (v) {
                  linha.confirmarConversaoEmbalagem = v ?? false;
                  _atualizarUi(aoAtualizar: aoAtualizar);
                },
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text(
                  avisoConversao,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.login, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entrada: ${_rotuloEntradaEstoque(linha)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (_estoqueTotalAposConfirmar(linha) case final total?) ...[
                        Builder(
                          builder: (context) {
                            final atual = _produtoDestinoLinha(linha);
                            final atualTxt = atual == null
                                ? ''
                                : ' (atual ${_nfQtd.format(atual.estoqueExibicao)})';
                            return Text(
                              'Estoque apos confirmar: ${_nfQtd.format(total)} ${linha.unidade.trim()}$atualTxt',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget secaoCusto() {
      if (destinoId == null) return const SizedBox.shrink();
      final painel = _buildComparativoCustoPainel(context, linha);
      if (modoDetalhe) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  atencao
                      ? Icons.warning_amber_rounded
                      : Icons.price_change_outlined,
                  color: atencao ? cs.error : cs.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Custo e margem',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            if (atencao) ...[
              const SizedBox(height: 4),
              Text(
                'Revise custo ou margem antes de confirmar.',
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            painel,
          ],
        );
      }
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('custo_$index'),
          initiallyExpanded: custoAberto,
          onExpansionChanged: (aberto) {
            if (aberto) {
              _custoExpandido.add(index);
            } else {
              _custoExpandido.remove(index);
            }
            _atualizarUi(aoAtualizar: aoAtualizar);
          },
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          leading: Icon(
            atencao ? Icons.warning_amber_rounded : Icons.price_change_outlined,
            color: atencao ? cs.error : cs.onSurfaceVariant,
            size: 20,
          ),
          title: Text(
            'Custo e margem',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          subtitle: atencao
              ? Text(
                  'Revise custo ou margem antes de confirmar.',
                  style: TextStyle(color: cs.error, fontSize: 12),
                )
              : null,
          children: [
            _buildComparativoCustoPainel(context, linha),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: modoDetalhe ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: atencao
              ? cs.error.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: status.fg, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final duasColunas = constraints.maxWidth >= 700;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: cs.surfaceContainerHighest,
                        child: Text(
                          '${item.numeroItem}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              item.descricao,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _buildStatusChip(context, linha),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (duasColunas)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              secaoXml(),
                              const SizedBox(height: 14),
                              secaoDestino(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              secaoConversao(),
                              const SizedBox(height: 8),
                              secaoCusto(),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    secaoXml(),
                    const SizedBox(height: 14),
                    secaoDestino(),
                    const SizedBox(height: 14),
                    secaoConversao(),
                    secaoCusto(),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String? _rotuloProdutoVinculado(_LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) return null;
    if (linha.vinculoManualProdutoNome != null) {
      return linha.vinculoManualProdutoNome;
    }
    final p = widget.produtoRepository.obterPorId(id);
    if (p == null) {
      return 'Produto #$id';
    }
    return '${p.codigoInterno} · ${p.nome}';
  }

  Future<void> _abrirDialogVincularProduto(_LinhaEdicao linha) async {
    final escolhido = await showProdutoPesquisaDialog(
      context: context,
      produtoRepository: widget.produtoRepository,
    );
    if (escolhido == null || !mounted) return;
    final u = escolhido.unidade.trim().toUpperCase();
    linha.vinculoManualProdutoId = escolhido.id;
    linha.vinculoManualProdutoNome =
        '${escolhido.codigoInterno} · ${escolhido.nome}';
    linha.embalagemMultiplica = escolhido.embalagemMultiplica;
    linha.confirmarConversaoEmbalagem = false;
    final fator = NfeEntradaConversaoUtil.fatorInicialConferencia(
      item: linha.sugestao.item,
      produto: escolhido,
    );
    linha.fatorCtrl.text = _formatarFator(fator);
    if (NfeEntradaRepository.unidadesInternasValidas.contains(u)) {
      linha.unidade = u;
    }
    _agendarRebuild();
  }

  @override
  void dispose() {
    for (final l in _linhas) {
      l.fatorCtrl.dispose();
      l.loteCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmar() async {
    for (final linha in _linhas) {
      linha.erroValidacao = null;
    }
    String? erroGlobal;
    final confirmacoes = <ConferenciaNfeLinhaConfirmacao>[];
    for (final linha in _linhas) {
      final f = _lerFator(linha.fatorCtrl.text);
      if (f <= 0) {
        final d = linha.sugestao.item.descricao;
        final curto = d.length > 48 ? '${d.substring(0, 48)}…' : d;
        linha.erroValidacao = 'Qtd. embalagem invalida ($curto)';
        setState(() {});
        return;
      }
      final qCom = linha.sugestao.item.quantidadeComercial;
      if (!qCom.isFinite || qCom < 0) {
        erroGlobal =
            'Quantidade da nota invalida em um dos itens. Verifique o XML.';
        break;
      }
      final calc = _entradaNotaCalculada(linha);
      final qtdCalc = calc.unidadeVenda;
      if (!qtdCalc.isFinite || qtdCalc <= 0) {
        linha.erroValidacao =
            'Quantidade para estoque invalida. Ajuste a qtd. na embalagem ou o modo x/.';
        setState(() {});
        return;
      }
      if (calc.armazenado > 2147483647) {
        linha.erroValidacao =
            'Quantidade acima do limite. Reduza a qtd. na embalagem ou corrija a nota.';
        setState(() {});
        return;
      }
      if (!NfeEntradaRepository.unidadesInternasValidas.contains(linha.unidade)) {
        linha.erroValidacao = 'Unidade invalida: ${linha.unidade}';
        setState(() {});
        return;
      }
      confirmacoes.add(
        ConferenciaNfeLinhaConfirmacao(
          item: linha.sugestao.item,
          fatorConversao: f,
          unidadeInterna: _unidadeEstoqueLinha(linha),
          embalagemMultiplica: linha.embalagemMultiplica,
          produtoExistenteId: linha.produtoDestinoId(),
          numeroLote: linha.loteCtrl.text.trim(),
          dataValidade: linha.dataValidade,
          confirmarConversaoEmbalagem: linha.produtoDestinoId() == null
              ? true
              : linha.confirmarConversaoEmbalagem,
        ),
      );
    }
    if (erroGlobal != null) {
      setState(() => _erroConfirmacaoGlobal = erroGlobal);
      return;
    }
    setState(() => _erroConfirmacaoGlobal = null);

    setState(() => _confirmando = true);
    try {
      if (widget.nfeRepository is NfeEntradaApiRepository &&
          !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
        return;
      }
      final confirmar = widget.nfeRepository.confirmarEntrada(
        nfe: widget.nfe,
        linhas: confirmacoes,
        opcoes: _opcoes,
        margemMinimaVendaPercentual: _margemMinimaPadrao,
        xmlOriginal: widget.xmlOriginal,
      );
      if (confirmar is Future) {
        await confirmar;
      }
      try {
        widget.produtoRepository.invalidarCacheBusca();
      } catch (_) {}
      if (!mounted) return;
      OperacaoFeedback.sucesso(context, 'Entrada da NF-e registrada com sucesso.');
      Navigator.of(context).pop(true);
    } on LanApiException catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Confirmar NF-e');
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Erro ao confirmar');
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conferencia NF-e (XML)')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                _initError!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): () {
          if (!_confirmando) _confirmar();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop(false);
        },
      },
      child: Scaffold(
          appBar: AppBar(
            title: const Text('Entrada de NF-e'),
            centerTitle: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    'F10 confirmar · Esc voltar',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: ConferenciaNfeRodape(
            totalItens: _linhas.length,
            itensProntos: _countProntos,
            valorTotalNota: widget.nfe.valorTotalNota,
            confirmando: _confirmando,
            onConfirmar: _confirmar,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_erroConfirmacaoGlobal != null)
                MaterialBanner(
                  content: Text(_erroConfirmacaoGlobal!),
                  leading: Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          setState(() => _erroConfirmacaoGlobal = null),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    context.isCompactLayout ? 12 : 20,
                    12,
                    context.isCompactLayout ? 12 : 20,
                    24,
                  ),
                  children: [
                    _buildPassoConferencia(context),
                    ConferenciaNfeCabecalho(
                      nfe: widget.nfe,
                      totalItens: _linhas.length,
                      itensVinculados: _countVinculados,
                      itensNovos: _countNovos,
                      itensAtencao: _countAtencao,
                    ),
                    const SizedBox(height: 12),
                    ConferenciaNfeOpcoesPainel(
                      opcoes: _opcoes,
                      onChanged: _alterarOpcoes,
                    ),
                    const SizedBox(height: 12),
                    ConferenciaNfeFinanceiroPainel(nfe: widget.nfe),
                    const SizedBox(height: 16),
                    _buildModoExibicaoToggle(context),
                    _buildFiltros(context),
                    _buildListaItens(context),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}

/// Tela de detalhe do item (rota em vez de dialog para evitar conflito com mouse no Windows).
class _ConferenciaItemDetalhePage extends StatefulWidget {
  const _ConferenciaItemDetalhePage({
    required this.screenState,
    required this.index,
  });

  final _ConferenciaXmlScreenState screenState;
  final int index;

  @override
  State<_ConferenciaItemDetalhePage> createState() =>
      _ConferenciaItemDetalhePageState();
}

class _ConferenciaItemDetalhePageState extends State<_ConferenciaItemDetalhePage> {
  @override
  Widget build(BuildContext context) {
    final item = widget.screenState._linhas[widget.index].sugestao.item;
    return Scaffold(
      appBar: AppBar(
        title: Text('Item ${item.numeroItem}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            item.descricao,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          widget.screenState._buildLinhaCard(
            context,
            widget.index,
            aoAtualizar: () => setState(() {}),
            modoDetalhe: true,
          ),
        ],
      ),
    );
  }
}
