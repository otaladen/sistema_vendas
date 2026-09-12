import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/conferencia_carga_repository.dart';
import '../data/api/conferencia_carga_api_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/usuario_repository.dart';
import '../data/api/funcionario_api_repository.dart';
import '../data/api/venda_api_repository.dart';
import '../data/sync/entrega_local_refresh_hub.dart';
import '../data/sync/entregas_foco_hub.dart';
import '../data/lote_produto_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../services/lote_fefo_service.dart';
import '../domain/filtro_listagem_entregas.dart';
import '../domain/complemento_entrega_codec.dart';
import '../domain/motorista_lista_safe.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../domain/venda_relacao_safe.dart';
import '../model/historico_entrega.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import 'entregas/entrega_card_lista.dart';
import 'entregas/entregas_barra_compacta.dart';
import 'entregas/entregas_visao_simples.dart';
import 'entregas/filtros_entrega_sheet.dart';
import 'entregas/logistica_entregas.dart';
import 'entregas/planejamento_entrega_dia.dart';
import 'entregas/agrupar_viagem_dialog.dart';
import 'entregas/entregas_guia.dart';
import 'entregas/entregas_montagem_callbacks.dart';
import 'entregas/montagem_entrega_viagem.dart';
import 'entregas/painel_montagem_entregas.dart';
import 'entregas/selecionar_motorista_dialog.dart';
import 'entregas/carreto_checklist_erro_dialog.dart';
import 'entregas/conferencia_carga_consolidada_lista.dart';
import 'entregas/romaneio_carga_consolidada.dart';
import 'entregas/romaneio_pdf.dart';
import 'entregas/romaneio_relatorios.dart';
import '../services/configuracoes_service.dart';
import '../domain/entregas/carreto_saida_produto_orfao.dart';
import '../domain/entregas/loja_origem_mercadoria.dart';
import '../domain/entregas/buscar_na_loja.dart';
import '../domain/entrega_pod_regra.dart';
import '../domain/entregas/carreto_checklist_estoque_helper.dart';
import '../services/entrega_fluxo_service.dart';
import '../services/entrega_pod_finalizacao.dart';
import '../services/entrega_pod_prefetch_service.dart';
import 'entregas/entrega_pod_chip.dart';
import 'entregas/entrega_pod_foto_panel.dart';
import 'entregas/pod_entrega_dialog.dart';
import 'pdv_vendedor_bloqueio.dart';
import 'registrar_devolucao_troca_page.dart';
import 'shell/main_menu_deps.dart';
import 'widgets/lan_api_feedback.dart';

/// Filtro rapido pelos contadores de resumo (atrasadas / pendentes hoje).
enum _FiltroResumoEntregas { nenhum, atrasadas, pendentesHoje, buscarNaLoja }

enum _ModoVisualizacaoDia { lista, kanban }

enum _TipoLinhaListaEntrega { cabecalho, rota, carreto, card }

/// Linha virtualizada da lista do dia (evita montar todos os cards do grupo).
class _LinhaListaEntrega {
  const _LinhaListaEntrega._({
    required this.tipo,
    this.rotuloGrupo,
    this.quantidade = 0,
    this.motorista,
    this.vendas,
    this.venda,
  });

  factory _LinhaListaEntrega.cabecalho(String grupo, int n) =>
      _LinhaListaEntrega._(
        tipo: _TipoLinhaListaEntrega.cabecalho,
        rotuloGrupo: grupo,
        quantidade: n,
      );

  factory _LinhaListaEntrega.rota(String motorista, List<Venda> vendas) =>
      _LinhaListaEntrega._(
        tipo: _TipoLinhaListaEntrega.rota,
        motorista: motorista,
        vendas: vendas,
      );

  factory _LinhaListaEntrega.carreto(List<Venda> bloco) =>
      _LinhaListaEntrega._(
        tipo: _TipoLinhaListaEntrega.carreto,
        vendas: bloco,
      );

  factory _LinhaListaEntrega.card(Venda venda) => _LinhaListaEntrega._(
        tipo: _TipoLinhaListaEntrega.card,
        venda: venda,
      );

  final _TipoLinhaListaEntrega tipo;
  final String? rotuloGrupo;
  final int quantidade;
  final String? motorista;
  final List<Venda>? vendas;
  final Venda? venda;
}

const _kMenuMarcarDataEntrega = '__acao_marcar_data_entrega__';
const _kMenuLimparDataEntrega = '__acao_limpar_data_entrega__';
const _kMenuDevolucaoPosCarreto = '__acao_devolucao_pos_carreto__';
const _kMenuRetiradaLojaCarreto = '__acao_retirada_loja_carreto__';

class EntregasPage extends StatefulWidget {
  const EntregasPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
    required this.motoristaRepository,
    required this.vendedorRepository,
    required this.usuarioAtual,
    required this.podeGerenciarStatusEntrega,
    required this.podeRegistrarPodEntrega,
    required this.podeRegistrarDevolucaoTrocaSemSenha,
    this.configuracoesService,
    this.ocultarValoresMonetarios = false,
  });

  final dynamic vendaRepository;
  final dynamic produtoRepository;
  final dynamic motoristaRepository;
  final dynamic vendedorRepository;
  final ConfiguracoesService? configuracoesService;
  final String usuarioAtual;
  final bool podeGerenciarStatusEntrega;
  final bool podeRegistrarPodEntrega;

  /// Mesmo criterio da listagem de vendas (admin / financeiro / auditoria de caixa).
  final bool podeRegistrarDevolucaoTrocaSemSenha;

  /// Motorista de campo: nao mostra preco nem total da carga.
  final bool ocultarValoresMonetarios;

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage>
    with SingleTickerProviderStateMixin {
  dynamic _conferenciaCargaRepository;
  late dynamic _usuarioRepository;

  bool get _usaVendaApi => widget.vendaRepository is VendaApiRepository;

  VendaApiRepository get _vendaApiRepo =>
      widget.vendaRepository as VendaApiRepository;

  dynamic _criarConferenciaCargaRepository() {
    if (widget.vendaRepository is VendaApiRepository) {
      final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
      if (client != null) {
        return ConferenciaCargaApiRepository(client);
      }
      return null;
    }
    try {
      return ConferenciaCargaRepository(widget.vendaRepository.objectBox);
    } catch (_) {
      return null;
    }
  }

  late TabController _tabEntregasController;
  bool _mostrarDicasEntregas = true;
  bool _visaoSimples = true;

  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final _bairroController = TextEditingController();
  final _numeroNotaController = TextEditingController();
  final _statuses = const [
    'todos',
    'pendente',
    'saiu_entrega',
    'entregue_complemento_pendente',
    'entregue',
    'reagendada',
    'cancelada',
  ];

  List<Venda> _entregas = [];
  List<Venda> _entregasResumoDias = [];
  int _contagemAtrasadasCache = 0;
  int _contagemPendentesHojeCache = 0;
  String _statusSelecionado = 'todos';
  String _filtroMotorista = 'todos';
  String _filtroVendedor = 'todos';
  List<String> _vendedoresDisponiveis = const [];
  String _agrupamento = 'motorista'; // bairro | motorista
  String _filtroDataMarcada = 'hoje'; // todos | hoje | amanha | sem_data
  DateTime? _inicio;
  DateTime? _fim;
  bool _modoAgruparMesmoCarro = false;
  final Set<int> _idsEntregasSelecionadas = {};

  /// Incrementado ao usar "Limpar tudo" para remontar dropdowns (initialValue vale apenas no primeiro build).
  int _filtrosDropdownNonce = 0;
  _FiltroResumoEntregas _filtroResumoLista = _FiltroResumoEntregas.nenhum;
  bool _filtroApenasSemMotorista = false;
  _ModoVisualizacaoDia _modoVisualizacaoDia = _ModoVisualizacaoDia.lista;
  late DateTime _inicioSemanaExibida;

  /// Chave igual a [resumoPorDia] (`dd/MM/yyyy` ou `Sem data marcada`); filtra so a lista.
  String? _chaveDiaPlanejamentoSelecionado;

  bool _proximosDiasPlanejamentoExpandido = false;

  final ScrollController _kanbanHScrollController = ScrollController();

  Timer? _refreshEntregaDebounce;
  bool _refreshEntregaViaApi = false;

  void _selecionarDiaPlanejamento(String? chave) {
    setState(() {
      _chaveDiaPlanejamentoSelecionado = chave;
      _filtroDataMarcada = _filtroDataMarcadaDeChaveDia(chave);
      _filtroApenasSemMotorista = false;
      if (chave != null && chave != PlanejamentoEntregaDia.semData) {
        final d = PlanejamentoEntregaDia.parseChave(chave);
        if (d != null) {
          _inicioSemanaExibida = PlanejamentoEntregaDia.inicioSemana(d);
        }
      }
    });
    _carregarEntregas();
  }

  void _selecionarDiaNaSemana(DateTime dia) {
    _selecionarDiaPlanejamento(PlanejamentoEntregaDia.chaveDeDateTime(dia));
  }

  void _deslocarSemanaExibida(int deltaSemanas) {
    setState(() {
      _inicioSemanaExibida = PlanejamentoEntregaDia.soDia(
        _inicioSemanaExibida,
      ).add(Duration(days: 7 * deltaSemanas));
    });
  }

  String _filtroDataMarcadaDeChaveDia(String? chave) {
    if (chave == null) return 'todos';
    if (chave == PlanejamentoEntregaDia.semData) return 'sem_data';
    final hoje = PlanejamentoEntregaDia.chaveDeDateTime(DateTime.now());
    if (chave == hoje) return 'hoje';
    final amanha = PlanejamentoEntregaDia.chaveDeDateTime(
      DateTime.now().add(const Duration(days: 1)),
    );
    if (chave == amanha) return 'amanha';
    return 'todos';
  }

  void _sincronizarChaveDiaComFiltroDataMarcada() {
    switch (_filtroDataMarcada) {
      case 'hoje':
        _chaveDiaPlanejamentoSelecionado =
            PlanejamentoEntregaDia.chaveDeDateTime(DateTime.now());
      case 'amanha':
        _chaveDiaPlanejamentoSelecionado =
            PlanejamentoEntregaDia.chaveDeDateTime(
              DateTime.now().add(const Duration(days: 1)),
            );
      case 'sem_data':
        _chaveDiaPlanejamentoSelecionado = PlanejamentoEntregaDia.semData;
      case 'todos':
        _chaveDiaPlanejamentoSelecionado = null;
    }
  }

  int _contagemFiltrosAtivos() {
    return contarFiltrosEntregaAtivos(
      status: _statusSelecionado,
      motorista: _filtroMotorista,
      vendedor: _filtroVendedor,
      agrupamento: _agrupamento,
      dataMarcada: _filtroDataMarcada,
      bairro: _bairroController.text,
      numeroNota: _numeroNotaController.text,
      inicio: _inicio,
      fim: _fim,
    );
  }

  String _nomeMotoristaFiltroExibicao() {
    if (_filtroMotorista == 'todos') return 'Todos';
    final ativos = MotoristaListaSafe.listarAtivos(widget.motoristaRepository);
    for (final x in ativos) {
      if (x.nome.trim().toLowerCase() == _filtroMotorista) {
        return x.nome;
      }
    }
    return _filtroMotorista;
  }

  String _nomeVendedorFiltroExibicao() {
    if (_filtroVendedor == 'todos') return 'Todos';
    final v = _vendedoresDisponiveis.where(
      (n) => n.toLowerCase() == _filtroVendedor,
    );
    return v.isNotEmpty ? v.first : _filtroVendedor;
  }

  Future<void> _abrirFiltrosEntrega() async {
    final resumos = resumosFiltrosEntregaAtivos(
      status: _statusSelecionado,
      rotuloStatus: _rotuloStatusFiltro,
      motorista: _filtroMotorista,
      nomeMotoristaExibicao: _nomeMotoristaFiltroExibicao(),
      vendedor: _filtroVendedor,
      nomeVendedorExibicao: _nomeVendedorFiltroExibicao(),
      agrupamento: _agrupamento,
      dataMarcada: _filtroDataMarcada,
      bairro: _bairroController.text,
      numeroNota: _numeroNotaController.text,
      rotuloPeriodo: _rotuloPeriodoSelecionado(),
    );
    if (!mounted) return;
    await showFiltrosEntregaSheet(
      context: context,
      filtrosDropdownNonce: _filtrosDropdownNonce,
      statuses: _statuses,
      rotuloStatus: _rotuloStatusFiltro,
      statusSelecionado: _statusSelecionado,
      onStatus: (v) {
        setState(() => _statusSelecionado = v);
        _carregarEntregas();
      },
      filtroMotorista: _filtroMotorista,
      motoristasAtivos: MotoristaListaSafe.listarAtivos(
        widget.motoristaRepository,
      ),
      onMotorista: (v) {
        setState(() => _filtroMotorista = v);
        _carregarEntregas();
      },
      filtroVendedor: _filtroVendedor,
      vendedoresDisponiveis: _vendedoresDisponiveis,
      onVendedor: (v) {
        setState(() => _filtroVendedor = v);
        _carregarEntregas();
      },
      agrupamento: _agrupamento,
      onAgrupamento: (v) => setState(() => _agrupamento = v),
      filtroDataMarcada: _filtroDataMarcada,
      onDataMarcada: (v) {
        setState(() {
          _filtroDataMarcada = v;
          _sincronizarChaveDiaComFiltroDataMarcada();
          _filtroApenasSemMotorista = false;
        });
        _carregarEntregas();
      },
      numeroNotaController: _numeroNotaController,
      bairroController: _bairroController,
      onAplicarTexto: _carregarEntregas,
      onLimparTudo: _redefinirFiltrosPadrao,
      onPeriodoHoje: _aplicarPeriodoMarcadasParaHoje,
      onPeriodoPersonalizado: _selecionarPeriodoPersonalizado,
      rotuloPeriodo: _rotuloPeriodoSelecionado(),
      resumosAtivos: resumos,
    );
  }

  Future<void> _abrirSeletorPlanejamentoDia(
    Map<String, int> resumoPorDia,
  ) async {
    final escolha = await showSeletorPlanejamentoEntregaDia(
      context: context,
      resumoPorDia: resumoPorDia,
      chaveInicial: _chaveDiaPlanejamentoSelecionado,
    );
    if (!mounted || escolha == null) return;
    _selecionarDiaPlanejamento(escolha.isEmpty ? null : escolha);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conferenciaCargaRepository ??= _criarConferenciaCargaRepository();
  }

  @override
  void initState() {
    super.initState();
    _usuarioRepository =
        MainMenuDeps.resolverUsuarioRepository(context);
    _tabEntregasController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 1,
    );
    _inicioSemanaExibida = PlanejamentoEntregaDia.inicioSemana(DateTime.now());
    _tabEntregasController.addListener(_onTabEntregasAlterada);
    _inicio = null;
    _fim = null;
    _chaveDiaPlanejamentoSelecionado = PlanejamentoEntregaDia.chaveDeDateTime(
      DateTime.now(),
    );
    _filtroDataMarcada = 'hoje';
    LanApiEventHub.instance.addListener(_onLanApiEntregaChanged);
    EntregaLocalRefreshHub.instance.addListener(_onEntregaLocalRefresh);
    EntregasFocoHub.instance.addListener(_onEntregasFocoPedido);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEntregasFocoPedido());
    if (_usaVendaApi) {
      unawaited(_inicializarEntregasApi());
    } else {
      _carregarEntregas();
    }
    unawaited(_prefetchPodFotos());
    unawaited(_carregarPreferenciaDicasEntregas());
    unawaited(_aplicarPreferenciasAberturaSalvas());
  }

  void _onEntregasFocoPedido() {
    final n = EntregasFocoHub.instance.numeroPedido;
    if (n == null || n <= 0) return;
    EntregasFocoHub.instance.consumir();
    if (!mounted) return;
    setState(() {
      _numeroNotaController.text = '$n';
      _filtroDataMarcada = 'todos';
      _chaveDiaPlanejamentoSelecionado = null;
      _statusSelecionado = 'todos';
      _filtroResumoLista = _FiltroResumoEntregas.nenhum;
      _filtroApenasSemMotorista = false;
    });
    _carregarEntregas();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Filtro do chat: pedido #$n')),
    );
  }

  Future<void> _garantirMotoristasHidratados() async {
    final repo = widget.motoristaRepository;
    if (repo is! MotoristaApiRepository) return;
    try {
      await repo.hidratar();
    } catch (_) {}
  }

  Future<void> _inicializarEntregasApi() async {
    try {
      await _vendaApiRepo.hidratarEntregas(limit: 500);
      await _garantirMotoristasHidratados();
    } on LanApiException catch (e) {
      debugPrint('EntregasPage.hidratarEntregas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Entregas: $e')),
        );
      }
    } catch (e, st) {
      debugPrint('EntregasPage.hidratarEntregas: $e\n$st');
    }
    if (mounted) _carregarEntregas();
  }

  Future<void> _aplicarPreferenciasAberturaSalvas() async {
    final prefs = await EntregasGuia.preferenciasAbertura();
    final simples = await EntregasGuia.visaoSimplesAtiva();
    if (!mounted) return;
    if (prefs.aba != _tabEntregasController.index) {
      _tabEntregasController.index = prefs.aba;
    }
    setState(() {
      _visaoSimples = simples;
      _modoVisualizacaoDia = prefs.kanban
          ? _ModoVisualizacaoDia.kanban
          : _ModoVisualizacaoDia.lista;
    });
  }

  Future<void> _definirVisaoSimples(bool simples) async {
    await EntregasGuia.setVisaoSimplesAtiva(simples);
    if (!mounted) return;
    setState(() => _visaoSimples = simples);
  }

  void _aplicarDiaRapidoSimples({required bool amanha}) {
    final base = DateTime.now();
    final dia = DateTime(
      base.year,
      base.month,
      base.day,
    ).add(Duration(days: amanha ? 1 : 0));
    _selecionarDiaPlanejamento(PlanejamentoEntregaDia.chaveDeDateTime(dia));
  }

  String _rotuloDiaSelecionadoSimples() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == null || chave.isEmpty) return 'Escolher dia';
    if (_filtroDataMarcada == 'hoje') return 'Hoje';
    if (_filtroDataMarcada == 'amanha') return 'Amanhã';
    return chave;
  }

  bool get _diaSelecionadoEhHojeSimples => _filtroDataMarcada == 'hoje';

  bool get _diaSelecionadoEhAmanhaSimples => _filtroDataMarcada == 'amanha';

  Widget _seletorAbaAvancadaAppBar() {
    final aba = _tabEntregasController.index.clamp(0, 1);
    final scheme = Theme.of(context).colorScheme;
    final onBar =
        Theme.of(context).appBarTheme.foregroundColor ?? scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'Patio (carga/rota) ou Dia (lista)',
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: aba,
            isDense: true,
            borderRadius: BorderRadius.circular(8),
            icon: Icon(Icons.arrow_drop_down, color: onBar, size: 20),
            dropdownColor: scheme.surface,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: onBar,
                  fontWeight: FontWeight.w600,
                ),
            selectedItemBuilder: (context) => [
              _rotuloAbaAvancada(
                Icons.inventory_2_outlined,
                'Patio',
                onBar,
              ),
              _rotuloAbaAvancada(
                Icons.calendar_view_week_outlined,
                'Dia',
                onBar,
              ),
            ],
            items: [
              DropdownMenuItem(
                value: 0,
                child: _rotuloAbaAvancada(
                  Icons.inventory_2_outlined,
                  'Patio',
                  scheme.onSurface,
                ),
              ),
              DropdownMenuItem(
                value: 1,
                child: _rotuloAbaAvancada(
                  Icons.calendar_view_week_outlined,
                  'Dia',
                  scheme.onSurface,
                ),
              ),
            ],
            onChanged: (v) {
              if (v == null || v == _tabEntregasController.index) return;
              _tabEntregasController.animateTo(v);
            },
          ),
        ),
      ),
    );
  }

  Widget _rotuloAbaAvancada(IconData icone, String texto, Color cor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 16, color: cor),
        const SizedBox(width: 6),
        Text(texto),
      ],
    );
  }

  void _salvarPreferenciasAberturaAtual() {
    unawaited(
      EntregasGuia.salvarPreferenciasAbertura(
        aba: _tabEntregasController.index,
        kanban: _modoVisualizacaoDia == _ModoVisualizacaoDia.kanban,
      ),
    );
  }

  void _onTabEntregasAlterada() {
    if (_tabEntregasController.indexIsChanging) return;
    _salvarPreferenciasAberturaAtual();
    setState(() {});
  }

  Future<void> _carregarPreferenciaDicasEntregas() async {
    final visivel = await EntregasGuia.dicasVisiveis();
    if (mounted) setState(() => _mostrarDicasEntregas = visivel);
  }

  Future<void> _ocultarDicasEntregas() async {
    await EntregasGuia.setDicasVisiveis(false);
    if (mounted) setState(() => _mostrarDicasEntregas = false);
  }

  void _onLanApiEntregaChanged() {
    if (!mounted) return;
    final ent = LanApiEventHub.instance.ultimaEntidade;
    if (ent != 'entrega' &&
        ent != 'venda' &&
        ent != 'conferencia_carga' &&
        ent != 'conferencia_carga_romaneio') {
      return;
    }
    _agendarRefreshAposEventoEntrega(viaApi: true);
  }

  void _onEntregaLocalRefresh() {
    if (!mounted) return;
    _agendarRefreshAposEventoEntrega(viaApi: false);
  }

  void _agendarRefreshAposEventoEntrega({required bool viaApi}) {
    if (viaApi) _refreshEntregaViaApi = true;
    _refreshEntregaDebounce?.cancel();
    _refreshEntregaDebounce = Timer(const Duration(milliseconds: 250), () {
      final api = _refreshEntregaViaApi;
      _refreshEntregaViaApi = false;
      if (!mounted) return;
      unawaited(_refreshAposEventoEntrega(viaApi: api));
    });
  }

  Future<void> _refreshAposEventoEntrega({required bool viaApi}) async {
    if (viaApi && _usaVendaApi) {
      try {
        await _vendaApiRepo.hidratarEntregas(limit: 500);
      } catch (_) {}
    }
    if (!mounted) return;
    _carregarEntregas();
    unawaited(_prefetchPodFotos());
  }

  Future<void> _prefetchPodFotos() async {
    final svc = widget.configuracoesService;
    if (svc == null || _entregas.isEmpty) return;
    await EntregaPodPrefetchService(
      configRepository: svc.repository,
    ).prefetchLista(_entregas);
  }

  void _copiarCamposPod(Venda destino, Venda origem) {
    destino.podRecebidoPor = origem.podRecebidoPor;
    destino.podRegistradoPor = origem.podRegistradoPor;
    destino.podRegistradoEm = origem.podRegistradoEm;
    destino.podFotoPath = origem.podFotoPath;
    destino.podFotoPathServidor = origem.podFotoPathServidor;
  }

  Future<bool> _editarPodEntrega(Venda venda) async {
    if (!widget.podeRegistrarPodEntrega) return false;
    final anterior = venda.podRecebidoPor.trim();
    final pod = await showPodEntregaDialog(
      context: context,
      vendaId: venda.id,
      recebidoPorInicial: anterior,
      modoEdicao: true,
      origemMercadoriaRotulo: _rotuloOrigemMercadoria(venda),
    );
    if (pod == null) return false;
    try {
      final podFinal = EntregaPodFinalizacao(
        configRepository: widget.configuracoesService?.repository,
      );
      final motivo = anterior.isEmpty
          ? 'POD registrado — recebido por: ${pod.recebidoPor}'
          : 'POD alterado — recebido por: ${pod.recebidoPor} (antes: $anterior)';
      await podFinal.registrarPod(
        vendaRepository: widget.vendaRepository,
        vendaId: venda.id,
        recebidoPor: pod.recebidoPor,
        usuarioLogin: widget.usuarioAtual,
        fotoPathLocal: pod.fotoPathLocal ?? venda.podFotoPath,
        fotoPathServidor: pod.fotoPathServidor ?? venda.podFotoPathServidor,
        ocorrenciaMotivo:
            widget.vendaRepository is VendaApiRepository ? motivo : '',
      );
      final atualizada = widget.vendaRepository.obterPorId(venda.id);
      if (atualizada != null) _copiarCamposPod(venda, atualizada);
      if (widget.vendaRepository is VendaApiRepository) {
        // Ocorrencia ja enviada no payload do POD.
      } else {
        widget.vendaRepository.registrarOcorrenciaEntrega(
          vendaId: venda.id,
          status: HistoricoEntregaEventos.podEntrega,
          motivo: motivo,
          usuario: widget.usuarioAtual,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prova de entrega atualizada.')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao alterar POD: $e')));
      }
      return false;
    }
  }

  @override
  void dispose() {
    _refreshEntregaDebounce?.cancel();
    _tabEntregasController.removeListener(_onTabEntregasAlterada);
    _tabEntregasController.dispose();
    LanApiEventHub.instance.removeListener(_onLanApiEntregaChanged);
    EntregaLocalRefreshHub.instance.removeListener(_onEntregaLocalRefresh);
    EntregasFocoHub.instance.removeListener(_onEntregasFocoPedido);
    _kanbanHScrollController.dispose();
    _bairroController.dispose();
    _numeroNotaController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  /// Itens sem depender de ToMany quebrado (terminal leve).
  List<ItemVenda> _itensDaVenda(Venda v) {
    try {
      final viaRepo =
          widget.vendaRepository.listarItensPorVenda(v.id) as List?;
      if (viaRepo != null && viaRepo.isNotEmpty) {
        return viaRepo.whereType<ItemVenda>().toList();
      }
    } catch (_) {}
    try {
      return v.itens.toList();
    } catch (_) {
      return const [];
    }
  }

  Produto? _obterProdutoPorId(int id) {
    if (id <= 0) return null;
    try {
      return widget.produtoRepository.obterPorId(id) as Produto?;
    } catch (_) {
      return null;
    }
  }

  bool _itemOrfaoNaCarga(ItemVenda item) {
    return RomaneioProdutoOrfaoHelper.itemOrfao(
      item,
      obterProduto: _obterProdutoPorId,
    );
  }

  bool _vendaUsaItensCarretoMigrado(Venda v) {
    try {
      return EntregaVendaHelper.vendaTemItensMigradosRetiradaParaCarreto(v);
    } catch (_) {
      return false;
    }
  }

  /// Carreto nativo (reserva ate a saida), nao migrado de retirada futura.
  bool _vendaCarretoReservaNativaSemMigracao(Venda v) {
    try {
      return EntregaVendaHelper.vendaTemItensCarreto(v) &&
          v.carretoReservaAteSaida &&
          !_vendaUsaItensCarretoMigrado(v);
    } catch (_) {
      return false;
    }
  }

  bool _podeRegistrarRetiradaLojaAntesSaidaCarreto(Venda v) {
    try {
      return EntregaVendaHelper.vendaPermiteRetiradaLojaCarretoAntesSaida(v) &&
          _vendaCarretoReservaNativaSemMigracao(v);
    } catch (_) {
      return false;
    }
  }

  /// Valor persistido (comparacoes / falta). UI usa [_textoQuantidadeExibicaoEntrega].
  int _quantidadeExibicaoEntrega(Venda v, ItemVenda item) =>
      EntregaVendaHelper.quantidadeRomaneioCarga(v, item);

  String _textoQuantidadeExibicaoEntrega(Venda v, ItemVenda item) =>
      EntregaVendaHelper.textoQuantidadeRomaneioCarga(v, item);

  double _subtotalExibicaoEntrega(Venda v, ItemVenda item) =>
      EntregaVendaHelper.subtotalRomaneioCarga(v, item);

  /// Mesma base da listagem de vendas (venda finalizada, itens ainda devolviveis).
  bool _podeRegistrarDevolucaoTrocaBase(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    if (v.vendaOrigemFreteRetiradaId > 0) return false;
    return _itensDaVenda(v).any((i) => i.quantidade - i.quantidadeDevolvida > 0);
  }

  /// Carreto com checklist "Saiu" e entrega em andamento ou concluida (mercadoria pode voltar).
  bool _podeDevolucaoPosCarretoNaEntrega(Venda v) {
    try {
      if (!_podeRegistrarDevolucaoTrocaBase(v)) return false;
      if (!EntregaVendaHelper.vendaTemItensCarreto(v)) return false;
      if (!v.cargaSaiu) return false;
      return v.statusEntrega == 'saiu_entrega' ||
          v.statusEntrega == 'entregue' ||
          v.statusEntrega == 'entregue_complemento_pendente';
    } catch (_) {
      return false;
    }
  }

  Future<void> _abrirRegistrarDevolucaoPosCarreto(Venda vIn) async {
    final clienteRepository = MainMenuDeps.maybeOf(context)?.clienteRepository;
    if (clienteRepository == null ||
        widget.vendaRepository is VendaApiRepository) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Devolucoes exigem a base local e nao estao disponiveis neste terminal.',
          ),
        ),
      );
      return;
    }
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!_podeDevolucaoPosCarretoNaEntrega(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Neste atalho: carreto com carga que ja saiu e quantidade ainda '
            'devolvivel. Nos demais casos use Vendas > Listagem > Devolucao / troca.',
          ),
        ),
      );
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrarDevolucaoTrocaPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: clienteRepository,
          produtoRepository: widget.produtoRepository,
          vendaId: v.id,
          usuarioAtual: widget.usuarioAtual,
          podeRegistrarSemSenha: widget.podeRegistrarDevolucaoTrocaSemSenha,
        ),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      _carregarEntregas();
    }
  }

  Future<void> _abrirRegistrarRetiradaLojaCarretoAntesSaida(Venda vIn) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!_podeRegistrarRetiradaLojaAntesSaidaCarreto(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Disponivel somente para carreto com reserva ate a saida, '
            'sem migracao de retirada futura, com checklist "Saiu" ainda desmarcado '
            'e com quantidade restante para o carro.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogRetiradaLojaCarretoAntesSaida(
        venda: v,
        vendaRepository: widget.vendaRepository,
        vendedorRepository: widget.vendedorRepository,
        usuarioRepository: _usuarioRepository,
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      _carregarEntregas();
    }
  }

  String _rotuloStatusEntrega(String status) {
    switch (status) {
      case HistoricoEntregaEventos.devolucao:
        return 'Devolucao registrada';
      case HistoricoEntregaEventos.troca:
        return 'Troca registrada';
      case HistoricoEntregaEventos.retiradaFutura:
        return 'Retirada futura';
      case HistoricoEntregaEventos.retiradaLojaPreSaida:
        return 'Retirada na loja (pre-saida)';
      case HistoricoEntregaEventos.complementoPendente:
        return 'Complemento pendente';
      case HistoricoEntregaEventos.buscarNaLoja:
        return 'Buscar nesta loja';
      case HistoricoEntregaEventos.carretoSaidaProdutoOrfao:
        return 'Saida carreto (produto excluido)';
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'Aguardando motorista';
      case 'saiu_entrega':
        return 'Saiu para entrega';
      case 'entregue_complemento_pendente':
        return 'Complemento pendente';
      case 'entregue':
        return 'Entregue';
      case 'reagendada':
        return 'Reagendada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Nao aplicavel';
    }
  }

  String _rotuloStatusFiltro(String status) {
    if (status == 'todos') return 'Todos';
    if (status == 'pendente') return 'Pendente';
    if (status == 'saiu_entrega') return 'Em rota';
    if (status == 'entregue_complemento_pendente') {
      return 'Compl. pendente';
    }
    return _rotuloStatusEntrega(status);
  }

  Color _corStatus(ColorScheme scheme, String status) {
    switch (status) {
      case 'entregue':
        return Colors.green.shade700;
      case 'entregue_complemento_pendente':
        return Colors.deepOrange.shade800;
      case 'saiu_entrega':
        return Colors.blue.shade700;
      case 'reagendada':
        return Colors.orange.shade700;
      case 'cancelada':
        return scheme.error;
      case 'roteirizada':
      case 'pendente':
      default:
        return scheme.primary;
    }
  }

  int _progressoCarga(Venda venda) {
    var total = 0;
    if (venda.cargaSeparada) total++;
    if (venda.cargaCarregada) total++;
    if (venda.cargaSaiu) total++;
    return total;
  }

  Color _corProgressoCarga(BuildContext context, int progresso) {
    final scheme = Theme.of(context).colorScheme;
    if (progresso >= 3) return Colors.green.shade700;
    if (progresso >= 1) return Colors.amber.shade800;
    return scheme.outline;
  }

  bool _vendaNaChaveDiaPlanejamento(
    Venda venda,
    String chaveDia,
    DateFormat dataMarcadaFmt,
  ) {
    if (chaveDia == 'Sem data marcada') {
      return venda.dataEntregaMarcada == null;
    }
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    return dataMarcadaFmt.format(marcada) == chaveDia;
  }

  ({
    DateTime? inicio,
    DateTime? fim,
    String filtroMemoria,
    bool filtradoNoBanco,
  })
  _parametrosDataMarcadaFiltro() {
    switch (_filtroDataMarcada) {
      case 'hoje':
        final h = PlanejamentoEntregaDia.soDia(DateTime.now());
        return (
          inicio: h,
          fim: PlanejamentoEntregaDia.fimDoDia(h),
          filtroMemoria: 'todos',
          filtradoNoBanco: true,
        );
      case 'amanha':
        final h = PlanejamentoEntregaDia.soDia(
          DateTime.now().add(const Duration(days: 1)),
        );
        return (
          inicio: h,
          fim: PlanejamentoEntregaDia.fimDoDia(h),
          filtroMemoria: 'todos',
          filtradoNoBanco: true,
        );
      case 'sem_data':
        return (
          inicio: null,
          fim: null,
          filtroMemoria: 'sem_data',
          filtradoNoBanco: false,
        );
      case 'todos':
      default:
        final chave = _chaveDiaPlanejamentoSelecionado;
        if (chave != null && chave != PlanejamentoEntregaDia.semData) {
          final d = PlanejamentoEntregaDia.parseChave(chave);
          if (d != null) {
            final h = PlanejamentoEntregaDia.soDia(d);
            return (
              inicio: h,
              fim: PlanejamentoEntregaDia.fimDoDia(h),
              filtroMemoria: 'todos',
              filtradoNoBanco: true,
            );
          }
        }
        return (
          inicio: null,
          fim: null,
          filtroMemoria: 'todos',
          filtradoNoBanco: false,
        );
    }
  }

  FiltroListagemEntregas _montarFiltroEntregas({
    required bool usarPeriodoVendaNaLista,
    bool paraContagemResumo = false,
  }) {
    final usarPeriodo = paraContagemResumo
        ? false
        : (_filtroResumoLista == _FiltroResumoEntregas.nenhum &&
              usarPeriodoVendaNaLista);
    final dataMarcada = paraContagemResumo
        ? (
            inicio: null,
            fim: null,
            filtroMemoria: 'todos',
            filtradoNoBanco: false,
          )
        : _parametrosDataMarcadaFiltro();
    return FiltroListagemEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: usarPeriodo ? _inicio : null,
      fim: usarPeriodo ? _fim : null,
      filtroDataMarcada: dataMarcada.filtroMemoria,
      dataMarcadaInicio: dataMarcada.inicio,
      dataMarcadaFim: dataMarcada.fim,
      dataMarcadaFiltradaNoBanco: dataMarcada.filtradoNoBanco,
      filtroMotorista: _filtroMotorista,
      filtroVendedor: _filtroVendedor,
      numeroNota: _numeroNotaController.text,
      apenasAtrasadas:
          !paraContagemResumo &&
          _filtroResumoLista == _FiltroResumoEntregas.atrasadas,
      apenasPendentesHoje:
          !paraContagemResumo &&
          _filtroResumoLista == _FiltroResumoEntregas.pendentesHoje,
    );
  }

  void _carregarEntregas() {
    try {
      final filtroLista = _montarFiltroEntregas(usarPeriodoVendaNaLista: true);
      final filtroContagem = _montarFiltroEntregas(
        usarPeriodoVendaNaLista: false,
        paraContagemResumo: true,
      );
      final resultado = widget.vendaRepository.carregarListagemEntregasComResumo(
        filtroLista: filtroLista,
        filtroContagem: filtroContagem,
      );
      final resultadoResumoDias = widget.vendaRepository
          .carregarListagemEntregasComResumo(
            filtroLista: filtroContagem,
            filtroContagem: filtroContagem,
          );
      final entregas = (resultado.entregas as List).whereType<Venda>().toList();
      final resumoDias =
          (resultadoResumoDias.entregas as List).whereType<Venda>().toList();
      final vendedoresDisponiveis =
          (entregas
              .map(_nomeVendedor)
              .map((n) => n.trim())
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
      if (!mounted) return;
      setState(() {
        _entregas = entregas;
        _entregasResumoDias = resumoDias;
        _contagemAtrasadasCache = resultado.atrasadas as int? ?? 0;
        _contagemPendentesHojeCache = resultado.pendentesHoje as int? ?? 0;
        _vendedoresDisponiveis = vendedoresDisponiveis;
        if (_chaveDiaPlanejamentoSelecionado != null &&
            _filtroDataMarcada == 'todos') {
          final fmtPlanej = DateFormat('dd/MM/yyyy');
          final aindaExiste = entregas.any(
            (v) => _vendaNaChaveDiaPlanejamento(
              v,
              _chaveDiaPlanejamentoSelecionado!,
              fmtPlanej,
            ),
          );
          if (!aindaExiste) _chaveDiaPlanejamentoSelecionado = null;
        }
      });
      unawaited(_prefetchPodFotos());
    } catch (e, st) {
      debugPrint('EntregasPage._carregarEntregas: $e\n$st');
      if (!mounted) return;
      setState(() {
        _entregas = const [];
        _entregasResumoDias = const [];
        _contagemAtrasadasCache = 0;
        _contagemPendentesHojeCache = 0;
        _vendedoresDisponiveis = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar entregas: $e')),
      );
    }
  }

  Future<void> _atualizarListaEntregas() async {
    if (_usaVendaApi) {
      try {
        await _vendaApiRepo.hidratarEntregas(limit: 500);
      } catch (_) {}
    }
    _carregarEntregas();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  void _alternarSelecaoEntrega(int vendaId) {
    setState(() {
      if (_idsEntregasSelecionadas.contains(vendaId)) {
        _idsEntregasSelecionadas.remove(vendaId);
      } else {
        _idsEntregasSelecionadas.add(vendaId);
      }
    });
  }

  Future<void> _confirmarAgrupamentoMesmoCarro() async {
    await _confirmarAgrupamentoIds(Set<int>.from(_idsEntregasSelecionadas));
  }

  Future<void> _confirmarAgrupamentoIds(Set<int> ids) async {
    if (ids.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos duas entregas para agrupar.'),
        ),
      );
      return;
    }
    final selecionadas = _entregas.where((v) => ids.contains(v.id)).toList();
    final nomesNasSelecionadas = selecionadas
        .map(nomeMotoristaEntrega)
        .where((n) => n != 'Nao definido')
        .toSet();
    final motoristaSugerido = nomesNasSelecionadas.length == 1
        ? nomesNasSelecionadas.first
        : null;
    if (!mounted) return;
    await _garantirMotoristasHidratados();
    if (!mounted) return;
    late final String? motorista;
    try {
      motorista = await showAgruparViagemMotoristaDialog(
        context,
        widget.motoristaRepository,
        motoristaSugerido: motoristaSugerido,
        vendasSelecionadas: selecionadas,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel escolher o motorista: $e')),
      );
      return;
    }
    if (motorista == null || motorista.isEmpty || !mounted) return;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.definirGrupoEntregaLogisticaRemoto(
          ids,
          motoristaEntrega: motorista,
        );
      } else {
        widget.vendaRepository.definirGrupoEntregaLogistica(
          ids,
          motoristaEntrega: motorista,
        );
      }
      await _carregarEntregasSyncState();
      if (!mounted) return;
      setState(() {
        _idsEntregasSelecionadas.clear();
        _modoAgruparMesmoCarro = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            agrupamentoTemClientesDistintos(selecionadas)
                ? 'Viagem agrupada (${selecionadas.length} pedidos, clientes diferentes). '
                      'Defina a ordem das paradas na rota.'
                : 'Pedidos agrupados na mesma viagem. '
                      'Defina a ordem das paradas na rota, se precisar.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _removerAgrupamentoSelecionadas() async {
    await _removerAgrupamentoIds(Set<int>.from(_idsEntregasSelecionadas));
  }

  Future<void> _removerAgrupamentoIds(Set<int> ids) async {
    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione as entregas para tirar do grupo.'),
        ),
      );
      return;
    }
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.limparGrupoEntregaLogisticaEmRemoto(ids);
      } else {
        widget.vendaRepository.limparGrupoEntregaLogisticaEm(ids);
      }
      await _carregarEntregasSyncState();
      if (!mounted) return;
      setState(() => _idsEntregasSelecionadas.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrupamento removido das selecionadas.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Mesma logica de [_carregarEntregas] sem segundo setState no fim (evita piscar).
  Future<void> _carregarEntregasSyncState() async {
    try {
      final filtroLista = _montarFiltroEntregas(usarPeriodoVendaNaLista: true);
      final filtroContagem = _montarFiltroEntregas(
        usarPeriodoVendaNaLista: false,
        paraContagemResumo: true,
      );
      final resultado = widget.vendaRepository.carregarListagemEntregasComResumo(
        filtroLista: filtroLista,
        filtroContagem: filtroContagem,
      );
      final resultadoResumoDias = widget.vendaRepository
          .carregarListagemEntregasComResumo(
            filtroLista: filtroContagem,
            filtroContagem: filtroContagem,
          );
      final entregas = (resultado.entregas as List).whereType<Venda>().toList();
      final resumoDias =
          (resultadoResumoDias.entregas as List).whereType<Venda>().toList();
      final vendedoresDisponiveis =
          (entregas
              .map(_nomeVendedor)
              .map((n) => n.trim())
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
      if (!mounted) return;
      setState(() {
        _entregas = entregas;
        _entregasResumoDias = resumoDias;
        _contagemAtrasadasCache = resultado.atrasadas as int? ?? 0;
        _contagemPendentesHojeCache = resultado.pendentesHoje as int? ?? 0;
        _vendedoresDisponiveis = vendedoresDisponiveis;
        if (_chaveDiaPlanejamentoSelecionado != null &&
            _filtroDataMarcada == 'todos') {
          final fmtPlanej = DateFormat('dd/MM/yyyy');
          final aindaExiste = entregas.any(
            (v) => _vendaNaChaveDiaPlanejamento(
              v,
              _chaveDiaPlanejamentoSelecionado!,
              fmtPlanej,
            ),
          );
          if (!aindaExiste) _chaveDiaPlanejamentoSelecionado = null;
        }
      });
    } catch (e, st) {
      debugPrint('EntregasPage._carregarEntregasSyncState: $e\n$st');
    }
  }

  Widget _conteudoRomaneioUmaVenda(
    BuildContext context,
    Venda venda,
    StateSetter setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)} · ${_nomeCliente(venda)}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 2),
        Text(
          'Bairro: ${_extrairBairro(venda)} · Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)} · '
          'Prioridade: ${_rotuloPrioridade(venda.prioridadeEntrega)}',
        ),
        Text('Motorista: ${_nomeMotorista(venda)}'),
        Text('Endereco: ${venda.enderecoEntrega}'),
        const SizedBox(height: 4),
        Text(
          'Itens:',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        ..._linhasItensEntrega(venda).map(
          (linha) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              '• $linha',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (venda.cargaSaiu)
          Text(
            'Saida ja liberada (estoque baixado). Proximo passo: Entregue.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          )
        else
          Text(
            'O motorista libera a saida no celular. Aqui acompanhe a rota '
            'e separe nesta loja so se ele pedir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _blocoRomaneioDoDia(
    BuildContext context,
    List<Venda> bloco,
    StateSetter setDialogState,
  ) {
    if (bloco.length >= 2 && bloco.first.grupoEntregaFreteId > 0) {
      final conf = _conferenciaCargaRepository;
      if (conf != null) {
        return _PainelRomaneioGrupoMesmoCarro(
          bloco: bloco,
          setDialogStateRomaneio: setDialogState,
          quantidadeItemEntrega: _quantidadeExibicaoEntrega,
          conteudoRomaneioUmaVenda: _conteudoRomaneioUmaVenda,
          escopoViagem: escopoViagemLogistica(bloco),
          conferenciaRepository: conf,
          usuarioAtual: widget.usuarioAtual,
          onConfirmarBuscarNaLoja: _confirmarBuscarNaLoja,
          obterProduto: _obterProdutoPorId,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in bloco) ...[
            _conteudoRomaneioUmaVenda(context, v, setDialogState),
            const SizedBox(height: 12),
          ],
        ],
      );
    }
    if (bloco.isEmpty) return const SizedBox.shrink();
    return _conteudoRomaneioUmaVenda(context, bloco.first, setDialogState);
  }

  Future<void> _abrirRomaneioVisual() async {
    final doDia = _entregasParaRomaneio();
    final blocosRom = blocosEntregaComCarretoAgrupado(doDia);
    final titulo = _rotuloPeriodoRomaneio();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Romaneio — $titulo'),
              content: SizedBox(
                width: 700,
                child: doDia.isEmpty
                    ? Text(_mensagemRomaneioVazio())
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: blocosRom.length,
                        separatorBuilder: (_, _) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          return _blocoRomaneioDoDia(
                            context,
                            blocosRom[index],
                            setDialogState,
                          );
                        },
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
  }

  List<Venda> _entregasDoDia(DateTime base) {
    return _entregas.where((v) {
      final d = v.dataEntregaMarcada?.toLocal();
      if (d == null) return false;
      return DateTime(d.year, d.month, d.day) == base;
    }).toList()..sort((a, b) {
      final pa = _pesoPrioridade(a.prioridadeEntrega);
      final pb = _pesoPrioridade(b.prioridadeEntrega);
      final byP = pb.compareTo(pa);
      if (byP != 0) return byP;
      return (a.janelaEntrega).compareTo(b.janelaEntrega);
    });
  }

  String _rotuloPeriodoRomaneio() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == 'Sem data marcada') return 'Sem data marcada';
    if (chave == null) {
      final n = DateTime.now();
      return DateFormat('dd/MM/yyyy').format(DateTime(n.year, n.month, n.day));
    }
    return chave;
  }

  List<Venda> _entregasParaRomaneio() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == 'Sem data marcada') {
      final lista = _entregas
          .where((v) => v.dataEntregaMarcada == null)
          .toList();
      lista.sort((a, b) {
        final pa = _pesoPrioridade(a.prioridadeEntrega);
        final pb = _pesoPrioridade(b.prioridadeEntrega);
        final byP = pb.compareTo(pa);
        if (byP != 0) return byP;
        return (a.janelaEntrega).compareTo(b.janelaEntrega);
      });
      return lista;
    }
    DateTime base;
    if (chave == null) {
      final n = DateTime.now();
      base = DateTime(n.year, n.month, n.day);
    } else {
      try {
        base = DateFormat('dd/MM/yyyy').parse(chave);
      } catch (_) {
        final n = DateTime.now();
        base = DateTime(n.year, n.month, n.day);
      }
    }
    return _entregasDoDia(base);
  }

  String _mensagemRomaneioVazio() {
    final chave = _chaveDiaPlanejamentoSelecionado;
    if (chave == 'Sem data marcada') {
      return 'Nao ha entregas sem data marcada na lista atual.';
    }
    if (chave == null) {
      return 'Nao ha entregas marcadas para hoje na lista atual.';
    }
    return 'Nao ha entregas marcadas para esta data na lista atual.';
  }

  List<String> _linhasItensEntrega(Venda venda) {
    final itens = _itensDaVenda(venda);
    if (itens.isEmpty) return const ['Sem itens cadastrados'];
    final linhas = itens
        .map((item) {
          final q = _quantidadeExibicaoEntrega(venda, item);
          if (q <= 0) return null;
          final tag = EntregaVendaHelper.abreviacaoTipoItem(
            item.tipoEntregaItem,
          );
          final qtdTxt = _textoQuantidadeExibicaoEntrega(venda, item);
          final un = RomaneioProdutoOrfaoHelper.unidadeSnapshot(
            item,
            obterProduto: _obterProdutoPorId,
          );
          final base = '$qtdTxt $un · ${item.nomeProduto} ($tag)';
          final lote = LoteFefoService.formatarRotuloRetiradaPatio(
            LoteConsumoSnapshot.decodeList(item.loteConsumosJson),
          );
          var linha = lote.isEmpty ? base : '$base\n  → $lote';
          if (_itemOrfaoNaCarga(item)) {
            linha =
                '$linha\n  ⚠ ${RomaneioProdutoOrfaoHelper.alertaProdutoNaoEncontrado}';
          }
          return linha;
        })
        .whereType<String>()
        .toList();
    return linhas.isEmpty ? const ['Sem itens para esta entrega'] : linhas;
  }

  pw.TextStyle _estiloPdfRomaneio({
    double fontSize = 10,
    bool negrito = false,
  }) {
    final f = pw.Font.courier();
    return pw.TextStyle(
      font: f,
      fontSize: fontSize,
      fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  pw.Widget _pdfRomaneioUmaEntrega(Venda venda, {int? parada}) {
    final cliente = _nomeCliente(venda);
    final dataMarcada = venda.dataEntregaMarcada == null
        ? 'Sem data'
        : DateFormat('dd/MM/yyyy').format(venda.dataEntregaMarcada!.toLocal());
    final endereco = enderecoExibicaoRomaneio(venda);
    final estilo = _estiloPdfRomaneio();
    final tituloPedido = parada != null && parada > 0
        ? 'Parada #$parada — ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)} - $cliente'
        : '${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)} - $cliente';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            tituloPedido,
            style: _estiloPdfRomaneio(fontSize: 10, negrito: true),
          ),
          pw.Text(
            'Bairro: ${_extrairBairro(venda)} | Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)} | Prioridade: ${_rotuloPrioridade(venda.prioridadeEntrega)}',
            style: estilo,
          ),
          pw.Text('Motorista: ${_nomeMotorista(venda)}', style: estilo),
          pw.Text('Vendedor: ${_nomeVendedor(venda)}', style: estilo),
          pw.Text('Data marcada: $dataMarcada', style: estilo),
          pw.Text(
            endereco.isEmpty
                ? 'Endereco: (nao informado)'
                : 'Endereco: $endereco',
            style: estilo,
          ),
          if (_observacaoSemMotorista(venda).trim().isNotEmpty)
            pw.Text('Obs: ${_observacaoSemMotorista(venda)}', style: estilo),
          if (_textoResumoComplementoNaVenda(venda) case final pend?)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                pend,
                style: _estiloPdfRomaneio(fontSize: 10, negrito: true),
              ),
            ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Itens:',
            style: _estiloPdfRomaneio(fontSize: 11, negrito: true),
          ),
          pw.SizedBox(height: 2),
          ..._linhasItensEntrega(venda).map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Text(
                '• $linha',
                style: _estiloPdfRomaneio(fontSize: 10.5, negrito: true),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '[${venda.cargaSeparada ? 'x' : ' '}] Separado    '
            '[${venda.cargaCarregada ? 'x' : ' '}] Carregado    '
            '[${venda.cargaSaiu ? 'x' : ' '}] Saiu',
            style: estilo.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfRomaneioUmaEntregaBobina(Venda venda, {int? parada}) {
    final cliente = _nomeCliente(venda);
    final dataMarcada = venda.dataEntregaMarcada == null
        ? 'Sem data'
        : DateFormat('dd/MM/yyyy').format(venda.dataEntregaMarcada!.toLocal());
    final endereco = enderecoExibicaoRomaneio(venda);
    const fsCorpo = 7.0;
    const fsTituloPedido = 8.0;
    const fsItens = 6.5;
    final estiloCorpo = _estiloPdfRomaneio(fontSize: fsCorpo);
    final tituloPedido = parada != null && parada > 0
        ? 'P#$parada ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)} $cliente'
        : '${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)} $cliente';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 5),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            tituloPedido,
            style: _estiloPdfRomaneio(fontSize: fsTituloPedido, negrito: true),
          ),
          pw.Text(
            '${_extrairBairro(venda)} · ${_rotuloJanelaEntrega(venda.janelaEntrega)} · ${_rotuloPrioridade(venda.prioridadeEntrega)}',
            style: estiloCorpo,
          ),
          pw.Text(
            'Mot: ${_nomeMotorista(venda)} · Vend: ${_nomeVendedor(venda)}',
            style: estiloCorpo,
          ),
          pw.Text('Data: $dataMarcada', style: estiloCorpo),
          pw.Text(
            endereco.isEmpty ? 'End: (nao informado)' : 'End: $endereco',
            style: estiloCorpo,
          ),
          if (_observacaoSemMotorista(venda).trim().isNotEmpty)
            pw.Text(
              'Obs: ${_observacaoSemMotorista(venda)}',
              style: estiloCorpo,
            ),
          if (_textoResumoComplementoNaVenda(venda) case final pendBob?)
            pw.Text(
              pendBob,
              style: _estiloPdfRomaneio(fontSize: fsCorpo, negrito: true),
            ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Itens',
            style: _estiloPdfRomaneio(fontSize: fsCorpo + 0.5, negrito: true),
          ),
          ..._linhasItensEntrega(venda).map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 0.5),
              child: pw.Text(
                '- $linha',
                style: _estiloPdfRomaneio(fontSize: fsItens, negrito: true),
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '[${venda.cargaSeparada ? 'x' : ' '}]Sep [${venda.cargaCarregada ? 'x' : ' '}]Carr [${venda.cargaSaiu ? 'x' : ' '}]Sai',
            style: estiloCorpo.copyWith(fontSize: 6.5),
          ),
        ],
      ),
    );
  }

  List<Venda> _entregasParaRomaneioComRelacoes() {
    return _entregasParaRomaneio()
        .map((v) => widget.vendaRepository.obterPorId(v.id) as Venda? ?? v)
        .toList();
  }

  Future<void> _abrirRelatoriosEntrega() async {
    final entregasDia = _entregasParaRomaneioComRelacoes();
    if (entregasDia.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemRomaneioVazio())));
      return;
    }
    final titulo = _rotuloPeriodoRomaneio();
    final motoristas = motoristasDistintosNasEntregas(entregasDia);
    final viagens = viagensAgrupadasNoDia(entregasDia);

    if (!mounted) return;
    var tipo = RelatorioEntregaTipo.romaneioMotoristaDia;
    var layoutEscolhido = RomaneioPdfLayout.a4;
    String? motoristaSel = motoristas.isNotEmpty ? motoristas.first : null;
    List<Venda>? viagemSel = viagens.isNotEmpty ? viagens.first : null;

    final escolha =
        await showDialog<
          ({
            RelatorioEntregaTipo tipo,
            RomaneioPdfLayout layout,
            String acao,
            String? motorista,
            List<Venda>? viagem,
          })?
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setLocal) {
              return AlertDialog(
                title: Text('Relatorios — $titulo'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tipo de relatorio',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        ...RelatorioEntregaTipo.values.map(
                          (t) => RadioListTile<RelatorioEntregaTipo>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.rotulo),
                            value: t,
                            groupValue: tipo,
                            onChanged: (v) {
                              if (v == null) return;
                              setLocal(() => tipo = v);
                            },
                          ),
                        ),
                        if (tipo.exigeMotorista) ...[
                          const SizedBox(height: 8),
                          if (motoristas.isEmpty)
                            Text(
                              'Nenhum motorista nas entregas. Defina ao agrupar ou no botao Motorista.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: motoristaSel,
                              decoration: const InputDecoration(
                                labelText: 'Motorista',
                              ),
                              items: motoristas
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setLocal(() => motoristaSel = v),
                            ),
                        ],
                        if (tipo.exigeViagem) ...[
                          const SizedBox(height: 8),
                          if (viagens.isEmpty)
                            const Text(
                              'Nenhuma viagem agrupada no periodo. Use "Agrupar mesmo carro".',
                            )
                          else
                            DropdownButtonFormField<int>(
                              initialValue:
                                  viagemSel?.first.grupoEntregaFreteId,
                              decoration: const InputDecoration(
                                labelText: 'Viagem (mesmo carro)',
                              ),
                              items: viagens
                                  .map(
                                    (bloco) => DropdownMenuItem(
                                      value: bloco.first.grupoEntregaFreteId,
                                      child: Text(rotuloGrupoLogistica(bloco)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (g) {
                                if (g == null) return;
                                setLocal(() {
                                  viagemSel = viagens.firstWhere(
                                    (b) => b.first.grupoEntregaFreteId == g,
                                  );
                                });
                              },
                            ),
                        ],
                        const Divider(height: 20),
                        Text(
                          'Formato do papel',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<RomaneioPdfLayout>(
                          segments: const [
                            ButtonSegment(
                              value: RomaneioPdfLayout.a4,
                              label: Text('A4'),
                            ),
                            ButtonSegment(
                              value: RomaneioPdfLayout.bobina80mm,
                              label: Text('80 mm'),
                            ),
                          ],
                          selected: {layoutEscolhido},
                          onSelectionChanged: (next) {
                            setLocal(() => layoutEscolhido = next.single);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, null),
                    child: const Text('Fechar'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _abrirRomaneioVisual();
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Visualizar na tela'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (tipo.exigeMotorista &&
                          (motoristaSel == null || motoristaSel!.isEmpty)) {
                        return;
                      }
                      if (tipo.exigeViagem && viagemSel == null) {
                        return;
                      }
                      Navigator.pop(dialogContext, (
                        tipo: tipo,
                        layout: layoutEscolhido,
                        acao: 'pdf',
                        motorista: motoristaSel,
                        viagem: viagemSel,
                      ));
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Exportar PDF'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (tipo.exigeMotorista &&
                          (motoristaSel == null || motoristaSel!.isEmpty)) {
                        return;
                      }
                      if (tipo.exigeViagem && viagemSel == null) {
                        return;
                      }
                      Navigator.pop(dialogContext, (
                        tipo: tipo,
                        layout: layoutEscolhido,
                        acao: 'imprimir',
                        motorista: motoristaSel,
                        viagem: viagemSel,
                      ));
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir'),
                  ),
                ],
              );
            },
          ),
        );
    if (!mounted || escolha == null) return;
    if (escolha.tipo.exigeMotorista &&
        (escolha.motorista == null || escolha.motorista!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Defina o motorista nas entregas ou selecione outro relatorio.',
          ),
        ),
      );
      return;
    }
    if (escolha.tipo.exigeViagem && escolha.viagem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma viagem agrupada para este relatorio.'),
        ),
      );
      return;
    }

    await _emitirRelatorioEntrega(
      tipo: escolha.tipo,
      motorista: escolha.motorista,
      viagem: escolha.viagem,
      layout: escolha.layout,
      salvarPdf: escolha.acao == 'pdf',
    );
  }

  Future<void> _emitirRelatorioEntrega({
    required RelatorioEntregaTipo tipo,
    String? motorista,
    List<Venda>? viagem,
    RomaneioPdfLayout layout = RomaneioPdfLayout.a4,
    required bool salvarPdf,
  }) async {
    final entregasDia = _entregasParaRomaneioComRelacoes();
    if (entregasDia.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemRomaneioVazio())));
      return;
    }
    final titulo = _rotuloPeriodoRomaneio();
    final emissao = DateTime.now();
    final bobina = layout == RomaneioPdfLayout.bobina80mm;
    final pdfBytes = await gerarRelatorioEntregaPdfBytes(
      tipo: tipo,
      entregasPeriodo: entregasDia,
      tituloPeriodo: titulo,
      emissao: emissao,
      layout: layout,
      motorista: motorista,
      viagem: viagem,
      pdfUmaEntrega: (v, {parada}) => bobina
          ? _pdfRomaneioUmaEntregaBobina(v, parada: parada)
          : _pdfRomaneioUmaEntrega(v, parada: parada),
      quantidadeEntrega: _quantidadeExibicaoEntrega,
    );
    if (!mounted) return;
    if (!salvarPdf) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
      return;
    }
    final arquivo = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio em PDF',
      fileName: nomeArquivoRelatorioEntrega(
        tipo: tipo,
        tituloPeriodo: titulo,
        motorista: motorista,
        bobina80: bobina,
      ),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (arquivo == null) return;
    final path = arquivo.toLowerCase().endsWith('.pdf')
        ? arquivo
        : '$arquivo.pdf';
    await File(path).writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Relatorio salvo em: $path')));
  }

  Future<void> _editarMotoristaGrupo(int grupoId, String atual) async {
    await _garantirMotoristasHidratados();
    if (!mounted) return;
    late final String? novo;
    try {
      novo = await showSelecionarMotoristaDialog(
        context,
        widget.motoristaRepository,
        titulo: 'Motorista da viagem',
        rotuloConfirmar: 'Salvar',
        motoristaSugerido: atual,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel escolher o motorista: $e')),
      );
      return;
    }
    if (novo == null || novo.isEmpty || !mounted) return;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.definirMotoristaEntregaNoGrupoRemoto(grupoId, novo);
      } else {
        widget.vendaRepository.definirMotoristaEntregaNoGrupo(grupoId, novo);
      }
      await _carregarEntregasSyncState();
      final idsGrupo = _entregas
          .where((v) => v.grupoEntregaFreteId == grupoId)
          .map((v) => v.id);
      await _autoRoteirizarIdsAposMotorista(idsGrupo);
      if (mounted) await _carregarEntregasSyncState();
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  int _pesoPrioridade(String prioridade) {
    switch (prioridade) {
      case 'urgente':
        return 3;
      case 'agendada':
        return 2;
      case 'normal':
      default:
        return 1;
    }
  }

  String _rotuloPrioridade(String prioridade) {
    switch (prioridade) {
      case 'urgente':
        return 'Urgente';
      case 'agendada':
        return 'Agendada';
      case 'normal':
      default:
        return 'Normal';
    }
  }

  String _rotuloJanelaEntrega(String janela) {
    switch (janela) {
      case 'manha':
        return 'Manha';
      case 'tarde':
        return 'Tarde';
      case 'nao_definida':
      default:
        return 'Nao definida';
    }
  }

  String _extrairBairro(Venda venda) {
    final endereco = venda.enderecoEntrega.trim();
    if (endereco.isEmpty) return 'Sem bairro';
    final partesPipe = endereco
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partesPipe.length >= 2) return partesPipe[1];
    final partesVirgula = endereco
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partesVirgula.length >= 2) return partesVirgula[1];
    return partesPipe.isNotEmpty ? partesPipe.first : 'Sem bairro';
  }

  String _nomeMotorista(Venda venda) => nomeMotoristaEntrega(venda);

  String _nomeVendedor(Venda venda) {
    return VendaRelacaoSafe.nomeVendedor(
      venda,
      vendedorRepository: widget.vendedorRepository,
    );
  }

  String _nomeCliente(Venda venda) {
    final deps = MainMenuDeps.maybeOf(context);
    return VendaRelacaoSafe.nomeCliente(
      venda,
      clienteRepository: deps?.clienteRepository,
    );
  }

  String _enderecoCompletoParaNavegacao(Venda venda) =>
      enderecoExibicaoRomaneio(venda);

  Future<void> _abrirNavegacaoParaEntrega(Venda venda) async {
    final endereco = _enderecoCompletoParaNavegacao(venda);
    if (endereco.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha endereco de entrega para abrir no mapa.'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}',
    );
    final url = uri.toString();

    // No Windows, url_launcher_windows ainda pode lancar PlatformException
    // em alguns builds. Abrir via rundll32 usa o navegador padrao sem o plugin.
    if (Platform.isWindows) {
      try {
        final r = await Process.run('rundll32', [
          'url.dll,FileProtocolHandler',
          url,
        ]);
        if (r.exitCode == 0) return;
      } catch (_) {
        // segue para launchUrl
      }
    }

    try {
      var ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!ok) {
        ok = await launchUrl(uri);
      }
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel abrir o mapa no navegador padrao.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao abrir mapa: $e')));
    }
  }

  Future<void> _swapParadasMesmoCarro(
    int grupoId,
    List<Venda> ordenado,
    int indiceA,
    int indiceB,
  ) async {
    if (indiceA == indiceB) return;
    if (indiceA < 0 ||
        indiceB < 0 ||
        indiceA >= ordenado.length ||
        indiceB >= ordenado.length) {
      return;
    }
    final nova = List<Venda>.from(ordenado);
    final tmp = nova[indiceA];
    nova[indiceA] = nova[indiceB];
    nova[indiceB] = tmp;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarSequenciaEntregaNoGrupoRemoto(
          grupoId,
          nova.map((x) => x.id).toList(),
        );
      } else {
        widget.vendaRepository.atualizarSequenciaEntregaNoGrupo(
          grupoId,
          nova.map((x) => x.id).toList(),
        );
      }
      await _carregarEntregasSyncState();
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _swapParadasMotoristaDia(
    String motorista,
    List<Venda> ordenado,
    int indiceA,
    int indiceB,
  ) async {
    if (indiceA == indiceB) return;
    if (indiceA < 0 ||
        indiceB < 0 ||
        indiceA >= ordenado.length ||
        indiceB >= ordenado.length) {
      return;
    }
    final nova = List<Venda>.from(ordenado);
    final tmp = nova[indiceA];
    nova[indiceA] = nova[indiceB];
    nova[indiceB] = tmp;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarSequenciaEntregaMotoristaRemoto(
          motorista,
          nova.map((x) => x.id).toList(),
        );
      } else {
        widget.vendaRepository.atualizarSequenciaEntregaMotorista(
          motorista,
          nova.map((x) => x.id).toList(),
        );
      }
      await _carregarEntregasSyncState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ordem da rota do motorista atualizada.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _observacaoSemMotorista(Venda venda) {
    if (venda.motoristaEntrega.trim().isNotEmpty) {
      return venda.observacaoEntrega.trim();
    }
    final linhas = venda.observacaoEntrega
        .split('\n')
        .map((linha) => linha.trimRight())
        .where((linha) => linha.trim().isNotEmpty)
        .where((linha) => !linha.trimLeft().startsWith('Motorista:'))
        .toList();
    return linhas.join('\n');
  }

  Future<void> _atualizarPrioridade(Venda venda, String novaPrioridade) async {
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarPrioridadeEntregaRemoto(
          venda.id,
          novaPrioridade,
        );
      } else {
        widget.vendaRepository.atualizarPrioridadeEntrega(
          venda.id,
          novaPrioridade,
        );
      }
      _carregarEntregas();
    } on LanApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prioridade: ${e.message}')),
      );
    }
  }

  Future<void> _definirMotoristaEmLoteIds(Set<int> ids) async {
    if (ids.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma entrega selecionada.')),
      );
      return;
    }
    await _garantirMotoristasHidratados();
    if (!mounted) return;
    final motorista = await showSelecionarMotoristaDialog(
      context,
      widget.motoristaRepository,
      titulo: 'Motorista das entregas',
      rotuloConfirmar: 'Aplicar',
      textoAuxiliar:
          'O mesmo motorista sera gravado em ${ids.length} pedido(s).',
    );
    if (motorista == null || motorista.isEmpty || !mounted) return;
    try {
      final n = _usaVendaApi
          ? await _vendaApiRepo.atualizarMotoristaEntregaEmLoteRemoto(
              ids,
              motorista,
            )
          : widget.vendaRepository.atualizarMotoristaEntregaEmLote(
              ids,
              motorista,
            );
      await _carregarEntregasSyncState();
      await _autoRoteirizarIdsAposMotorista(ids);
      if (mounted) await _carregarEntregasSyncState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Motorista definido em $n entrega(s).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : 'Erro ao definir motorista: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _editarMotoristaEntrega(Venda venda) async {
    if (!mounted) return;
    await _garantirMotoristasHidratados();
    if (!mounted) return;
    late final String? nome;
    try {
      nome = await showSelecionarMotoristaDialog(
        context,
        widget.motoristaRepository,
        titulo: 'Motorista ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)}',
        rotuloConfirmar: 'Salvar',
        motoristaSugerido: venda.motoristaEntrega,
        permitirLimpar: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel escolher o motorista: $e')),
      );
      return;
    }
    if (nome == null) return;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarMotoristaEntregaRemoto(venda.id, nome);
      } else {
        widget.vendaRepository.atualizarMotoristaEntrega(venda.id, nome);
      }
      venda.motoristaEntrega = nome;
      if (nome.trim().isNotEmpty) {
        await _autoRoteirizarAposMotorista(venda);
      }
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nome.trim().isEmpty
                ? 'Motorista removido.'
                : 'Motorista atualizado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : 'Erro ao atualizar motorista: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Future<void> _marcarOuAlterarDataEntrega(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final marcada = venda.dataEntregaMarcada?.toLocal();
    final inicial = marcada != null
        ? DateTime(marcada.year, marcada.month, marcada.day)
        : hoje;
    final escolhido = await showDatePicker(
      context: context,
      initialDate: inicial.isBefore(hoje) ? hoje : inicial,
      firstDate: DateTime(agora.year - 1, 1, 1),
      lastDate: DateTime(agora.year + 3, 12, 31),
    );
    if (!mounted || escolhido == null) return;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarDataEntregaMarcadaRemoto(
          venda.id,
          escolhido,
        );
      } else {
        widget.vendaRepository.atualizarDataEntregaMarcada(venda.id, escolhido);
      }
      _carregarEntregas();
      if (!mounted) return;
      final fmt = DateFormat('dd/MM/yyyy');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Data da entrega definida: ${fmt.format(escolhido)}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : 'Erro ao salvar data: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _limparDataEntregaMarcada(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    if (venda.dataEntregaMarcada == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar data de entrega'),
        content: Text(
          'Remover a data marcada da venda ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmar != true) return;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarDataEntregaMarcadaRemoto(venda.id, null);
      } else {
        widget.vendaRepository.atualizarDataEntregaMarcada(venda.id, null);
      }
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data da entrega removida.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is LanApiException ? e.message : 'Erro ao limpar data: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _aplicarPeriodoMarcadasParaHoje() {
    setState(() {
      _filtrosDropdownNonce++;
      _inicio = null;
      _fim = null;
      _filtroDataMarcada = 'hoje';
      _chaveDiaPlanejamentoSelecionado = PlanejamentoEntregaDia.chaveDeDateTime(
        DateTime.now(),
      );
      _filtroApenasSemMotorista = false;
    });
    _carregarEntregas();
  }

  /// Volta filtros, periodo e texto de busca ao padrao amplo ("Todos" em tudo aplicavel).
  void _redefinirFiltrosPadrao() {
    setState(() {
      _filtrosDropdownNonce++;
      _filtroResumoLista = _FiltroResumoEntregas.nenhum;
      _chaveDiaPlanejamentoSelecionado = PlanejamentoEntregaDia.chaveDeDateTime(
        DateTime.now(),
      );
      _statusSelecionado = 'todos';
      _filtroMotorista = 'todos';
      _filtroVendedor = 'todos';
      _agrupamento = 'motorista';
      _filtroDataMarcada = 'hoje';
      _filtroApenasSemMotorista = false;
      _bairroController.clear();
      _numeroNotaController.clear();
      _modoAgruparMesmoCarro = false;
      _idsEntregasSelecionadas.clear();
      _inicio = null;
      _fim = null;
    });
    _carregarEntregas();
  }

  Future<void> _selecionarPeriodoPersonalizado() async {
    final agora = DateTime.now();
    final inicioAtual = _inicio ?? DateTime(agora.year, agora.month, agora.day);
    final fimAtual = _fim ?? agora;
    final intervalo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: DateTime(inicioAtual.year, inicioAtual.month, inicioAtual.day),
        end: DateTime(fimAtual.year, fimAtual.month, fimAtual.day),
      ),
      helpText: 'Periodo personalizado',
      saveText: 'Aplicar',
    );
    if (intervalo == null) return;
    setState(() {
      _filtrosDropdownNonce++;
      _filtroDataMarcada = 'todos';
      _inicio = DateTime(
        intervalo.start.year,
        intervalo.start.month,
        intervalo.start.day,
      );
      _fim = DateTime(
        intervalo.end.year,
        intervalo.end.month,
        intervalo.end.day,
        23,
        59,
        59,
        999,
      );
    });
    _carregarEntregas();
  }

  String _rotuloPeriodoSelecionado() {
    if (_inicio == null && _fim == null) {
      if (_filtroDataMarcada == 'hoje') {
        return 'Marcadas para hoje';
      }
      return 'Periodo: todos';
    }
    final fmt = DateFormat('dd/MM/yyyy');
    return 'Periodo: ${fmt.format(_inicio!.toLocal())} ate ${fmt.format(_fim!.toLocal())}';
  }

  bool _transicaoStatusPermitida(String atual, String novo) {
    if (atual == novo) return true;
    if (atual == 'entregue' || atual == 'cancelada') return false;

    if (atual == 'entregue_complemento_pendente') {
      if (novo == 'entregue') return true;
      if (novo == 'reagendada' || novo == 'cancelada') return true;
      if (novo == 'pendente') return true;
      return false;
    }

    if (novo == 'entregue_complemento_pendente') {
      return atual == 'saiu_entrega';
    }

    if (novo == 'reagendada' || novo == 'cancelada') return true;
    const ordem = {
      'pendente': 0,
      'roteirizada': 1,
      'saiu_entrega': 2,
      'entregue': 3,
    };
    final iAtual = ordem[atual];
    final iNovo = ordem[novo];
    if (iAtual == null || iNovo == null) return true;
    return iNovo == iAtual + 1 || (iNovo == 0 && atual == 'reagendada');
  }

  String _mensagemBloqueioTransicao(String atual, String novo) {
    return 'Nao foi possivel mudar de "${_rotuloStatusEntrega(atual)}" para '
        '"${_rotuloStatusEntrega(novo)}". Fluxo normal: Pendente -> '
        'Saiu -> Entregue. Com falta na ida: em "Saiu" use "Faltou item" para registrar '
        'complemento pendente; depois "Concluir complemento" ou reabrir rota (Pendente).';
  }

  bool _checklistPodeAtualizar(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    final novoSeparado = separado ?? venda.cargaSeparada;
    final novoCarregado = carregado ?? venda.cargaCarregada;
    final novoSaiu = saiu ?? venda.cargaSaiu;
    if (novoCarregado && !novoSeparado) return false;
    if (novoSaiu && (!novoSeparado || !novoCarregado)) return false;
    return true;
  }

  String _mensagemChecklistInvalido() {
    return 'Siga a sequencia do checklist: Separado -> Carregado -> Saiu.';
  }

  String _mensagemSemPermissaoStatus() {
    return 'Seu perfil nao possui permissao para alterar status de entrega.';
  }

  Future<void> _abrirHistoricoEntrega(Venda venda) async {
    List historico;
    if (_usaVendaApi) {
      try {
        historico = await _vendaApiRepo.listarHistoricoEntregaRemoto(venda.id);
      } catch (e) {
        if (!mounted) return;
        final msg = e is LanApiException ? e.message : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Historico: $msg')),
        );
        return;
      }
    } else {
      historico = widget.vendaRepository.listarHistoricoEntrega(venda.id);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Historico da entrega ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)}',
          ),
          content: SizedBox(
            width: 620,
            child: historico.isEmpty
                ? const Text('Sem movimentacoes registradas.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: historico.length,
                    separatorBuilder: (_, _) => const Divider(height: 8),
                    itemBuilder: (context, index) {
                      final item = historico[index];
                      final evento = HistoricoEntregaEventos.ehEventoOcorrencia(
                        item.statusNovo,
                      );
                      final quando =
                          '${DateFormat('dd/MM/yyyy HH:mm').format(item.dataHora.toLocal())} · ${item.usuario}';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          evento
                              ? _rotuloStatusEntrega(item.statusNovo)
                              : '${_rotuloStatusEntrega(item.statusAnterior)} -> ${_rotuloStatusEntrega(item.statusNovo)}',
                        ),
                        subtitle: Text(
                          evento && item.statusAnterior.trim().isNotEmpty
                              ? '$quando\n${HistoricoEntregaEventos.textoDetalhe(item.statusNovo, item.statusAnterior)}'
                              : quando,
                        ),
                      );
                    },
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

  String? _textoResumoComplementoNaVenda(Venda venda, [String? jsonBruto]) {
    final linhas = ComplementoEntregaCodec.decode(
      jsonBruto ?? venda.complementoEntregaJson,
    );
    if (linhas.isEmpty) return null;
    final partes = linhas
        .map((l) => '${l.quantidade}x ${l.nomeProduto}')
        .toList();
    return 'Falta na ida: ${partes.join('; ')}';
  }

  Future<bool> _atualizarStatusEntrega(
    Venda venda,
    String novoStatus, {
    String? complementoEntregaJson,
    String? notaComplementoExtra,
    bool mostrarSnackSucesso = true,
  }) async {
    try {
      if (!widget.podeGerenciarStatusEntrega) {
        if (!mounted) return false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
        return false;
      }
      final statusAnterior = venda.statusEntrega;
      if (!_transicaoStatusPermitida(statusAnterior, novoStatus)) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mensagemBloqueioTransicao(statusAnterior, novoStatus),
            ),
          ),
        );
        return false;
      }
      if ((novoStatus == 'entregue' ||
              novoStatus == 'entregue_complemento_pendente') &&
          _progressoCarga(venda) < 3) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checklist de carga incompleto. Finalize Separado, Carregado e Saiu antes de entregar.',
            ),
          ),
        );
        return false;
      }
      if (novoStatus == 'entregue_complemento_pendente') {
        final j = complementoEntregaJson?.trim() ?? '';
        if (j.isEmpty) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Informe pelo menos um item em falta para registrar complemento pendente.',
              ),
            ),
          );
          return false;
        }
      }
      String? motivo;
      var retornouParaLoja = false;
      if (novoStatus == 'reagendada' || novoStatus == 'cancelada') {
        final pedido = await _solicitarMotivoMudancaStatus(novoStatus);
        if (pedido == null) return false;
        motivo = pedido.motivo;
        retornouParaLoja = pedido.retornouParaLoja;
        if (novoStatus == 'reagendada') {
          motivo = retornouParaLoja
              ? '$motivo. Carga retornou para a loja.'
              : '$motivo. Carga permanece no caminhao.';
        }
      }
      final podComplemento = statusAnterior == 'entregue_complemento_pendente';
      if (EntregaPodRegra.deveSolicitarPod(
        novoStatus: novoStatus,
        statusAnterior: statusAnterior,
        podRecebidoPorAtual: venda.podRecebidoPor,
      )) {
        final pod = await showPodEntregaDialog(
          context: context,
          vendaId: venda.id,
          recebidoPorInicial: podComplemento ? '' : venda.podRecebidoPor.trim(),
          podComplemento: podComplemento,
          origemMercadoriaRotulo: _rotuloOrigemMercadoria(venda),
        );
        if (pod == null) return false;
        final podFinal = EntregaPodFinalizacao(
          configRepository: widget.configuracoesService?.repository,
        );
        await podFinal.registrarPod(
          vendaRepository: widget.vendaRepository,
          vendaId: venda.id,
          recebidoPor: pod.recebidoPor,
          usuarioLogin: widget.usuarioAtual,
          fotoPathLocal: pod.fotoPathLocal ?? '',
          fotoPathServidor: pod.fotoPathServidor ?? '',
        );
        final atualizada = widget.vendaRepository.obterPorId(venda.id);
        venda.podRecebidoPor = pod.recebidoPor;
        venda.podFotoPath = atualizada?.podFotoPath ?? pod.fotoPathLocal ?? '';
        venda.podFotoPathServidor =
            atualizada?.podFotoPathServidor ?? pod.fotoPathServidor ?? '';
      }
      if (widget.vendaRepository is VendaApiRepository) {
        final api = widget.vendaRepository as VendaApiRepository;
        await api.atualizarStatusEntregaRemoto(
          venda.id,
          novoStatus,
          complementoEntregaJson: complementoEntregaJson,
          retornouParaLoja: retornouParaLoja,
        );
        await api.registrarHistoricoStatusEntregaRemoto(
          vendaId: venda.id,
          statusAnterior: statusAnterior,
          statusNovo: novoStatus,
          usuario: widget.usuarioAtual,
        );
      } else {
        widget.vendaRepository.atualizarStatusEntrega(
          venda.id,
          novoStatus,
          complementoEntregaJson: complementoEntregaJson,
          retornouParaLoja: retornouParaLoja,
        );
        widget.vendaRepository.registrarHistoricoStatusEntrega(
          vendaId: venda.id,
          statusAnterior: statusAnterior,
          statusNovo: novoStatus,
          usuario: widget.usuarioAtual,
        );
      }
      if (novoStatus == 'entregue' && venda.podRecebidoPor.trim().isNotEmpty) {
        final comFoto = EntregaPodRegra.temReferenciaFoto(
          podFotoPath: venda.podFotoPath,
          podFotoPathServidor: venda.podFotoPathServidor,
        );
        final prefixo = podComplemento ? 'Complemento — ' : '';
        final motivoPod =
            '${prefixo}Recebido por: ${venda.podRecebidoPor.trim()}${comFoto ? ' (com foto)' : ''}';
        if (widget.vendaRepository is VendaApiRepository) {
          await (widget.vendaRepository as VendaApiRepository)
              .registrarOcorrenciaEntregaRemoto(
            vendaId: venda.id,
            status: HistoricoEntregaEventos.podEntrega,
            motivo: motivoPod,
            usuario: widget.usuarioAtual,
          );
        } else {
          widget.vendaRepository.registrarOcorrenciaEntrega(
            vendaId: venda.id,
            status: HistoricoEntregaEventos.podEntrega,
            motivo: motivoPod,
            usuario: widget.usuarioAtual,
          );
        }
      }
      if (motivo != null) {
        if (widget.vendaRepository is VendaApiRepository) {
          await (widget.vendaRepository as VendaApiRepository)
              .registrarOcorrenciaEntregaRemoto(
            vendaId: venda.id,
            status: novoStatus,
            motivo: motivo,
            usuario: widget.usuarioAtual,
          );
        } else {
          widget.vendaRepository.registrarOcorrenciaEntrega(
            vendaId: venda.id,
            status: novoStatus,
            motivo: motivo,
            usuario: widget.usuarioAtual,
          );
        }
      }
      if (novoStatus == 'entregue_complemento_pendente' &&
          complementoEntregaJson != null) {
        var resumo = _textoResumoComplementoNaVenda(
          venda,
          complementoEntregaJson.trim(),
        );
        if (notaComplementoExtra != null &&
            notaComplementoExtra.trim().isNotEmpty) {
          final extra = notaComplementoExtra.trim();
          resumo = resumo == null ? 'Obs: $extra' : '$resumo | Obs: $extra';
        }
        if (resumo != null) {
          if (widget.vendaRepository is VendaApiRepository) {
            await (widget.vendaRepository as VendaApiRepository)
                .registrarOcorrenciaEntregaRemoto(
              vendaId: venda.id,
              status: HistoricoEntregaEventos.complementoPendente,
              motivo: resumo,
              usuario: widget.usuarioAtual,
            );
          } else {
            widget.vendaRepository.registrarOcorrenciaEntrega(
              vendaId: venda.id,
              status: HistoricoEntregaEventos.complementoPendente,
              motivo: resumo,
              usuario: widget.usuarioAtual,
            );
          }
        }
      }
      _carregarEntregas();
      if (!mounted) return false;
      if (mostrarSnackSucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status de entrega atualizado.')),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar status: $e')));
      return false;
    }
  }

  Future<({String motivo, bool retornouParaLoja})?>
      _solicitarMotivoMudancaStatus(String novoStatus) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    var retornouParaLoja = false;
    final confirmarReagendada = novoStatus == 'reagendada';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            'Motivo da ${_rotuloStatusEntrega(novoStatus).toLowerCase()}',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Motivo (obrigatorio)',
                      hintText: 'Descreva o motivo desta alteracao',
                    ),
                  ),
                  if (confirmarReagendada) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Mercadoria',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: !retornouParaLoja,
                      title: const Text('Permanece no caminhao'),
                      leading: Icon(
                        !retornouParaLoja
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: () => setLocal(() => retornouParaLoja = false),
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: retornouParaLoja,
                      title: const Text('Voltou para a loja'),
                      subtitle: const Text(
                        'Estorna a saida de estoque do carreto.',
                      ),
                      leading: Icon(
                        retornouParaLoja
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: () => setLocal(() => retornouParaLoja = true),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    final texto = controller.text.trim();
    controller.dispose();
    if (ok != true || texto.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Motivo obrigatorio para reagendar ou cancelar entrega.',
          ),
        ),
      );
      return null;
    }
    return (motivo: texto, retornouParaLoja: retornouParaLoja);
  }

  Future<void> _confirmarConcluirComplemento(Venda venda) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Concluir complemento ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)}',
        ),
        content: const Text(
          'Confirma que os itens em falta ja foram entregues ao cliente? '
          'O status passara para Entregue e o registro de complemento sera limpo. '
          'No carreto com reserva ate a saida, o estoque baixa de novo pelas '
          'quantidades do complemento (segunda viagem).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _atualizarStatusEntrega(venda, 'entregue');
  }

  Future<void> _abrirDialogRegistrarComplemento(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return;
    }
    if (venda.statusEntrega != 'saiu_entrega') return;
    if (_progressoCarga(venda) < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checklist de carga incompleto. Finalize Separado, Carregado e Saiu antes.',
          ),
        ),
      );
      return;
    }
    final itens = _itensDaVenda(venda)
        .where((i) => _quantidadeExibicaoEntrega(venda, i) > 0)
        .toList();
    if (itens.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha itens de entrega neste pedido.')),
      );
      return;
    }
    final controllers = <int, TextEditingController>{
      for (final i in itens) i.id: TextEditingController(text: '0'),
    };
    final obsCtrl = TextEditingController();
    if (!mounted) return;
    final jsonResult = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Faltou item na ida — ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Informe quantas unidades faltaram na ida para cada linha. '
                    'Pelo menos um item deve ter falta maior que zero. '
                    'No carreto com reserva ate a saida, o estoque fisico e reservado '
                    'serao ajustados (volta o que nao saiu na ida).',
                  ),
                  const SizedBox(height: 10),
                  for (final item in itens) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${_textoQuantidadeExibicaoEntrega(venda, item)}x ${item.nomeProduto}',
                          ),
                        ),
                        SizedBox(
                          width: 76,
                          child: TextField(
                            controller: controllers[item.id],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Falta',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: obsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observacao (opcional)',
                      hintText: 'Ex.: cliente aceitou aguardar segunda ida',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final linhas = <LinhaComplementoEntrega>[];
                for (final item in itens) {
                  final raw = controllers[item.id]?.text.trim() ?? '';
                  final f = int.tryParse(raw) ?? 0;
                  final max = _quantidadeExibicaoEntrega(venda, item);
                  if (f < 0 || f > max) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Quantidade invalida para "${item.nomeProduto}" '
                          '(maximo $max).',
                        ),
                      ),
                    );
                    return;
                  }
                  if (f > 0) {
                    linhas.add(
                      LinhaComplementoEntrega(
                        itemVendaId: item.id,
                        quantidade: f,
                        nomeProduto: item.nomeProduto,
                      ),
                    );
                  }
                }
                if (linhas.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Informe falta em pelo menos um item (valor maior que zero).',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  ComplementoEntregaCodec.encode(linhas),
                );
              },
              child: const Text('Registrar complemento pendente'),
            ),
          ],
        );
      },
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    final obsExtra = obsCtrl.text.trim();
    obsCtrl.dispose();
    if (jsonResult == null || jsonResult.trim().isEmpty || !mounted) return;
    await _atualizarStatusEntrega(
      venda,
      'entregue_complemento_pendente',
      complementoEntregaJson: jsonResult,
      notaComplementoExtra: obsExtra.isEmpty ? null : obsExtra,
    );
  }

  Future<bool> _permitirVendaSemEstoqueAtual() async {
    final svc = widget.configuracoesService;
    if (svc == null) return true;
    try {
      final cfg = await svc.carregarEfetiva();
      return cfg.permitirVendaSemEstoque;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _atualizarChecklistCarga(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
    bool forcarSaidaRomaneio = false,
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
  }) async {
    try {
      if (!_checklistPodeAtualizar(
        venda,
        separado: separado,
        carregado: carregado,
        saiu: saiu,
      )) {
        if (!mounted) return false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mensagemChecklistInvalido())));
        return false;
      }
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarChecklistCargaEntregaRemoto(
          venda.id,
          separado: separado,
          carregado: carregado,
          saiu: saiu,
          forcarSaidaRomaneio: forcarSaidaRomaneio,
          lojaOrigemMercadoria: lojaOrigemMercadoria,
          origemPorItem: origemPorItem,
          usuario: widget.usuarioAtual,
        );
      } else {
        widget.vendaRepository.atualizarChecklistCargaEntrega(
          venda.id,
          separado: separado,
          carregado: carregado,
          saiu: saiu,
          permitirVendaSemEstoque: await _permitirVendaSemEstoqueAtual(),
          forcarSaidaRomaneio: forcarSaidaRomaneio,
          lojaOrigemMercadoria: lojaOrigemMercadoria,
          origemPorItem: origemPorItem,
          usuario: widget.usuarioAtual,
        );
      }
      // Atualiza flags locais imediatamente (evita flicker antes do hidratar).
      if (separado != null) venda.cargaSeparada = separado;
      if (carregado != null) venda.cargaCarregada = carregado;
      if (saiu != null) venda.cargaSaiu = saiu;
      if (lojaOrigemMercadoria != null) {
        venda.lojaOrigemMercadoria =
            LojaOrigemMercadoria.normalizar(lojaOrigemMercadoria);
      }
      if (origemPorItem != null && origemPorItem.isNotEmpty) {
        for (final item in _itensDaVenda(venda)) {
          if (!origemPorItem.containsKey(item.id)) continue;
          item.lojaOrigemMercadoria =
              LojaOrigemMercadoria.normalizar(origemPorItem[item.id]);
        }
        venda.lojaOrigemMercadoria = LojaOrigemMercadoria.resumo(
          _itensDaVenda(venda).map(
            (i) => LojaOrigemMercadoria.origemEfetiva(
              origemItem: i.lojaOrigemMercadoria,
              origemVenda: venda.lojaOrigemMercadoria,
            ),
          ),
        );
      }
      if (mounted) setState(() {});
      return true;
    } on LanApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checklist: ${e.message}')),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      if (saiu == true && CarretoChecklistEstoqueHelper.ehErroAoMarcarSaiu(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(CarretoChecklistEstoqueHelper.mensagemResumida(e)),
            action: SnackBarAction(
              label: 'Detalhes',
              onPressed: () => _mostrarErroChecklistSaiu(venda, e),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar checklist: $e')),
      );
      return false;
    }
  }

  String _rotuloOrigemMercadoria(Venda venda) {
    return LojaOrigemMercadoria.rotulo(venda.lojaOrigemMercadoria);
  }

  Future<void> _confirmarBuscarNaLoja(int vendaId, List<int> itemIds) async {
    if (itemIds.isEmpty) return;
    try {
      if (_usaVendaApi) {
        await _vendaApiRepo.atualizarBuscarNaLojaRemoto(
          vendaId: vendaId,
          acao: BuscarNaLoja.confirmar,
          itemIds: itemIds,
          usuario: widget.usuarioAtual,
        );
      } else {
        widget.vendaRepository.atualizarBuscarNaLoja(
          vendaId,
          acao: BuscarNaLoja.confirmar,
          itemIds: itemIds,
          usuario: widget.usuarioAtual,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material marcado para sair desta loja.')),
      );
      _carregarEntregas();
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Separar nesta loja');
    }
  }

  /// Marca Separado+Carregado+Saiu (baixa estoque) e status `saiu_entrega`.
  Future<bool> _liberarSaidaEntrega(
    Venda venda, {
    bool mostrarSnackSucesso = true,
    bool forcarSaidaRomaneio = false,
    String? lojaOrigemMercadoria,
    Map<int, String>? origemPorItem,
  }) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensagemSemPermissaoStatus())));
      return false;
    }
    if (!EntregaFluxoService.podeLiberarSaida(venda)) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nao e possivel liberar saida a partir de '
            '"${_rotuloStatusEntrega(venda.statusEntrega)}".',
          ),
        ),
      );
      return false;
    }

    var origem = lojaOrigemMercadoria;
    var origensItem = origemPorItem;
    origensItem ??= {
      for (final i in _itensDaVenda(venda))
        if (i.id > 0)
          i.id: LojaOrigemMercadoria.origemEfetiva(
            origemItem: i.lojaOrigemMercadoria,
            origemVenda: venda.lojaOrigemMercadoria,
          ),
    };
    origem ??= LojaOrigemMercadoria.resumo(origensItem.values);

    final okChecklist = await _atualizarChecklistCarga(
      venda,
      separado: true,
      carregado: true,
      saiu: true,
      forcarSaidaRomaneio: forcarSaidaRomaneio,
      lojaOrigemMercadoria: origem,
      origemPorItem: origensItem,
    );
    if (!okChecklist) return false;

    var atual = widget.vendaRepository.obterPorId(venda.id) ?? venda;
    if (atual.statusEntrega == 'pendente' ||
        atual.statusEntrega == 'reagendada') {
      final okRota = await _atualizarStatusEntrega(
        atual,
        'roteirizada',
        mostrarSnackSucesso: false,
      );
      if (!okRota) return false;
      atual = widget.vendaRepository.obterPorId(venda.id) ?? atual;
    }

    if (atual.statusEntrega == 'roteirizada') {
      final okSaiu = await _atualizarStatusEntrega(
        atual,
        'saiu_entrega',
        mostrarSnackSucesso: false,
      );
      if (!okSaiu) return false;
    }

    if (mostrarSnackSucesso && mounted) {
      if (forcarSaidaRomaneio) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saida forcada — romaneio liberado sem validar reserva de estoque. '
              'Consulte o historico da entrega.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
        return true;
      }
      final origemTxt = LojaOrigemMercadoria.ehLocal(venda.lojaOrigemMercadoria)
          ? 'estoque desta loja baixado'
          : LojaOrigemMercadoria.ehMisto(venda.lojaOrigemMercadoria)
              ? 'origem mista (baixa fisica so nos itens desta loja)'
              : 'outra loja (sem baixa fisica local)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saida liberada — ${VendaDocumentoRotuloHelper.rotuloPedidoEntrega(venda)} em rota ($origemTxt).',
          ),
        ),
      );
    }
    return true;
  }

  Future<bool> _forcarSaidaRomaneioEntrega(Venda venda) async {
    if (!widget.podeGerenciarStatusEntrega) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensagemSemPermissaoStatus())),
      );
      return false;
    }
    if (!EntregaFluxoService.podeLiberarSaida(venda) && venda.cargaSaiu) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este pedido ja consta como saido.')),
      );
      return false;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forcar saida do romaneio?'),
        content: Text(
          '${VendaDocumentoRotuloHelper.rotuloPedidoEntrega(venda)}: libera "Saiu" ignorando reserva '
          'de estoque e conferencia de patio. Use apenas para romaneios antigos '
          'com pendencia de saldo ou cadastro inconsistente.\n\n'
          'A acao fica registrada no historico da entrega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forcar saida'),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    return _liberarSaidaEntrega(
      venda,
      forcarSaidaRomaneio: true,
    );
  }

  Future<bool> _autoRoteirizarAposMotorista(Venda venda) async {
    if (!EntregaFluxoService.deveAutoRoteirizar(
      statusEntrega: venda.statusEntrega,
      motorista: venda.motoristaEntrega,
    )) {
      return false;
    }
    return _atualizarStatusEntrega(
      venda,
      'roteirizada',
      mostrarSnackSucesso: false,
    );
  }

  Future<void> _autoRoteirizarIdsAposMotorista(Iterable<int> ids) async {
    for (final id in ids) {
      final v = widget.vendaRepository.obterPorId(id);
      if (v == null) continue;
      try {
        await _autoRoteirizarAposMotorista(v);
      } catch (_) {}
    }
  }

  Future<void> _mostrarErroChecklistSaiu(Venda venda, Object erro) async {
    if (!mounted) return;
    await mostrarDialogoErroChecklistSaiu(
      context: context,
      venda: venda,
      erro: erro,
      listarMovimentos: (produtoId) =>
          widget.produtoRepository.listarMovimentosEstoquePorProduto(produtoId),
    );
  }

  Future<void> _abrirDetalhesItensVenda(Venda venda) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final exibir = widget.vendaRepository.obterPorId(venda.id) ?? venda;
            final usaMigrado = _vendaUsaItensCarretoMigrado(exibir);
            final itensLista = _itensDaVenda(exibir)
                .where((i) => _quantidadeExibicaoEntrega(exibir, i) > 0)
                .toList();
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              title: Text(
                VendaDocumentoRotuloHelper.tituloItensPedidoEntrega(
                  exibir,
                  paraEntrega: usaMigrado,
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EntregaPodFotoPanel(
                        key: ValueKey(
                          '${exibir.podRecebidoPor}|${exibir.podRegistradoEm}|'
                          '${exibir.podFotoPathServidor}',
                        ),
                        venda: exibir,
                        configuracoesService: widget.configuracoesService,
                        podeEditar: widget.podeRegistrarPodEntrega,
                        onEditar: () async {
                          final ok = await _editarPodEntrega(exibir);
                          if (ok) {
                            final ref = widget.vendaRepository.obterPorId(
                              venda.id,
                            );
                            if (ref != null) {
                              _copiarCamposPod(venda, ref);
                              _copiarCamposPod(exibir, ref);
                            }
                            setDialogState(() {});
                            _carregarEntregas();
                          }
                        },
                      ),
                      if (itensLista.isEmpty)
                        const Text('Nenhum item encontrado para esta entrega.')
                      else ...[
                        Text(
                          'Cliente: ${_nomeCliente(exibir)}',
                        ),
                        Text('Vendedor: ${_nomeVendedor(exibir)}'),
                        if (usaMigrado) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Somente o que segue no carreto (cliente ja pode ter retirado parte na loja).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (!usaMigrado &&
                            _vendaCarretoReservaNativaSemMigracao(exibir) &&
                            _itensDaVenda(exibir).any(
                              (i) => i.quantidadeJaRetirada > 0,
                            )) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Parte dos itens ja foi retirada na loja antes da saida do carro; '
                            'abaixo consta o que ainda segue para entrega.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: itensLista.length,
                          separatorBuilder: (_, _) => const Divider(height: 10),
                          itemBuilder: (context, index) {
                            final item = itensLista[index];
                            final qTxt =
                                _textoQuantidadeExibicaoEntrega(exibir, item);
                            final sub = _subtotalExibicaoEntrega(exibir, item);
                            return _linhaItemDetalheEntrega(
                              context,
                              item: item,
                              quantidadeTexto: qTxt,
                              subtotal: sub,
                              origemVenda: exibir.lojaOrigemMercadoria,
                              cargaSaiu: exibir.cargaSaiu,
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        if (!widget.ocultarValoresMonetarios) ...[
                          Text(
                            'Total na carga: ${_formatarMoeda(itensLista.fold<double>(0, (s, i) => s + _subtotalExibicaoEntrega(exibir, i)))}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (usaMigrado)
                            Text(
                              'Total da venda (produtos): ${_formatarMoeda(exibir.total)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _linhaItemDetalheEntrega(
    BuildContext context, {
    required ItemVenda item,
    required String quantidadeTexto,
    required double subtotal,
    String origemVenda = '',
    bool cargaSaiu = false,
  }) {
    final tipo = EntregaVendaHelper.rotuloTipoItem(item.tipoEntregaItem);
    final preco = '${_formatarMoeda(item.precoUnitario)} / un';
    final total = _formatarMoeda(subtotal);
    final esconderValor = widget.ocultarValoresMonetarios;
    final origemItem = LojaOrigemMercadoria.origemEfetiva(
      origemItem: item.lojaOrigemMercadoria,
      origemVenda: origemVenda,
      cargaSaiu: cargaSaiu,
    );
    final origemTxt = LojaOrigemMercadoria.ehLocal(origemItem)
        ? ''
        : 'Origem: ${LojaOrigemMercadoria.rotulo(origemItem)}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final estreito = largura < 420;
        if (estreito) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${quantidadeTexto}x  ${item.nomeProduto}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(tipo, style: Theme.of(context).textTheme.labelSmall),
              if (origemTxt.isNotEmpty)
                Text(
                  origemTxt,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (!esconderValor) ...[
                const SizedBox(height: 2),
                Text(
                  '$preco  ·  $total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '${quantidadeTexto}x',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nomeProduto,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(tipo, style: Theme.of(context).textTheme.labelSmall),
                  if (origemTxt.isNotEmpty)
                    Text(
                      origemTxt,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!esconderValor) ...[
              Flexible(
                child: Text(
                  preco,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  total,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _abrirChecklistCargaEntrega(Venda venda) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final podeLiberar = EntregaFluxoService.podeLiberarSaida(venda) &&
                widget.podeGerenciarStatusEntrega;
            return AlertDialog(
              title: Text(
                'Carga ${VendaDocumentoRotuloHelper.hashIdentificadorEntrega(venda)}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cliente: ${_nomeCliente(venda)}'),
                  Text('Vendedor: ${_nomeVendedor(venda)}'),
                  const SizedBox(height: 8),
                  Text(
                    venda.cargaSaiu
                        ? 'Saida ja liberada. Proximo passo: marcar Entregue.'
                        : 'O motorista libera a saida no celular. '
                            'Use o menu do pedido so se precisar liberar daqui.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
                if (podeLiberar)
                  TextButton(
                    onPressed: () async {
                      final ok = await _liberarSaidaEntrega(venda);
                      if (!context.mounted) return;
                      if (ok) Navigator.pop(context);
                      setDialogState(() {});
                    },
                    child: const Text('Liberar saida (reserva)'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _onPopupCardEntrega(Venda venda, String value) {
    if (value == '__acao_historico__') {
      _abrirHistoricoEntrega(venda);
      return;
    }
    if (value == '__acao_complemento__') {
      _abrirDialogRegistrarComplemento(venda);
      return;
    }
    if (value == _kMenuMarcarDataEntrega) {
      _marcarOuAlterarDataEntrega(venda);
      return;
    }
    if (value == _kMenuLimparDataEntrega) {
      _limparDataEntregaMarcada(venda);
      return;
    }
    if (value == _kMenuDevolucaoPosCarreto) {
      _abrirRegistrarDevolucaoPosCarreto(venda);
      return;
    }
    if (value == _kMenuRetiradaLojaCarreto) {
      _abrirRegistrarRetiradaLojaCarretoAntesSaida(venda);
      return;
    }
    if (value.startsWith('prioridade:')) {
      _atualizarPrioridade(venda, value.split(':').last);
      return;
    }
    if (value == 'saiu_entrega') {
      _liberarSaidaEntrega(venda);
      return;
    }
    _atualizarStatusEntrega(venda, value);
  }

  Widget _buildCardEntrega(
    Venda venda,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt, {
    bool dentroDeGrupoCarreto = false,
    bool modoSelecao = false,
    bool selecionada = false,
    int? paradaNoMesmoCarro,
  }) {
    return EntregaCardLista(
      venda: venda,
      dateFormat: dateFormat,
      dataMarcadaFmt: dataMarcadaFmt,
      dentroDeGrupoCarreto: dentroDeGrupoCarreto,
      modoSelecao: modoSelecao,
      selecionada: selecionada,
      paradaNoMesmoCarro: paradaNoMesmoCarro,
      callbacks: EntregaCardListaCallbacks(
        formatarMoeda: _formatarMoeda,
        rotuloStatus: _rotuloStatusEntrega,
        rotuloJanela: _rotuloJanelaEntrega,
        rotuloPrioridade: _rotuloPrioridade,
        extrairBairro: _extrairBairro,
        nomeMotorista: _nomeMotorista,
        nomeVendedor: _nomeVendedor,
        progressoCarga: _progressoCarga,
        corProgressoCarga: _corProgressoCarga,
        corStatus: _corStatus,
        observacaoSemMotorista: _observacaoSemMotorista,
        textoResumoComplemento: _textoResumoComplementoNaVenda,
        textoBuscarNaLoja: (v) =>
            BuscarNaLoja.resumoPendentes(v, _itensDaVenda(v)),
        onSepararNestaLoja: widget.podeGerenciarStatusEntrega
            ? (v) => _confirmarBuscarNaLoja(
                  v.id,
                  BuscarNaLoja.pendentesDaVenda(v, _itensDaVenda(v))
                      .map((i) => i.id)
                      .toList(),
                )
            : null,
        podeDevolucaoPosCarreto: _podeDevolucaoPosCarretoNaEntrega,
        podeRetiradaLojaAntesSaida: _podeRegistrarRetiradaLojaAntesSaidaCarreto,
        onTapDetalhes: () => _abrirDetalhesItensVenda(venda),
        onAlternarSelecao: () => _alternarSelecaoEntrega(venda.id),
        onNavegar: () => _abrirNavegacaoParaEntrega(venda),
        onHistorico: () => _abrirHistoricoEntrega(venda),
        onMotorista: () => _editarMotoristaEntrega(venda),
        onChecklistCarga: () => _abrirChecklistCargaEntrega(venda),
        onMarcarData: () => _marcarOuAlterarDataEntrega(venda),
        onAcaoPrincipal: () => _executarAcaoPrincipalEntrega(venda),
        onPopupSelected: (value) => _onPopupCardEntrega(venda, value),
        labelAcaoPrincipal: (v) => _acaoPrincipalEntrega(v)?.label,
        podeGerenciarStatus: widget.podeGerenciarStatusEntrega,
      ),
    );
  }

  Widget _buildPainelRotaMotoristaLista(
    String motorista,
    List<Venda> entregasMotorista,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
  ) {
    if (!widget.podeGerenciarStatusEntrega || entregasMotorista.length < 2) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final ordenado = ordenarParadasMotoristaDia(entregasMotorista);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
      ),
      color: scheme.primaryContainer.withValues(alpha: 0.18),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          'Rota do dia — $motorista (${ordenado.length} paradas)',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'Use as setas para definir a ordem das entregas (sem agrupar viagens).',
        ),
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Column(
              children: [
                for (var i = 0; i < ordenado.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Subir na rota',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 26,
                              ),
                              onPressed: i == 0
                                  ? null
                                  : () => _swapParadasMotoristaDia(
                                      motorista,
                                      ordenado,
                                      i,
                                      i - 1,
                                    ),
                              icon: Icon(
                                Icons.arrow_upward_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Descer na rota',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 26,
                              ),
                              onPressed: i == ordenado.length - 1
                                  ? null
                                  : () => _swapParadasMotoristaDia(
                                      motorista,
                                      ordenado,
                                      i,
                                      i + 1,
                                    ),
                              icon: Icon(
                                Icons.arrow_downward_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _buildCardEntrega(
                          ordenado[i],
                          dateFormat,
                          dataMarcadaFmt,
                          dentroDeGrupoCarreto: true,
                          paradaNoMesmoCarro: i + 1,
                        ),
                      ),
                    ],
                  ),
                  if (i < ordenado.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPainelGrupoCarretoLista(
    List<Venda> bloco,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final ordenado = ordenarBlocoMesmoCarro(bloco);
    final grupoId = ordenado.first.grupoEntregaFreteId;
    final motorista = _nomeMotorista(ordenado.first);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.55)),
      ),
      color: scheme.tertiaryContainer.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            isThreeLine: true,
            leading: Icon(
              Icons.local_shipping_outlined,
              color: scheme.tertiary,
            ),
            title: Text(
              rotuloGrupoLogistica(ordenado),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${ordenado.length} pedidos no mesmo veiculo · use as setas para '
              'a ordem de paradas (salva no banco).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              tooltip: 'Alterar motorista da viagem',
              icon: const Icon(Icons.person_outline),
              onPressed: () => _editarMotoristaGrupo(grupoId, motorista),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _emitirRelatorioEntrega(
                    tipo: RelatorioEntregaTipo.separacaoViagem,
                    viagem: ordenado,
                    salvarPdf: false,
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Separacao viagem'),
                ),
                if (motorista != 'Nao definido')
                  TextButton.icon(
                    onPressed: () => _emitirRelatorioEntrega(
                      tipo: RelatorioEntregaTipo.romaneioMotoristaDia,
                      motorista: motorista,
                      salvarPdf: false,
                    ),
                    icon: const Icon(Icons.assignment_outlined, size: 18),
                    label: const Text('Romaneio do motorista'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < ordenado.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Subir na rota',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 26,
                              ),
                              onPressed: i == 0
                                  ? null
                                  : () => _swapParadasMesmoCarro(
                                      grupoId,
                                      ordenado,
                                      i,
                                      i - 1,
                                    ),
                              icon: Icon(
                                Icons.arrow_upward_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Descer na rota',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 26,
                              ),
                              onPressed: i == ordenado.length - 1
                                  ? null
                                  : () => _swapParadasMesmoCarro(
                                      grupoId,
                                      ordenado,
                                      i,
                                      i + 1,
                                    ),
                              icon: Icon(
                                Icons.arrow_downward_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _buildCardEntrega(
                          ordenado[i],
                          dateFormat,
                          dataMarcadaFmt,
                          dentroDeGrupoCarreto: true,
                          modoSelecao: _modoAgruparMesmoCarro,
                          selecionada: _idsEntregasSelecionadas.contains(
                            ordenado[i].id,
                          ),
                          paradaNoMesmoCarro: i + 1,
                        ),
                      ),
                    ],
                  ),
                  if (i < ordenado.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Venda> _listaEntregasPlanejadasExibicao() => List<Venda>.from(_entregas);

  List<Venda> _listaEntregasExibicaoFinal() {
    var lista = _listaEntregasPlanejadasExibicao();
    if (_filtroApenasSemMotorista) {
      lista = lista
          .where((v) => !motoristaLogisticaDefinido(nomeMotoristaEntrega(v)))
          .toList();
    }
    if (_filtroResumoLista == _FiltroResumoEntregas.buscarNaLoja) {
      lista = lista.where((v) => BuscarNaLoja.temPendente(v, _itensDaVenda(v))).toList();
    }
    return lista;
  }

  int _contagemSemMotoristaLista(List<Venda> lista) =>
      contarEntregasSemMotorista(lista);

  Set<int> _idsEntregasSemMotoristaLista(List<Venda> lista) => lista
      .where((v) => !motoristaLogisticaDefinido(nomeMotoristaEntrega(v)))
      .map((v) => v.id)
      .toSet();

  Future<void> _definirMotoristaEmLoteSemMotoristaLista(
    List<Venda> lista,
  ) async {
    final ids = _idsEntregasSemMotoristaLista(lista);
    if (ids.isEmpty) return;
    await _definirMotoristaEmLoteIds(ids);
  }

  ({String label, bool complemento, String? status, bool liberarSaida})?
      _acaoPrincipalEntrega(Venda venda) {
    if (!widget.podeGerenciarStatusEntrega) return null;
    switch (venda.statusEntrega) {
      case 'saiu_entrega':
        return (
          label: 'Marcar entregue',
          status: 'entregue',
          complemento: false,
          liberarSaida: false,
        );
      case 'entregue_complemento_pendente':
        return (
          label: 'Concluir complemento',
          status: null,
          complemento: true,
          liberarSaida: false,
        );
      default:
        return null;
    }
  }

  Future<void> _executarAcaoPrincipalEntrega(Venda venda) async {
    final acao = _acaoPrincipalEntrega(venda);
    if (acao == null) return;
    if (acao.complemento) {
      await _confirmarConcluirComplemento(venda);
      return;
    }
    if (acao.liberarSaida) {
      await _liberarSaidaEntrega(venda);
      return;
    }
    await _atualizarStatusEntrega(venda, acao.status!);
  }

  bool _statusKanbanNoPatio(String s) {
    return s == 'pendente' || s == 'reagendada' || s == 'roteirizada';
  }

  bool _vendaKanbanColunaPatio(Venda v) => _statusKanbanNoPatio(v.statusEntrega);

  int? _kanbanIndiceOrdenacaoStatus(String status) {
    switch (status) {
      case 'pendente':
      case 'reagendada':
      case 'roteirizada':
        return 0;
      case 'saiu_entrega':
      case 'entregue_complemento_pendente':
        return 1;
      case 'entregue':
        return 2;
      default:
        return null;
    }
  }

  /// Status alvo da coluna visivel (0..2). Patio junta pendente e roteirizada.
  String? _statusEntregaColunaKanban(int coluna, [Venda? venda]) {
    switch (coluna) {
      case 0:
        if (venda != null && venda.motoristaEntrega.trim().isNotEmpty) {
          return 'roteirizada';
        }
        return 'pendente';
      case 1:
        return 'saiu_entrega';
      case 2:
        return 'entregue';
      default:
        return null;
    }
  }

  String? _proximoPassoKanbanEmDirecao(String atual, String destino) {
    if (atual == destino) return null;
    if (atual == 'reagendada' && destino == 'pendente') return 'pendente';
    if (atual == 'entregue_complemento_pendente' && destino == 'entregue') {
      return 'entregue';
    }
    if (_statusKanbanNoPatio(atual) &&
        (destino == 'pendente' || destino == 'roteirizada')) {
      return destino == atual ? null : destino;
    }
    final ia = _kanbanIndiceOrdenacaoStatus(atual);
    final ib = _kanbanIndiceOrdenacaoStatus(destino);
    if (ia == null || ib == null) return null;
    if (ib > ia) {
      if (ia == 0) return 'saiu_entrega';
      if (ia == 1) return 'entregue';
    }
    if (ib < ia) {
      if (ia == 2) return 'saiu_entrega';
      if (ia == 1) return destino == 'pendente' ? 'pendente' : 'roteirizada';
    }
    return null;
  }

  bool _kanbanCaminhoInteiroValido(Venda vRef, String destino) {
    var s = vRef.statusEntrega;
    final v = vRef;
    var guard = 0;
    while (s != destino && guard++ < 8) {
      final next = _proximoPassoKanbanEmDirecao(s, destino);
      if (next == null) return false;
      final puloLiberarSaida =
          next == 'saiu_entrega' && _statusKanbanNoPatio(s);
      if (!puloLiberarSaida && !_transicaoStatusPermitida(s, next)) {
        return false;
      }
      if ((next == 'entregue' || next == 'entregue_complemento_pendente') &&
          _progressoCarga(v) < 3) {
        return false;
      }
      s = next;
    }
    return s == destino;
  }

  List<Venda> _filtrarKanban(List<Venda> fonte) {
    return fonte.where((v) => v.statusEntrega != 'cancelada').toList();
  }

  List<Venda> _entregasColunaKanban(List<Venda> visiveis, int col) {
    final base = _filtrarKanban(visiveis);
    switch (col) {
      case 0:
        return base.where(_vendaKanbanColunaPatio).toList();
      case 1:
        return base
            .where(
              (v) =>
                  v.statusEntrega == 'saiu_entrega' ||
                  v.statusEntrega == 'entregue_complemento_pendente',
            )
            .toList();
      case 2:
        return base.where((v) => v.statusEntrega == 'entregue').toList();
      default:
        return const [];
    }
  }

  bool _kanbanPodeSoltarNaColuna(int vendaId, int colDestino) {
    if (!widget.podeGerenciarStatusEntrega) return false;
    final v = widget.vendaRepository.obterPorId(vendaId);
    if (v == null || v.statusEntrega == 'cancelada') return false;
    final destino = _statusEntregaColunaKanban(colDestino, v);
    if (destino == null) return false;
    if (_kanbanIndiceOrdenacaoStatus(v.statusEntrega) == colDestino) {
      return false;
    }
    if (destino == 'entregue' &&
        v.statusEntrega == 'entregue_complemento_pendente') {
      return true;
    }
    if (!_kanbanCaminhoInteiroValido(v, destino)) return false;
    return true;
  }

  Future<void> _onKanbanAceitarSoltar(int vendaId, int colDestino) async {
    if (!_kanbanPodeSoltarNaColuna(vendaId, colDestino)) return;

    var v = widget.vendaRepository.obterPorId(vendaId);
    if (v == null || !mounted) return;

    final destino = _statusEntregaColunaKanban(colDestino, v)!;

    if (destino == 'entregue' &&
        v.statusEntrega == 'entregue_complemento_pendente') {
      await _confirmarConcluirComplemento(v);
      return;
    }

    if (v.statusEntrega == destino) return;

    var passos = 0;
    var algumPasso = false;
    while (mounted && passos < 8) {
      passos++;
      v = widget.vendaRepository.obterPorId(vendaId);
      if (v == null) return;
      if (v.statusEntrega == destino) break;
      final prox = _proximoPassoKanbanEmDirecao(v.statusEntrega, destino);
      if (prox == null) break;
      final bool ok;
      if (prox == 'saiu_entrega') {
        ok = await _liberarSaidaEntrega(v, mostrarSnackSucesso: false);
      } else {
        ok = await _atualizarStatusEntrega(
          v,
          prox,
          mostrarSnackSucesso: false,
        );
      }
      if (!ok) break;
      algumPasso = true;
    }

    v = widget.vendaRepository.obterPorId(vendaId);
    if (!mounted) return;
    if (algumPasso && v != null && v.statusEntrega == destino) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status de entrega atualizado (Kanban).')),
      );
    }
  }

  static const _titulosKanban = [
    'Aguardando motorista',
    'Em rota',
    'Entregue',
  ];

  Widget _kanbanCardMosaico(Venda venda, DateFormat dataFmt) {
    final scheme = Theme.of(context).colorScheme;
    final statusCor = _corStatus(scheme, venda.statusEntrega);
    final subtitulo = _nomeCliente(venda);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalhesItensVenda(venda),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      VendaDocumentoRotuloHelper.rotuloPedidoEntrega(venda),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.drag_indicator, size: 18, color: scheme.outline),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: statusCor.withValues(alpha: 0.14),
                      border: Border.all(
                        color: statusCor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _rotuloStatusEntrega(venda.statusEntrega),
                      style: TextStyle(
                        fontSize: 11,
                        color: statusCor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  EntregaPodChip(venda: venda, compacto: true),
                  Text(
                    venda.dataEntregaMarcada == null
                        ? 'Sem data'
                        : dataFmt.format(venda.dataEntregaMarcada!.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _abrirNavegacaoParaEntrega(venda),
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Navegar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKanbanCompactCard(Venda venda, DateFormat dataFmt) {
    if (!widget.podeGerenciarStatusEntrega) {
      return _kanbanCardMosaico(venda, dataFmt);
    }
    return Draggable<int>(
      data: venda.id,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Opacity(
            opacity: 0.92,
            child: _kanbanCardMosaico(venda, dataFmt),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _kanbanCardMosaico(venda, dataFmt),
      ),
      child: _kanbanCardMosaico(venda, dataFmt),
    );
  }

  Widget _colunaKanban(
    BuildContext context, {
    required int coluna,
    required List<Venda> itens,
    required DateFormat dataMarcadaFmt,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const largura = 286.0;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          _kanbanPodeSoltarNaColuna(details.data, coluna),
      onAcceptWithDetails: (details) =>
          _onKanbanAceitarSoltar(details.data, coluna),
      builder: (context, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return SizedBox(
          width: largura,
          child: Card(
            elevation: highlight ? 2 : 0,
            margin: const EdgeInsets.only(right: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: highlight
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.7),
                width: highlight ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _titulosKanban[coluna],
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          label: Text('${itens.length}'),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: itens.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Nenhum pedido',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.outline),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                          itemCount: itens.length,
                          itemBuilder: (context, i) =>
                              _buildKanbanCompactCard(itens[i], dataMarcadaFmt),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _corpoQuadroKanban(
    BuildContext context, {
    required List<Venda> listaVisivel,
    required DateFormat dataMarcadaFmt,
    required double altura,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (!widget.podeGerenciarStatusEntrega)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              _mensagemSemPermissaoStatus(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ),
        SizedBox(
          height: altura,
          child: SingleChildScrollView(
            controller: _kanbanHScrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < 3; c++)
                  _colunaKanban(
                    context,
                    coluna: c,
                    itens: _entregasColunaKanban(listaVisivel, c),
                    dataMarcadaFmt: dataMarcadaFmt,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  EntregasMontagemCallbacks get _callbacksMontagem => EntregasMontagemCallbacks(
    atualizarChecklist: (v, {separado, carregado, saiu}) =>
        _atualizarChecklistCarga(
          v,
          separado: separado,
          carregado: carregado,
          saiu: saiu,
        ),
    atualizarStatus: _atualizarStatusEntrega,
    liberarSaida: _liberarSaidaEntrega,
    forcarSaidaRomaneio: _forcarSaidaRomaneioEntrega,
    emitirRelatorio: ({required tipo, motorista, viagem, required salvarPdf}) =>
        _emitirRelatorioEntrega(
          tipo: tipo,
          motorista: motorista,
          viagem: viagem,
          salvarPdf: salvarPdf,
        ),
    trocarParada: _swapParadasMesmoCarro,
    trocarParadaMotorista: _swapParadasMotoristaDia,
    editarMotoristaGrupo: _editarMotoristaGrupo,
    abrirDetalheItens: _abrirDetalhesItensVenda,
    abrirNavegacao: _abrirNavegacaoParaEntrega,
    recarregar: _atualizarListaEntregas,
    confirmarAgrupamento: _confirmarAgrupamentoIds,
    removerAgrupamento: _removerAgrupamentoIds,
    editarMotoristaPedido: _editarMotoristaEntrega,
    definirMotoristaEmLote: _definirMotoristaEmLoteIds,
    confirmarBuscarNaLoja: _confirmarBuscarNaLoja,
  );

  Widget _buildAbaMontagem(List<Venda> listaExibicao) {
    if (_conferenciaCargaRepository == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Conferencia de carga requer conexao com o PC servidor. '
            'Verifique a rede e reabra Entregas.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return PainelMontagemEntregas(
      entregas: listaExibicao,
      quantidadeItemEntrega: _quantidadeExibicaoEntrega,
      callbacks: _callbacksMontagem,
      podeGerenciarStatus: widget.podeGerenciarStatusEntrega,
      conferenciaRepository: _conferenciaCargaRepository!,
      usuarioAtual: widget.usuarioAtual,
      obterProduto: _obterProdutoPorId,
    );
  }

  Widget _buildAbaLista(
    List<Venda> listaExibicao,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
    List<String> gruposLista,
    Map<String, List<Venda>> groupedLista,
  ) {
    final qtdSemMotorista = _contagemSemMotoristaLista(
      _listaEntregasPlanejadasExibicao(),
    );
    final linhasLista = _linhasListaDia(gruposLista, groupedLista);
    return Column(
      children: [
        EntregasFaixaSemMotorista(
          quantidade: qtdSemMotorista,
          podeGerenciar: widget.podeGerenciarStatusEntrega,
          filtroAtivo: _filtroApenasSemMotorista,
          onAlternarFiltro: () {
            setState(() {
              _filtroApenasSemMotorista = !_filtroApenasSemMotorista;
            });
          },
          onDefinirMotoristaEmLote:
              qtdSemMotorista > 0 && widget.podeGerenciarStatusEntrega
              ? () => _definirMotoristaEmLoteSemMotoristaLista(
                  _listaEntregasPlanejadasExibicao(),
                )
              : null,
        ),
        if (_modoAgruparMesmoCarro) ...[
          EntregasBarraAgrupamentoMesmoCarro(
            selecionadas: _idsEntregasSelecionadas.length,
            onConfirmar: _idsEntregasSelecionadas.length >= 2
                ? _confirmarAgrupamentoMesmoCarro
                : null,
            onLimparSelecao: () => setState(_idsEntregasSelecionadas.clear),
            onRemoverAgrupamento: _removerAgrupamentoSelecionadas,
          ),
          const SizedBox(height: 6),
        ],
        Expanded(
          child: listaExibicao.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 48),
                    Center(
                      child: Text(
                        _chaveDiaPlanejamentoSelecionado == null
                            ? 'Nenhuma entrega encontrada para os filtros.'
                            : 'Nenhuma entrega para o dia selecionado no planejamento.',
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: linhasLista.length,
                  itemBuilder: (context, i) {
                    final linha = linhasLista[i];
                    switch (linha.tipo) {
                      case _TipoLinhaListaEntrega.cabecalho:
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                          child: Text(
                            '${_agrupamento == 'motorista' ? 'Motorista' : 'Bairro'}: ${linha.rotuloGrupo} (${linha.quantidade})',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        );
                      case _TipoLinhaListaEntrega.rota:
                        return _buildPainelRotaMotoristaLista(
                          linha.motorista!,
                          linha.vendas!,
                          dateFormat,
                          dataMarcadaFmt,
                        );
                      case _TipoLinhaListaEntrega.carreto:
                        return _buildPainelGrupoCarretoLista(
                          linha.vendas!,
                          dateFormat,
                          dataMarcadaFmt,
                        );
                      case _TipoLinhaListaEntrega.card:
                        final v = linha.venda!;
                        return _buildCardEntrega(
                          v,
                          dateFormat,
                          dataMarcadaFmt,
                          modoSelecao: _modoAgruparMesmoCarro,
                          selecionada: _idsEntregasSelecionadas.contains(v.id),
                        );
                    }
                  },
                ),
        ),
      ],
    );
  }

  List<_LinhaListaEntrega> _linhasListaDia(
    List<String> gruposLista,
    Map<String, List<Venda>> groupedLista,
  ) {
    final linhas = <_LinhaListaEntrega>[];
    for (final grupo in gruposLista) {
      final vendasGrupo = groupedLista[grupo] ?? const <Venda>[];
      linhas.add(_LinhaListaEntrega.cabecalho(grupo, vendasGrupo.length));
      if (_agrupamento == 'motorista' &&
          widget.podeGerenciarStatusEntrega &&
          vendasGrupo.length >= 2 &&
          motoristaLogisticaDefinido(grupo)) {
        linhas.add(_LinhaListaEntrega.rota(grupo, vendasGrupo));
      }
      for (final bloco in blocosEntregaComCarretoAgrupado(vendasGrupo)) {
        if (bloco.length >= 2 && bloco.first.grupoEntregaFreteId > 0) {
          linhas.add(_LinhaListaEntrega.carreto(bloco));
        } else {
          for (final v in bloco) {
            linhas.add(_LinhaListaEntrega.card(v));
          }
        }
      }
    }
    return linhas;
  }

  Widget _buildAbaDia(
    List<Venda> listaExibicao,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
    List<String> gruposLista,
    Map<String, List<Venda>> groupedLista,
    double alturaKanban,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_ModoVisualizacaoDia>(
              segments: const [
                ButtonSegment(
                  value: _ModoVisualizacaoDia.lista,
                  icon: Icon(Icons.view_list_outlined, size: 18),
                  label: Text('Lista'),
                ),
                ButtonSegment(
                  value: _ModoVisualizacaoDia.kanban,
                  icon: Icon(Icons.view_kanban_outlined, size: 18),
                  label: Text('Kanban'),
                ),
              ],
              selected: {_modoVisualizacaoDia},
              onSelectionChanged: (selecao) {
                setState(() => _modoVisualizacaoDia = selecao.first);
                _salvarPreferenciasAberturaAtual();
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (_modoVisualizacaoDia == _ModoVisualizacaoDia.lista)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _modoAgruparMesmoCarro = !_modoAgruparMesmoCarro;
                    if (!_modoAgruparMesmoCarro) {
                      _idsEntregasSelecionadas.clear();
                    }
                  });
                },
                icon: Icon(
                  Icons.merge_type_outlined,
                  color: _modoAgruparMesmoCarro
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                label: Text(
                  _modoAgruparMesmoCarro
                      ? 'Sair do modo agrupar viagens'
                      : 'Agrupar mesmo carro (lista)',
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _modoVisualizacaoDia == _ModoVisualizacaoDia.lista
              ? _buildAbaLista(
                  listaExibicao,
                  dateFormat,
                  dataMarcadaFmt,
                  gruposLista,
                  groupedLista,
                )
              : _buildAbaKanban(listaExibicao, dataMarcadaFmt, alturaKanban),
        ),
      ],
    );
  }

  Widget _buildAbaKanban(
    List<Venda> listaExibicao,
    DateFormat dataMarcadaFmt,
    double alturaKanban,
  ) {
    return _corpoQuadroKanban(
      context,
      listaVisivel: listaExibicao,
      dataMarcadaFmt: dataMarcadaFmt,
      altura: alturaKanban,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final dataMarcadaFmt = DateFormat('dd/MM/yyyy');
    final atrasadas = _contagemAtrasadasCache;
    final pendentesHoje = _contagemPendentesHojeCache;
    final resumoPorDia = PlanejamentoEntregaDia.resumoDeEntregas(
      _entregasResumoDias,
    );
    final temProximosDias = PlanejamentoEntregaDia.proximosDiasComEntrega(
      resumoPorDia,
    ).isNotEmpty;
    final listaExibicao = _listaEntregasExibicaoFinal();
    final groupedLista = <String, List<Venda>>{};
    for (final venda in listaExibicao) {
      final chaveGrupo = _agrupamento == 'motorista'
          ? _nomeMotorista(venda)
          : _extrairBairro(venda);
      groupedLista.putIfAbsent(chaveGrupo, () => <Venda>[]).add(venda);
    }
    final gruposLista = groupedLista.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    if (_visaoSimples) {
      final motoristas = MotoristaListaSafe.nomesAtivos(
        widget.motoristaRepository,
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Entregas'),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _atualizarListaEntregas,
            ),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            10,
            MediaQuery.sizeOf(context).height < 800 ? 6 : 10,
            10,
            MediaQuery.sizeOf(context).height < 800 ? 6 : 10,
          ),
          child: EntregasVisaoSimples(
            entregas: listaExibicao,
            nomesMotoristas: motoristas,
            atrasadas: atrasadas,
            diaEhHoje: _diaSelecionadoEhHojeSimples,
            diaEhAmanha: _diaSelecionadoEhAmanhaSimples,
            rotuloDiaSelecionado: _rotuloDiaSelecionadoSimples(),
            rotuloStatus: _rotuloStatusEntrega,
            corStatus: _corStatus,
            labelAcaoPrincipal: (v) => _acaoPrincipalEntrega(v)?.label,
            onHoje: () => _aplicarDiaRapidoSimples(amanha: false),
            onAmanha: () => _aplicarDiaRapidoSimples(amanha: true),
            onEscolherDia: () => _abrirSeletorPlanejamentoDia(resumoPorDia),
            onAtribuirMotorista: _editarMotoristaEntrega,
            onAcaoPrincipal: _executarAcaoPrincipalEntrega,
            onAbrirDetalhes: _abrirDetalhesItensVenda,
            onVisaoAvancada: () => unawaited(_definirVisaoSimples(false)),
            podeGerenciar: widget.podeGerenciarStatusEntrega,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entregas'),
        actions: [
          _seletorAbaAvancadaAppBar(),
          TextButton.icon(
            onPressed: () => unawaited(_definirVisaoSimples(true)),
            icon: const Icon(Icons.view_agenda_outlined, size: 18),
            label: const Text('Visão simples'),
          ),
          IconButton(
            tooltip: 'Como usar Entregas',
            icon: const Icon(Icons.help_outline),
            onPressed: () => EntregasGuia.mostrarDialogoCompleto(context),
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _atualizarListaEntregas,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          MediaQuery.sizeOf(context).height < 800 ? 4 : 8,
          8,
          MediaQuery.sizeOf(context).height < 800 ? 4 : 8,
        ),
        child: Column(
          children: [
            Builder(
              builder: (context) {
                return EntregasBarraCompacta(
                  atrasadas: atrasadas,
                  pendentesHoje: pendentesHoje,
                  filtroAtrasadasAtivo:
                      _filtroResumoLista == _FiltroResumoEntregas.atrasadas,
                  filtroPendentesHojeAtivo:
                      _filtroResumoLista == _FiltroResumoEntregas.pendentesHoje,
                  onFiltroAtrasadas: (ligar) {
                    setState(() {
                      _filtroResumoLista = ligar
                          ? _FiltroResumoEntregas.atrasadas
                          : _FiltroResumoEntregas.nenhum;
                    });
                    _carregarEntregas();
                  },
                  onFiltroPendentesHoje: (ligar) {
                    setState(() {
                      _filtroResumoLista = ligar
                          ? _FiltroResumoEntregas.pendentesHoje
                          : _FiltroResumoEntregas.nenhum;
                    });
                    _carregarEntregas();
                  },
                  mostrarPlanejamento: _entregasResumoDias.isNotEmpty,
                  resumoPorDia: resumoPorDia,
                  chaveDiaSelecionada: _chaveDiaPlanejamentoSelecionado,
                  onSelecionarDia: _selecionarDiaPlanejamento,
                  onAbrirSeletorDia: () =>
                      _abrirSeletorPlanejamentoDia(resumoPorDia),
                  filtrosAtivos: _contagemFiltrosAtivos(),
                  onAbrirFiltros: _abrirFiltrosEntrega,
                  mostrarRelatorios: _entregasResumoDias.isNotEmpty,
                  onRelatorios: _abrirRelatoriosEntrega,
                  mostrarProximosDias:
                      _entregasResumoDias.isNotEmpty && temProximosDias,
                  proximosDiasExpandido: _proximosDiasPlanejamentoExpandido,
                  onAlternarProximosDias: () {
                    setState(() {
                      _proximosDiasPlanejamentoExpandido =
                          !_proximosDiasPlanejamentoExpandido;
                    });
                  },
                  statusSelecionado: _statusSelecionado,
                  rotuloStatus: _rotuloStatusFiltro,
                  onStatusRapido: (status) {
                    setState(() => _statusSelecionado = status);
                    _carregarEntregas();
                  },
                  filtroSemMotoristaAtivo: _filtroApenasSemMotorista,
                  onFiltroSemMotorista: (ligar) {
                    setState(() => _filtroApenasSemMotorista = ligar);
                  },
                  inicioSemanaExibida: _inicioSemanaExibida,
                  onSemanaAnterior: () => _deslocarSemanaExibida(-1),
                  onSemanaProxima: () => _deslocarSemanaExibida(1),
                  onSelecionarDiaSemana: _selecionarDiaNaSemana,
                  compacto: true,
                );
              },
            ),
            if (_mostrarDicasEntregas &&
                _tabEntregasController.index != 0 &&
                MediaQuery.sizeOf(context).height >= 800)
              EntregasFaixaDicaAba(
                indiceAba: _tabEntregasController.index,
                kanban:
                    _tabEntregasController.index == 1 &&
                    _modoVisualizacaoDia == _ModoVisualizacaoDia.kanban,
                onAbrirGuia: () => EntregasGuia.mostrarDialogoCompleto(context),
                onOcultar: _ocultarDicasEntregas,
              ),
            if (!widget.podeGerenciarStatusEntrega) ...[
              const SizedBox(height: 8),
              MaterialBanner(
                padding: const EdgeInsets.all(12),
                leading: const Icon(Icons.visibility_outlined),
                content: const Text(
                  'Modo somente leitura — voce pode acompanhar entregas, '
                  'mas nao alterar status, motorista ou montagem de carga.',
                ),
                actions: const [SizedBox.shrink()],
              ),
            ],
            if (BuscarNaLoja.contarPedidosPendentes(
                  _listaEntregasPlanejadasExibicao(),
                  _itensDaVenda,
                ) >
                0) ...[
              const SizedBox(height: 4),
              Material(
                color: Colors.orange.shade50,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.storefront_outlined,
                    color: Colors.orange.shade800,
                  ),
                  title: Text(
                    '${BuscarNaLoja.contarPedidosPendentes(_listaEntregasPlanejadasExibicao(), _itensDaVenda)} '
                    'pedido(s) com material para buscar nesta loja',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        _filtroResumoLista =
                            _filtroResumoLista ==
                                _FiltroResumoEntregas.buscarNaLoja
                            ? _FiltroResumoEntregas.nenhum
                            : _FiltroResumoEntregas.buscarNaLoja;
                      });
                    },
                    child: Text(
                      _filtroResumoLista == _FiltroResumoEntregas.buscarNaLoja
                          ? 'Ver todos'
                          : 'Ver',
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final alturaKanban = (constraints.maxHeight - 4).clamp(
                    280.0,
                    4000.0,
                  );
                  return RefreshIndicator(
                    onRefresh: _atualizarListaEntregas,
                    child: _entregas.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 48),
                              Center(
                                child: Text(
                                  'Nenhuma entrega encontrada para os filtros.',
                                ),
                              ),
                            ],
                          )
                        : TabBarView(
                            controller: _tabEntregasController,
                            children: [
                              _buildAbaMontagem(listaExibicao),
                              _buildAbaDia(
                                listaExibicao,
                                dateFormat,
                                dataMarcadaFmt,
                                gruposLista,
                                groupedLista,
                                alturaKanban,
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Romaneio (dialogo): bloco "mesmo carro" com [Por pedido] ou [Carga consolidada].
class _PainelRomaneioGrupoMesmoCarro extends StatefulWidget {
  const _PainelRomaneioGrupoMesmoCarro({
    required this.bloco,
    required this.setDialogStateRomaneio,
    required this.quantidadeItemEntrega,
    required this.conteudoRomaneioUmaVenda,
    required this.escopoViagem,
    required this.conferenciaRepository,
    required this.usuarioAtual,
    this.onConfirmarBuscarNaLoja,
    this.obterProduto,
  });

  final List<Venda> bloco;
  final StateSetter setDialogStateRomaneio;
  final int Function(Venda venda, ItemVenda item) quantidadeItemEntrega;
  final Widget Function(
    BuildContext context,
    Venda venda,
    StateSetter setDialogStateRomaneio,
  )
  conteudoRomaneioUmaVenda;
  final String escopoViagem;
  final dynamic conferenciaRepository;
  final String usuarioAtual;
  final Future<void> Function(int vendaId, List<int> itemIds)?
      onConfirmarBuscarNaLoja;
  final Produto? Function(int id)? obterProduto;

  @override
  State<_PainelRomaneioGrupoMesmoCarro> createState() =>
      _PainelRomaneioGrupoMesmoCarroState();
}

class _PainelRomaneioGrupoMesmoCarroState
    extends State<_PainelRomaneioGrupoMesmoCarro> {
  static const int _abaPorPedido = 0;
  static const int _abaConsolidada = 1;

  int _abaRomaneioGrupo = _abaPorPedido;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linhas = romaneioMergeCargaGrupo(
      widget.bloco,
      widget.quantidadeItemEntrega,
      obterProduto: widget.obterProduto,
    );
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotuloGrupoLogistica(widget.bloco),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text('${widget.bloco.length} pedidos no mesmo veiculo'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: _abaPorPedido,
                  label: Text('Por pedido'),
                  icon: Icon(Icons.list_alt_outlined),
                ),
                ButtonSegment<int>(
                  value: _abaConsolidada,
                  label: Text('Carga consolidada (total do carro)'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
              ],
              selected: {_abaRomaneioGrupo},
              onSelectionChanged: (Set<int> s) {
                setState(() => _abaRomaneioGrupo = s.first);
              },
            ),
          ),
          const Divider(height: 16),
          if (_abaRomaneioGrupo == _abaPorPedido) ...[
            for (var i = 0; i < widget.bloco.length; i++) ...[
              widget.conteudoRomaneioUmaVenda(
                context,
                widget.bloco[i],
                widget.setDialogStateRomaneio,
              ),
              if (i < widget.bloco.length - 1) const Divider(height: 12),
            ],
          ] else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quantidades somadas de todos os pedidos deste veiculo. '
                  'O motorista libera a saida no celular; se faltar material '
                  'nesta loja, use Separar aqui.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                ConferenciaCargaConsolidadaLista(
                  linhas: linhas,
                  escopoViagem: widget.escopoViagem,
                  conferenciaRepository: widget.conferenciaRepository,
                  usuarioAtual: widget.usuarioAtual,
                  vendasGrupo: widget.bloco,
                  quantidadeEntrega: widget.quantidadeItemEntrega,
                  podeConfirmarBuscarNaLoja: widget.onConfirmarBuscarNaLoja != null,
                  onConfirmarBuscarNaLoja: widget.onConfirmarBuscarNaLoja,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DialogRetiradaLojaCarretoAntesSaida extends StatefulWidget {
  const _DialogRetiradaLojaCarretoAntesSaida({
    required this.venda,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.usuarioRepository,
  });

  final Venda venda;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final UsuarioRepository usuarioRepository;

  @override
  State<_DialogRetiradaLojaCarretoAntesSaida> createState() =>
      _DialogRetiradaLojaCarretoAntesSaidaState();
}

class _DialogRetiradaLojaCarretoAntesSaidaState
    extends State<_DialogRetiradaLojaCarretoAntesSaida> {
  late final Map<int, TextEditingController> _controllers;
  late final TextEditingController _quemRetirouController;

  List<ItemVenda> get _itensCarretoPendentes {
    List<ItemVenda> itens;
    try {
      final viaRepo =
          widget.vendaRepository.listarItensPorVenda(widget.venda.id) as List?;
      if (viaRepo != null && viaRepo.isNotEmpty) {
        itens = viaRepo.whereType<ItemVenda>().toList();
      } else {
        itens = widget.venda.itens.toList();
      }
    } catch (_) {
      try {
        itens = widget.venda.itens.toList();
      } catch (_) {
        itens = const [];
      }
    }
    return itens
        .where((i) => i.quantidadeAindaNoCarretoAntesSaida > 0)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _quemRetirouController = TextEditingController();
    _controllers = {
      for (final it in _itensCarretoPendentes)
        it.id: TextEditingController(text: ''),
    };
  }

  @override
  void dispose() {
    _quemRetirouController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _preencherPendente() {
    for (final it in _itensCarretoPendentes) {
      final c = _controllers[it.id];
      if (c != null) {
        c.text = '${it.quantidadeAindaNoCarretoAntesSaida}';
      }
    }
    setState(() {});
  }

  Future<void> _confirmar() async {
    final map = <int, int>{};
    for (final it in _itensCarretoPendentes) {
      final c = _controllers[it.id];
      if (c == null) continue;
      final q = int.tryParse(c.text.trim()) ?? 0;
      if (q > 0) {
        map[it.id] = q;
      }
    }
    if (map.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos uma quantidade maior que zero.'),
        ),
      );
      return;
    }
    final operador = await solicitarOperadorRetiradaNaLoja(
      context: context,
      vendedorRepository: widget.vendedorRepository,
      usuarioRepository: widget.usuarioRepository,
    );
    if (operador == null || !mounted) return;
    try {
      final quem = _quemRetirouController.text.trim();
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .registrarRetiradaParcialLojaCarretoAntesSaidaRemoto(
          widget.venda.id,
          map,
          usuario: operador,
          retiradoPor: quem.isEmpty ? null : quem,
        );
      } else {
        widget.vendaRepository.registrarRetiradaParcialLojaCarretoAntesSaida(
          widget.venda.id,
          map,
          usuario: operador,
          retiradoPor: quem.isEmpty ? null : quem,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nao foi possivel registrar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Retirada na loja (antes do carro sair)'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _preencherPendente,
                  child: const Text(
                    'Preencher com toda a quantidade ainda destinada ao carro',
                  ),
                ),
              ),
              TextField(
                controller: _quemRetirouController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Quem retirou',
                  hintText: 'Opcional',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              for (final it in _itensCarretoPendentes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.nomeProduto,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Ainda para o carro: '
                              '${it.quantidadeAindaNoCarretoAntesSaida} un.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _controllers[it.id],
                          enabled: it.quantidadeAindaNoCarretoAntesSaida > 0,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'Qtd',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Registrar retirada'),
        ),
      ],
    );
  }
}
