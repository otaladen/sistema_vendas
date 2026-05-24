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
import '../../domain/fiscal/fiscal_pedido_nfce.dart';
import '../../domain/pagamento_orcamento.dart';
import '../../domain/plano_fiado.dart';
import '../../model/caixa_sessao.dart';
import '../../model/cliente.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import '../../services/auditoria_registrar.dart';
import '../../services/cupom_nao_fiscal_venda_pdf.dart';
import '../../services/fiscal_service.dart';
import '../../services/print_service.dart';
import '../clientes_page.dart';
import '../cupom_venda_impressao_helper.dart';
import '../segunda_via_cupom_autorizacao.dart';
import '../widgets/conta_sessao_app_bar_actions.dart';
import '../widgets/receber_fiado_panel.dart';
import '../../services/recibo_movimento_caixa_pdf.dart';
import '../../services/recibo_recebimento_fiado_pdf.dart';
import 'caixa_feedback.dart';

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
  final _valorRecebidoController = TextEditingController();
  final _valorRecebidoFocusNode = FocusNode();
  final ScrollController _itensScrollController = ScrollController();
  final _descontoController = TextEditingController();
  late final MensageriaRepository _mensageriaRepository;
  final _usuarioRepository = UsuarioRepository();
  double? _valorRecebido;
  String _tipoDesconto = 'percentual';
  int? _itemSelecionadoId;
  List<Cliente> _clientesAtivos = [];
  bool _caixaAberto = false;
  String _operadorCaixa = '';
  DateTime? _aberturaCaixaEm;
  double _fundoTrocoAbertura = 0;
  double _totalSuprimentos = 0;
  double _totalSangrias = 0;
  double _limiteDivergenciaSemSupervisor = 20;
  bool _mostrarCampoDescontoCaixa = true;
  bool _permitirVendaSemEstoque = true;
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

  @override
  void initState() {
    super.initState();
    _mensageriaRepository = MensageriaRepository();
    _atualizarListaClientesAtivos();
    _carregarLimiteDivergenciaCaixa();
    _carregarSessaoCaixa();
    _carregarOrcamentos();
  }

  Future<void> _carregarLimiteDivergenciaCaixa() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _limiteDivergenciaSemSupervisor = config.limiteDivergenciaCaixa;
      _mostrarCampoDescontoCaixa = config.mostrarCampoDescontoCaixa;
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
      if (!_mostrarCampoDescontoCaixa) {
        _descontoController.clear();
        _tipoDesconto = 'percentual';
      }
    });
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
        _descontoController.clear();
        _tipoDesconto = 'percentual';
        _valorRecebidoFocusNode.unfocus();
        _itemSelecionadoId = null;
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
    setState(() {
      _selecionado = selecionado;
      _descontoController.clear();
      _tipoDesconto = 'percentual';
      _itemSelecionadoId = null;
      _prepararEdicaoMisto(selecionado!);
      _sincronizarRecebidoPdVComOrcamento();
    });
    _focarEntradaPrincipalCaixa();
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
      gerarPdfBytes: () => ReciboMovimentoCaixaPdf.gerarBytes(
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
      ),
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
    var dinheiro = 0.0;
    var pix = 0.0;
    var debito = 0.0;
    var credito = 0.0;
    for (final venda in widget.vendaRepository.listarTodas()) {
      if (venda.status != 'finalizada' || venda.cancelada) continue;
      if (abertura != null && venda.data.isBefore(abertura)) continue;
      if (venda.data.isAfter(agora)) continue;
      if (venda.formaPagamento == 'misto' &&
          venda.pagamentosJson.trim().isNotEmpty) {
        for (final l in PagamentoOrcamentoCodec.decode(venda.pagamentosJson)) {
          switch (l.meio) {
            case 'pix':
              pix += l.valor;
              break;
            case 'cartao_debito':
              debito += l.valor;
              break;
            case 'cartao_credito':
              credito += l.valor;
              break;
            case 'dinheiro':
              dinheiro += l.valor;
              break;
            default:
              break;
          }
        }
        continue;
      }
      switch (venda.formaPagamento) {
        case 'pix':
          pix += venda.total;
          break;
        case 'cartao_debito':
          debito += venda.total;
          break;
        case 'cartao_credito':
          credito += venda.total;
          break;
        case 'dinheiro':
        default:
          dinheiro += venda.total;
      }
    }
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
    var totalVendas = 0.0;
    var quantidadeVendas = 0;
    for (final venda in widget.vendaRepository.listarTodas()) {
      if (venda.status != 'finalizada' || venda.cancelada) continue;
      if (abertura != null && venda.data.isBefore(abertura)) continue;
      if (venda.data.isAfter(agora)) continue;
      totalVendas += venda.total;
      quantidadeVendas++;
    }
    return (totalVendas: totalVendas, quantidadeVendas: quantidadeVendas);
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
      gerarPdfBytes: () => ReciboRecebimentoFiadoPdf.gerarBytes(
        recebimento: rec,
        cliente: resultado.cliente,
        vendaRepository: widget.vendaRepository,
        config: config,
        operadorCaixa: _operadorCaixa,
      ),
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

  double _descontoAplicado(Venda venda) {
    if (!_mostrarCampoDescontoCaixa) {
      return 0;
    }
    final valorDigitado = _parseValor(_descontoController.text) ?? 0;
    if (valorDigitado <= 0) {
      return 0;
    }
    if (_tipoDesconto == 'percentual') {
      final percentual = valorDigitado.clamp(0, 100).toDouble();
      return (venda.total * (percentual / 100)).clamp(0, venda.total).toDouble();
    }
    return valorDigitado.clamp(0, venda.total).toDouble();
  }

  double _totalComDesconto(Venda venda) {
    final desconto = _descontoAplicado(venda);
    return (venda.total - desconto).clamp(0, double.infinity).toDouble();
  }

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
      final mesmoMeio = linhaEsperada.meio == linhaInformada.meio;
      final mesmasParcelas = linhaEsperada.parcelas == linhaInformada.parcelas;
      if (!mesmoMeio || !mesmasParcelas) {
        return 'Forma de pagamento alterada no caixa. Use o mesmo resumo do pedido.';
      }
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
    DateTime? ultima;
    for (final venda in widget.vendaRepository.listarTodas()) {
      if (venda.status != 'finalizada' || venda.cancelada) continue;
      if (ultima == null || venda.data.isAfter(ultima)) {
        ultima = venda.data;
      }
    }
    return ultima;
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
      if (descontoAplicado > 0) {
        widget.vendaRepository.aplicarDescontoNoOrcamento(
          venda.id,
          descontoAplicado,
        );
      }
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
      _disposeMistoEdicao();
      setState(() {
        _selecionado = null;
        _itemSelecionadoId = null;
        _valorRecebidoController.clear();
        _descontoController.clear();
        _tipoDesconto = 'percentual';
        _valorRecebido = null;
      });
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
      await _mostrarAcoesNotaPosVenda(
        venda: vendaFinalizada,
        totalRecebido: totalRecebido,
        troco: trocoFinal,
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(context, 'Nao foi possivel finalizar: $e');
    }
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

  Future<void> _mostrarAcoesNotaPosVenda({
    required Venda venda,
    required double totalRecebido,
    required double troco,
  }) async {
    if (!mounted) return;
    final numCupom = venda.numeroOrcamento > 0
        ? venda.numeroOrcamento
        : venda.id;
    final cliente = _clienteDaVenda(venda);
    final acao = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(dialogContext, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.digit1): () =>
                Navigator.pop(dialogContext, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.digit2): () =>
                Navigator.pop(dialogContext, 'cupom'),
            const SingleActivator(LogicalKeyboardKey.digit3): () =>
                Navigator.pop(dialogContext, 'nfce'),
            const SingleActivator(LogicalKeyboardKey.numpad1): () =>
                Navigator.pop(dialogContext, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.numpad2): () =>
                Navigator.pop(dialogContext, 'cupom'),
            const SingleActivator(LogicalKeyboardKey.numpad3): () =>
                Navigator.pop(dialogContext, 'nfce'),
          },
          child: AlertDialog(
            title: Text('Venda $numCupom finalizada'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pagamento confirmado. O que deseja fazer agora?',
                  ),
                  const SizedBox(height: 12),
                  Text('Total: ${_formatarMoeda(venda.total)}'),
                  Text(
                    'Cliente: ${cliente?.nomeRazao ?? 'Consumidor / sem cadastro'}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A NFC-e deve ser emitida no caixa apos o recebimento.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'fechar'),
                child: const Text('Fechar (Esc · 1)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'cupom'),
                icon: const Icon(Icons.receipt_outlined),
                label: const Text('Cupom nao fiscal (2)'),
              ),
              FilledButton.icon(
                autofocus: true,
                onPressed: () => Navigator.pop(dialogContext, 'nfce'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Emitir NFC-e (3 · Enter)'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;

    if (acao == 'nfce') {
      await _aguardarEntreDialogos();
      if (!mounted) return;
      await _emitirNfceParaVenda(venda);
      return;
    }

    if (acao == 'cupom') {
      await _imprimirCupomNaoFiscalPosVenda(
        venda: venda,
        totalRecebido: totalRecebido,
        troco: troco,
      );
    }
  }

  Future<void> _imprimirCupomNaoFiscalPosVenda({
    required Venda venda,
    required double totalRecebido,
    required double troco,
  }) async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final nomeArquivo =
        'venda_${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      gerarPdfBytes: () => CupomNaoFiscalVendaPdf.gerarBytes(
        venda: venda,
        config: config,
        cliente: _clienteDaVenda(venda),
        vendedor: _vendedorDaVenda(venda),
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

  Future<bool?> _mostrarDialogoFalhaNfce({required String mensagem}) {
    if (!mounted) return Future.value(false);
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Falha na NFC-e'),
        content: SingleChildScrollView(child: Text(mensagem)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Future<_EmissaoNfceDialogResult> _executarChamadaFiscalNfce(Venda venda) async {
    final vendaAtual =
        widget.vendaRepository.obterPorId(venda.id) ?? venda;
    final itens = List<ItemVenda>.from(vendaAtual.itens);
    if (itens.isEmpty) {
      return _EmissaoNfceDialogResult.erroValidacao(
        'A venda nao possui itens para emitir NFC-e.',
      );
    }

    try {
      final resultado = await FiscalService().emitirNfceDaVenda(
        venda: vendaAtual,
        itens: itens,
        cliente: _clienteDaVenda(vendaAtual),
        valorDesconto: vendaAtual.descontoImplicitoTotal,
      );

      if (resultado.sucesso) {
        return _EmissaoNfceDialogResult.sucesso(
          resultado: resultado,
          vendaAtual: vendaAtual,
        );
      }

      final msg = resultado.mensagem.isEmpty
          ? 'A API fiscal retornou erro sem mensagem.'
          : resultado.mensagem;
      return _EmissaoNfceDialogResult.erroApi(msg, vendaAtual);
    } on FiscalConfigIncompletaException catch (e) {
      return _EmissaoNfceDialogResult.erroConfig(e.message);
    } on FiscalValidacaoException catch (e) {
      return _EmissaoNfceDialogResult.erroValidacao(e.message);
    } catch (e) {
      return _EmissaoNfceDialogResult.erroGenerico('Erro ao emitir NFC-e: $e');
    }
  }

  Future<void> _emitirNfceParaVenda(Venda venda) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var vendaAtual = widget.vendaRepository.obterPorId(venda.id) ?? venda;

    while (mounted) {
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

      final rootNav = Navigator.of(context, rootNavigator: true);
      if (!mounted) return;

      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Emitindo NFC-e...\nAguarde a resposta da SEFAZ.',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
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
          messenger.showSnackBar(
            SnackBar(
              content: Text(dialogResult.mensagem),
              duration: const Duration(seconds: 8),
            ),
          );
          return;
        case _EmissaoNfceDialogKind.erroValidacao:
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
        case _EmissaoNfceDialogKind.sucesso:
          final r = dialogResult.resultado!;
          final vSalvar = dialogResult.vendaAtual ?? vendaAtual;
          try {
            widget.vendaRepository.registrarNfceEmitida(
              vendaId: vSalvar.id,
              chaveAcesso: r.chaveAcesso,
              numero: r.numero,
              serie: r.serie,
              protocolo: r.protocolo,
              urlDanfe: r.urlDanfe,
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

          final detalhe = <String>[
            if (r.numero.isNotEmpty) 'Numero: ${r.numero}',
            if (r.serie.isNotEmpty) 'Serie: ${r.serie}',
            if (r.chaveAcesso.isNotEmpty) 'Chave: ${r.chaveAcesso}',
            if (r.protocolo.isNotEmpty) 'Protocolo: ${r.protocolo}',
            if (r.urlDanfe.isNotEmpty) 'DANFE salvo para reimpressao.',
          ].join('\n');

          await showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (ctx) => AlertDialog(
              title: const Text('NFC-e emitida com sucesso'),
              content: Text(
                detalhe.isEmpty
                    ? (r.mensagem.isEmpty ? 'Nota autorizada.' : r.mensagem)
                    : detalhe,
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('NFC-e emitida com sucesso.'),
              backgroundColor: Colors.green,
            ),
          );
          return;
      }
    }
  }

  Venda? _buscarVendaFinalizadaParaSegundaVia(int numeroOuId) {
    final todas = widget.vendaRepository.listarTodas();
    for (final v in todas) {
      if (v.status != 'finalizada' || v.cancelada) continue;
      if (v.numeroOrcamento == numeroOuId) return v;
    }
    for (final v in todas) {
      if (v.status != 'finalizada' || v.cancelada) continue;
      if (v.id == numeroOuId) return v;
    }
    return null;
  }

  static const int _ultimasVendasFinalizadasLimite = 20;

  List<Venda> _ultimasVendasFinalizadasParaCaixa() {
    final todas = widget.vendaRepository.listarTodas();
    final lista = todas
        .where((v) => v.status == 'finalizada' && !v.cancelada)
        .toList()
      ..sort((a, b) => b.data.compareTo(a.data));
    if (lista.length <= _ultimasVendasFinalizadasLimite) {
      return lista;
    }
    return lista.sublist(0, _ultimasVendasFinalizadasLimite);
  }

  Future<void> _abrirAcoesVendaFinalizada(Venda vIn) async {
    final autorizado = await solicitarSenhaAutorizacaoSegundaViaCupom(
      context,
      _usuarioRepository,
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
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final infer = CupomNaoFiscalVendaPdf.inferirRecebidoTrocoSegundaVia(v);
    final nomeArquivo =
        'venda_${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}_2via.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Segunda via do cupom',
      content: 'Deseja imprimir ou gerar PDF da segunda via?',
      gerarPdfBytes: () => CupomNaoFiscalVendaPdf.gerarBytes(
        venda: v,
        config: config,
        cliente: _clienteDaVenda(v),
        vendedor: _vendedorDaVenda(v),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: true,
        dataCabecalhoVenda: v.data,
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

  Future<void> _alterarQuantidadeItemSelecionado(int delta) async {
    final venda = _selecionado;
    final itemId = _itemSelecionadoId;
    if (venda == null || itemId == null) {
      return;
    }
    final item = venda.itens.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      return;
    }
    final novaQuantidade = item.quantidade + delta;
    if (novaQuantidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade precisa ser maior que zero.')),
      );
      return;
    }
    try {
      widget.vendaRepository.atualizarQuantidadeItemOrcamento(
        venda.id,
        item.id,
        novaQuantidade,
      );
      _carregarOrcamentos();
      setState(() {
        _itemSelecionadoId = item.id;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel atualizar quantidade: $e')),
      );
    }
  }

  Future<void> _removerItemSelecionado() async {
    final venda = _selecionado;
    final itemId = _itemSelecionadoId;
    if (venda == null || itemId == null) {
      return;
    }
    try {
      widget.vendaRepository.removerItemOrcamento(venda.id, itemId);
      _carregarOrcamentos();
      setState(() {
        _itemSelecionadoId = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel remover item: $e')),
      );
    }
  }

  void _atualizarListaClientesAtivos() {
    _clientesAtivos = widget.clienteRepository
        .listarTodos()
        .where((c) => c.ativo)
        .toList()
      ..sort(
        (a, b) => a.nomeRazao.toLowerCase().compareTo(b.nomeRazao.toLowerCase()),
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
    setState(_atualizarListaClientesAtivos);
    return cliente.id;
  }

  Future<void> _vincularClienteAgora() async {
    final venda = _selecionado;
    if (venda == null) return;
    int? clienteSelecionadoId = venda.cliente.target?.id;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                    DropdownButtonFormField<int?>(
                      key: ValueKey<int?>(clienteSelecionadoId),
                      initialValue: clienteSelecionadoId,
                      decoration: const InputDecoration(
                        labelText: 'Cliente (opcional)',
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Sem cliente'),
                        ),
                        ..._clientesAtivos.map(
                          (c) => DropdownMenuItem<int?>(
                            value: c.id,
                            child: Text(
                              c.nomeRazao,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          clienteSelecionadoId = value;
                        });
                      },
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

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    _descontoController.dispose();
    _valorRecebidoFocusNode.dispose();
    _itensScrollController.dispose();
    _disposeMistoEdicao();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selecionado = _selecionado;
    final clienteSelecionado = selecionado == null
        ? null
        : _clienteDaVenda(selecionado);
    final descontoSelecionado = selecionado == null
        ? 0.0
        : _descontoAplicado(selecionado);
    final totalComDesconto = selecionado == null
        ? 0.0
        : _totalComDesconto(selecionado);
    final freteSelecionado = selecionado?.valorFrete ?? 0;
    final subtotalProdutos = selecionado?.somaSubtotalItens ?? 0;
    final descontoPdvOrcamento = selecionado?.descontoImplicitoTotal ?? 0;
    final parteDinheiroResumo = selecionado == null
        ? 0.0
        : _parteDinheiroNaFinalizacao(selecionado, totalComDesconto);
    final linhasMistoCaixa = selecionado != null &&
            selecionado.formaPagamento == 'misto'
        ? (_mistoValorControllers.isNotEmpty
            ? _linhasMistoDoFormulario()
            : _linhasPagamentoEscaladasCaixa(selecionado, totalComDesconto))
        : <PagamentoOrcamentoLinha>[];
    final somaMistoCaixa = linhasMistoCaixa.isEmpty
        ? 0.0
        : PagamentoOrcamentoCodec.soma(linhasMistoCaixa);
    final troco = selecionado == null
        ? 0.0
        : selecionado.formaPagamento == 'misto'
            ? (somaMistoCaixa - totalComDesconto)
                .clamp(0.0, double.infinity)
                .toDouble()
            : (parteDinheiroResumo > 0.001
                ? ((_valorRecebido ?? 0) - parteDinheiroResumo)
                    .clamp(0, double.infinity)
                    .toDouble()
                : 0.0);
    final valorTotalRecebidoCard = selecionado == null
        ? 0.0
        : selecionado.formaPagamento == 'misto' && linhasMistoCaixa.isNotEmpty
            ? somaMistoCaixa
            : (_caixaPrecisaValorRecebidoDinheiro(selecionado)
                ? (_valorRecebido ?? 0)
                : totalComDesconto);
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.numpadAdd):
            const _AumentarQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.equal, LogicalKeyboardKey.shift):
            const _AumentarQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadSubtract):
            const _DiminuirQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.minus):
            const _DiminuirQuantidadeIntent(),
        LogicalKeySet(LogicalKeyboardKey.delete): const _RemoverItemIntent(),
        LogicalKeySet(LogicalKeyboardKey.f1): const _ImportarOrcamentoIntent(),
        LogicalKeySet(LogicalKeyboardKey.f2): const _SegundaViaCupomIntent(),
        LogicalKeySet(LogicalKeyboardKey.f3): const _ReceberFiadoIntent(),
        LogicalKeySet(LogicalKeyboardKey.f4): const _VincularClienteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _AumentarQuantidadeIntent: CallbackAction<_AumentarQuantidadeIntent>(
            onInvoke: (intent) {
              if (ModalRoute.of(context)?.isCurrent != true) {
                return null;
              }
              if (_itemSelecionadoId != null) {
                _alterarQuantidadeItemSelecionado(1);
              }
              return null;
            },
          ),
          _DiminuirQuantidadeIntent: CallbackAction<_DiminuirQuantidadeIntent>(
            onInvoke: (intent) {
              if (ModalRoute.of(context)?.isCurrent != true) {
                return null;
              }
              if (_itemSelecionadoId != null) {
                _alterarQuantidadeItemSelecionado(-1);
              }
              return null;
            },
          ),
          _RemoverItemIntent: CallbackAction<_RemoverItemIntent>(
            onInvoke: (intent) {
              if (ModalRoute.of(context)?.isCurrent != true) {
                return null;
              }
              if (_itemSelecionadoId != null) {
                _removerItemSelecionado();
              }
              return null;
            },
          ),
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
              if (_selecionado != null) {
                _vincularClienteAgora();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
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
                child: selecionado == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildBarraAcoesIniciaisCaixa(context),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _buildPainelStatusCaixa(context),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
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
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.point_of_sale_outlined,
                                  color: theme.colorScheme.primary,
                                ),
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
                                    _operadorCaixa.trim().isEmpty
                                        ? ''
                                        : 'Operador: $_operadorCaixa',
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
                                  onPressed: _abrirSegundaViaCupom,
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  label: const Text('Segunda via (F2)'),
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
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final isCompact = constraints.maxHeight < 700;
                                          return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        'Pagamento: ${_rotuloPagamentoCabecalho(selecionado)}',
                                                      ),
                                                    ),
                                                    Text(
                                                      'TOTAL: ${_formatarMoeda(totalComDesconto)}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                                if (descontoPdvOrcamento >
                                                    0.001)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      top: 6,
                                                    ),
                                                    child: Text(
                                                      'Desconto (PDV): -${_formatarMoeda(descontoPdvOrcamento)}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .tertiary,
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              'Entrega: ${_textoEntregaCaixa(selecionado)}',
                                              if (_vendaExigeDadosCarreto(selecionado))
                                                'Frete: ${_formatarMoeda(selecionado.valorFrete)}',
                                              if (_vendaExigeDadosCarreto(selecionado) &&
                                                  selecionado.enderecoEntrega.trim().isNotEmpty)
                                                'Endereco: ${selecionado.enderecoEntrega}',
                                              if (_vendaExigeDadosCarreto(selecionado))
                                                'Status: ${_rotuloStatusEntrega(selecionado.statusEntrega)}',
                                              if (_vendaExigeDadosCarreto(selecionado) &&
                                                  selecionado.observacaoEntrega.trim().isNotEmpty)
                                                'Obs: ${selecionado.observacaoEntrega}',
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
                                                onPressed:
                                                    _vincularClienteAgora,
                                                icon: const Icon(
                                                  Icons
                                                      .person_add_alt_1_outlined,
                                                ),
                                                label: const Text(
                                                  'Vincular cliente agora (F4)',
                                                ),
                                              ),
                                            ],
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                'Vendedor: ${_rotuloVendedorUmLinha(selecionado)} '
                                                '(definido no Ponto de Venda)',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium,
                                              ),
                                            ),
                                          ),
                                          if (selecionado.formaPagamento ==
                                              'cartao_credito') ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              'Parcela: ${_formatarMoeda(selecionado.total / selecionado.quantidadeParcelas)}'
                                              ' (minimo ${_formatarMoeda(_valorMinimoParcela)})',
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Expanded(
                                            flex: 2,
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: Card(
                                                    elevation: 0,
                                                    color: Colors.grey.shade50,
                                                    child: Column(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .blueGrey
                                                                .shade100,
                                                            borderRadius:
                                                                const BorderRadius.only(
                                                                  topLeft:
                                                                      Radius.circular(
                                                                        8,
                                                                      ),
                                                                  topRight:
                                                                      Radius.circular(
                                                                        8,
                                                                      ),
                                                                ),
                                                          ),
                                                          child: const Row(
                                                            children: [
                                                              SizedBox(
                                                                width: 32,
                                                                child: Text(
                                                                  '#',
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                flex: 4,
                                                                child: Text(
                                                                  'Produto',
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  'Qtd',
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  'Vlr Unit',
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  'Total',
                                                                  textAlign:
                                                                      TextAlign
                                                                          .right,
                                                                  style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Expanded(
                                                          child: RawScrollbar(
                                                            controller:
                                                                _itensScrollController,
                                                            thumbVisibility:
                                                                true,
                                                            trackVisibility:
                                                                true,
                                                            thickness: 10,
                                                            radius:
                                                                const Radius.circular(
                                                                  8,
                                                                ),
                                                            child: ListView.builder(
                                                              controller:
                                                                  _itensScrollController,
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    right: 10,
                                                                  ),
                                                              itemCount:
                                                                  selecionado
                                                                      .itens
                                                                      .length,
                                                              itemBuilder: (context, index) {
                                                                final item =
                                                                    selecionado
                                                                        .itens[index];
                                                                final selecionadoItem =
                                                                    _itemSelecionadoId ==
                                                                    item.id;
                                                                return InkWell(
                                                                  onTap: () {
                                                                    setState(() {
                                                                      _itemSelecionadoId =
                                                                          item.id;
                                                                    });
                                                                  },
                                                                  child: Container(
                                                                    color:
                                                                        selecionadoItem
                                                                        ? Colors
                                                                              .blue
                                                                              .shade50
                                                                        : null,
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          6,
                                                                    ),
                                                                    child: Row(
                                                                      children: [
                                                                        SizedBox(
                                                                          width:
                                                                              32,
                                                                          child: Text(
                                                                            '${index + 1}',
                                                                          ),
                                                                        ),
                                                                        Expanded(
                                                                          flex:
                                                                              4,
                                                                          child: Text(
                                                                            '${item.nomeProduto} '
                                                                            '(${EntregaVendaHelper.abreviacaoTipoItem(item.tipoEntregaItem)})',
                                                                          ),
                                                                        ),
                                                                        Expanded(
                                                                          child: Text(
                                                                            item.quantidade.toString(),
                                                                          ),
                                                                        ),
                                                                        Expanded(
                                                                          child: Text(
                                                                            _formatarMoeda(
                                                                              item.precoUnitario,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        Expanded(
                                                                          child: Text(
                                                                            _formatarMoeda(
                                                                              item.subtotal,
                                                                            ),
                                                                            textAlign:
                                                                                TextAlign.right,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                SizedBox(
                                                  width: isCompact ? 180 : 160,
                                                  child: isCompact
                                                      ? Column(
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: OutlinedButton(
                                                                    onPressed: _itemSelecionadoId ==
                                                                            null
                                                                        ? null
                                                                        : () => _alterarQuantidadeItemSelecionado(1),
                                                                    style: OutlinedButton.styleFrom(
                                                                      visualDensity: VisualDensity.compact,
                                                                      minimumSize: const Size(0, 32),
                                                                    ),
                                                                    child: const Text('+ Qtd'),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 6),
                                                                Expanded(
                                                                  child: OutlinedButton(
                                                                    onPressed: _itemSelecionadoId ==
                                                                            null
                                                                        ? null
                                                                        : () => _alterarQuantidadeItemSelecionado(-1),
                                                                    style: OutlinedButton.styleFrom(
                                                                      visualDensity: VisualDensity.compact,
                                                                      minimumSize: const Size(0, 32),
                                                                    ),
                                                                    child: const Text('- Qtd'),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 6),
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child: OutlinedButton(
                                                                    onPressed: _itemSelecionadoId ==
                                                                            null
                                                                        ? null
                                                                        : _removerItemSelecionado,
                                                                    style: OutlinedButton.styleFrom(
                                                                      visualDensity: VisualDensity.compact,
                                                                      minimumSize: const Size(0, 32),
                                                                    ),
                                                                    child: const Text('Remover'),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 6),
                                                                Expanded(
                                                                  child: OutlinedButton(
                                                                    onPressed: _carregarOrcamentos,
                                                                    style: OutlinedButton.styleFrom(
                                                                      visualDensity: VisualDensity.compact,
                                                                      minimumSize: const Size(0, 32),
                                                                    ),
                                                                    child: const Text('Atualizar'),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        )
                                                      : Column(
                                                          children: [
                                                            _buildAcaoCaixaButton(
                                                              context,
                                                              label: '+ Quantidade',
                                                              onPressed:
                                                                  _itemSelecionadoId ==
                                                                          null
                                                                      ? null
                                                                      : () => _alterarQuantidadeItemSelecionado(
                                                                            1,
                                                                          ),
                                                            ),
                                                            const SizedBox(height: 8),
                                                            _buildAcaoCaixaButton(
                                                              context,
                                                              label: '- Quantidade',
                                                              onPressed:
                                                                  _itemSelecionadoId ==
                                                                          null
                                                                      ? null
                                                                      : () => _alterarQuantidadeItemSelecionado(
                                                                            -1,
                                                                          ),
                                                            ),
                                                            const SizedBox(height: 8),
                                                            _buildAcaoCaixaButton(
                                                              context,
                                                              label: 'Remover item',
                                                              onPressed:
                                                                  _itemSelecionadoId ==
                                                                          null
                                                                      ? null
                                                                      : _removerItemSelecionado,
                                                            ),
                                                            const SizedBox(height: 8),
                                                            _buildAcaoCaixaButton(
                                                              context,
                                                              label: 'Atualizar',
                                                              onPressed:
                                                                  _carregarOrcamentos,
                                                            ),
                                                          ],
                                                        ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Expanded(
                                                  child: SingleChildScrollView(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      bottom: 8,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                          const SizedBox(height: 4),
                                          _buildBotaoGestaoCaixa(context),
                                          const SizedBox(height: 12),
                                          if (selecionado.formaPagamento ==
                                                  'misto' &&
                                              linhasMistoCaixa.isNotEmpty) ...[
                                            _buildPainelPagamentosMistoNoCaixa(
                                              context,
                                              venda: selecionado,
                                              totalComDesconto: totalComDesconto,
                                              descontoCaixaAplicado:
                                                  descontoSelecionado > 0.001,
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                          if (!isCompact && _mostrarCampoDescontoCaixa) ...[
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(
                                                  8,
                                                ),
                                                border: Border.all(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Text('Desconto rapido:'),
                                                  const SizedBox(width: 8),
                                                  SegmentedButton<String>(
                                                    segments: const [
                                                      ButtonSegment<String>(
                                                        value: 'percentual',
                                                        label: Text('%'),
                                                      ),
                                                      ButtonSegment<String>(
                                                        value: 'valor',
                                                        label: Text('R\$'),
                                                      ),
                                                    ],
                                                    selected: {_tipoDesconto},
                                                    onSelectionChanged: (values) {
                                                      setState(() {
                                                        _tipoDesconto = values.first;
                                                        if (_selecionado !=
                                                                null &&
                                                            _selecionado!
                                                                    .formaPagamento ==
                                                                'misto') {
                                                          _prepararEdicaoMisto(
                                                            _selecionado!,
                                                          );
                                                        }
                                                        _sincronizarRecebidoPdVComOrcamento();
                                                      });
                                                    },
                                                  ),
                                                  const SizedBox(width: 8),
                                                  SizedBox(
                                                    width: 140,
                                                    child: TextField(
                                                      controller:
                                                          _descontoController,
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      decoration: InputDecoration(
                                                        isDense: true,
                                                        labelText: _tipoDesconto ==
                                                                'percentual'
                                                            ? 'Valor %'
                                                            : 'Valor R\$',
                                                        hintText: _tipoDesconto ==
                                                                'percentual'
                                                            ? 'Ex.: 10'
                                                            : 'Ex.: 25,00',
                                                      ),
                                                      onChanged: (_) {
                                                        setState(() {
                                                          if (_selecionado !=
                                                                  null &&
                                                              _selecionado!
                                                                      .formaPagamento ==
                                                                  'misto') {
                                                            _prepararEdicaoMisto(
                                                              _selecionado!,
                                                            );
                                                          }
                                                          _sincronizarRecebidoPdVComOrcamento();
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Aplicado: -${_formatarMoeda(descontoSelecionado)}',
                                                      textAlign: TextAlign.right,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleSmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                          ],
                                          if (!isCompact) ...[
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: _buildResumoCard(
                                                    context,
                                                    label: 'SUBTOTAL PRODUTOS',
                                                    valor: _formatarMoeda(
                                                      subtotalProdutos,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildResumoCard(
                                                    context,
                                                    label: 'FRETE',
                                                    valor: _formatarMoeda(
                                                      freteSelecionado,
                                                    ),
                                                  ),
                                                ),
                                                if (descontoPdvOrcamento >
                                                    0.001) ...[
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: _buildResumoCard(
                                                      context,
                                                      label: 'DESCONTO PDV',
                                                      valor:
                                                          '- ${_formatarMoeda(descontoPdvOrcamento)}',
                                                    ),
                                                  ),
                                                ],
                                                if (_mostrarCampoDescontoCaixa) ...[
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: _buildResumoCard(
                                                      context,
                                                      label:
                                                          descontoPdvOrcamento >
                                                                  0.001
                                                              ? 'DESCONTO CAIXA'
                                                              : 'DESCONTO',
                                                      valor: '- ${_formatarMoeda(descontoSelecionado)}',
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildResumoCard(
                                                    context,
                                                    label: 'TOTAL A PAGAR',
                                                    valor: _formatarMoeda(
                                                      totalComDesconto,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildResumoCard(
                                                    context,
                                                    label: selecionado
                                                                .formaPagamento ==
                                                            'misto'
                                                        ? 'SOMA DOS MEIOS'
                                                        : 'TOTAL RECEBIDO',
                                                    valor: _formatarMoeda(
                                                      valorTotalRecebidoCard,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildResumoCard(
                                                    context,
                                                    label: 'TROCO',
                                                    valor: _formatarMoeda(troco),
                                                    destaque: true,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(
                                              height:
                                                  _caixaPrecisaValorRecebidoDinheiro(
                                                    selecionado,
                                                  )
                                                      ? 16
                                                      : 10,
                                            ),
                                          ],
                                          if (_caixaPrecisaValorRecebidoDinheiro(
                                            selecionado,
                                          ))
                                            TextField(
                                              controller:
                                                  _valorRecebidoController,
                                              focusNode:
                                                  _valorRecebidoFocusNode,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              decoration: InputDecoration(
                                                labelText:
                                                    selecionado.formaPagamento ==
                                                            'misto'
                                                        ? 'Valor recebido em dinheiro (troco sobre especie)'
                                                        : 'Valor recebido (dinheiro)',
                                                hintText: 'Ex.: 100,00',
                                              ),
                                              onChanged: (value) {
                                                setState(() {
                                                  _valorRecebido = _parseValor(
                                                    value,
                                                  );
                                                });
                                              },
                                            ),
                                          if (!isCompact) ...[
                                            const SizedBox(height: 4),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                'Atalhos: Enter = finalizar | Esc = limpar recebido | + = aumentar qtd | - = diminuir qtd | Del = remover item | F4 = vincular cliente',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          if (!isCompact)
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Checkout',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.titleMedium,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Finalize a venda pelo caixa. A escolha de retirada futura e feita no orcamento.',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                                ],
                                              ),
                                            ),
                                          ),
                                                SafeArea(
                                                  top: false,
                                                  minimum: EdgeInsets.zero,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                      top: 6,
                                                    ),
                                                    child: Material(
                                                      elevation: 4,
                                                      shadowColor: Colors.black26,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .surface,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 4,
                                                          vertical: 8,
                                                        ),
                                                        child: SizedBox(
                                                          width:
                                                              double.infinity,
                                                          height: 48,
                                                          child:
                                                              ElevatedButton
                                                                  .icon(
                                                            onPressed: () =>
                                                                _finalizarOrcamento(
                                                              selecionado,
                                                            ),
                                                            icon: const Icon(
                                                              Icons
                                                                  .check_circle_outline,
                                                            ),
                                                            label: const Text(
                                                              'Finalizar venda (Enter)',
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        );
                                        },
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
        const Text('Caixa'),
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
                    'Toque na venda para segunda via, NFC-e ou DANFE.',
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
    final lista = _ultimasVendasFinalizadasParaCaixa();
    final dtCurto = DateFormat('dd/MM HH:mm');
    if (lista.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma venda finalizada ainda.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: lista.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final v = lista[index];
            final cliente = _clienteDaVenda(v);
            final badge = v.numeroOrcamento > 0 ? '${v.numeroOrcamento}' : '${v.id}';
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: CircleAvatar(
                radius: 16,
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              title: Text(
                'Venda ${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: Text(
                '${dtCurto.format(v.data.toLocal())} · '
                '${cliente?.nomeRazao ?? 'Sem cliente'} · '
                '${v.itens.length} itens',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v.nfceEmitida)
                    Tooltip(
                      message: 'NFC-e emitida',
                      child: Icon(
                        Icons.receipt_long,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                    ),
                  if (v.nfceEmitida) const SizedBox(width: 8),
                  Text(
                    _formatarMoeda(v.total),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              onTap: () => _abrirAcoesVendaFinalizada(v),
            );
          },
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

  Widget _buildCampoValorMistoCaixa(BuildContext context, {required int index}) {
    final theme = Theme.of(context);
    final meio = _mistoLinhasModelo[index].meio;
    final parcelas = _mistoLinhasModelo[index].parcelas;
    final rotulo = '${_rotuloFormaPagamento(meio)}'
        '${meio == 'cartao_credito' ? ' · ${parcelas}x' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rotulo,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _mistoValorControllers[index],
          focusNode: index < _mistoValorFocusNodes.length
              ? _mistoValorFocusNodes[index]
              : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Valor',
            alignLabelWithHint: true,
          ),
          onChanged: (_) {
            setState(() {
              _sincronizarRecebidoPdVComOrcamento();
            });
          },
        ),
      ],
    );
  }

  Widget _buildCardTrocoMistoCaixa(BuildContext context, double troco) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.payments_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'Troco',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatarMoeda(troco),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicadorResumoMisto(
    BuildContext context, {
    required String rotulo,
    required String valor,
    Color? corValor,
    bool alinharFim = false,
  }) {
    final theme = Theme.of(context);
    final alinhamento =
        alinharFim ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alinhamento,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rotulo,
          textAlign: alinharFim ? TextAlign.right : TextAlign.left,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          textAlign: alinharFim ? TextAlign.right : TextAlign.left,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: corValor,
          ),
        ),
      ],
    );
  }

  Widget _buildPainelPagamentosMistoNoCaixa(
    BuildContext context, {
    required Venda venda,
    required double totalComDesconto,
    required bool descontoCaixaAplicado,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pagamento misto (conferir / ajustar)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
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
          if (descontoCaixaAplicado) ...[
            const SizedBox(height: 4),
            Text(
              'Valores abaixo ja consideram o desconto aplicado no caixa.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (fiadoOrc > 0.001) ...[
            Text(
              'Fiado ${_formatarMoeda(fiadoOrc)}: a receber depois (definido no PDV). '
              'Confira abaixo apenas o que entra no caixa agora.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            if (planoFiado.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                PlanoFiadoCodec.formatarResumoLinhas(planoFiado),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
          ],
          if (indicesCaixa.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var j = 0; j < indicesCaixa.length; j++) ...[
                      if (j > 0) const SizedBox(width: 8),
                      SizedBox(
                        width: 128,
                        child: _buildCampoValorMistoCaixa(
                          context,
                          index: indicesCaixa[j],
                        ),
                      ),
                    ],
                    if (!pagamentoInsuficiente && trocoSobreTotal > 0.02) ...[
                      const SizedBox(width: 8),
                      _buildCardTrocoMistoCaixa(context, trocoSobreTotal),
                    ],
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIndicadorResumoMisto(
                      context,
                      rotulo: 'Recebido agora (caixa)',
                      valor: _formatarMoeda(recebidoAgora),
                      corValor: pagamentoInsuficiente
                          ? theme.colorScheme.error
                          : null,
                      alinharFim: true,
                    ),
                    if (fiadoOrc > 0.001) ...[
                      const SizedBox(width: 16),
                      _buildIndicadorResumoMisto(
                        context,
                        rotulo: '+ Fiado (a receber)',
                        valor: _formatarMoeda(fiadoOrc),
                        alinharFim: true,
                      ),
                    ],
                    const SizedBox(width: 16),
                    _buildIndicadorResumoMisto(
                      context,
                      rotulo: 'Total da venda',
                      valor: _formatarMoeda(totalComDesconto),
                      alinharFim: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
          if (pagamentoInsuficiente)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'O valor recebido agora ainda nao cobre '
                  '${_formatarMoeda(aPagarAgora)} (total menos fiado).',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          if (fiadoOrc > 0.001) ...[
            const SizedBox(height: 8),
            Text(
              'Fiado nao e recebido no caixa. Confira PIX, cartao e dinheiro; '
              'o troco considera so o que entra agora.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
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

  Widget _buildAcaoCaixaButton(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      ),
    );
  }
}

enum _EmissaoNfceDialogKind {
  sucesso,
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
  final FiscalEmissaoResultado? resultado;
  final String mensagem;
  final Venda? vendaAtual;

  factory _EmissaoNfceDialogResult.sucesso({
    required FiscalEmissaoResultado resultado,
    required Venda vendaAtual,
  }) =>
      _EmissaoNfceDialogResult._(
        kind: _EmissaoNfceDialogKind.sucesso,
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

class _AumentarQuantidadeIntent extends Intent {
  const _AumentarQuantidadeIntent();
}

class _DiminuirQuantidadeIntent extends Intent {
  const _DiminuirQuantidadeIntent();
}

class _RemoverItemIntent extends Intent {
  const _RemoverItemIntent();
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
