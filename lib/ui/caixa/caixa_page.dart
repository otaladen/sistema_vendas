import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart';
import '../../data/app_config_repository.dart';
import '../../data/caixa_sessao_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/mensageria_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/usuario_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../domain/promocao_cadastro.dart';
import '../../domain/promocao_preco_result.dart';
import '../../domain/promocao_preco_service.dart';
import '../../config/fiscal_config.dart';
import '../../domain/fiscal/cliente_fiscal_helper.dart';
import '../../config/focus_nfe_runtime.dart';
import '../../domain/pagamento_orcamento.dart';
import '../../domain/plano_fiado.dart';
import '../../model/caixa_sessao.dart';
import '../../model/cliente.dart';
import '../../data/promocao_repository.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import '../../services/auditoria_registrar.dart';
import '../../services/cupom_nao_fiscal_venda_pdf.dart';
import '../../data/sync/sync_cursor_storage.dart';
import '../../domain/fiscal/fiscal_emissao_lock.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../services/nfce_reconciliacao_service.dart';
import '../../services/gaveta_esc_pos_service.dart';
import '../../services/print_service.dart';
import '../clientes_page.dart';
import '../cupom_venda_impressao_helper.dart';
import '../segunda_via_cupom_autorizacao.dart';
import '../widgets/conta_sessao_app_bar_actions.dart';
import '../widgets/receber_fiado_panel.dart';
import '../../services/recibo_movimento_caixa_pdf.dart';
import '../../services/recibo_recebimento_fiado_pdf.dart';
import '../fiscal/nfe_gerenciamento_page.dart';
import '../pdv_consulta_produtos_page.dart';
import '../pdv_pesquisa_comando.dart';
import '../promocao_margem_autorizacao.dart';
import '../../model/usuario_sistema.dart';
import 'alterar_pagamento_caixa_dialog.dart';
import 'autorizacao_gerente_caixa.dart';
import 'caixa_etapa.dart';
import 'caixa_feedback.dart';
import 'caixa_pos_venda_sessao.dart';
import 'caixa_ultimas_vendas_list.dart';
import 'widgets/caixa_cobranca_painel.dart';
import 'widgets/caixa_etapas_bar.dart';
import 'widgets/caixa_pos_venda_fiscal_painel.dart';
import '../vendas/cancelar_venda_ui.dart';

class CaixaPage extends StatefulWidget {
  const CaixaPage({
    super.key,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioAtual,
    required this.podeCancelarVendas,
    required this.podeLeituraParcialCaixa,
    required this.podeVisualizarAuditoriaCaixa,
    required this.podeManutencaoAuditoriaCaixa,
    required this.onLogout,
  });

  final ClienteRepository clienteRepository;
  final ProdutoRepository produtoRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final String usuarioAtual;
  final bool podeCancelarVendas;
  final bool podeLeituraParcialCaixa;
  final bool podeVisualizarAuditoriaCaixa;
  final bool podeManutencaoAuditoriaCaixa;
  final VoidCallback onLogout;

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  static const String _kCaixaAuditoriaKey = 'caixa_auditoria_eventos_v1';

  static String _prefsUltimoTrocoValor(String terminalId) =>
      'caixa_${terminalId}_ultimo_troco_valor_v1';

  static String _prefsUltimoTrocoNumero(String terminalId) =>
      'caixa_${terminalId}_ultimo_troco_numero_v1';

  static String _prefsUltimoTrocoVendaId(String terminalId) =>
      'caixa_${terminalId}_ultimo_troco_venda_id_v1';
  final _sessaoRepo = CaixaSessaoRepository();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  static const double _valorMinimoParcela = 5.0;
  List<Venda> _orcamentos = [];
  Venda? _selecionado;
  CaixaEtapa _etapaCaixa = CaixaEtapa.fila;
  final _valorRecebidoController = TextEditingController();
  final _valorRecebidoFocusNode = FocusNode();
  final ScrollController _itensScrollController = ScrollController();
  late final MensageriaRepository _mensageriaRepository;
  final _usuarioRepository = UsuarioRepository();
  PromocaoPrecoService? _promoPrecoCache;
  final _pesquisaProdutoConferenciaController = TextEditingController();
  final _pesquisaProdutoConferenciaFocus = FocusNode();
  final List<int> _produtosRecentesConferencia = [];
  GavetaEscPosService? _gavetaService;
  double? _valorRecebido;
  bool _posVendaProcessando = false;
  CaixaPosVendaSessao? _posVenda;
  bool _caixaAberto = false;
  String _operadorCaixa = '';
  DateTime? _aberturaCaixaEm;
  double _fundoTrocoAbertura = 0;
  double _totalSuprimentos = 0;
  double _totalSangrias = 0;
  double _limiteDivergenciaSemSupervisor = 20;
  bool _exigirAutorizacaoSegundaViaCupom = true;
  bool _permitirVendaSemEstoque = false;
  int? _mistoPreparadoParaId;
  List<PagamentoOrcamentoLinha> _mistoLinhasModelo = [];
  final List<TextEditingController> _mistoValorControllers = [];
  final List<FocusNode> _mistoValorFocusNodes = [];
  String _terminalId = '';
  Map<String, CaixaSessao> _sessoesRede = const {};
  bool _pesquisaOrcamentoDialogAberta = false;
  bool _gestaoCaixaExpandida = false;
  int? _ultimoTrocoVendaId;
  int _ultimoTrocoNumeroOrcamento = 0;
  double _ultimoTrocoValor = 0;
  late final FocusNfeService _focusNfeService;
  late final NfceReconciliacaoService _nfceReconciliacao;
  Timer? _timerReconciliacaoNfce;
  String? _deviceIdSync;

  PromocaoPrecoService get _promoPreco => _promoPrecoCache ??= PromocaoPrecoService(
        PromocaoRepository(widget.produtoRepository.objectBox),
      );

  @override
  void initState() {
    super.initState();
    _focusNfeService = FocusNfeService(config: criarFocusNfeConfigPadrao());
    _nfceReconciliacao = NfceReconciliacaoService(
      vendaRepository: widget.vendaRepository,
      focusNfe: _focusNfeService,
    );
    _mensageriaRepository = MensageriaRepository();
    _carregarLimiteDivergenciaCaixa();
    _carregarSessaoCaixa();
    _carregarOrcamentos();
    unawaited(_carregarDeviceIdSync());
    unawaited(_reconciliarNfcePendentes(mostrarFeedback: false));
    _iniciarPollReconciliacaoNfce();
  }

  Future<String> _obterDeviceIdSync() async {
    _deviceIdSync ??= await SyncCursorStorage().obterOuCriarDeviceId();
    return _deviceIdSync!;
  }

  Future<void> _carregarDeviceIdSync() async {
    _deviceIdSync = await SyncCursorStorage().obterOuCriarDeviceId();
  }

  void _iniciarPollReconciliacaoNfce() {
    _timerReconciliacaoNfce?.cancel();
    _timerReconciliacaoNfce = Timer.periodic(
      const Duration(seconds: 45),
      (_) {
        if (!mounted) return;
        unawaited(_reconciliarNfcePendentes(mostrarFeedback: true));
      },
    );
  }

  Future<void> _reconciliarNfcePendentes({required bool mostrarFeedback}) async {
    try {
      _focusNfeService.validarConfiguracao();
    } catch (_) {
      return;
    }
    final lote = await _nfceReconciliacao.reconsultarTodasPendentes();
    if (!mounted || !mostrarFeedback || lote.autorizadas <= 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lote.autorizadas == 1
              ? 'NFC-e pendente autorizada na reconsulta.'
              : '${lote.autorizadas} NFC-e(s) autorizada(s) na reconsulta.',
        ),
      ),
    );
  }

  Future<void> _carregarLimiteDivergenciaCaixa() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _limiteDivergenciaSemSupervisor = config.limiteDivergenciaCaixa;
      _exigirAutorizacaoSegundaViaCupom =
          config.exigirAutorizacaoSegundaViaCupom;
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
    });
  }

  /// Limpa selecao e campos apos finalizar venda — caixa pronto para o proximo orcamento.
  void _prepararCaixaPosProximaVenda() {
    _carregarOrcamentos();
    _disposeMistoEdicao();
    setState(() {
      _selecionado = null;
      _posVenda = null;
      _posVendaProcessando = false;
      _etapaCaixa = CaixaEtapa.fila;
      _valorRecebidoController.clear();
      _valorRecebido = null;
      _valorRecebidoFocusNode.unfocus();
    });
  }

  void _selecionarOrcamentoParaConferencia(Venda venda) {
    setState(() {
      _selecionado = venda;
      _etapaCaixa = CaixaEtapa.conferencia;
      _prepararEdicaoMisto(venda);
      _sincronizarRecebidoPdVComOrcamento();
    });
  }

  void _voltarParaFila() {
    _disposeMistoEdicao();
    setState(() {
      _selecionado = null;
      _etapaCaixa = CaixaEtapa.fila;
      _valorRecebidoController.clear();
      _valorRecebido = null;
      _valorRecebidoFocusNode.unfocus();
    });
  }

  void _irParaCobranca() {
    if (_selecionado == null) return;
    setState(() => _etapaCaixa = CaixaEtapa.cobranca);
    _focarEntradaPrincipalCaixa();
  }

  void _voltarParaConferencia() {
    setState(() => _etapaCaixa = CaixaEtapa.conferencia);
  }

  bool _campoTextoComFoco() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    return focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _tratarTeclaCaixaWizard(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_atalhoCaixaAtivo()) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_etapaCaixa == CaixaEtapa.fiscal) {
        unawaited(_encerrarPosVendaFiscal());
        return KeyEventResult.handled;
      }
      if (_etapaCaixa == CaixaEtapa.cobranca) {
        _voltarParaConferencia();
        return KeyEventResult.handled;
      }
      if (_etapaCaixa != CaixaEtapa.fila) {
        _voltarParaFila();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_campoTextoComFoco() && _etapaCaixa == CaixaEtapa.conferencia) {
        return KeyEventResult.ignored;
      }
      if (_etapaCaixa == CaixaEtapa.conferencia && _selecionado != null) {
        _irParaCobranca();
        return KeyEventResult.handled;
      }
      if (_etapaCaixa == CaixaEtapa.cobranca && _selecionado != null) {
        unawaited(_finalizarOrcamento(_selecionado!));
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _carregarOrcamentos() {
    unawaited(_recarregarSessaoRede());
    setState(() {
      _orcamentos = widget.vendaRepository.listarOrcamentosPendentes();

      if (_selecionado != null) {
        _selecionado = _orcamentos
            .where((v) => v.id == _selecionado!.id)
            .firstOrNull;
      }
      if (_selecionado == null) {
        _valorRecebidoController.clear();
        _valorRecebido = null;
        _valorRecebidoFocusNode.unfocus();
        _disposeMistoEdicao();
      } else if (_mistoPreparadoParaId != _selecionado!.id) {
        _prepararEdicaoMisto(_selecionado!);
        _sincronizarRecebidoPdVComOrcamento();
      }
    });
  }

  bool _atalhoCaixaAtivo() {
    if (!mounted || _pesquisaOrcamentoDialogAberta) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  Future<void> _abrirPesquisaOrcamento() async {
    if (_pesquisaOrcamentoDialogAberta) return;
    _carregarOrcamentos();
    _pesquisaOrcamentoDialogAberta = true;
    Venda? selecionado;
    try {
      selecionado = await showDialog<Venda>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _DialogoPesquisaOrcamento(
          orcamentos: List<Venda>.from(_orcamentos),
          clienteDaVenda: _clienteDaVenda,
          rotuloVendedor: _rotuloVendedorUmLinha,
          formatarMoeda: _formatarMoeda,
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pesquisaOrcamentoDialogAberta = false;
      });
    }
    if (selecionado == null || !mounted) return;
    _selecionarOrcamentoParaConferencia(selecionado);
  }

  /// No misto, foca o primeiro valor do painel de conferencia; em dinheiro puro, foca o campo de especie.
  void _focarEntradaPrincipalCaixa() {
    final selecionado = _selecionado;
    if (selecionado == null) return;
    if (selecionado.formaPagamento == 'misto' &&
        _mistoValorFocusNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mistoValorFocusNodes.first.requestFocus();
        }
      });
      return;
    }
    if (_caixaPrecisaValorRecebidoDinheiro(selecionado)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _valorRecebidoFocusNode.requestFocus();
        }
      });
    }
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double? _parseValor(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) {
      return null;
    }
    return double.tryParse(normalizado);
  }

  Future<void> _carregarSessaoCaixa() async {
    _terminalId = await _sessaoRepo.obterTerminalId();
    await _recarregarSessaoRede();
    final s = await _sessaoRepo.carregarSessaoLocal();
    if (!mounted) return;
    setState(() {
      _caixaAberto = s.aberto;
      _operadorCaixa = s.operador;
      _aberturaCaixaEm = s.aberturaEm;
      _fundoTrocoAbertura = s.fundoTroco;
      _totalSuprimentos = s.suprimentos;
      _totalSangrias = s.sangrias;
    });
    await _carregarUltimoTrocoRegistrado();
  }

  Future<void> _carregarUltimoTrocoRegistrado() async {
    if (_terminalId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final vendaId = prefs.getInt(_prefsUltimoTrocoVendaId(_terminalId));
    if (vendaId == null) return;
    if (!mounted) return;
    setState(() {
      _ultimoTrocoVendaId = vendaId;
      _ultimoTrocoNumeroOrcamento =
          prefs.getInt(_prefsUltimoTrocoNumero(_terminalId)) ?? 0;
      _ultimoTrocoValor =
          prefs.getDouble(_prefsUltimoTrocoValor(_terminalId)) ?? 0;
    });
  }

  Future<void> _registrarUltimoTrocoFinalizado({
    required int vendaId,
    required int numeroOrcamento,
    required double troco,
  }) async {
    if (!mounted) return;
    setState(() {
      _ultimoTrocoVendaId = vendaId;
      _ultimoTrocoNumeroOrcamento = numeroOrcamento;
      _ultimoTrocoValor = troco;
    });
    if (_terminalId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsUltimoTrocoVendaId(_terminalId), vendaId);
    await prefs.setInt(_prefsUltimoTrocoNumero(_terminalId), numeroOrcamento);
    await prefs.setDouble(_prefsUltimoTrocoValor(_terminalId), troco);
  }

  Future<void> _recarregarSessaoRede() async {
    final mapa = await _sessaoRepo.listarTodasSessoes();
    if (!mounted) return;
    setState(() => _sessoesRede = mapa);
  }

  Future<void> _salvarSessaoCaixa() async {
    if (_terminalId.isEmpty) {
      _terminalId = await _sessaoRepo.obterTerminalId();
    }
    await _sessaoRepo.salvarSessaoLocal(
      CaixaSessao(
        terminalId: _terminalId,
        aberto: _caixaAberto,
        operador: _operadorCaixa,
        aberturaEm: _aberturaCaixaEm,
        fundoTroco: _fundoTrocoAbertura,
        suprimentos: _totalSuprimentos,
        sangrias: _totalSangrias,
      ),
    );
    await _recarregarSessaoRede();
  }

  Future<void> _registrarAuditoriaCaixa(
    String evento, {
    Map<String, dynamic>? detalhes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCaixaAuditoriaKey);
    List<dynamic> lista = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          lista = decoded;
        }
      } catch (_) {}
    }
    final registro = <String, dynamic>{
      'em': DateTime.now().toIso8601String(),
      'usuario': widget.usuarioAtual,
      'operadorCaixa': _operadorCaixa,
      'evento': evento,
      'detalhes': detalhes ?? <String, dynamic>{},
    };
    lista.add(registro);
    if (lista.length > 300) {
      lista = lista.sublist(lista.length - 300);
    }
    await prefs.setString(_kCaixaAuditoriaKey, jsonEncode(lista));
    _espelharAuditoriaNoLogCentral(evento, detalhes ?? <String, dynamic>{});
  }

  void _espelharAuditoriaNoLogCentral(
    String evento,
    Map<String, dynamic> detalhes,
  ) {
    switch (evento) {
      case 'fechamento_caixa':
        final operador = detalhes['operador']?.toString() ?? _operadorCaixa;
        final dif = detalhes['diferencaTotal'];
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.caixa,
          acao: AuditoriaAcao.fechamentoCaixa,
          usuarioLogin: widget.usuarioAtual,
          entidade: 'caixa',
          resumo:
              'Fechamento de caixa — operador $operador'
              '${dif is num ? ' (dif. ${_formatarMoeda(dif.toDouble())})' : ''}',
          detalhes: detalhes,
        );
        break;
      case 'fechamento_negado_divergencia':
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.caixa,
          acao: AuditoriaAcao.fechamentoNegado,
          usuarioLogin: widget.usuarioAtual,
          entidade: 'caixa',
          resumo: 'Fechamento negado por divergencia',
          detalhes: detalhes,
        );
    }
  }

  Future<void> _salvarAuditoriaCaixa(List<Map<String, dynamic>> registros) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCaixaAuditoriaKey, jsonEncode(registros));
  }

  Future<List<Map<String, dynamic>>> _carregarAuditoriaCaixa() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCaixaAuditoriaKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _autorizarSupervisorSeNecessario(double diferencaTotal) async {
    if (diferencaTotal.abs() <= _limiteDivergenciaSemSupervisor) {
      return true;
    }
    final loginController = TextEditingController();
    final senhaController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Autorizacao de supervisor'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Divergencia acima de ${_formatarMoeda(_limiteDivergenciaSemSupervisor)}. '
                    'Informe credenciais de supervisor/administrador.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: loginController,
                    decoration: const InputDecoration(labelText: 'Login'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                  ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Autorizar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      loginController.dispose();
      senhaController.dispose();
      return false;
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final usuario = await _usuarioRepository.autenticar(login, senha);
    final autorizado = usuario != null && usuario.ativo && (usuario.admin || usuario.podeFinanceiro);
    if (!autorizado && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credenciais sem permissao de supervisor/financeiro.'),
        ),
      );
    }
    return autorizado;
  }

  Future<void> _abrirHistoricoAuditoria() async {
    var registros = await _carregarAuditoriaCaixa();
    if (!mounted) return;
    final dtFmt = DateFormat('dd/MM HH:mm:ss');
    await showDialog<void>(
      context: context,
      builder: (context) {
        String operadorFiltro = '';
        DateTime? inicioFiltro;
        DateTime? fimFiltro;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtrados = _filtrarRegistrosAuditoria(
              registros: registros,
              operadorFiltro: operadorFiltro,
              inicio: inicioFiltro,
              fim: fimFiltro,
            );
            final resumo = _resumoEventosAuditoria(filtrados);
            return AlertDialog(
              title: const Text('Auditoria do caixa'),
              content: SizedBox(
                width: 860,
                height: 520,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Filtrar por operador/usuario',
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                operadorFiltro = value.trim();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final data = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              initialDate: inicioFiltro ?? DateTime.now(),
                            );
                            if (data == null) return;
                            setDialogState(() {
                              inicioFiltro = DateTime(data.year, data.month, data.day, 0, 0, 0);
                            });
                          },
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                            inicioFiltro == null
                                ? 'Inicio'
                                : DateFormat('dd/MM/yyyy').format(inicioFiltro!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final data = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              initialDate: fimFiltro ?? DateTime.now(),
                            );
                            if (data == null) return;
                            setDialogState(() {
                              fimFiltro = DateTime(data.year, data.month, data.day, 23, 59, 59);
                            });
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            fimFiltro == null
                                ? 'Fim'
                                : DateFormat('dd/MM/yyyy').format(fimFiltro!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Limpar filtros',
                          onPressed: () {
                            setDialogState(() {
                              operadorFiltro = '';
                              inicioFiltro = null;
                              fimFiltro = null;
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off_outlined),
                        ),
                        if (widget.podeManutencaoAuditoriaCaixa)
                          IconButton(
                          tooltip: 'Manutencao da auditoria',
                          onPressed: () async {
                            final acao = await _abrirManutencaoAuditoriaDialog(
                              filtradosCount: filtrados.length,
                            );
                            if (acao == null) return;
                            if (!context.mounted) return;
                            if (acao == 'older_60' || acao == 'older_90') {
                              final dias = acao == 'older_60' ? 60 : 90;
                              final limite = DateTime.now().subtract(Duration(days: dias));
                              final antes = registros.length;
                              registros = registros.where((item) {
                                final em = DateTime.tryParse((item['em'] ?? '').toString());
                                if (em == null) return false;
                                return !em.isBefore(limite);
                              }).toList();
                              await _salvarAuditoriaCaixa(registros);
                              if (!context.mounted) return;
                              setDialogState(() {});
                              final removidos = antes - registros.length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Manutencao concluida. $removidos registros removidos.'),
                                ),
                              );
                              return;
                            }
                            if (acao == 'filtered') {
                              if (filtrados.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Nao ha registros no filtro atual para remover.'),
                                  ),
                                );
                                return;
                              }
                              final idsFiltrados = filtrados
                                  .map((item) => (item['em'] ?? '').toString() + (item['evento'] ?? '').toString())
                                  .toSet();
                              final antes = registros.length;
                              registros = registros.where((item) {
                                final chave = (item['em'] ?? '').toString() + (item['evento'] ?? '').toString();
                                return !idsFiltrados.contains(chave);
                              }).toList();
                              await _salvarAuditoriaCaixa(registros);
                              if (!context.mounted) return;
                              setDialogState(() {});
                              final removidos = antes - registros.length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Registros filtrados removidos: $removidos.'),
                                ),
                              );
                              return;
                            }
                          },
                          icon: const Icon(Icons.build_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text('Aberturas: ${resumo['aberturas'] ?? 0}'),
                          Text('Suprimentos: ${resumo['suprimentos'] ?? 0}'),
                          Text('Sangrias: ${resumo['sangrias'] ?? 0}'),
                          Text('Fechamentos: ${resumo['fechamentos'] ?? 0}'),
                          Text('Leituras parciais: ${resumo['leituras_parciais'] ?? 0}'),
                          Text('Negados: ${resumo['negados'] ?? 0}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtrados.isEmpty
                          ? const Center(child: Text('Sem registros de auditoria.'))
                          : ListView.builder(
                              itemCount: filtrados.length,
                              itemBuilder: (context, index) {
                                final item = filtrados[filtrados.length - 1 - index];
                                final em = DateTime.tryParse((item['em'] ?? '').toString());
                                final emFmt = em == null ? '-' : dtFmt.format(em.toLocal());
                                final evento = (item['evento'] ?? '-').toString();
                                final usuario = (item['usuario'] ?? '-').toString();
                                final detalhes = item['detalhes'];
                                final detalhesTxt = detalhes is Map ? jsonEncode(detalhes) : '';
                                return ListTile(
                                  dense: true,
                                  title: Text('$emFmt | $evento'),
                                  subtitle: Text(
                                    'Usuario: $usuario${detalhesTxt.isEmpty ? '' : ' | $detalhesTxt'}',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () => _exportarAuditoriaCsv(filtrados),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Exportar CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportarAuditoriaPdf(filtrados),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Exportar PDF'),
                ),
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

  Future<String?> _abrirManutencaoAuditoriaDialog({
    required int filtradosCount,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Manutencao da auditoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Escolha uma acao para limpar registros antigos.'),
              const SizedBox(height: 10),
              Text('Registros no filtro atual: $filtradosCount'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'older_60'),
              child: const Text('Remover > 60 dias'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'older_90'),
              child: const Text('Remover > 90 dias'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'filtered'),
              child: const Text('Remover periodo filtrado'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _abrirGestaoCaixaDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Gestao de Caixa'),
          content: SizedBox(
            width: 760,
            child: _buildConteudoGestaoCaixaDialog(context),
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

  Widget _buildConteudoGestaoCaixaDialog(BuildContext context) {
    final aberturaFmt = _aberturaCaixaEm == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(_aberturaCaixaEm!.toLocal());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_caixaAberto ? 'Status: Aberto' : 'Status: Fechado'),
        Text('Operador: ${_operadorCaixa.trim().isEmpty ? '-' : _operadorCaixa}'),
        Text('Abertura: $aberturaFmt'),
        const SizedBox(height: 4),
        Text('Fundo inicial: ${_formatarMoeda(_fundoTrocoAbertura)}'),
        Text('Suprimentos: ${_formatarMoeda(_totalSuprimentos)}'),
        Text('Sangrias: ${_formatarMoeda(_totalSangrias)}'),
        const SizedBox(height: 10),
        _buildBotoesGestaoCaixa(),
      ],
    );
  }

  List<Map<String, dynamic>> _filtrarRegistrosAuditoria({
    required List<Map<String, dynamic>> registros,
    required String operadorFiltro,
    required DateTime? inicio,
    required DateTime? fim,
  }) {
    final filtro = operadorFiltro.trim().toLowerCase();
    return registros.where((item) {
      final em = DateTime.tryParse((item['em'] ?? '').toString());
      if (inicio != null && (em == null || em.isBefore(inicio))) return false;
      if (fim != null && (em == null || em.isAfter(fim))) return false;
      if (filtro.isNotEmpty) {
        final usuario = (item['usuario'] ?? '').toString().toLowerCase();
        final operador = (item['operadorCaixa'] ?? '').toString().toLowerCase();
        if (!usuario.contains(filtro) && !operador.contains(filtro)) return false;
      }
      return true;
    }).toList();
  }

  Map<String, int> _resumoEventosAuditoria(List<Map<String, dynamic>> registros) {
    int contar(String evento) =>
        registros.where((r) => (r['evento'] ?? '').toString() == evento).length;
    return {
      'aberturas': contar('abertura_caixa'),
      'suprimentos': contar('suprimento'),
      'sangrias': contar('sangria'),
      'fechamentos': contar('fechamento_caixa'),
      'leituras_parciais': contar('leitura_parcial_caixa'),
      'negados': contar('fechamento_negado_divergencia'),
    };
  }

  Future<void> _exportarAuditoriaCsv(List<Map<String, dynamic>> registros) async {
    if (registros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha dados para exportar.')),
      );
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar auditoria em CSV',
      fileName: 'auditoria_caixa_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null) return;
    final buffer = StringBuffer();
    buffer.writeln('data_hora,evento,usuario,operador_caixa,detalhes');
    for (final item in registros) {
      String esc(String v) => '"${v.replaceAll('"', '""')}"';
      final em = (item['em'] ?? '').toString();
      final evento = (item['evento'] ?? '').toString();
      final usuario = (item['usuario'] ?? '').toString();
      final operador = (item['operadorCaixa'] ?? '').toString();
      final detalhes = item['detalhes'] is Map ? jsonEncode(item['detalhes']) : '';
      buffer.writeln(
        '${esc(em)},${esc(evento)},${esc(usuario)},${esc(operador)},${esc(detalhes)}',
      );
    }
    final arquivo = File(path.toLowerCase().endsWith('.csv') ? path : '$path.csv');
    await arquivo.writeAsString(buffer.toString(), encoding: utf8, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV salvo em: ${arquivo.path}')),
    );
  }

  Future<void> _exportarAuditoriaPdf(List<Map<String, dynamic>> registros) async {
    if (registros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha dados para exportar.')),
      );
      return;
    }
    final doc = pw.Document();
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return [
            pw.Text(
              'Auditoria do Caixa',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            ...registros.map((item) {
              final em = DateTime.tryParse((item['em'] ?? '').toString());
              final emFmt = em == null ? '-' : dtFmt.format(em.toLocal());
              final evento = (item['evento'] ?? '-').toString();
              final usuario = (item['usuario'] ?? '-').toString();
              final detalhes = item['detalhes'] is Map ? jsonEncode(item['detalhes']) : '';
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '$emFmt | $evento | usuario: $usuario${detalhes.isEmpty ? '' : ' | $detalhes'}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              );
            }),
          ];
        },
      ),
    );
    final path = await _escolherSalvarPdf(
      bytes: await doc.save(),
      suggestedFileName:
          'auditoria_caixa_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
    );
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF salvo em: $path')),
    );
  }

  Future<void> _abrirCaixa() async {
    if (_caixaAberto) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('O caixa ja esta aberto.')));
      return;
    }
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (config.umCaixaAbertoPorLoja) {
      final outra =
          await CaixaSessaoRepository().obterSessaoAbertaEmOutroTerminal();
      if (outra != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Caixa ja aberto na rede'),
            content: Text(
              'Somente um caixa pode ficar aberto por loja. '
              'Terminal ${outra.terminalId} esta aberto '
              '(operador: ${outra.operador}). '
              'Feche o caixa na outra maquina ou desative a regra em Configuracoes.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
        return;
      }
    }
    final operadorController = TextEditingController(text: widget.usuarioAtual);
    final fundoController = TextEditingController(text: '0,00');
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Abrir caixa'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: operadorController,
                    decoration: const InputDecoration(labelText: 'Operador responsavel'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fundoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Fundo de troco inicial',
                      hintText: 'Ex.: 150,00',
                    ),
                  ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir caixa'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      operadorController.dispose();
      fundoController.dispose();
      return;
    }
    if (!mounted) {
      operadorController.dispose();
      fundoController.dispose();
      return;
    }
    final operador = operadorController.text.trim();
    final fundo = _parseValor(fundoController.text) ?? 0;
    operadorController.dispose();
    fundoController.dispose();
    if (operador.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o operador para abrir o caixa.')),
      );
      return;
    }
    setState(() {
      _caixaAberto = true;
      _operadorCaixa = operador;
      _aberturaCaixaEm = DateTime.now();
      _fundoTrocoAbertura = fundo;
      _totalSuprimentos = 0;
      _totalSangrias = 0;
    });
    await _salvarSessaoCaixa();
    await _registrarAuditoriaCaixa(
      'abertura_caixa',
      detalhes: {
        'operador': operador,
        'fundoTroco': _fundoTrocoAbertura,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Caixa aberto por $operador com fundo ${_formatarMoeda(_fundoTrocoAbertura)}.',
        ),
      ),
    );
  }

  Future<void> _registrarMovimentoCaixa({
    required bool suprimento,
  }) async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abra o caixa antes de registrar movimentos.')),
      );
      return;
    }
    final valorController = TextEditingController();
    final obsController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(suprimento ? 'Registrar suprimento' : 'Registrar sangria'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: valorController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      hintText: 'Ex.: 100,00',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: obsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observacao (opcional)',
                    ),
                  ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      valorController.dispose();
      obsController.dispose();
      return;
    }
    if (!mounted) {
      valorController.dispose();
      obsController.dispose();
      return;
    }
    final valor = _parseValor(valorController.text) ?? 0;
    final obs = obsController.text.trim();
    valorController.dispose();
    obsController.dispose();
    if (valor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um valor valido.')));
      return;
    }
    setState(() {
      if (suprimento) {
        _totalSuprimentos += valor;
      } else {
        _totalSangrias += valor;
      }
    });
    await _salvarSessaoCaixa();
    final dataHora = DateTime.now();
    await _registrarAuditoriaCaixa(
      suprimento ? 'suprimento' : 'sangria',
      detalhes: {
        'valor': valor,
        'observacao': obs,
        'em': dataHora.toIso8601String(),
      },
    );
    if (!mounted) return;
    final tipo = suprimento ? 'Suprimento' : 'Sangria';
    final tipoArquivo = suprimento ? 'suprimento' : 'sangria';
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    CaixaFeedback.sucesso(context, '$tipo de ${_formatarMoeda(valor)} registrado.');
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Comprovante de $tipo',
      content: 'Deseja imprimir o comprovante desta $tipo?',
      suggestedFileName:
          '${tipoArquivo}_caixa_${DateFormat('yyyyMMdd_HHmmss').format(dataHora)}.pdf',
      gerarPdf: () async {
        final layout = config.layoutImpressao.cupom;
        final bytes = await ReciboMovimentoCaixaPdf.gerarBytes(
          suprimento: suprimento,
          valor: valor,
          observacao: obs,
          operadorCaixa: _operadorCaixa,
          terminalId: _terminalId,
          dataHora: dataHora,
          config: config,
          fundoInicial: _fundoTrocoAbertura,
          totalSuprimentos: _totalSuprimentos,
          totalSangrias: _totalSangrias,
        );
        return cupomPdfLegado(
          bytes: bytes,
          config: config,
          layout: layout,
          linhasTexto: 18,
        );
      },
    );
  }

  ({double total, int quantidade}) _resumoRecebimentosFiadoNoPeriodoCaixa() {
    final abertura = _aberturaCaixaEm;
    if (abertura == null) {
      return (total: 0.0, quantidade: 0);
    }
    final lista = widget.vendaRepository.recebimentos.listarNoPeriodo(
      inicio: abertura,
      fim: DateTime.now(),
    );
    return (
      total: lista.fold<double>(0, (s, r) => s + r.valorTotal),
      quantidade: lista.length,
    );
  }

  Map<String, double> _totaisEsperadosFechamento() {
    final abertura = _aberturaCaixaEm;
    final agora = DateTime.now();
    final totais = widget.vendaRepository.totaisMeiosPagamentoVendasFinalizadas(
      inicio: abertura,
      fim: agora,
    );
    var dinheiro = totais.dinheiro;
    var pix = totais.pix;
    var debito = totais.debito;
    var credito = totais.credito;
    if (abertura != null) {
      for (final rec in widget.vendaRepository.recebimentos.listarNoPeriodo(
        inicio: abertura,
        fim: agora,
      )) {
        switch (rec.formaPagamento) {
          case 'pix':
            pix += rec.valorTotal;
            break;
          case 'cartao_debito':
            debito += rec.valorTotal;
            break;
          case 'cartao_credito':
            credito += rec.valorTotal;
            break;
          case 'dinheiro':
          default:
            dinheiro += rec.valorTotal;
        }
      }
    }
    final dinheiroEsperado = (_fundoTrocoAbertura + dinheiro + _totalSuprimentos - _totalSangrias)
        .clamp(0, double.infinity)
        .toDouble();
    return {
      'dinheiro': dinheiroEsperado,
      'pix': pix,
      'debito': debito,
      'credito': credito,
    };
  }

  ({double totalVendas, int quantidadeVendas}) _totalVendasNoPeriodoCaixa() {
    final abertura = _aberturaCaixaEm;
    final agora = DateTime.now();
    final resumo = widget.vendaRepository.resumoVendasFinalizadasNoPeriodo(
      inicio: abertura,
      fim: agora,
    );
    return (
      totalVendas: resumo.totalVendas,
      quantidadeVendas: resumo.quantidadeVendas,
    );
  }

  Future<void> _abrirReceberFiado() async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abra o caixa antes de receber pagamentos de fiado.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Receber fiado'),
          content: SizedBox(
            width: 720,
            height: 520,
            child: ReceberFiadoPanel(
              vendaRepository: widget.vendaRepository,
              clienteRepository: widget.clienteRepository,
              onRecebimentoRegistrado: (resultado) {
                _aposRecebimentoFiadoNoCaixa(resultado);
              },
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

  Future<void> _aposRecebimentoFiadoNoCaixa(
    RecebimentoFiadoResultado resultado,
  ) async {
    await _registrarAuditoriaCaixa(
      'recebimento_fiado',
      detalhes: {
        'recebimentoId': resultado.recebimentoId,
        'clienteId': resultado.cliente.id,
        'clienteNome': resultado.cliente.nomeRazao,
        'valor': resultado.valorTotal,
        'formaPagamento': resultado.formaPagamento,
      },
    );
    if (!mounted) return;

    final rotuloForma = _rotuloFormaPagamento(resultado.formaPagamento);
    final acaoRecibo = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Recebimento registrado'),
        content: Text(
          '${resultado.cliente.nomeRazao}\n'
          'Valor: ${_formatarMoeda(resultado.valorTotal)}\n'
          'Forma: $rotuloForma\n\n'
          'O valor entrou no fluxo do caixa (fechamento/leitura parcial).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'fechar'),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'recibo'),
            icon: const Icon(Icons.receipt_outlined),
            label: const Text('Recibo (opcional)'),
          ),
        ],
      ),
    );
    if (!mounted || acaoRecibo != 'recibo') return;

    final rec = widget.vendaRepository.recebimentos.obterPorId(
      resultado.recebimentoId,
    );
    if (rec == null) return;

    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;

    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Recibo de pagamento (fiado)',
      content: 'Deseja imprimir o recibo para o cliente?',
      suggestedFileName:
          'recibo_fiado_${resultado.cliente.id}_${rec.id}.pdf',
      gerarPdf: () async {
        final layout = config.layoutImpressao.cupom;
        final bytes = await ReciboRecebimentoFiadoPdf.gerarBytes(
          recebimento: rec,
          cliente: resultado.cliente,
          vendaRepository: widget.vendaRepository,
          config: config,
          operadorCaixa: _operadorCaixa,
        );
        return cupomPdfLegado(
          bytes: bytes,
          config: config,
          layout: layout,
          linhasTexto: 20,
        );
      },
    );
  }

  Future<void> _mostrarLeituraParcial() async {
    if (!widget.podeLeituraParcialCaixa) {
      return;
    }
    if (!_caixaAberto) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abra o caixa para consultar a leitura parcial.'),
        ),
      );
      return;
    }
    final esperados = _totaisEsperadosFechamento();
    final vendas = _totalVendasNoPeriodoCaixa();
    final recFiado = _resumoRecebimentosFiadoNoPeriodoCaixa();
    await _registrarAuditoriaCaixa(
      'leitura_parcial_caixa',
      detalhes: {
        'totalVendas': vendas.totalVendas,
        'quantidadeVendas': vendas.quantidadeVendas,
        'recebimentosFiado': recFiado.total,
        'quantidadeRecebimentosFiado': recFiado.quantidade,
        'esperadoDinheiro': esperados['dinheiro'] ?? 0,
        'esperadoPix': esperados['pix'] ?? 0,
        'esperadoDebito': esperados['debito'] ?? 0,
        'esperadoCredito': esperados['credito'] ?? 0,
      },
    );
    if (!mounted) return;
    final aberturaFmt = _aberturaCaixaEm == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(_aberturaCaixaEm!.toLocal());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leitura parcial do caixa'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Resumo desde a abertura ($aberturaFmt) ate agora, '
                    'sem fechar o caixa.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Vendas finalizadas',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text('Quantidade: ${vendas.quantidadeVendas}'),
                  Text('Total em vendas: ${_formatarMoeda(vendas.totalVendas)}'),
                  const SizedBox(height: 8),
                  Text(
                    'Recebimentos de fiado: ${recFiado.quantidade} '
                    '(${_formatarMoeda(recFiado.total)})',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Recebimentos por forma de pagamento (esperado)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Inclui vendas do periodo + quitacoes de fiado no caixa.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dinheiro na gaveta (fundo + vendas em dinheiro + '
                    'suprimentos - sangrias): ${_formatarMoeda(esperados['dinheiro'] ?? 0)}',
                  ),
                  Text('PIX: ${_formatarMoeda(esperados['pix'] ?? 0)}'),
                  Text(
                    'Cartao debito: ${_formatarMoeda(esperados['debito'] ?? 0)}',
                  ),
                  Text(
                    'Cartao credito: ${_formatarMoeda(esperados['credito'] ?? 0)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fundo inicial: ${_formatarMoeda(_fundoTrocoAbertura)} | '
                    'Suprimentos: ${_formatarMoeda(_totalSuprimentos)} | '
                    'Sangrias: ${_formatarMoeda(_totalSangrias)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
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

  Future<void> _fecharCaixa() async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('O caixa ja esta fechado.')));
      return;
    }
    final esperados = _totaisEsperadosFechamento();
    final dinheiroController = TextEditingController(text: '0,00');
    final pixController = TextEditingController(text: '0,00');
    final debitoController = TextEditingController(text: '0,00');
    final creditoController = TextEditingController(text: '0,00');
    final obsController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Fechamento de caixa'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLinhaConferenciaFechamento(
                    label: 'Dinheiro',
                    controller: dinheiroController,
                  ),
                  const SizedBox(height: 8),
                  _buildLinhaConferenciaFechamento(
                    label: 'PIX',
                    controller: pixController,
                  ),
                  const SizedBox(height: 8),
                  _buildLinhaConferenciaFechamento(
                    label: 'Cartao debito',
                    controller: debitoController,
                  ),
                  const SizedBox(height: 8),
                  _buildLinhaConferenciaFechamento(
                    label: 'Cartao credito',
                    controller: creditoController,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: obsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observacao de fechamento',
                    ),
                  ),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar fechamento'),
            ),
          ],
        );
      },
    );
    final declaradoDinheiro = _parseValor(dinheiroController.text) ?? 0;
    final declaradoPix = _parseValor(pixController.text) ?? 0;
    final declaradoDebito = _parseValor(debitoController.text) ?? 0;
    final declaradoCredito = _parseValor(creditoController.text) ?? 0;
    final obs = obsController.text.trim();
    dinheiroController.dispose();
    pixController.dispose();
    debitoController.dispose();
    creditoController.dispose();
    obsController.dispose();
    if (confirmar != true) return;
    final difDinheiro = declaradoDinheiro - (esperados['dinheiro'] ?? 0);
    final difPix = declaradoPix - (esperados['pix'] ?? 0);
    final difDebito = declaradoDebito - (esperados['debito'] ?? 0);
    final difCredito = declaradoCredito - (esperados['credito'] ?? 0);
    final difTotal = difDinheiro + difPix + difDebito + difCredito;
    final autorizado = await _autorizarSupervisorSeNecessario(difTotal);
    if (!autorizado) {
      await _registrarAuditoriaCaixa(
        'fechamento_negado_divergencia',
        detalhes: {
          'diferencaTotal': difTotal,
        },
      );
      return;
    }
    final operadorFechamento = _operadorCaixa;
    final aberturaFechamento = _aberturaCaixaEm;
    final fundoAbertura = _fundoTrocoAbertura;
    final suprimentos = _totalSuprimentos;
    final sangrias = _totalSangrias;
    final fechamentoEm = DateTime.now();
    setState(() {
      _caixaAberto = false;
      _operadorCaixa = '';
      _aberturaCaixaEm = null;
      _fundoTrocoAbertura = 0;
      _totalSuprimentos = 0;
      _totalSangrias = 0;
    });
    await _salvarSessaoCaixa();
    await _registrarAuditoriaCaixa(
      'fechamento_caixa',
      detalhes: {
        'operador': operadorFechamento,
        'fundoTroco': fundoAbertura,
        'suprimentos': suprimentos,
        'sangrias': sangrias,
        'esperadoDinheiro': esperados['dinheiro'] ?? 0,
        'esperadoPix': esperados['pix'] ?? 0,
        'esperadoDebito': esperados['debito'] ?? 0,
        'esperadoCredito': esperados['credito'] ?? 0,
        'declaradoDinheiro': declaradoDinheiro,
        'declaradoPix': declaradoPix,
        'declaradoDebito': declaradoDebito,
        'declaradoCredito': declaradoCredito,
        'diferencaTotal': difTotal,
        'observacao': obs,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Caixa fechado. Diferenca total: ${_formatarMoeda(difTotal)}.'
          '${obs.isEmpty ? '' : ' Obs: $obs'}',
        ),
      ),
    );
    await _mostrarAcoesRelatorioFechamentoCaixa(
      operador: operadorFechamento,
      aberturaEm: aberturaFechamento,
      fechamentoEm: fechamentoEm,
      fundoTroco: fundoAbertura,
      suprimentos: suprimentos,
      sangrias: sangrias,
      esperadoDinheiro: esperados['dinheiro'] ?? 0,
      esperadoPix: esperados['pix'] ?? 0,
      esperadoDebito: esperados['debito'] ?? 0,
      esperadoCredito: esperados['credito'] ?? 0,
      declaradoDinheiro: declaradoDinheiro,
      declaradoPix: declaradoPix,
      declaradoDebito: declaradoDebito,
      declaradoCredito: declaradoCredito,
      observacao: obs,
    );
  }

  Future<Uint8List> _gerarRelatorioFechamentoPdfBytes({
    required String operador,
    required DateTime? aberturaEm,
    required DateTime fechamentoEm,
    required double fundoTroco,
    required double suprimentos,
    required double sangrias,
    required double esperadoDinheiro,
    required double esperadoPix,
    required double esperadoDebito,
    required double esperadoCredito,
    required double declaradoDinheiro,
    required double declaradoPix,
    required double declaradoDebito,
    required double declaradoCredito,
    required String observacao,
  }) async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(
            config.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final doc = pw.Document();
    double dif(double declarado, double esperado) => declarado - esperado;
    final diferencaTotal = dif(declaradoDinheiro, esperadoDinheiro) +
        dif(declaradoPix, esperadoPix) +
        dif(declaradoDebito, esperadoDebito) +
        dif(declaradoCredito, esperadoCredito);
    pw.Widget linha(String forma, double esperado, double declarado) {
      final delta = dif(declarado, esperado);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          children: [
            pw.Expanded(flex: 2, child: pw.Text(forma)),
            pw.Expanded(child: pw.Text('Esp: ${_formatarMoeda(esperado)}')),
            pw.Expanded(child: pw.Text('Dec: ${_formatarMoeda(declarado)}')),
            pw.Expanded(
              child: pw.Text(
                'Dif: ${_formatarMoeda(delta)}',
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  config.nomeLoja,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 48),
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  'RELATORIO DE FECHAMENTO DE CAIXA (X/Z)',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Operador: ${operador.isEmpty ? '-' : operador}'),
              pw.Text(
                'Abertura: ${aberturaEm == null ? '-' : dtFmt.format(aberturaEm.toLocal())}',
              ),
              pw.Text('Fechamento: ${dtFmt.format(fechamentoEm.toLocal())}'),
              pw.SizedBox(height: 8),
              pw.Text('Fundo inicial: ${_formatarMoeda(fundoTroco)}'),
              pw.Text('Suprimentos: ${_formatarMoeda(suprimentos)}'),
              pw.Text('Sangrias: ${_formatarMoeda(sangrias)}'),
              pw.Divider(),
              pw.Text(
                'Conferencia por forma de pagamento',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              linha('Dinheiro', esperadoDinheiro, declaradoDinheiro),
              linha('PIX', esperadoPix, declaradoPix),
              linha('Cartao debito', esperadoDebito, declaradoDebito),
              linha('Cartao credito', esperadoCredito, declaradoCredito),
              pw.Divider(),
              pw.Text(
                'Diferenca total: ${_formatarMoeda(diferencaTotal)} '
                '${diferencaTotal.abs() < 0.01 ? '(sem divergencia)' : diferencaTotal > 0 ? '(sobra)' : '(falta)'}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              if (observacao.trim().isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text(
                  'Observacao: $observacao',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _mostrarAcoesRelatorioFechamentoCaixa({
    required String operador,
    required DateTime? aberturaEm,
    required DateTime fechamentoEm,
    required double fundoTroco,
    required double suprimentos,
    required double sangrias,
    required double esperadoDinheiro,
    required double esperadoPix,
    required double esperadoDebito,
    required double esperadoCredito,
    required double declaradoDinheiro,
    required double declaradoPix,
    required double declaradoDebito,
    required double declaradoCredito,
    required String observacao,
  }) async {
    if (!mounted) return;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Relatorio de fechamento'),
          content: const Text('Deseja imprimir o fechamento ou salvar em PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Salvar PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'direto'),
              icon: const Icon(Icons.print),
              label: const Text('Impressao direta'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    try {
      final pdfBytes = await _gerarRelatorioFechamentoPdfBytes(
        operador: operador,
        aberturaEm: aberturaEm,
        fechamentoEm: fechamentoEm,
        fundoTroco: fundoTroco,
        suprimentos: suprimentos,
        sangrias: sangrias,
        esperadoDinheiro: esperadoDinheiro,
        esperadoPix: esperadoPix,
        esperadoDebito: esperadoDebito,
        esperadoCredito: esperadoCredito,
        declaradoDinheiro: declaradoDinheiro,
        declaradoPix: declaradoPix,
        declaradoDebito: declaradoDebito,
        declaradoCredito: declaradoCredito,
        observacao: observacao,
      );
      if (acao == 'imprimir') {
        await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
        return;
      }
      if (acao == 'direto') {
        final printer = await widget.printService
            .resolverImpressoraPorNome(config.impressoraPadrao);
        if (printer == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impressora padrao nao configurada/encontrada.')),
          );
          return;
        }
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdfBytes,
          name: 'Fechamento Caixa ${DateFormat('yyyyMMdd_HHmm').format(fechamentoEm)}',
          format: PdfPageFormat.a4,
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdfBytes,
        suggestedFileName:
            'fechamento_caixa_${DateFormat('yyyyMMdd_HHmm').format(fechamentoEm)}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Relatorio salvo em: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel gerar/imprimir relatorio: $e')),
      );
    }
  }

  double _descontoAplicado(Venda venda) => 0;

  double _totalComDesconto(Venda venda) => venda.total;

  /// Linhas do misto com valores proporcionais ao [totalComDesconto] exibido no caixa.
  List<PagamentoOrcamentoLinha> _linhasPagamentoEscaladasCaixa(
    Venda v,
    double totalComDesconto,
  ) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return const [];
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return const [];
    final fator = totalComDesconto / soma;
    return linhas
        .map(
          (l) => PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: (l.valor * fator),
            parcelas: l.parcelas,
          ),
        )
        .toList();
  }

  void _disposeMistoEdicao() {
    for (final c in _mistoValorControllers) {
      c.dispose();
    }
    _mistoValorControllers.clear();
    for (final f in _mistoValorFocusNodes) {
      f.dispose();
    }
    _mistoValorFocusNodes.clear();
    _mistoLinhasModelo.clear();
    _mistoPreparadoParaId = null;
  }

  /// Prepara campos do misto para conferencia manual no caixa.
  /// Os valores iniciam zerados para o operador digitar o recebido.
  void _prepararEdicaoMisto(Venda v) {
    _disposeMistoEdicao();
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return;
    }
    final tv = _totalComDesconto(v);
    final scaled = _linhasPagamentoEscaladasCaixa(v, tv);
    _mistoLinhasModelo = List<PagamentoOrcamentoLinha>.from(scaled);
    for (final linha in scaled) {
      final textoValor = linha.meio == 'fiado'
          ? linha.valor.toStringAsFixed(2).replaceAll('.', ',')
          : '0,00';
      _mistoValorControllers.add(TextEditingController(text: textoValor));
      _mistoValorFocusNodes.add(FocusNode());
    }
    _mistoPreparadoParaId = v.id;
  }

  double _valorFiadoMistoOrcamentoCaixa() =>
      PagamentoOrcamentoCodec.somaPorMeio(_mistoLinhasModelo, 'fiado');

  double _somaMistoRecebidaNoCaixaAgora() {
    final linhas = _linhasMistoDoFormulario();
    return linhas
        .where((l) => l.meio != 'fiado')
        .fold<double>(0, (s, l) => s + l.valor);
  }

  List<PagamentoOrcamentoLinha> _linhasMistoDoFormulario() {
    if (_mistoLinhasModelo.length != _mistoValorControllers.length) {
      return const [];
    }
    final out = <PagamentoOrcamentoLinha>[];
    for (var i = 0; i < _mistoLinhasModelo.length; i++) {
      final m = _mistoLinhasModelo[i];
      final valor = _parseValor(_mistoValorControllers[i].text) ?? 0;
      out.add(
        PagamentoOrcamentoLinha(
          meio: m.meio,
          valor: valor,
          parcelas: m.parcelas,
        ),
      );
    }
    return out;
  }

  String? _validarConferenciaMistoIgualOrcamento(Venda venda, double totalComDesconto) {
    final informado = _linhasMistoDoFormulario();
    final esperado = _linhasPagamentoEscaladasCaixa(venda, totalComDesconto);
    if (informado.length != esperado.length) {
      return 'Pagamento misto invalido para conferencia no caixa.';
    }
    for (var i = 0; i < esperado.length; i++) {
      final linhaEsperada = esperado[i];
      final linhaInformada = informado[i];
      if (linhaEsperada.meio == 'fiado') {
        continue;
      }
      if ((linhaInformada.valor - linhaEsperada.valor).abs() > _tolMistoPagamento) {
        final sufixoParcelas = linhaEsperada.meio == 'cartao_credito'
            ? ' (${linhaEsperada.parcelas}x)'
            : '';
        return 'Valor divergente em ${_rotuloFormaPagamento(linhaEsperada.meio)}$sufixoParcelas. '
            'Esperado: ${_formatarMoeda(linhaEsperada.valor)}.';
      }
    }
    return null;
  }

  void _recarregarOrcamentoSelecionadoAposAjusteItens() {
    final id = _selecionado?.id;
    if (id == null) return;
    _carregarOrcamentos();
    final atualizado = widget.vendaRepository.obterPorId(id);
    if (atualizado == null || !mounted) return;
    final avisoPagamento = atualizado.formaPagamento == 'misto' ||
        (atualizado.formaPagamento == 'fiado' &&
            atualizado.planoFiadoJson.trim().isNotEmpty);
    setState(() {
      _selecionado = atualizado;
      _prepararEdicaoMisto(atualizado);
      _sincronizarRecebidoPdVComOrcamento();
    });
    if (avisoPagamento) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Total atualizado. Revise valores de pagamento na cobranca.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _alterarQuantidadeItemConferencia(
    Venda venda,
    ItemVenda item,
    int delta,
  ) async {
    if (_etapaCaixa != CaixaEtapa.conferencia) return;
    final novaQtd = item.quantidade + delta;
    if (novaQtd <= 0) {
      await _removerItemConferencia(venda, item);
      return;
    }
    try {
      widget.vendaRepository.atualizarQuantidadeItemOrcamento(
        venda.id,
        item.id,
        novaQtd,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
      await _registrarAuditoriaCaixa(
        'ajuste_quantidade_item_orcamento',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'itemId': item.id,
          'produto': item.nomeProduto,
          'quantidadeAnterior': item.quantidade,
          'quantidadeNova': novaQtd,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      CaixaFeedback.sucesso(
        context,
        'Quantidade atualizada: ${item.nomeProduto} ($novaQtd).',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel alterar quantidade: $e');
    }
  }

  Future<void> _removerItemConferencia(Venda venda, ItemVenda item) async {
    if (_etapaCaixa != CaixaEtapa.conferencia) return;
    if (venda.itens.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O orcamento precisa manter ao menos um item.'),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover item do orcamento?'),
        content: Text(
          '${item.nomeProduto}\n\n'
          'Quantidade: ${item.quantidade}\n'
          'Valor da linha: ${_formatarMoeda(item.subtotal)}\n\n'
          'O total sera recalculado automaticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final autorizado = await solicitarAutorizacaoGerenteCaixa(
      context,
      _usuarioRepository,
    );
    if (!autorizado || !mounted) return;

    try {
      widget.vendaRepository.removerItemOrcamento(venda.id, item.id);
      await _registrarAuditoriaCaixa(
        'remover_item_orcamento_caixa',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'itemId': item.id,
          'produto': item.nomeProduto,
          'quantidade': item.quantidade,
          'subtotal': item.subtotal,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      CaixaFeedback.sucesso(
        context,
        'Item removido. Total do orcamento atualizado.',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel remover item: $e');
    }
  }

  String? get _segmentoClienteConferencia {
    final id = _selecionado?.cliente.targetId ?? 0;
    if (id <= 0) return null;
    return _clienteDaVenda(_selecionado!)?.segmento;
  }

  String _precoListaPadraoConferencia(Venda venda) {
    if (venda.itens.isEmpty) return 'preco1';
    final t = venda.itens.first.precoTipo.trim();
    if (t == PromocaoCadastro.precoTipoPromo) return 'preco1';
    return t.isEmpty ? 'preco1' : t;
  }

  String _tipoEntregaPadraoConferencia(Venda venda) {
    if (venda.itens.isEmpty) {
      return EntregaVendaHelper.tipoRetirada;
    }
    return EntregaVendaHelper.normalizarTipoItem(
      venda.itens.first.tipoEntregaItem,
    );
  }

  String _rotuloPrecoConferencia(String precoTipo) => switch (precoTipo) {
        PromocaoCadastro.precoTipoPromo => 'Promocao',
        'preco2' => 'A Vista',
        'preco3' => 'Atacado',
        _ => 'A Prazo',
      };

  double _precoExibicaoConsultaConferencia(Produto produto, String precoTipo) {
    return _promoPreco
        .resolver(
          produto,
          dataReferencia: DateTime.now(),
          precoTipoLista: precoTipo,
          segmentoCliente: _segmentoClienteConferencia,
        )
        .precoFinal;
  }

  int _quantidadeProdutoNoOrcamentoSelecionado(int produtoId) {
    final v = _selecionado;
    if (v == null) return 0;
    var soma = 0;
    for (final item in v.itens) {
      if (item.produto.targetId == produtoId) {
        soma += item.quantidade;
      }
    }
    return soma;
  }

  void _registrarProdutoRecenteConferencia(int produtoId) {
    if (produtoId <= 0) return;
    _produtosRecentesConferencia.remove(produtoId);
    _produtosRecentesConferencia.insert(0, produtoId);
    if (_produtosRecentesConferencia.length > 30) {
      _produtosRecentesConferencia.removeRange(30, _produtosRecentesConferencia.length);
    }
  }

  Future<void> _abrirConsultaProdutoConferencia({String? termo}) async {
    final venda = _selecionado;
    if (venda == null || _etapaCaixa != CaixaEtapa.conferencia) return;

    final texto = (termo ?? _pesquisaProdutoConferenciaController.text).trim();
    final precoLista = _precoListaPadraoConferencia(venda);
    final clienteId = venda.cliente.targetId;
    final cid = clienteId > 0 ? clienteId : null;

    final result = await Navigator.of(context).push<PdvConsultaProdutoResult>(
      MaterialPageRoute(
        builder: (_) => PdvConsultaProdutosPage(
          produtoRepository: widget.produtoRepository,
          vendaRepository: widget.vendaRepository,
          termoInicial: texto,
          precoListaAtivoInicial: precoLista,
          clienteId: cid,
          produtosRecentesIds: List<int>.from(_produtosRecentesConferencia),
          formatarMoeda: _formatarMoeda,
          rotuloPreco: _rotuloPrecoConferencia,
          precoUnitarioDe: _precoExibicaoConsultaConferencia,
          resolverPromocao: (p, t) => _promoPreco.resolver(
            p,
            dataReferencia: DateTime.now(),
            precoTipoLista: t,
            segmentoCliente: _segmentoClienteConferencia,
          ),
          campanhasVigentesDe: (p) => _promoPreco.listarCampanhasVigentesParaProduto(
            p,
            dataReferencia: DateTime.now(),
            segmentoCliente: _segmentoClienteConferencia,
          ),
        ),
      ),
    );

    if (!mounted) return;
    _pesquisaProdutoConferenciaController.clear();
    if (result == null) {
      _pesquisaProdutoConferenciaFocus.requestFocus();
      return;
    }

    await _aplicarProdutoConsultaConferencia(venda, result, precoLista);
  }

  Future<void> _aplicarProdutoConsultaConferencia(
    Venda venda,
    PdvConsultaProdutoResult result,
    String precoLista,
  ) async {
    _registrarProdutoRecenteConferencia(result.produto.id);

    if (result.adicaoDireta) {
      await _adicionarProdutoAoOrcamentoConferencia(
        venda,
        result.produto,
        1,
        precoLista: result.precoListaAtivo.isNotEmpty
            ? result.precoListaAtivo
            : precoLista,
      );
      return;
    }
    if (result.quantidadeDireta != null && result.quantidadeDireta! > 0) {
      await _adicionarProdutoAoOrcamentoConferencia(
        venda,
        result.produto,
        result.quantidadeDireta!,
        precoLista: result.precoListaAtivo.isNotEmpty
            ? result.precoListaAtivo
            : precoLista,
      );
      return;
    }

    final qtd = await _perguntarQuantidadeProdutoConferencia(
      result.produto,
      quantidadeSugerida: 1,
    );
    if (qtd == null || !mounted) return;
    await _adicionarProdutoAoOrcamentoConferencia(
      venda,
      result.produto,
      qtd,
      precoLista: result.precoListaAtivo.isNotEmpty
          ? result.precoListaAtivo
          : precoLista,
    );
  }

  Future<int?> _perguntarQuantidadeProdutoConferencia(
    Produto produto, {
    required int quantidadeSugerida,
  }) async {
    final ctrl = TextEditingController(text: '$quantidadeSugerida');
    final qtd = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quantidade — ${produto.nome}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantidade',
            hintText: 'Ex.: 1',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final q = int.tryParse(ctrl.text.trim());
              if (q == null || q <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Informe quantidade valida.')),
                );
                return;
              }
              Navigator.pop(ctx, q);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return qtd;
  }

  Future<void> _adicionarProdutoAoOrcamentoConferencia(
    Venda venda,
    Produto produto,
    int quantidade, {
    required String precoLista,
  }) async {
    if (quantidade <= 0) return;

    final resPreco = _promoPreco.resolver(
      produto,
      dataReferencia: DateTime.now(),
      quantidade: quantidade,
      precoTipoLista: precoLista,
      segmentoCliente: _segmentoClienteConferencia,
    );

    if (resPreco.emPromocao) {
      if (resPreco.quantidadeMaximaPorVenda > 0 &&
          quantidade > resPreco.quantidadeMaximaPorVenda) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite da promocao: max. ${resPreco.quantidadeMaximaPorVenda} '
              'un. para ${produto.nome}.',
            ),
          ),
        );
        return;
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
          if (!ok || !mounted) return;
        }
      }
    }

    if (!_permitirVendaSemEstoque) {
      final fresh = widget.produtoRepository.obterPorId(produto.id) ?? produto;
      final disp = fresh.estoqueLivreParaVenda;
      final ja = _quantidadeProdutoNoOrcamentoSelecionado(produto.id);
      if (ja + quantidade > disp) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque insuficiente para ${produto.nome}. '
              'Disponivel: $disp (ja no orcamento: $ja).',
            ),
          ),
        );
        return;
      }
    }

    try {
      widget.vendaRepository.adicionarItemAoOrcamento(
        venda.id,
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: quantidade,
          precoUnitario: resPreco.precoFinal,
          precoTipo: resPreco.precoTipo,
          tipoEntregaItem: _tipoEntregaPadraoConferencia(venda),
          promocaoId: resPreco.promocaoId,
          promocaoNomeSnapshot: resPreco.promocaoNome,
        ),
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
      await _registrarAuditoriaCaixa(
        'adicionar_item_orcamento_caixa',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'produtoId': produto.id,
          'produto': produto.nome,
          'quantidade': quantidade,
          'precoUnitario': resPreco.precoFinal,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      CaixaFeedback.sucesso(
        context,
        '${produto.nome} adicionado ($quantidade un.).',
      );
      _pesquisaProdutoConferenciaFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel adicionar produto: $e');
    }
  }

  Widget _buildBarraBuscaProdutoConferencia(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _pesquisaProdutoConferenciaController,
            focusNode: _pesquisaProdutoConferenciaFocus,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Adicionar produto',
              hintText: 'Nome, codigo, barras — Enter ou F5',
              prefixIcon: Icon(Icons.search, size: 20),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => unawaited(_abrirConsultaProdutoConferencia(termo: v)),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: () => unawaited(_abrirConsultaProdutoConferencia()),
          icon: const Icon(Icons.add_shopping_cart_outlined),
          label: const Text('Buscar (F5)'),
        ),
      ],
    );
  }

  Future<void> _alterarFormaPagamentoCaixa(Venda venda) async {
    final autorizado = await solicitarAutorizacaoGerenteCaixa(
      context,
      _usuarioRepository,
    );
    if (!autorizado || !mounted) return;

    final totalExibido = _totalComDesconto(venda);
    final resultado = await showDialog<DadosPagamentoOrcamento>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlterarPagamentoCaixaDialog(
        venda: venda,
        totalExibidoCaixa: totalExibido,
        totalGravacaoOrcamento: venda.total,
        clienteVinculado: venda.cliente.targetId > 0,
        formatarMoeda: _formatarMoeda,
      ),
    );
    if (resultado == null || !mounted) return;

    try {
      widget.vendaRepository.alterarPagamentoOrcamento(venda.id, resultado);
      _carregarOrcamentos();
      if (!mounted) return;
      final atualizado = widget.vendaRepository.obterPorId(venda.id);
      if (atualizado != null) {
        setState(() {
          _selecionado = atualizado;
          _prepararEdicaoMisto(atualizado);
          _sincronizarRecebidoPdVComOrcamento();
        });
      }
      CaixaFeedback.sucesso(
        context,
        'Forma de pagamento atualizada. Confira os valores e finalize.',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel alterar pagamento: $e');
    }
  }

  static const double _tolMistoPagamento = 0.05;

  /// Reduz linhas do formulario do caixa para somar [targetTotal] (valor da venda).
  /// Quando o cliente paga a mais (ex.: entrega nota maior em dinheiro), o excesso
  /// vira troco e nao entra na soma gravada no orcamento.
  List<PagamentoOrcamentoLinha> _normalizarLinhasMistoGravacao(
    List<PagamentoOrcamentoLinha> form,
    double targetTotal,
  ) {
    if (form.isEmpty) return form;
    final soma = PagamentoOrcamentoCodec.soma(form);
    if (soma <= targetTotal + _tolMistoPagamento) {
      return List<PagamentoOrcamentoLinha>.from(form);
    }
    final nd = <PagamentoOrcamentoLinha>[];
    for (final l in form) {
      if (l.meio != 'dinheiro') {
        nd.add(l);
      }
    }
    final sNd = PagamentoOrcamentoCodec.soma(nd);
    if (sNd < targetTotal - 1e-6) {
      final dVenda = targetTotal - sNd;
      return [
        ...nd.map(
          (l) => PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: l.valor,
            parcelas: l.parcelas,
          ),
        ),
        PagamentoOrcamentoLinha(meio: 'dinheiro', valor: dVenda, parcelas: 1),
      ];
    }
    return _escalarLinhasParaTotalMisto(nd, targetTotal);
  }

  List<PagamentoOrcamentoLinha> _escalarLinhasParaTotalMisto(
    List<PagamentoOrcamentoLinha> linhas,
    double targetTotal,
  ) {
    if (linhas.isEmpty) return linhas;
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return linhas;
    final fator = targetTotal / soma;
    final out = <PagamentoOrcamentoLinha>[];
    for (final l in linhas) {
      out.add(
        PagamentoOrcamentoLinha(
          meio: l.meio,
          valor: l.valor * fator,
          parcelas: l.parcelas,
        ),
      );
    }
    var soma2 = PagamentoOrcamentoCodec.soma(out);
    final diff = targetTotal - soma2;
    if (out.isNotEmpty && diff.abs() > 1e-4) {
      final i = out.length - 1;
      final u = out[i];
      out[i] = PagamentoOrcamentoLinha(
        meio: u.meio,
        valor: (u.valor + diff).clamp(0, double.infinity),
        parcelas: u.parcelas,
      );
    }
    return out;
  }

  /// Parte em dinheiro apos desconto do caixa (escala proporcional ao total).
  double _parteDinheiroNaFinalizacao(Venda v, double totalComDesconto) {
    if (v.formaPagamento != 'misto') {
      return v.formaPagamento == 'dinheiro' ? totalComDesconto : 0;
    }
    final linhasForm = _linhasMistoDoFormulario();
    if (linhasForm.isNotEmpty) {
      return PagamentoOrcamentoCodec.somaPorMeio(linhasForm, 'dinheiro');
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return 0;
    final parte = PagamentoOrcamentoCodec.somaPorMeio(linhas, 'dinheiro');
    return parte * (totalComDesconto / soma);
  }

  /// Campo separado de especie/troco: apenas venda 100% em dinheiro.
  /// No pagamento misto, valores e conferencia ficam no painel misto.
  bool _caixaPrecisaValorRecebidoDinheiro(Venda v) {
    return v.formaPagamento == 'dinheiro';
  }

  /// Preenche valor recebido com a parte em dinheiro ja definida no PDV (apos desconto).
  void _sincronizarRecebidoPdVComOrcamento() {
    final v = _selecionado;
    if (v == null) return;
    if (v.formaPagamento == 'misto') {
      final linhas = _linhasMistoDoFormulario();
      final d = PagamentoOrcamentoCodec.somaPorMeio(linhas, 'dinheiro');
      if (d > 0.001) {
        final texto = d.toStringAsFixed(2).replaceAll('.', ',');
        _valorRecebidoController.value = TextEditingValue(
          text: texto,
          selection: TextSelection.collapsed(offset: texto.length),
        );
        _valorRecebido = d;
      } else {
        _valorRecebidoController.clear();
        _valorRecebido = null;
      }
      return;
    }
    final tv = _totalComDesconto(v);
    final parte = _parteDinheiroNaFinalizacao(v, tv);
    if (parte > 0.001) {
      final texto = parte.toStringAsFixed(2).replaceAll('.', ',');
      _valorRecebidoController.value = TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
      _valorRecebido = parte;
    } else {
      _valorRecebidoController.clear();
      _valorRecebido = null;
    }
  }

  String _textoDetalheLinhasPagamento(List<PagamentoOrcamentoLinha> linhas) {
    if (linhas.isEmpty) return '';
    return linhas
        .map(
          (l) =>
              '${_rotuloFormaPagamento(l.meio)} ${_formatarMoeda(l.valor)}'
              '${l.meio == 'cartao_credito' ? ' ${l.parcelas}x' : ''}',
        )
        .join(' + ');
  }

  String _rotuloPagamentoCabecalho(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return '${_rotuloFormaPagamento(v.formaPagamento)}'
          '${v.formaPagamento == 'cartao_credito' ? ' | ${v.quantidadeParcelas}x' : ''}';
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    if (linhas.isEmpty) return 'Misto';
    return _textoDetalheLinhasPagamento(linhas);
  }

  /// Na finalizacao, valores do misto no caixa podem divergir do JSON do orcamento ate gravar.
  String _rotuloPagamentoResumoNaFinalizacao(Venda venda) {
    if (venda.formaPagamento == 'misto') {
      final textoForm = _textoDetalheLinhasPagamento(_linhasMistoDoFormulario());
      if (textoForm.isNotEmpty) return textoForm;
    }
    return _rotuloPagamentoCabecalho(venda);
  }

  String _rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao de credito';
      case 'cartao_debito':
        return 'Cartao de debito';
      case 'fiado':
        return 'Fiado';
      case 'transferencia':
        return 'Transferencia';
      case 'misto':
        return 'Misto';
      case 'dinheiro':
      default:
        return 'Dinheiro';
    }
  }

  String _textoEntregaCaixa(Venda v) =>
      EntregaVendaHelper.textoEntregaCabecalhoVenda(v);

  bool _vendaExigeDadosCarreto(Venda v) =>
      EntregaVendaHelper.vendaTemItensCarreto(v);

  String _rotuloStatusEntrega(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'Roteirizada';
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

  Cliente? _clienteDaVenda(Venda venda) {
    final clienteLigado = venda.cliente.target;
    if (clienteLigado != null) {
      return clienteLigado;
    }
    final clienteId = venda.cliente.targetId;
    if (clienteId == 0) {
      return null;
    }
    return widget.clienteRepository.obterPorId(clienteId);
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    final ligado = venda.vendedor.target;
    if (ligado != null) {
      return ligado;
    }
    final vid = venda.vendedor.targetId;
    if (vid == 0) {
      return null;
    }
    return widget.vendedorRepository.obterPorId(vid);
  }

  String _rotuloVendedorUmLinha(Venda venda) {
    final v = _vendedorDaVenda(venda);
    if (v == null) {
      return 'Sem vendedor';
    }
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  DateTime? _ultimaVendaFinalizada() {
    return widget.vendaRepository.dataUltimaVendaFinalizada();
  }

  bool _horarioSistemaInconsistente() {
    final agora = DateTime.now();
    final ultima = _ultimaVendaFinalizada();
    if (ultima == null) return false;
    return agora.isBefore(ultima.subtract(const Duration(minutes: 2)));
  }

  Future<void> _abrirAjusteDataHoraSO() async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'ms-settings:dateandtime']);
      } else if (Platform.isLinux) {
        await Process.start('sh', ['-c', 'gnome-control-center datetime']);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          'x-apple.systempreferences:com.apple.preference.datetime',
        ]);
      }
    } catch (_) {}
  }

  double _valorFiadoEfetivoNaFinalizacao(Venda venda, double totalVenda) {
    if (venda.formaPagamento == 'misto') {
      final doForm = PagamentoOrcamentoCodec.somaPorMeio(
        _linhasMistoDoFormulario(),
        'fiado',
      );
      if (doForm > 0.001) return doForm;
      return PagamentoOrcamentoCodec.somaPorMeio(
        PagamentoOrcamentoCodec.decode(venda.pagamentosJson),
        'fiado',
      );
    }
    if (venda.formaPagamento == 'fiado') {
      return totalVenda;
    }
    return 0;
  }

  Future<void> _finalizarOrcamento(Venda venda) async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abra o caixa antes de finalizar vendas.'),
        ),
      );
      return;
    }
    if (_horarioSistemaInconsistente()) {
      if (!mounted) return;
      final ultima = _ultimaVendaFinalizada();
      final ultimaFmt = ultima == null
          ? '-'
          : DateFormat('dd/MM/yyyy HH:mm:ss').format(ultima.toLocal());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Relogio do sistema inconsistente. Ultima venda: $ultimaFmt. '
            'Corrija data/hora no Windows para finalizar no caixa.',
          ),
          action: SnackBarAction(
            label: 'Ajustar',
            onPressed: () {
              _abrirAjusteDataHoraSO();
            },
          ),
        ),
      );
      return;
    }

    final descontoAplicado = _descontoAplicado(venda);
    final totalVenda = _totalComDesconto(venda);
    final valorFiado = _valorFiadoEfetivoNaFinalizacao(venda, totalVenda);
    final clienteId = venda.cliente.targetId;
    if (valorFiado > 0.001 && clienteId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Orcamento com fiado exige cliente vinculado. Edite o orcamento no PDV.',
          ),
        ),
      );
      return;
    }
    if (valorFiado > 0.001) {
      final plano = PlanoFiadoCodec.decode(venda.planoFiadoJson);
      if (!PlanoFiadoCodec.validarContraValor(plano, valorFiado)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Orçamento fiado sem plano de parcelas válido. '
              'Edite no PDV e defina vencimentos antes de finalizar.',
            ),
          ),
        );
        return;
      }
    }
    if (valorFiado > 0.001 && clienteId > 0) {
      final r = widget.vendaRepository.validarLimiteCredito(
        clienteId: clienteId,
        valorFiadoOperacao: valorFiado,
      );
      if (!r.permitido) {
        if (!mounted) return;
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
        return;
      }
    }
    late final double totalRecebido;
    late final double trocoFinal;
    if (venda.formaPagamento == 'misto') {
      final linhasBruto = _linhasMistoDoFormulario();
      final fiado = PagamentoOrcamentoCodec.somaPorMeio(linhasBruto, 'fiado');
      final recebidoCaixa = linhasBruto
          .where((l) => l.meio != 'fiado')
          .fold<double>(0, (s, l) => s + l.valor);
      final aPagarAgora = (totalVenda - fiado).clamp(0, double.infinity).toDouble();
      totalRecebido = recebidoCaixa + fiado;
      trocoFinal =
          (recebidoCaixa - aPagarAgora).clamp(0, double.infinity).toDouble();
    } else {
      final parteDinheiro = _parteDinheiroNaFinalizacao(venda, totalVenda);
      totalRecebido = parteDinheiro > 0.001
          ? (_valorRecebido ?? 0)
          : totalVenda;
      trocoFinal = parteDinheiro > 0.001
          ? ((_valorRecebido ?? 0) - parteDinheiro)
              .clamp(0, double.infinity)
              .toDouble()
          : 0.0;
    }
    final itensCount = venda.itens.length;

    if (venda.formaPagamento == 'misto') {
      final linhasBruto = _linhasMistoDoFormulario();
      final fiado = PagamentoOrcamentoCodec.somaPorMeio(linhasBruto, 'fiado');
      final recebidoCaixa = linhasBruto
          .where((l) => l.meio != 'fiado')
          .fold<double>(0, (s, l) => s + l.valor);
      final aPagarAgora = (totalVenda - fiado).clamp(0, double.infinity).toDouble();
      final divergenciaMisto = _validarConferenciaMistoIgualOrcamento(
        venda,
        totalVenda,
      );
      if (divergenciaMisto != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(divergenciaMisto)),
        );
        return;
      }
      if (recebidoCaixa < aPagarAgora - _tolMistoPagamento) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pagamento misto: recebido agora (${_formatarMoeda(recebidoCaixa)}) '
              'menor que o esperado (${_formatarMoeda(aPagarAgora)}). '
              '${fiado > 0.001 ? 'Fiado ${_formatarMoeda(fiado)} ja esta no orcamento.' : ''}',
            ),
          ),
        );
        return;
      }
      final linhas = _normalizarLinhasMistoGravacao(linhasBruto, totalVenda);
      for (final l in linhas) {
        if (l.meio == 'cartao_credito') {
          final valorParcela =
              l.parcelas > 0 ? l.valor / l.parcelas : l.valor;
          if (valorParcela < _valorMinimoParcela) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Parcela minima de ${_formatarMoeda(_valorMinimoParcela)} no cartao de credito.',
                ),
              ),
            );
            return;
          }
        }
        if (l.meio == 'cartao_debito' && l.parcelas != 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cartao de debito deve ser a vista em cada linha.'),
            ),
          );
          return;
        }
      }
    } else {
      if (venda.formaPagamento == 'dinheiro') {
        final recebido = _valorRecebido ?? 0;
        if (recebido < totalVenda) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Valor recebido insuficiente para finalizar em dinheiro.',
              ),
            ),
          );
          return;
        }
      }
      if (venda.formaPagamento == 'cartao_credito') {
        final valorParcela = venda.quantidadeParcelas > 0
            ? (totalVenda / venda.quantidadeParcelas)
            : totalVenda;
        if (valorParcela < _valorMinimoParcela) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Parcela minima de ${_formatarMoeda(_valorMinimoParcela)} nao atingida. Ajuste as parcelas.',
              ),
            ),
          );
          return;
        }
      }
      if (venda.formaPagamento == 'cartao_debito' &&
          venda.quantidadeParcelas != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cartao de debito deve ser sempre a vista (1x).'),
          ),
        );
        return;
      }
    }
    final planoFiado = valorFiado > 0.001
        ? PlanoFiadoCodec.decode(venda.planoFiadoJson)
        : const <PlanoFiadoParcela>[];
    final confirmarFinalizacao = await _mostrarResumoFechamentoVenda(
      numeroOrcamento: venda.numeroOrcamento,
      textoPagamento: _rotuloPagamentoResumoNaFinalizacao(venda),
      textoPlanoFiado: planoFiado.isEmpty
          ? null
          : PlanoFiadoCodec.formatarResumoLinhas(planoFiado),
      totalVenda: totalVenda,
      descontoAplicado: descontoAplicado,
      totalRecebido: totalRecebido,
      troco: trocoFinal,
      quantidadeItens: itensCount,
    );
    if (confirmarFinalizacao != true) {
      return;
    }
    try {
      if (venda.formaPagamento == 'misto') {
        final linhasBruto = _linhasMistoDoFormulario();
        if (linhasBruto.isNotEmpty) {
          final linhasConf =
              _normalizarLinhasMistoGravacao(linhasBruto, totalVenda);
          widget.vendaRepository.substituirPagamentosMistoOrcamento(
            venda.id,
            linhasConf,
          );
        }
      }
      widget.vendaRepository.converterOrcamentoParaVenda(
        venda.id,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
      await LanSyncScheduler.solicitarSyncImediato();
      if (!mounted) return;
      final vendaFinalizada = widget.vendaRepository.obterPorId(venda.id) ?? venda;
      final clienteId = vendaFinalizada.cliente.targetId;
      if (clienteId != 0) {
        final cliente = widget.clienteRepository.obterPorId(clienteId);
        if (cliente != null) {
          await _mensageriaRepository.enfileirarAgradecimentoVenda(
            venda: vendaFinalizada,
            cliente: cliente,
          );
          await _mensageriaRepository.processarFilaPendente(limite: 5);
        }
      }
      _carregarOrcamentos();
      if (!mounted) return;
      final numCupom =
          vendaFinalizada.numeroOrcamento > 0
              ? vendaFinalizada.numeroOrcamento
              : venda.numeroOrcamento;
      await _registrarUltimoTrocoFinalizado(
        vendaId: vendaFinalizada.id,
        numeroOrcamento: numCupom,
        troco: trocoFinal,
      );
      if (!mounted) return;
      CaixaFeedback.sucesso(context, 'Venda $numCupom finalizada.');
      unawaited(_tentarAbrirGavetaPosPagamento());
      setState(() {
        _posVenda = CaixaPosVendaSessao(
          venda: vendaFinalizada,
          totalRecebido: totalRecebido,
          troco: trocoFinal,
        );
        _etapaCaixa = CaixaEtapa.fiscal;
        _selecionado = null;
        _valorRecebidoController.clear();
        _valorRecebido = null;
        _disposeMistoEdicao();
      });
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel finalizar: $e');
    }
  }

  GavetaEscPosService get _gaveta =>
      _gavetaService ??= GavetaEscPosService(widget.appConfigRepository);

  Future<void> _tentarAbrirGavetaPosPagamento() async {
    final r = await _gaveta.abrirAposPagamento();
    if (!mounted || r.sucesso) return;
    if (r.codigo == GavetaResultadoCodigo.desativada) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.mensagem),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _testarGavetaManual() async {
    final r = await _gaveta.testarAbrir();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.mensagem)),
    );
  }

  Future<String?> _escolherSalvarPdf({
    required Uint8List bytes,
    required String suggestedFileName,
    String? initialDirectory,
  }) async {
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Escolha onde salvar o PDF',
      fileName: suggestedFileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) {
      return null;
    }
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    final file = File(normalizedPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _atualizarPosVendaDoRepositorio() {
    final sessao = _posVenda;
    if (sessao == null) return;
    final v = widget.vendaRepository.obterPorId(sessao.venda.id);
    if (v != null && mounted) {
      setState(() => _posVenda = sessao.copyWith(venda: v));
    }
  }

  Future<void> _cancelarVendaNoCaixa(Venda venda) async {
    final resultado = await CancelarVendaUi.executar(
      context: context,
      vendaRepository: widget.vendaRepository,
      clienteRepository: widget.clienteRepository,
      usuarioRepository: _usuarioRepository,
      usuarioAtual: widget.usuarioAtual,
      podeCancelarVendas: widget.podeCancelarVendas,
      venda: venda,
    );
    if (!mounted) return;
    if (resultado != CancelarVendaUiResultado.sucesso) return;
    _carregarOrcamentos();
    if (_posVenda?.venda.id == venda.id) {
      _prepararCaixaPosProximaVenda();
    } else {
      setState(() {});
    }
  }

  Future<void> _encerrarPosVendaFiscal() async {
    final sessao = _posVenda;
    if (sessao == null) {
      _prepararCaixaPosProximaVenda();
      return;
    }
    await _alertarVendaSemNfe55SeNecessario(sessao.venda);
    if (!mounted) return;
    await _alertarVendaSemBaixaEstoqueSeNecessario(sessao.venda);
    if (!mounted) return;
    _prepararCaixaPosProximaVenda();
  }

  Future<void> _executarAcaoPosVendaFiscal(String acao) async {
    final sessao = _posVenda;
    if (sessao == null || _posVendaProcessando) return;
    final venda = sessao.venda;

    if (acao == 'nfe55') {
      setState(() => _posVendaProcessando = true);
      try {
        final vendaId = venda.id;
        final usuarioNfe = await _resolverUsuarioSessaoParaNfe();
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => NfeGerenciamentoPage(
              vendaRepository: widget.vendaRepository,
              clienteRepository: widget.clienteRepository,
              appConfigRepository: widget.appConfigRepository,
              usuarioLogado: usuarioNfe,
              vendaIdInicial: vendaId,
            ),
          ),
        );
        if (!mounted) return;
        await _tentarCupomInternoPosNfe55Autorizada(vendaId);
        _atualizarPosVendaDoRepositorio();
      } finally {
        if (mounted) setState(() => _posVendaProcessando = false);
      }
      return;
    }

    if (acao == 'nfce') {
      setState(() => _posVendaProcessando = true);
      try {
        await _aguardarEntreDialogos();
        if (!mounted) return;
        await _emitirNfceParaVenda(venda);
        _atualizarPosVendaDoRepositorio();
      } finally {
        if (mounted) setState(() => _posVendaProcessando = false);
      }
      return;
    }

    if (acao == 'cupom') {
      setState(() => _posVendaProcessando = true);
      try {
        await _imprimirCupomNaoFiscalPosVenda(
          venda: venda,
          totalRecebido: sessao.totalRecebido,
          troco: sessao.troco,
        );
        _atualizarPosVendaDoRepositorio();
      } finally {
        if (mounted) setState(() => _posVendaProcessando = false);
      }
    }
  }

  Future<void> _registrarCupomInternoPosFiscalAutorizada(
    int vendaId, {
    String origem = 'nota fiscal',
  }) async {
    try {
      widget.vendaRepository.registrarCupomInternoPosAutorizacaoFiscal(
        vendaId,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nota autorizada, mas falhou ao registrar cupom interno (estoque): $e',
      );
    }
  }

  Future<UsuarioSistema> _resolverUsuarioSessaoParaNfe() async {
    final todos = await UsuarioRepository().listarTodos();
    for (final u in todos) {
      if (u.login == widget.usuarioAtual) return u;
    }
    return UsuarioSistema(
      id: 'sessao',
      nome: widget.usuarioAtual,
      login: widget.usuarioAtual,
      senha: '',
      admin: true,
      podeEmitirNfeSaida: true,
      podeCancelarNfeSaida: true,
    );
  }

  Future<void> _tentarCupomInternoPosNfe55Autorizada(int vendaId) async {
    final v = widget.vendaRepository.obterPorId(vendaId);
    if (v == null || v.estoqueBaixadoCupom) return;
    final nfe = widget.vendaRepository.obterNfe55AutorizadaPorVenda(vendaId);
    if (nfe == null) return;
    await _registrarCupomInternoPosFiscalAutorizada(
      vendaId,
      origem: 'NF-e 55',
    );
    if (!mounted) return;
    final atualizado = widget.vendaRepository.obterPorId(vendaId);
    if (atualizado?.estoqueBaixadoCupom == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NF-e ${nfe.numero.isNotEmpty ? nfe.numero : nfe.referenciaFocus} '
            'vinculada — cupom interno e estoque atualizados.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _alertarVendaSemNfe55SeNecessario(Venda venda) async {
    final cliente = _clienteDaVenda(venda);
    if (!ClienteFiscalHelper.clienteExigeNfe55(cliente)) return;
    if (widget.vendaRepository.obterNfe55AutorizadaPorVenda(venda.id) != null) {
      return;
    }
    if (!mounted) return;
    final r = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.description_outlined, color: Colors.orange.shade800),
        title: const Text('NF-e modelo 55 pendente'),
        content: Text(
          'A venda para ${cliente?.nomeRazao ?? 'cliente CNPJ'} foi finalizada '
          'sem NF-e autorizada.\n\n'
          'Construtoras e revendas costumam exigir NF-e 55. '
          'Abra Notas Fiscais → NF-e de saida ou use a tecla 4 neste dialogo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'emitir'),
            child: const Text('Emitir NF-e agora'),
          ),
        ],
      ),
    );
    if (!mounted || r != 'emitir') return;
    final usuarioNfe = await _resolverUsuarioSessaoParaNfe();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NfeGerenciamentoPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          appConfigRepository: widget.appConfigRepository,
          usuarioLogado: usuarioNfe,
          vendaIdInicial: venda.id,
        ),
      ),
    );
  }

  Future<void> _alertarVendaSemBaixaEstoqueSeNecessario(Venda venda) async {
    final v = widget.vendaRepository.obterPorId(venda.id) ?? venda;
    if (v.estoqueBaixadoCupom) return;
    final temNfce = v.nfceEmitida;
    final nfe55 =
        widget.vendaRepository.obterNfe55AutorizadaPorVenda(v.id) != null;
    if (temNfce || nfe55) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
        title: const Text('Venda sem baixa de estoque'),
        content: const Text(
          'Esta venda foi finalizada sem cupom interno e sem nota fiscal '
          'autorizada.\n\n'
          'Itens retirados agora na loja ainda nao tiveram baixa no estoque. '
          'Emita NFC-e/NF-e autorizada ou use o cupom nao fiscal (2) / '
          'listagem de vendas.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _imprimirCupomNaoFiscalPosVenda({
    required Venda venda,
    required double totalRecebido,
    required double troco,
  }) async {
    try {
      widget.vendaRepository.registrarBaixaEstoqueCupomNaoFiscal(
        venda.id,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel baixar estoque: $e');
      return;
    }
    final vendaAtualizada =
        widget.vendaRepository.obterPorId(venda.id) ?? venda;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final nomeArquivo =
        'venda_${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      gerarPdf: () => CupomNaoFiscalVendaPdf.gerar(
        venda: vendaAtualizada,
        config: config,
        cliente: _clienteDaVenda(vendaAtualizada),
        vendedor: _vendedorDaVenda(vendaAtualizada),
        totalRecebido: totalRecebido,
        troco: troco,
        segundaVia: false,
        dataCabecalhoVenda: DateTime.now(),
      ),
      suggestedFileName: nomeArquivo,
    );
  }

  Future<void> _aguardarEntreDialogos() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  String? _dicaCorrecaoFalhaNfce(String mensagem) {
    final m = mensagem.toLowerCase();
    if (m.contains('habilitad') && m.contains('nfce')) {
      return 'No painel Focus (ambiente de homologacao):\n\n'
          '1. Menu Empresas — cadastre o CNPJ de ${FiscalConfig.cnpjEmitente} '
          '(se ainda nao existir).\n'
          '2. Na empresa, marque/habilite NFC-e (modelo 65) para a Bahia.\n'
          '3. Envie o certificado digital A1 (.pfx) e a senha.\n'
          '4. Confira CSC e ID CSC da SEFAZ-BA (se a Focus nao preencher sozinha).\n'
          '5. Use o token de homologacao dessa mesma empresa em fiscal_config.dart.\n'
          '6. Aguarde alguns minutos apos salvar e tente de novo.\n\n'
          'Guia: focusnfe.com.br/guides/configurando-empresa/';
    }
    return null;
  }

  Future<bool?> _mostrarDialogoFalhaNfce({required String mensagem}) {
    if (!mounted) return Future.value(false);
    final dica = _dicaCorrecaoFalhaNfce(mensagem);
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(Icons.error_outline, color: theme.colorScheme.error, size: 32),
          title: const Text('NFC-e rejeitada'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      mensagem,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  if (dica != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dica,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Fechar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tentar reemitir'),
            ),
          ],
        );
      },
    );
  }

  Future<_EmissaoNfceDialogResult> _executarChamadaFiscalNfce(Venda venda) async {
    final vendaAtual = widget.vendaRepository.obterPorId(venda.id) ?? venda;
    if (vendaAtual.itens.isEmpty) {
      return _EmissaoNfceDialogResult.erroValidacao(
        'A venda nao possui itens para emitir NFC-e.',
      );
    }

    try {
      _focusNfeService.validarConfiguracao();
    } on FocusNfeConfigIncompletaException catch (e) {
      return _EmissaoNfceDialogResult.erroConfig(e.message);
    }

    try {
      var resultado = await _focusNfeService.emitirNfce(
        vendaAtual,
        cliente: _clienteDaVenda(vendaAtual),
        entregaDomicilio: vendaAtual.tipoEntrega == 'entrega_loja' ||
            vendaAtual.enderecoEntrega.trim().isNotEmpty,
      );

      final ref = FocusNfeService.referenciaVendaNfce(vendaAtual);
      if (!resultado.autorizada && !resultado.processando) {
        resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
          original: resultado,
          reconsultar: () => _focusNfeService.consultarNfce(ref),
        );
        if (FocusNfeService.pareceFalhaComunicacao(resultado) &&
            !resultado.autorizada &&
            !resultado.processando) {
          resultado = FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
            referencia: ref,
          );
        }
      }

      if (resultado.autorizada) {
        return _EmissaoNfceDialogResult.sucesso(
          resultado: resultado,
          vendaAtual: vendaAtual,
        );
      }
      if (resultado.processando) {
        return _EmissaoNfceDialogResult.processando(
          resultado: resultado,
          vendaAtual: vendaAtual,
        );
      }

      final msg = resultado.mensagem.isEmpty
          ? 'A SEFAZ rejeitou a NFC-e sem mensagem detalhada.'
          : resultado.mensagem;
      return _EmissaoNfceDialogResult.erroApi(msg, vendaAtual);
    } on FocusNfeValidacaoException catch (e) {
      return _EmissaoNfceDialogResult.erroValidacao(e.message);
    } catch (e) {
      final ref = FocusNfeService.referenciaVendaNfce(vendaAtual);
      try {
        final consulta = await _focusNfeService.consultarNfce(ref);
        if (consulta.autorizada) {
          return _EmissaoNfceDialogResult.sucesso(
            resultado: consulta,
            vendaAtual: vendaAtual,
          );
        }
        if (consulta.processando) {
          return _EmissaoNfceDialogResult.processando(
            resultado: consulta,
            vendaAtual: vendaAtual,
          );
        }
      } catch (_) {}
      return _EmissaoNfceDialogResult.erroGenerico('Erro ao emitir NFC-e: $e');
    }
  }

  Future<void> _emitirNfceParaVenda(Venda venda) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var vendaAtual = widget.vendaRepository.obterPorId(venda.id) ?? venda;

    while (mounted) {
      vendaAtual = widget.vendaRepository.obterPorId(venda.id) ?? vendaAtual;
      if (vendaAtual.nfceEmitida) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'NFC-e ja consta emitida para esta venda. '
              'Use Visualizar/Reimprimir DANFE.',
            ),
          ),
        );
        return;
      }

      final deviceId = await _obterDeviceIdSync();
      if (FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(vendaAtual, deviceId)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Outro PC esta emitindo NFC-e desta venda. '
              'Aguarde alguns minutos e tente novamente.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
        return;
      }

      final refNfce = FocusNfeService.referenciaVendaNfce(vendaAtual);
      widget.vendaRepository.registrarNfceEmissaoEmAndamento(
        vendaId: vendaAtual.id,
        deviceId: deviceId,
        referencia: refNfce,
      );

      final rootNav = Navigator.of(context, rootNavigator: true);
      if (!mounted) return;

      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Emissao NFC-e'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Comunicando com a SEFAZ através da Focus NFe...',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      await _aguardarEntreDialogos();

      _EmissaoNfceDialogResult dialogResult;
      try {
        dialogResult = await _executarChamadaFiscalNfce(vendaAtual);
      } finally {
        if (rootNav.mounted && rootNav.canPop()) {
          rootNav.pop();
        }
      }

      await _aguardarEntreDialogos();
      if (!mounted) return;

      switch (dialogResult.kind) {
        case _EmissaoNfceDialogKind.erroConfig:
          widget.vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
          messenger.showSnackBar(
            SnackBar(
              content: Text(dialogResult.mensagem),
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case _EmissaoNfceDialogKind.erroValidacao:
          widget.vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
          messenger.showSnackBar(
            SnackBar(
              content: Text(dialogResult.mensagem),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case _EmissaoNfceDialogKind.erroApi:
        case _EmissaoNfceDialogKind.erroGenerico:
          widget.vendaRepository.liberarNfceEmissaoEmAndamento(vendaAtual.id);
          final tentar = await _mostrarDialogoFalhaNfce(
            mensagem: dialogResult.mensagem,
          );
          await _aguardarEntreDialogos();
          if (!mounted) return;
          if (tentar == true) {
            vendaAtual =
                dialogResult.vendaAtual ??
                widget.vendaRepository.obterPorId(vendaAtual.id) ??
                vendaAtual;
            continue;
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text('NFC-e nao emitida: ${dialogResult.mensagem}'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case _EmissaoNfceDialogKind.processando:
          final r = dialogResult.resultado!;
          final vSalvar = dialogResult.vendaAtual ?? vendaAtual;
          try {
            widget.vendaRepository.registrarNfcePendenteFocus(
              vendaId: vSalvar.id,
              referencia: r.referencia,
              protocolo: r.protocolo,
              statusFocus: r.statusFocus,
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'NFC-e em processamento, mas falhou ao salvar pendencia: $e',
                ),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 10),
              ),
            );
          }
          await showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) {
              final theme = Theme.of(ctx);
              return AlertDialog(
                icon: Icon(
                  Icons.hourglass_top_outlined,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
                title: const Text('NFC-e em processamento'),
                content: Text(
                  r.mensagem.isEmpty
                      ? 'A nota foi enviada a Focus NFe e aguarda retorno da '
                          'SEFAZ. Consulte novamente pelo painel Focus ou '
                          'reemita quando o servico normalizar.\n\n'
                          'Referencia: ${r.referencia}'
                      : '${r.mensagem}\n\nReferencia: ${r.referencia}',
                  textAlign: TextAlign.center,
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Entendi'),
                  ),
                ],
              );
            },
          );
          return;
        case _EmissaoNfceDialogKind.sucesso:
          final r = dialogResult.resultado!;
          final vSalvar = dialogResult.vendaAtual ?? vendaAtual;
          try {
            widget.vendaRepository.registrarNfceEmitida(
              vendaId: vSalvar.id,
              chaveAcesso: r.chaveNfe,
              numero: r.numero,
              serie: r.serie,
              protocolo: r.protocolo,
              urlDanfe: r.urlDanfe,
              urlXml: r.urlXml,
              statusFocus:
                  r.cancelada ? 'cancelado' : (r.statusFocus.isNotEmpty
                      ? r.statusFocus
                      : 'autorizado'),
              urlXmlCancelamento: r.urlXmlCancelamento,
            );
            await _registrarCupomInternoPosFiscalAutorizada(
              vSalvar.id,
              origem: 'NFC-e',
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'NFC-e autorizada, mas falhou ao salvar na venda: $e',
                ),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 10),
              ),
            );
            return;
          }

          final vendaComNfce =
              widget.vendaRepository.obterPorId(vSalvar.id) ?? vSalvar;
          final detalhe = <String>[
            if (r.numero.isNotEmpty) 'Numero: ${r.numero}',
            if (r.serie.isNotEmpty) 'Serie: ${r.serie}',
            if (r.chaveNfe.isNotEmpty) 'Chave: ${r.chaveNfe}',
            if (r.protocolo.isNotEmpty) 'Protocolo: ${r.protocolo}',
            if (r.mensagem.isNotEmpty) r.mensagem,
          ].join('\n');
          final temDanfe = r.urlDanfe.trim().isNotEmpty;

          await showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) {
              final theme = Theme.of(ctx);
              return AlertDialog(
                icon: Icon(
                  Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                  size: 36,
                ),
                title: const Text('NFC-e autorizada'),
                content: SizedBox(
                  width: 420,
                  child: Text(
                    detalhe.isEmpty ? 'Nota autorizada pela SEFAZ.' : detalhe,
                  ),
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  if (temDanfe)
                    FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _abrirDanfeNfceVenda(vendaComNfce);
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Imprimir DANFE (NFC-e)'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(temDanfe ? 'Fechar' : 'OK'),
                  ),
                ],
              );
            },
          );
          if (!mounted) return;
          final vPosCupom =
              widget.vendaRepository.obterPorId(vSalvar.id) ?? vendaComNfce;
          final msgCupom = vPosCupom.estoqueBaixadoCupom
              ? ' Cupom interno vinculado — estoque dos itens retirados agora atualizado.'
              : '';
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                temDanfe
                    ? 'NFC-e ${r.numero.isNotEmpty ? r.numero : ''} autorizada.$msgCupom '
                        'Use Imprimir DANFE para o PDF.'
                    : 'NFC-e autorizada.$msgCupom',
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 8),
            ),
          );
          return;
      }
    }
  }

  Venda? _buscarVendaFinalizadaParaSegundaVia(int numeroOuId) {
    return widget.vendaRepository.buscarVendaFinalizadaPorNumeroOuId(numeroOuId);
  }

  static const int _ultimasVendasFinalizadasLimite = 20;

  List<Venda> _ultimasVendasFinalizadasParaCaixa() {
    return widget.vendaRepository.listarUltimasVendasFinalizadas(
      limit: _ultimasVendasFinalizadasLimite,
    );
  }

  Future<void> _abrirAcoesVendaFinalizada(Venda vIn) async {
    final autorizado = await autorizarSegundaViaCupomSeConfigurado(
      context: context,
      usuarioRepository: _usuarioRepository,
      exigirAutorizacao: _exigirAutorizacaoSegundaViaCupom,
    );
    if (!mounted || !autorizado) return;
    await _aguardarEntreDialogos();
    if (!mounted) return;
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!mounted) return;
    if (v.cancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao e possivel abrir acoes de venda cancelada.'),
        ),
      );
      return;
    }
    if (v.status != 'finalizada') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Acoes disponiveis apenas para vendas finalizadas.',
          ),
        ),
      );
      return;
    }

    final numCupom = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
    final cliente = _clienteDaVenda(v);
    final nfceEmitida = v.nfceEmitida;
    final temDanfe = v.nfceUrlDanfe.trim().isNotEmpty;

    final acao = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Venda $numCupom'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total: ${_formatarMoeda(v.total)}'),
                Text(
                  'Cliente: ${cliente?.nomeRazao ?? 'Consumidor / sem cadastro'}',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      nfceEmitida
                          ? Icons.check_circle_outline
                          : Icons.receipt_long_outlined,
                      size: 20,
                      color: nfceEmitida
                          ? Colors.green.shade700
                          : Theme.of(ctx).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nfceEmitida
                            ? 'NFC-e ja emitida para esta venda.'
                            : 'NFC-e ainda nao emitida.',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                if (nfceEmitida) ...[
                  const SizedBox(height: 8),
                  if (v.nfceNumero.isNotEmpty)
                    Text('Numero NFC-e: ${v.nfceNumero}'),
                  if (v.nfceSerie.isNotEmpty) Text('Serie: ${v.nfceSerie}'),
                  if (v.nfceChaveAcesso.isNotEmpty)
                    Text(
                      'Chave: ${v.nfceChaveAcesso}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  if (v.nfceEmitidaEm != null)
                    Text(
                      'Emitida em: ${DateFormat('dd/MM/yyyy HH:mm').format(v.nfceEmitidaEm!.toLocal())}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  if (!temDanfe)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Link do DANFE nao foi salvo nesta venda.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800,
                            ),
                      ),
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
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cancelar'),
              icon: Icon(Icons.cancel_outlined, color: Theme.of(ctx).colorScheme.error),
              label: Text(
                'Cancelar venda',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cupom'),
              icon: const Icon(Icons.receipt_outlined),
              label: const Text('Segunda via cupom'),
            ),
            if (!nfceEmitida)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'nfce'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Emitir NFC-e'),
              ),
            if (nfceEmitida && temDanfe)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'danfe'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Visualizar/Reimprimir DANFE'),
              ),
          ],
        );
      },
    );
    if (!mounted || acao == null) return;

    if (acao == 'cancelar') {
      await _cancelarVendaNoCaixa(v);
      return;
    }
    if (acao == 'cupom') {
      await _emitirSegundaViaCupomParaVenda(v);
    } else if (acao == 'nfce') {
      await _aguardarEntreDialogos();
      if (!mounted) return;
      await _emitirNfceParaVenda(v);
    } else if (acao == 'danfe') {
      await _abrirDanfeNfceVenda(v);
    }
  }

  Future<void> _emitirSegundaViaCupomParaVenda(Venda v) async {
    if (!v.estoqueBaixadoCupom) {
      try {
        widget.vendaRepository.registrarBaixaEstoqueCupomNaoFiscal(
          v.id,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      } catch (e) {
        if (!mounted) return;
        CaixaFeedback.erro(context, 'Nao foi possivel baixar estoque: $e');
        return;
      }
    }
    final vendaAtualizada = widget.vendaRepository.obterPorId(v.id) ?? v;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final infer =
        CupomNaoFiscalVendaPdf.inferirRecebidoTrocoSegundaVia(vendaAtualizada);
    final nomeArquivo =
        'venda_${vendaAtualizada.numeroOrcamento > 0 ? vendaAtualizada.numeroOrcamento : vendaAtualizada.id}_2via.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Segunda via do cupom',
      content: 'Deseja imprimir ou gerar PDF da segunda via?',
      gerarPdf: () => CupomNaoFiscalVendaPdf.gerar(
        venda: vendaAtualizada,
        config: config,
        cliente: _clienteDaVenda(vendaAtualizada),
        vendedor: _vendedorDaVenda(vendaAtualizada),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: true,
        dataCabecalhoVenda: vendaAtualizada.data,
      ),
      suggestedFileName: nomeArquivo,
    );
  }

  Future<void> _abrirDanfeNfceVenda(Venda venda) async {
    final url = venda.nfceUrlDanfe.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta venda nao possui link do DANFE salvo. '
            'Reemita pela API fiscal ou consulte o portal da SEFAZ.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
      return;
    }
    await _abrirUrlExterna(url);
  }

  Future<void> _abrirUrlExterna(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link do DANFE invalido.')),
      );
      return;
    }

    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'rundll32',
          ['url.dll,FileProtocolHandler', uri.toString()],
        );
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
            content: Text('Nao foi possivel abrir o DANFE no navegador.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir DANFE: $e')),
      );
    }
  }

  Future<void> _abrirSegundaViaCupom() async {
    final numeroController = TextEditingController();
    final encontrada = await showDialog<Venda>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Segunda via do cupom'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informe o numero da venda no cupom ou o ID interno.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numeroController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Numero da venda ou ID',
                    hintText: 'Ex.: 1042',
                  ),
                  onSubmitted: (_) {
                    final n = int.tryParse(
                      numeroController.text.replaceAll(RegExp(r'[^0-9]'), ''),
                    );
                    if (n == null) return;
                    final v = _buscarVendaFinalizadaParaSegundaVia(n);
                    if (v == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Venda nao encontrada, cancelada ou ainda nao finalizada.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final n = int.tryParse(
                  numeroController.text.replaceAll(RegExp(r'[^0-9]'), ''),
                );
                if (n == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Digite um numero valido.'),
                    ),
                  );
                  return;
                }
                final v = _buscarVendaFinalizadaParaSegundaVia(n);
                if (v == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Venda nao encontrada, cancelada ou ainda nao finalizada.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    numeroController.dispose();
    if (!mounted || encontrada == null) return;
    await _abrirAcoesVendaFinalizada(encontrada);
  }

  Future<bool?> _mostrarResumoFechamentoVenda({
    required int numeroOrcamento,
    required String textoPagamento,
    String? textoPlanoFiado,
    required double totalVenda,
    required double descontoAplicado,
    required double totalRecebido,
    required double troco,
    required int quantidadeItens,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final semantic = Theme.of(context).extension<AppSemanticColors>();
        return AlertDialog(
          title: Text('Venda $numeroOrcamento finalizada'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pagamento: $textoPagamento'),
                if (textoPlanoFiado != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Plano fiado (definido no PDV):',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(textoPlanoFiado),
                ],
                const SizedBox(height: 4),
                Text('Itens: $quantidadeItens'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: semantic?.successBg ?? Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: semantic?.successBorder ?? Colors.green.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('TROCO'),
                      const SizedBox(height: 4),
                      Text(
                        _formatarMoeda(troco),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color:
                                  semantic?.successFg ?? Colors.green.shade800,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (descontoAplicado > 0) ...[
                      Expanded(
                        child: _buildResumoCard(
                          context,
                          label: 'DESCONTO',
                          valor: '- ${_formatarMoeda(descontoAplicado)}',
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: _buildResumoCard(
                        context,
                        label: 'TOTAL DA VENDA',
                        valor: _formatarMoeda(totalVenda),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildResumoCard(
                        context,
                        label: 'TOTAL RECEBIDO',
                        valor: _formatarMoeda(totalRecebido),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar e nao finalizar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Concluir venda'),
            ),
          ],
        );
      },
    );
  }

  Future<int?> _abrirCadastroNovoCliente() async {
    final cliente = await Navigator.push<Cliente>(
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
    if (!mounted || cliente == null) return null;
    return cliente.id;
  }

  Future<void> _vincularClienteAgora() async {
    final venda = _selecionado;
    if (venda == null) return;
    int? clienteSelecionadoId = venda.cliente.target?.id;
    final pesquisaClienteController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        var clientesExibidos = widget.clienteRepository.listarPaginado(
          limit: 60,
          somenteAtivos: true,
        );
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void atualizarBusca(String termo) {
              final t = termo.trim();
              setDialogState(() {
                clientesExibidos = t.isEmpty
                    ? widget.clienteRepository.listarPaginado(
                        limit: 60,
                        somenteAtivos: true,
                      )
                    : widget.clienteRepository
                        .pesquisar(t)
                        .where((c) => c.ativo)
                        .take(60)
                        .toList();
              });
            }

            return AlertDialog(
              title: const Text('Vincular cliente ao orcamento'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final novoId = await _abrirCadastroNovoCliente();
                        if (novoId == null) return;
                        setDialogState(() {
                          clienteSelecionadoId = novoId;
                          clientesExibidos = [
                            widget.clienteRepository.obterPorId(novoId),
                          ].whereType<Cliente>().toList();
                        });
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cliente cadastrado. Toque Salvar para vincular ao orcamento.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Cadastrar novo cliente'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pesquisaClienteController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar cliente',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: atualizarBusca,
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      selected: clienteSelecionadoId == null,
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Sem cliente'),
                      onTap: () => setDialogState(() => clienteSelecionadoId = null),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: clientesExibidos.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Nenhum cliente. Digite para buscar ou cadastre um novo.',
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: clientesExibidos.length,
                              itemBuilder: (context, index) {
                                final c = clientesExibidos[index];
                                return ListTile(
                                  dense: true,
                                  selected: clienteSelecionadoId == c.id,
                                  title: Text(c.nomeRazao),
                                  subtitle: c.documento.trim().isEmpty
                                      ? null
                                      : Text(c.documento),
                                  onTap: () => setDialogState(
                                    () => clienteSelecionadoId = c.id,
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
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    pesquisaClienteController.dispose();
    if (confirmar != true) return;
    try {
      widget.vendaRepository.vincularClienteNoOrcamento(
        venda.id,
        clienteSelecionadoId,
      );
      _carregarOrcamentos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente atualizado no orcamento.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel vincular cliente: $e')),
      );
    }
  }

  /// Barra compacta de acoes quando nenhum orcamento esta selecionado.
  Widget _buildBarraAcoesIniciaisCaixa(BuildContext context) {
    final outlinedCompact = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final filledCompact = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    Widget botao({
      required String rotulo,
      required String dica,
      required IconData icone,
      required VoidCallback? onPressed,
      required bool destaque,
    }) {
      final filho = destaque
          ? FilledButton.tonalIcon(
              style: filledCompact,
              onPressed: onPressed,
              icon: Icon(icone, size: 20),
              label: Text(rotulo),
            )
          : OutlinedButton.icon(
              style: outlinedCompact,
              onPressed: onPressed,
              icon: Icon(icone, size: 20),
              label: Text(rotulo),
            );
      return Tooltip(message: dica, child: filho);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final estreito = constraints.maxWidth < 400;
        final rotuloImportar = estreito
            ? 'Importar (F1)'
            : 'Importar Orçamento (F1)';

        Widget importar() => botao(
              rotulo: rotuloImportar,
              dica: 'Pesquisar orcamento para importar (F1)',
              icone: Icons.search,
              onPressed: _abrirPesquisaOrcamento,
              destaque: false,
            );
        Widget segundaVia() => botao(
              rotulo: '2a via (F2)',
              dica: 'Segunda via da nota (F2)',
              icone: Icons.receipt_long_outlined,
              onPressed: _abrirSegundaViaCupom,
              destaque: false,
            );
        Widget fiado() => botao(
              rotulo: 'Fiado (F3)',
              dica: 'Receber fiado (F3)',
              icone: Icons.payments_outlined,
              onPressed: _caixaAberto ? _abrirReceberFiado : null,
              destaque: true,
            );

        if (estreito) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: importar()),
                  const SizedBox(width: 8),
                  Expanded(child: segundaVia()),
                ],
              ),
              const SizedBox(height: 8),
              fiado(),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: importar()),
            const SizedBox(width: 8),
            Expanded(child: segundaVia()),
            const SizedBox(width: 8),
            Expanded(child: fiado()),
          ],
        );
      },
    );
  }

  Widget _buildEtapaFila(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBarraAcoesIniciaisCaixa(context),
        const SizedBox(height: 10),
        Expanded(child: _buildPainelStatusCaixa(context)),
      ],
    );
  }

  Widget _buildCabecalhoOrcamentoAtivo(
    BuildContext context,
    Venda selecionado,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.point_of_sale_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            _caixaAberto ? 'CAIXA ABERTO' : 'CAIXA FECHADO',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_caixaAberto) ...[
            const SizedBox(width: 10),
            Text(
              _operadorCaixa.trim().isEmpty ? '' : 'Operador: $_operadorCaixa',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _abrirPesquisaOrcamento,
            icon: const Icon(Icons.search),
            label: const Text('Pesquisar (F1)'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _voltarParaFila,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Fila (Esc)'),
          ),
          const SizedBox(width: 8),
          Text(
            'Orcamento ${selecionado.numeroOrcamento}',
            style: theme.textTheme.titleMedium,
          ),
          if (selecionado.entregaPendente) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('Retirada futura'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelStyle: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabelaItensConferencia(
    BuildContext context,
    Venda selecionado,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final podeRemover = selecionado.itens.length > 1;

    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 4,
                  child: Text('Produto', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 132,
                  child: Text(
                    'Qtd',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text('Vlr Unit', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Text(
                    'Total',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 44),
              ],
            ),
          ),
          Expanded(
            child: RawScrollbar(
              controller: _itensScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 10,
              radius: const Radius.circular(8),
              child: ListView.builder(
                controller: _itensScrollController,
                padding: const EdgeInsets.only(right: 10),
                itemCount: selecionado.itens.length,
                itemBuilder: (context, index) {
                  final item = selecionado.itens[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 32, child: Text('${index + 1}')),
                        Expanded(
                          flex: 4,
                          child: Text(
                            '${item.nomeProduto} '
                            '(${EntregaVendaHelper.abreviacaoTipoItem(item.tipoEntregaItem)})',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 132,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                tooltip: item.quantidade <= 1
                                    ? 'Remover item'
                                    : 'Diminuir quantidade',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: item.quantidade <= 1
                                    ? (podeRemover
                                        ? () => unawaited(
                                              _removerItemConferencia(
                                                selecionado,
                                                item,
                                              ),
                                            )
                                        : null)
                                    : () => unawaited(
                                          _alterarQuantidadeItemConferencia(
                                            selecionado,
                                            item,
                                            -1,
                                          ),
                                        ),
                              ),
                              Text(
                                '${item.quantidade}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                tooltip: 'Aumentar quantidade',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => unawaited(
                                  _alterarQuantidadeItemConferencia(
                                    selecionado,
                                    item,
                                    1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(_formatarMoeda(item.precoUnitario)),
                        ),
                        Expanded(
                          child: Text(
                            _formatarMoeda(item.subtotal),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tooltip: podeRemover
                                ? 'Remover item (gerente)'
                                : 'Ultimo item — nao pode remover',
                            icon: Icon(
                              Icons.delete_outline,
                              color: podeRemover
                                  ? scheme.error
                                  : scheme.onSurface.withValues(alpha: 0.3),
                            ),
                            onPressed: podeRemover
                                ? () => unawaited(
                                      _removerItemConferencia(selecionado, item),
                                    )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rodape fixo da conferencia: pagamento + total em destaque (padrao PDV).
  Widget _buildRodapeConferenciaPagamentoTotal(
    BuildContext context, {
    required Venda selecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
  }) {
    return CaixaRodapeTotalDestaque(
      tituloSecaoPagamento: 'Pagamento previsto',
      rotuloPagamento: _rotuloPagamentoCabecalho(selecionado),
      totalFormatado: _formatarMoeda(totalComDesconto),
      formatarMoeda: _formatarMoeda,
      descontoPdvOrcamento: descontoPdvOrcamento,
    );
  }

  Widget _buildEtapaConferencia(
    BuildContext context, {
    required Venda selecionado,
    required Cliente? clienteSelecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCabecalhoOrcamentoAtivo(context, selecionado),
        const SizedBox(height: 10),
        CaixaEtapasBar(etapaAtual: _etapaCaixa),
        const SizedBox(height: 10),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    [
                      'Entrega: ${_textoEntregaCaixa(selecionado)}',
                      if (_vendaExigeDadosCarreto(selecionado))
                        'Frete: ${_formatarMoeda(selecionado.valorFrete)}',
                    ].join(' | '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Cliente: ${clienteSelecionado?.nomeRazao ?? 'Sem cliente'}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _vincularClienteAgora,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Vincular (F4)'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Text(
                      'Vendedor: ${_rotuloVendedorUmLinha(selecionado)} (PDV)',
                    ),
                  ),
                  _buildBarraBuscaProdutoConferencia(context),
                  const SizedBox(height: 8),
                  Expanded(child: _buildTabelaItensConferencia(context, selecionado)),
                  _buildRodapeConferenciaPagamentoTotal(
                    context,
                    selecionado: selecionado,
                    totalComDesconto: totalComDesconto,
                    descontoPdvOrcamento: descontoPdvOrcamento,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Atalhos: Enter = cobranca | F5 = buscar produto | Esc = inicio | F4 = cliente | +/- = qtd',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _irParaCobranca,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Ir para cobranca (Enter)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCorpoRecebimentoCobranca(
    BuildContext context, {
    required Venda selecionado,
    required double totalComDesconto,
    required double troco,
    required List<PagamentoOrcamentoLinha> linhasMistoCaixa,
  }) {
    if (selecionado.formaPagamento == 'misto' && linhasMistoCaixa.isNotEmpty) {
      return _buildPainelPagamentosMistoNoCaixa(
        context,
        venda: selecionado,
        totalComDesconto: totalComDesconto,
      );
    }

    if (_caixaPrecisaValorRecebidoDinheiro(selecionado)) {
      final parteDinheiro =
          _parteDinheiroNaFinalizacao(selecionado, totalComDesconto);
      return CaixaCobrancaCampoDinheiro(
        controller: _valorRecebidoController,
        focusNode: _valorRecebidoFocusNode,
        totalAPagar: parteDinheiro > 0.001 ? parteDinheiro : totalComDesconto,
        troco: troco,
        formatarMoeda: _formatarMoeda,
        onChanged: (value) {
          setState(() => _valorRecebido = _parseValor(value));
        },
      );
    }

    final forma = selecionado.formaPagamento;
    final planoFiado = PlanoFiadoCodec.decode(selecionado.planoFiadoJson);
    var detalhe = '';
    if (forma == 'fiado' && planoFiado.isNotEmpty) {
      detalhe = PlanoFiadoCodec.formatarResumoLinhas(planoFiado);
    }

    return CaixaCobrancaConfirmacaoSimples(
      icone: _iconeFormaPagamentoCaixa(forma),
      titulo: _rotuloFormaPagamento(forma),
      subtitulo:
          'Confirme o recebimento de ${_formatarMoeda(totalComDesconto)} '
          'e pressione Enter para finalizar.',
      detalhe: detalhe.isEmpty ? null : detalhe,
    );
  }

  IconData _iconeFormaPagamentoCaixa(String forma) => switch (forma) {
        'dinheiro' => Icons.payments_outlined,
        'pix' => Icons.qr_code_2_outlined,
        'cartao_credito' || 'cartao_debito' => Icons.credit_card_outlined,
        'fiado' => Icons.receipt_long_outlined,
        'misto' => Icons.account_balance_wallet_outlined,
        _ => Icons.point_of_sale_outlined,
      };

  Widget _buildEtapaCobranca(
    BuildContext context, {
    required Venda selecionado,
    required Cliente? clienteSelecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
    required List<PagamentoOrcamentoLinha> linhasMistoCaixa,
    required double valorTotalRecebidoCard,
    required double troco,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCabecalhoOrcamentoAtivo(context, selecionado),
        const SizedBox(height: 10),
        CaixaEtapasBar(etapaAtual: _etapaCaixa),
        const SizedBox(height: 10),
        Expanded(
          child: CaixaCobrancaPainel(
            numeroOrcamento: selecionado.numeroOrcamento > 0
                ? selecionado.numeroOrcamento
                : selecionado.id,
            clienteNome: clienteSelecionado?.nomeRazao ?? 'Sem cliente',
            qtdItens: selecionado.itens.length,
            rotuloPagamento: _rotuloPagamentoCabecalho(selecionado),
            totalComDesconto: totalComDesconto,
            descontoPdvOrcamento: descontoPdvOrcamento,
            formatarMoeda: _formatarMoeda,
            onAlterarForma: () => _alterarFormaPagamentoCaixa(selecionado),
            recebimento: _buildCorpoRecebimentoCobranca(
              context,
              selecionado: selecionado,
              totalComDesconto: totalComDesconto,
              troco: troco,
              linhasMistoCaixa: linhasMistoCaixa,
            ),
            valorRecebidoExibicao: valorTotalRecebidoCard,
            troco: troco,
            acaoConfirmar: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Atalhos: Enter = confirmar | Esc = conferencia',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () =>
                        unawaited(_finalizarOrcamento(selecionado)),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirmar pagamento (Enter)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEtapaFiscal(BuildContext context) {
    final sessao = _posVenda;
    if (sessao == null) {
      return _buildEtapaFila(context);
    }
    final venda = sessao.venda;
    final cliente = _clienteDaVenda(venda);
    final exigeNfe55 = ClienteFiscalHelper.clienteExigeNfe55(cliente);
    final jaTemNfe55 =
        widget.vendaRepository.obterNfe55AutorizadaPorVenda(venda.id) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaixaEtapasBar(etapaAtual: _etapaCaixa),
        const SizedBox(height: 10),
        Expanded(
          child: CaixaPosVendaFiscalPainel(
            venda: venda,
            cliente: cliente,
            totalRecebido: sessao.totalRecebido,
            troco: sessao.troco,
            formatarMoeda: _formatarMoeda,
            exigeNfe55: exigeNfe55,
            jaTemNfe55: jaTemNfe55,
            processando: _posVendaProcessando,
            onCupomNaoFiscal: () => unawaited(_executarAcaoPosVendaFiscal('cupom')),
            onEmitirNfce: () => unawaited(_executarAcaoPosVendaFiscal('nfce')),
            onEmitirNfe55: () => unawaited(_executarAcaoPosVendaFiscal('nfe55')),
            onConcluir: () => unawaited(_encerrarPosVendaFiscal()),
            onCancelarVenda: () =>
                unawaited(_cancelarVendaNoCaixa(venda)),
          ),
        ),
      ],
    );
  }

  Widget _buildCorpoCaixa(BuildContext context) {
    if (_etapaCaixa == CaixaEtapa.fiscal && _posVenda != null) {
      return _buildEtapaFiscal(context);
    }

    if (_selecionado == null) {
      if (_etapaCaixa != CaixaEtapa.fila) {
        _etapaCaixa = CaixaEtapa.fila;
      }
      return _buildEtapaFila(context);
    }

    final selecionado = _selecionado!;
    final clienteSelecionado = _clienteDaVenda(selecionado);
    final descontoSelecionado = _descontoAplicado(selecionado);
    final totalComDesconto = _totalComDesconto(selecionado);
    final freteSelecionado = selecionado.valorFrete;
    final subtotalProdutos = selecionado.somaSubtotalItens;
    final descontoPdvOrcamento = selecionado.descontoImplicitoTotal;
    final parteDinheiroResumo =
        _parteDinheiroNaFinalizacao(selecionado, totalComDesconto);
    final linhasMistoCaixa = selecionado.formaPagamento == 'misto'
        ? (_mistoValorControllers.isNotEmpty
            ? _linhasMistoDoFormulario()
            : _linhasPagamentoEscaladasCaixa(selecionado, totalComDesconto))
        : <PagamentoOrcamentoLinha>[];
    final somaMistoCaixa = linhasMistoCaixa.isEmpty
        ? 0.0
        : PagamentoOrcamentoCodec.soma(linhasMistoCaixa);
    final troco = selecionado.formaPagamento == 'misto'
        ? (somaMistoCaixa - totalComDesconto).clamp(0.0, double.infinity).toDouble()
        : (parteDinheiroResumo > 0.001
            ? ((_valorRecebido ?? 0) - parteDinheiroResumo)
                .clamp(0, double.infinity)
                .toDouble()
            : 0.0);
    final valorTotalRecebidoCard = selecionado.formaPagamento == 'misto' &&
            linhasMistoCaixa.isNotEmpty
        ? somaMistoCaixa
        : (_caixaPrecisaValorRecebidoDinheiro(selecionado)
            ? (_valorRecebido ?? 0)
            : totalComDesconto);

    switch (_etapaCaixa) {
      case CaixaEtapa.fiscal:
        return _buildEtapaFiscal(context);
      case CaixaEtapa.cobranca:
        return _buildEtapaCobranca(
          context,
          selecionado: selecionado,
          clienteSelecionado: clienteSelecionado,
          totalComDesconto: totalComDesconto,
          descontoPdvOrcamento: descontoPdvOrcamento,
          linhasMistoCaixa: linhasMistoCaixa,
          valorTotalRecebidoCard: valorTotalRecebidoCard,
          troco: troco,
        );
      case CaixaEtapa.fila:
      case CaixaEtapa.conferencia:
        return _buildEtapaConferencia(
          context,
          selecionado: selecionado,
          clienteSelecionado: clienteSelecionado,
          totalComDesconto: totalComDesconto,
          descontoPdvOrcamento: descontoPdvOrcamento,
        );
    }
  }

  @override
  void dispose() {
    _timerReconciliacaoNfce?.cancel();
    _valorRecebidoController.dispose();
    _valorRecebidoFocusNode.dispose();
    _itensScrollController.dispose();
    _pesquisaProdutoConferenciaController.dispose();
    _pesquisaProdutoConferenciaFocus.dispose();
    _disposeMistoEdicao();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.f1): const _ImportarOrcamentoIntent(),
        LogicalKeySet(LogicalKeyboardKey.f2): const _SegundaViaCupomIntent(),
        LogicalKeySet(LogicalKeyboardKey.f3): const _ReceberFiadoIntent(),
        LogicalKeySet(LogicalKeyboardKey.f4): const _VincularClienteIntent(),
        LogicalKeySet(LogicalKeyboardKey.f5): const _BuscarProdutoConferenciaIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ImportarOrcamentoIntent:
              CallbackAction<_ImportarOrcamentoIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              _abrirPesquisaOrcamento();
              return null;
            },
          ),
          _SegundaViaCupomIntent: CallbackAction<_SegundaViaCupomIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              _abrirSegundaViaCupom();
              return null;
            },
          ),
          _ReceberFiadoIntent: CallbackAction<_ReceberFiadoIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              if (!_caixaAberto) return null;
              _abrirReceberFiado();
              return null;
            },
          ),
          _VincularClienteIntent: CallbackAction<_VincularClienteIntent>(
            onInvoke: (intent) {
              if (ModalRoute.of(context)?.isCurrent != true) {
                return null;
              }
              if (_selecionado != null &&
                  (_etapaCaixa == CaixaEtapa.conferencia ||
                      _etapaCaixa == CaixaEtapa.cobranca)) {
                _vincularClienteAgora();
              }
              return null;
            },
          ),
          _BuscarProdutoConferenciaIntent:
              CallbackAction<_BuscarProdutoConferenciaIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              if (_etapaCaixa != CaixaEtapa.conferencia ||
                  _selecionado == null) {
                return null;
              }
              unawaited(_abrirConsultaProdutoConferencia());
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _tratarTeclaCaixaWizard,
          child: Scaffold(
            appBar: AppBar(
              title: _buildTituloAppBarCaixa(context),
              actions: [
                ContaSessaoAppBarActions(
                  login: widget.usuarioAtual,
                  onLogout: widget.onLogout,
                ),
              ],
            ),
            body: Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildCorpoCaixa(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAvisosCaixasRemotos(BuildContext context) {
    final outros = _sessoesRede.values
        .where((s) => s.aberto && s.terminalId != _terminalId)
        .toList();
    if (outros.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      ...outros.map(
        (s) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.cloud_sync_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Rede: caixa aberto em ${s.terminalId}'
                  '${s.operador.trim().isNotEmpty ? ' (${s.operador})' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildTituloAppBarCaixa(BuildContext context) {
    final theme = Theme.of(context);
    final trocoCentro = _ultimoTrocoVendaId == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.payments_outlined,
                size: 17,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Troco da ultima venda '
                  '(${_ultimoTrocoNumeroOrcamento > 0 ? _ultimoTrocoNumeroOrcamento : _ultimoTrocoVendaId})',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatarMoeda(_ultimoTrocoValor),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          );

    return Row(
      children: [
        Text(_etapaCaixa == CaixaEtapa.fiscal ? 'Caixa — Fiscal' : 'Caixa'),
        Expanded(
          child: Center(
            child: trocoCentro ?? const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildBotoesGestaoCaixa() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: _caixaAberto ? null : _abrirCaixa,
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Abrir caixa'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _caixaAberto
              ? () => _registrarMovimentoCaixa(suprimento: true)
              : null,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Suprimento'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _caixaAberto
              ? () => _registrarMovimentoCaixa(suprimento: false)
              : null,
          icon: const Icon(Icons.remove_circle_outline),
          label: const Text('Sangria'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _caixaAberto ? _fecharCaixa : null,
          icon: const Icon(Icons.task_alt_outlined),
          label: const Text('Fechamento'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.podeLeituraParcialCaixa ? _mostrarLeituraParcial : null,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('Leitura parcial'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.podeVisualizarAuditoriaCaixa
              ? _abrirHistoricoAuditoria
              : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Auditoria'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _testarGavetaManual,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: const Text('Testar gaveta'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildGestaoCaixaColapsavel(BuildContext context) {
    final theme = Theme.of(context);
    final status = _caixaAberto ? 'Aberto' : 'Fechado';
    final operador = _operadorCaixa.trim().isEmpty ? '-' : _operadorCaixa;
    final avisosRede = _buildAvisosCaixasRemotos(context);
    final aberturaFmt = _aberturaCaixaEm == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(_aberturaCaixaEm!.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() => _gestaoCaixaExpandida = !_gestaoCaixaExpandida);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.point_of_sale_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gestao de Caixa — $status · $operador',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (avisosRede.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.cloud_sync_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Icon(
                    _gestaoCaixaExpandida
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_gestaoCaixaExpandida) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_caixaAberto ? 'Status: Aberto' : 'Status: Fechado'),
                  Text('Operador: $operador'),
                  Text('Abertura: $aberturaFmt'),
                  const SizedBox(height: 4),
                  Text('Fundo inicial: ${_formatarMoeda(_fundoTrocoAbertura)}'),
                  Text('Suprimentos: ${_formatarMoeda(_totalSuprimentos)}'),
                  Text('Sangrias: ${_formatarMoeda(_totalSangrias)}'),
                  if (_terminalId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Terminal: $_terminalId',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  ...avisosRede,
                  const SizedBox(height: 10),
                  _buildBotoesGestaoCaixa(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPainelStatusCaixa(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGestaoCaixaColapsavel(context),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ultimas vendas finalizadas',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Toque na venda para segunda via, NFC-e, cancelar ou DANFE.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildListaUltimasVendasFinalizadasCaixa(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListaUltimasVendasFinalizadasCaixa(BuildContext context) {
    return CaixaUltimasVendasList(
      vendas: _ultimasVendasFinalizadasParaCaixa(),
      clienteDaVenda: _clienteDaVenda,
      formatarMoeda: _formatarMoeda,
      onVendaTap: _abrirAcoesVendaFinalizada,
    );
  }

  Widget _buildLinhaResumoCheckoutCaixa(
    BuildContext context, {
    required Venda selecionado,
    required double subtotalProdutos,
    required double freteSelecionado,
    required double descontoPdvOrcamento,
    required double descontoSelecionado,
    required double totalComDesconto,
    required double valorTotalRecebidoCard,
    required double troco,
    required bool compacto,
  }) {
    final cards = <Widget>[
      _buildResumoCard(
        context,
        label: compacto ? 'SUBTOTAL' : 'SUBTOTAL PRODUTOS',
        valor: _formatarMoeda(subtotalProdutos),
      ),
      _buildResumoCard(
        context,
        label: 'FRETE',
        valor: _formatarMoeda(freteSelecionado),
      ),
      if (descontoPdvOrcamento > 0.001)
        _buildResumoCard(
          context,
          label: compacto ? 'DESC. PDV' : 'DESCONTO PDV',
          valor: '- ${_formatarMoeda(descontoPdvOrcamento)}',
        ),
      _buildResumoCard(
        context,
        label: compacto ? 'A PAGAR' : 'TOTAL A PAGAR',
        valor: _formatarMoeda(totalComDesconto),
      ),
      _buildResumoCard(
        context,
        label: selecionado.formaPagamento == 'misto'
            ? (compacto ? 'SOMA' : 'SOMA DOS MEIOS')
            : (compacto ? 'RECEBIDO' : 'TOTAL RECEBIDO'),
        valor: _formatarMoeda(valorTotalRecebidoCard),
      ),
      _buildResumoCard(
        context,
        label: 'TROCO',
        valor: _formatarMoeda(troco),
        destaque: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final estreito = constraints.maxWidth < 720;
        if (estreito) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SizedBox(width: compacto ? 108 : 128, child: cards[i]),
                ],
              ],
            ),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRodapeCheckoutCaixa(
    BuildContext context, {
    required Venda selecionado,
    required double subtotalProdutos,
    required double freteSelecionado,
    required double descontoPdvOrcamento,
    required double descontoSelecionado,
    required double totalComDesconto,
    required double valorTotalRecebidoCard,
    required double troco,
    required bool isCompact,
    required VoidCallback onFinalizar,
    bool incluirCampoDinheiro = true,
    String labelFinalizar = 'Finalizar venda (Enter)',
  }) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLinhaResumoCheckoutCaixa(
              context,
              selecionado: selecionado,
              subtotalProdutos: subtotalProdutos,
              freteSelecionado: freteSelecionado,
              descontoPdvOrcamento: descontoPdvOrcamento,
              descontoSelecionado: descontoSelecionado,
              totalComDesconto: totalComDesconto,
              valorTotalRecebidoCard: valorTotalRecebidoCard,
              troco: troco,
              compacto: isCompact,
            ),
            if (incluirCampoDinheiro &&
                _caixaPrecisaValorRecebidoDinheiro(selecionado)) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _valorRecebidoController,
                focusNode: _valorRecebidoFocusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Valor recebido (dinheiro)',
                  hintText: 'Ex.: 100,00',
                ),
                onChanged: (value) {
                  setState(() {
                    _valorRecebido = _parseValor(value);
                  });
                },
              ),
            ],
            SafeArea(
              top: false,
              minimum: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: onFinalizar,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(labelFinalizar),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoGestaoCaixa(BuildContext context) {
    final status = _caixaAberto ? 'Aberto' : 'Fechado';
    final operador = _operadorCaixa.trim().isEmpty ? '-' : _operadorCaixa;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _abrirGestaoCaixaDialog,
        icon: const Icon(Icons.point_of_sale_outlined),
        label: Text('Gestao de Caixa ($status) - Operador: $operador'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  Widget _buildLinhaConferenciaFechamento({
    required String label,
    required TextEditingController controller,
  }) {
    return Row(
      children: [
        Expanded(flex: 3, child: Text(label)),
        const SizedBox(width: 8),
        SizedBox(
          width: 170,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Declarado',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPainelPagamentosMistoNoCaixa(
    BuildContext context, {
    required Venda venda,
    required double totalComDesconto,
  }) {
    if (_mistoValorControllers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final fiadoOrc = _valorFiadoMistoOrcamentoCaixa();
    final recebidoAgora = _somaMistoRecebidaNoCaixaAgora();
    final aPagarAgora =
        (totalComDesconto - fiadoOrc).clamp(0, double.infinity).toDouble();
    final pagamentoInsuficiente =
        recebidoAgora < aPagarAgora - _tolMistoPagamento;
    final trocoSobreTotal =
        (recebidoAgora - aPagarAgora).clamp(0.0, double.infinity).toDouble();
    final planoFiado = PlanoFiadoCodec.decode(venda.planoFiadoJson);
    final indicesCaixa = <int>[
      for (var i = 0; i < _mistoValorControllers.length; i++)
        if (_mistoLinhasModelo[i].meio != 'fiado') i,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pagamento misto',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _prepararEdicaoMisto(venda);
                    _sincronizarRecebidoPdVComOrcamento();
                  });
                  _focarEntradaPrincipalCaixa();
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Restaurar PDV'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildChipResumoMisto(
                context,
                'A receber agora',
                _formatarMoeda(aPagarAgora),
              ),
              _buildChipResumoMisto(
                context,
                'Recebido no caixa',
                _formatarMoeda(recebidoAgora),
                corValor: pagamentoInsuficiente
                    ? theme.colorScheme.error
                    : null,
              ),
              if (fiadoOrc > 0.001)
                _buildChipResumoMisto(
                  context,
                  'Fiado (depois)',
                  _formatarMoeda(fiadoOrc),
                ),
              if (!pagamentoInsuficiente && trocoSobreTotal > 0.02)
                _buildChipResumoMisto(
                  context,
                  'Troco',
                  _formatarMoeda(trocoSobreTotal),
                  corValor: theme.colorScheme.primary,
                ),
            ],
          ),
          if (fiadoOrc > 0.001) ...[
            const SizedBox(height: 10),
            Text(
              PlanoFiadoCodec.formatarResumoLinhas(planoFiado).isEmpty
                  ? 'Fiado definido no PDV — nao entra no caixa agora.'
                  : PlanoFiadoCodec.formatarResumoLinhas(planoFiado),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (indicesCaixa.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var j = 0; j < indicesCaixa.length; j++) ...[
              if (j > 0) const SizedBox(height: 8),
              _buildLinhaValorMistoCaixa(context, index: indicesCaixa[j]),
            ],
          ],
          if (pagamentoInsuficiente)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Recebido agora menor que ${_formatarMoeda(aPagarAgora)} '
                '(total menos fiado).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipResumoMisto(
    BuildContext context,
    String rotulo,
    String valor, {
    Color? corValor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            valor,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: corValor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaValorMistoCaixa(BuildContext context, {required int index}) {
    final theme = Theme.of(context);
    final meio = _mistoLinhasModelo[index].meio;
    final parcelas = _mistoLinhasModelo[index].parcelas;
    final rotulo = '${_rotuloFormaPagamento(meio)}'
        '${meio == 'cartao_credito' ? ' · ${parcelas}x' : ''}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            rotulo,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _mistoValorControllers[index],
            focusNode: index < _mistoValorFocusNodes.length
                ? _mistoValorFocusNodes[index]
                : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Valor no caixa',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() => _sincronizarRecebidoPdVComOrcamento());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResumoCard(
    BuildContext context, {
    required String label,
    required String valor,
    bool destaque = false,
  }) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final color = destaque
        ? semantic?.successBg ?? Colors.green.shade50
        : semantic?.infoBg ?? Colors.blueGrey.shade50;
    final border = destaque
        ? semantic?.successBorder ?? Colors.green.shade200
        : semantic?.infoBorder ?? Colors.blueGrey.shade100;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            valor,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

enum _EmissaoNfceDialogKind {
  sucesso,
  processando,
  erroApi,
  erroConfig,
  erroValidacao,
  erroGenerico,
}

class _EmissaoNfceDialogResult {
  const _EmissaoNfceDialogResult._({
    required this.kind,
    this.resultado,
    this.mensagem = '',
    this.vendaAtual,
  });

  final _EmissaoNfceDialogKind kind;
  final FocusNfeEmissaoResultado? resultado;
  final String mensagem;
  final Venda? vendaAtual;

  factory _EmissaoNfceDialogResult.sucesso({
    required FocusNfeEmissaoResultado resultado,
    required Venda vendaAtual,
  }) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.sucesso,
        resultado: resultado,
        vendaAtual: vendaAtual,
      );

  factory _EmissaoNfceDialogResult.processando({
    required FocusNfeEmissaoResultado resultado,
    required Venda vendaAtual,
  }) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.processando,
        resultado: resultado,
        vendaAtual: vendaAtual,
      );

  factory _EmissaoNfceDialogResult.erroApi(String mensagem, Venda vendaAtual) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.erroApi,
        mensagem: mensagem,
        vendaAtual: vendaAtual,
      );

  factory _EmissaoNfceDialogResult.erroConfig(String mensagem) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.erroConfig,
        mensagem: mensagem,
      );

  factory _EmissaoNfceDialogResult.erroValidacao(String mensagem) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.erroValidacao,
        mensagem: mensagem,
      );

  factory _EmissaoNfceDialogResult.erroGenerico(String mensagem) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.erroGenerico,
        mensagem: mensagem,
      );
}

/// Dialogo de pesquisa com ciclo de vida proprio (evita dispose antecipado do campo).
class _DialogoPesquisaOrcamento extends StatefulWidget {
  const _DialogoPesquisaOrcamento({
    required this.orcamentos,
    required this.clienteDaVenda,
    required this.rotuloVendedor,
    required this.formatarMoeda,
  });

  final List<Venda> orcamentos;
  final Cliente? Function(Venda venda) clienteDaVenda;
  final String Function(Venda venda) rotuloVendedor;
  final String Function(double valor) formatarMoeda;

  @override
  State<_DialogoPesquisaOrcamento> createState() =>
      _DialogoPesquisaOrcamentoState();
}

class _DialogoPesquisaOrcamentoState extends State<_DialogoPesquisaOrcamento> {
  late final TextEditingController _pesquisaController;
  late final FocusNode _pesquisaFocusNode;
  late final ScrollController _listaScrollController;
  late List<Venda> _resultados;
  int _indiceSelecionado = 0;

  @override
  void initState() {
    super.initState();
    _pesquisaController = TextEditingController();
    _pesquisaFocusNode = FocusNode();
    _listaScrollController = ScrollController();
    _resultados = List<Venda>.from(widget.orcamentos);
    _indiceSelecionado = _resultados.isEmpty ? -1 : 0;
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
    _listaScrollController.dispose();
    super.dispose();
  }

  void _rolarParaIndiceSelecionado() {
    if (!_listaScrollController.hasClients || _indiceSelecionado < 0) {
      return;
    }
    const alturaEstimadaLinha = 72.0;
    final posicaoDesejada = (_indiceSelecionado * alturaEstimadaLinha).clamp(
      0.0,
      _listaScrollController.position.maxScrollExtent,
    );
    _listaScrollController.animateTo(
      posicaoDesejada,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _selecionarIndice(int indice) {
    if (indice < 0 || indice >= _resultados.length) return;
    Navigator.pop(context, _resultados[indice]);
  }

  KeyEventResult _tratarTeclaLista(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _resultados.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_indiceSelecionado < 0) {
          _indiceSelecionado = 0;
        } else {
          _indiceSelecionado = math.min(
            _indiceSelecionado + 1,
            _resultados.length - 1,
          );
        }
      });
      _rolarParaIndiceSelecionado();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_indiceSelecionado < 0) {
          _indiceSelecionado = 0;
        } else {
          _indiceSelecionado = math.max(_indiceSelecionado - 1, 0);
        }
      });
      _rolarParaIndiceSelecionado();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final indice = _indiceSelecionado >= 0 ? _indiceSelecionado : 0;
      _selecionarIndice(indice);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _filtrar(String value) {
    final termo = value.trim().toLowerCase();
    setState(() {
      if (termo.isEmpty) {
        _resultados = List<Venda>.from(widget.orcamentos);
      } else {
        _resultados = widget.orcamentos.where((orc) {
          final cliente = widget.clienteDaVenda(orc)?.nomeRazao ?? '';
          final vendedor = widget.rotuloVendedor(orc);
          return orc.numeroOrcamento.toString().contains(termo) ||
              cliente.toLowerCase().contains(termo) ||
              vendedor.toLowerCase().contains(termo);
        }).toList();
      }
      _indiceSelecionado = _resultados.isEmpty ? -1 : 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listaScrollController.hasClients) {
        _listaScrollController.jumpTo(0);
      }
      if (_pesquisaFocusNode.canRequestFocus) {
        _pesquisaFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final alturaDialogo =
        (MediaQuery.sizeOf(context).height * 0.62).clamp(320.0, 560.0);
    final corDestaque = Theme.of(context).colorScheme.primary.withValues(
          alpha: 0.08,
        );

    return Focus(
      onKeyEvent: _tratarTeclaLista,
      child: AlertDialog(
        title: const Text('Pesquisar orcamento'),
        content: SizedBox(
          width: 760,
          height: alturaDialogo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pesquisaController,
                focusNode: _pesquisaFocusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Numero, cliente, vendedor...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _filtrar,
                onSubmitted: (_) {
                  if (_resultados.isEmpty) return;
                  final indice = _indiceSelecionado >= 0 ? _indiceSelecionado : 0;
                  _selecionarIndice(indice);
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _resultados.isEmpty
                    ? const Center(child: Text('Nenhum orcamento pendente.'))
                    : ListView.builder(
                        controller: _listaScrollController,
                        itemCount: _resultados.length,
                        itemBuilder: (context, index) {
                          final orc = _resultados[index];
                          final cliente = widget.clienteDaVenda(orc)?.nomeRazao ??
                              'Sem cliente';
                          final descPdv = orc.descontoImplicitoTotal;
                          final selecionado = index == _indiceSelecionado;
                          return MouseRegion(
                            onEnter: (_) {
                              if (_indiceSelecionado == index) return;
                              setState(() => _indiceSelecionado = index);
                            },
                            child: ListTile(
                              selected: selecionado,
                              selectedTileColor: corDestaque,
                              title: Text('Orcamento ${orc.numeroOrcamento}'),
                              subtitle: Text(
                                '$cliente | Itens: ${orc.itens.length} | Total: ${widget.formatarMoeda(orc.total)}'
                                '${descPdv > 0.001 ? ' | Desc. PDV: -${widget.formatarMoeda(descPdv)}' : ''}',
                              ),
                              onTap: () => _selecionarIndice(index),
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
            child: const Text('Fechar (Esc)'),
          ),
        ],
      ),
    );
  }
}

class _ImportarOrcamentoIntent extends Intent {
  const _ImportarOrcamentoIntent();
}

class _SegundaViaCupomIntent extends Intent {
  const _SegundaViaCupomIntent();
}

class _ReceberFiadoIntent extends Intent {
  const _ReceberFiadoIntent();
}

class _VincularClienteIntent extends Intent {
  const _VincularClienteIntent();
}

class _BuscarProdutoConferenciaIntent extends Intent {
  const _BuscarProdutoConferenciaIntent();
}
