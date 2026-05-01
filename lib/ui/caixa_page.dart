import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/venda_service.dart';
import '../model/cliente.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';

class CaixaPage extends StatefulWidget {
  const CaixaPage({
    super.key,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.usuarioAtual,
    required this.podeManutencaoAuditoriaCaixa,
  });

  final ClienteRepository clienteRepository;
  final ProdutoRepository produtoRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final String usuarioAtual;
  final bool podeManutencaoAuditoriaCaixa;

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  static const String _kCaixaSessaoKey = 'caixa_sessao_atual_v1';
  static const String _kCaixaAuditoriaKey = 'caixa_auditoria_eventos_v1';
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  static const double _valorMinimoParcela = 5.0;
  List<Venda> _orcamentos = [];
  Venda? _selecionado;
  final _valorRecebidoController = TextEditingController();
  final _valorRecebidoFocusNode = FocusNode();
  final ScrollController _orcamentosScrollController = ScrollController();
  final ScrollController _itensScrollController = ScrollController();
  final _descontoController = TextEditingController();
  final _configRepository = AppConfigRepository();
  final _usuarioRepository = UsuarioRepository();
  late final VendaService _vendaService;
  final _senhaRetiradaController = TextEditingController();
  double? _valorRecebido;
  String _tipoDesconto = 'percentual';
  int? _itemSelecionadoId;
  List<Cliente> _clientesAtivos = [];
  bool _mostrarCampoSenhaRetirada = false;
  bool _caixaAberto = false;
  String _operadorCaixa = '';
  DateTime? _aberturaCaixaEm;
  double _fundoTrocoAbertura = 0;
  double _totalSuprimentos = 0;
  double _totalSangrias = 0;
  double _limiteDivergenciaSemSupervisor = 20;

  @override
  void initState() {
    super.initState();
    _vendaService = VendaService(widget.vendaRepository);
    _clientesAtivos = widget.clienteRepository
        .listarTodos()
        .where((c) => c.ativo)
        .toList();
    _carregarLimiteDivergenciaCaixa();
    _carregarSessaoCaixa();
    _carregarOrcamentos();
  }

  Future<void> _carregarLimiteDivergenciaCaixa() async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _limiteDivergenciaSemSupervisor = config.limiteDivergenciaCaixa;
    });
  }

  void _carregarOrcamentos() {
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
        _mostrarCampoSenhaRetirada = false;
        _senhaRetiradaController.clear();
      }
    });
  }

  Future<void> _abrirPesquisaOrcamento() async {
    _carregarOrcamentos();
    final pesquisaController = TextEditingController();
    List<Venda> resultados = List<Venda>.from(_orcamentos);
    final selecionado = await showDialog<Venda>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pesquisar orcamento'),
              content: SizedBox(
                width: 760,
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
                          resultados = _orcamentos.where((orc) {
                            final cliente = _clienteDaVenda(orc)?.nomeRazao ?? '';
                            final vendedor = _rotuloVendedorUmLinha(orc);
                            return orc.numeroOrcamento.toString().contains(termo) ||
                                cliente.toLowerCase().contains(termo) ||
                                vendedor.toLowerCase().contains(termo);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 220,
                        maxHeight: MediaQuery.of(context).size.height * 0.58,
                      ),
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum orcamento pendente.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final orc = resultados[index];
                                final cliente = _clienteDaVenda(orc)?.nomeRazao ?? 'Sem cliente';
                                return ListTile(
                                  title: Text('Orcamento #${orc.numeroOrcamento}'),
                                  subtitle: Text(
                                    '$cliente | Itens: ${orc.itens.length} | Total: ${_formatarMoeda(orc.total)}',
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
    if (selecionado == null || !mounted) return;
    setState(() {
      _selecionado = selecionado;
      _valorRecebidoController.clear();
      _valorRecebido = null;
      _descontoController.clear();
      _tipoDesconto = 'percentual';
      _itemSelecionadoId = null;
    });
    _focarValorRecebidoSeDinheiro();
  }

  void _focarValorRecebidoSeDinheiro() {
    final selecionado = _selecionado;
    if (selecionado == null || selecionado.formaPagamento != 'dinheiro') {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _valorRecebidoFocusNode.requestFocus();
      }
    });
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCaixaSessaoKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _caixaAberto = map['aberto'] == true;
        _operadorCaixa = (map['operador'] as String?) ?? '';
        final aberturaIso = map['aberturaEm'] as String?;
        _aberturaCaixaEm = aberturaIso == null ? null : DateTime.tryParse(aberturaIso);
        _fundoTrocoAbertura = ((map['fundoTroco'] as num?) ?? 0).toDouble();
        _totalSuprimentos = ((map['suprimentos'] as num?) ?? 0).toDouble();
        _totalSangrias = ((map['sangrias'] as num?) ?? 0).toDouble();
      });
    } catch (_) {
      // ignore invalid persisted format
    }
  }

  Future<void> _salvarSessaoCaixa() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'aberto': _caixaAberto,
      'operador': _operadorCaixa,
      'aberturaEm': _aberturaCaixaEm?.toIso8601String(),
      'fundoTroco': _fundoTrocoAbertura,
      'suprimentos': _totalSuprimentos,
      'sangrias': _totalSangrias,
    };
    await prefs.setString(_kCaixaSessaoKey, jsonEncode(payload));
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
                              if (!mounted) return;
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
                              if (!mounted) return;
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _caixaAberto ? null : _abrirCaixa,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Abrir caixa'),
            ),
            OutlinedButton.icon(
              onPressed: _caixaAberto
                  ? () => _registrarMovimentoCaixa(suprimento: true)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Suprimento'),
            ),
            OutlinedButton.icon(
              onPressed: _caixaAberto
                  ? () => _registrarMovimentoCaixa(suprimento: false)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Sangria'),
            ),
            ElevatedButton.icon(
              onPressed: _caixaAberto ? _fecharCaixa : null,
              icon: const Icon(Icons.task_alt_outlined),
              label: const Text('Fechamento'),
            ),
            OutlinedButton.icon(
              onPressed: _abrirHistoricoAuditoria,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Auditoria'),
            ),
          ],
        ),
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
    await _registrarAuditoriaCaixa(
      suprimento ? 'suprimento' : 'sangria',
      detalhes: {
        'valor': valor,
        'observacao': obs,
      },
    );
    if (!mounted) return;
    final tipo = suprimento ? 'Suprimento' : 'Sangria';
    final sufixoObs = obs.isEmpty ? '' : ' Obs: $obs';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$tipo de ${_formatarMoeda(valor)} registrado.$sufixoObs')),
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
    final config = await _configRepository.carregarEmpresaConfig();
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
    final config = await _configRepository.carregarEmpresaConfig();
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
        final printer = await _obterImpressoraPadrao(config.impressoraPadrao);
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
      case 'dinheiro':
      default:
        return 'Dinheiro';
    }
  }

  String _rotuloTipoEntrega(String tipoEntrega) {
    switch (tipoEntrega) {
      case 'entrega_loja':
        return 'Entrega da loja';
      case 'retirada':
      default:
        return 'Retirada na loja';
    }
  }

  String _rotuloStatusEntrega(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'Roteirizada';
      case 'saiu_entrega':
        return 'Saiu para entrega';
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
    final formaPagamento = venda.formaPagamento;
    final parcelas = venda.quantidadeParcelas;
    final totalRecebido = formaPagamento == 'dinheiro'
        ? (_valorRecebido ?? 0)
        : totalVenda;
    final trocoFinal = formaPagamento == 'dinheiro'
        ? (totalRecebido - totalVenda).clamp(0, double.infinity).toDouble()
        : 0.0;
    final itensCount = venda.itens.length;

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
    final confirmarFinalizacao = await _mostrarResumoFechamentoVenda(
      numeroOrcamento: venda.numeroOrcamento,
      formaPagamento: formaPagamento,
      quantidadeParcelas: parcelas,
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
      widget.vendaRepository.converterOrcamentoParaVenda(venda.id);
      final vendaFinalizada = widget.vendaRepository.obterPorId(venda.id) ?? venda;
      _carregarOrcamentos();
      if (!mounted) return;
      setState(() {
        _selecionado = null;
        _itemSelecionadoId = null;
        _valorRecebidoController.clear();
        _descontoController.clear();
        _tipoDesconto = 'percentual';
        _valorRecebido = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orcamento #${venda.numeroOrcamento} finalizado.'),
        ),
      );
      await _mostrarAcoesNotaPosVenda(
        venda: vendaFinalizada,
        totalRecebido: totalRecebido,
        troco: trocoFinal,
        descontoAplicado: descontoAplicado,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Nao foi possivel finalizar: $e')));
    }
  }

  Future<void> _solicitarRetiradaFutura(Venda venda) async {
    final senha = _senhaRetiradaController.text.trim();
    if (senha.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a senha do dia com 4 digitos.')),
      );
      return;
    }
    try {
      final eraOrcamento = venda.status == 'orcamento';
      _vendaService.solicitarRetiradaFutura(
        vendaId: venda.id,
        senhaDoDiaInformada: senha,
      );
      _carregarOrcamentos();
      if (!mounted) return;
      setState(() {
        _mostrarCampoSenhaRetirada = false;
        _senhaRetiradaController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            eraOrcamento
                ? 'Orcamento marcado para retirada futura. Ao finalizar a venda, o estoque sera reservado.'
                : 'Venda marcada com retirada futura (pendente).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel marcar retirada futura: $e')),
      );
    }
  }

  Future<Uint8List> _gerarNotaPdfBytes({
    required Venda venda,
    required double totalRecebido,
    required double troco,
    required double descontoAplicado,
  }) async {
    final cliente = _clienteDaVenda(venda);
    final config = await _configRepository.carregarEmpresaConfig();
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(
            config.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    doc.addPage(
      pw.Page(
        pageFormat: config.modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          final subtotalProdutos = (venda.total - venda.valorFrete)
              .clamp(0, double.infinity)
              .toDouble();
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  config.nomeLoja,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 45),
                  ),
                ),
              if (config.telefone.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: ${config.telefone}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              if (config.endereco.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    config.endereco,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  'CUPOM NAO FISCAL',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text(
                'ORCAMENTO #${venda.numeroOrcamento}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Data: $dataHora',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Vendedor: ${_rotuloVendedorUmLinha(venda)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if ((cliente?.documento.trim().isNotEmpty ?? false))
                pw.Text(
                  'Documento: ${cliente!.documento}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if ((cliente?.telefone.trim().isNotEmpty ?? false))
                pw.Text(
                  'Telefone: ${cliente!.telefone}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'Pagamento: ${_rotuloFormaPagamento(venda.formaPagamento)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (venda.formaPagamento == 'cartao_credito')
                pw.Text(
                  'Parcelas: ${venda.quantidadeParcelas}x',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'Entrega: ${_rotuloTipoEntrega(venda.tipoEntrega)}'
                '${venda.tipoEntrega == 'entrega_loja' ? ' | Frete: ${_formatarMoeda(venda.valorFrete)}' : ''}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (venda.enderecoEntrega.trim().isNotEmpty)
                pw.Text(
                  'Endereco: ${venda.enderecoEntrega}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.SizedBox(height: 10),
              pw.Text(
                'ITENS',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              ...venda.itens.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.nomeProduto,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        '${item.quantidade} x ${_formatarMoeda(item.precoUnitario)} = ${_formatarMoeda(item.subtotal)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              pw.Text(
                'Subtotal: ${_formatarMoeda(subtotalProdutos)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Frete: ${_formatarMoeda(venda.valorFrete)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (descontoAplicado > 0)
                pw.Text(
                  'Desconto: - ${_formatarMoeda(descontoAplicado)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'TOTAL: ${_formatarMoeda(venda.total)}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Recebido: ${_formatarMoeda(totalRecebido)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Troco: ${_formatarMoeda(troco)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  config.rodapeNota,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
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

  Future<Printer?> _obterImpressoraPadrao(String printerName) async {
    if (printerName.trim().isEmpty) return null;
    final printers = await Printing.listPrinters();
    for (final printer in printers) {
      if (printer.name == printerName) {
        return printer;
      }
    }
    return null;
  }

  Future<void> _mostrarAcoesNotaPosVenda({
    required Venda venda,
    required double totalRecebido,
    required double troco,
    required double descontoAplicado,
  }) async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nota da venda'),
          content: const Text('Deseja imprimir a nota agora ou gerar PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Mandar nota em PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'direto'),
              icon: const Icon(Icons.print),
              label: const Text('Impressao direta'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir nota'),
            ),
          ],
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    try {
      final pdfBytes = await _gerarNotaPdfBytes(
        venda: venda,
        totalRecebido: totalRecebido,
        troco: troco,
        descontoAplicado: descontoAplicado,
      );
      if (acao == 'imprimir') {
        await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
        return;
      }
      if (acao == 'direto') {
        final printer = await _obterImpressoraPadrao(config.impressoraPadrao);
        if (printer == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impressora padrao nao configurada/encontrada.'),
            ),
          );
          return;
        }
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdfBytes,
          name: 'Nota Orcamento ${venda.numeroOrcamento}',
          format: config.modeloPdf == 'a4'
              ? PdfPageFormat.a4
              : PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdfBytes,
        suggestedFileName: 'nota_orcamento_${venda.numeroOrcamento}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF salvo em: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel gerar/imprimir nota: $e')),
      );
    }
  }

  Future<bool?> _mostrarResumoFechamentoVenda({
    required int numeroOrcamento,
    required String formaPagamento,
    required int quantidadeParcelas,
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
          title: Text('Venda finalizada - Orcamento #$numeroOrcamento'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagamento: ${_rotuloFormaPagamento(formaPagamento)}'
                  '${formaPagamento == 'cartao_credito' ? ' | ${quantidadeParcelas}x' : ''}',
                ),
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
              content: DropdownButtonFormField<int?>(
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
                      child: Text(c.nomeRazao),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    clienteSelecionadoId = value;
                  });
                },
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

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    _descontoController.dispose();
    _senhaRetiradaController.dispose();
    _valorRecebidoFocusNode.dispose();
    _orcamentosScrollController.dispose();
    _itensScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selecionado = _selecionado;
    final clienteSelecionado = selecionado == null
        ? null
        : _clienteDaVenda(selecionado);
    final totalSelecionado = selecionado?.total ?? 0;
    final descontoSelecionado = selecionado == null
        ? 0.0
        : _descontoAplicado(selecionado);
    final totalComDesconto = selecionado == null
        ? 0.0
        : _totalComDesconto(selecionado);
    final freteSelecionado = selecionado?.valorFrete ?? 0;
    final subtotalProdutos = (totalSelecionado - freteSelecionado)
        .clamp(0, double.infinity)
        .toDouble();
    final troco = (((_valorRecebido ?? 0) - totalComDesconto).clamp(
      0,
      double.infinity,
    )).toDouble();
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
            appBar: AppBar(title: const Text('Caixa')),
            body: Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: selecionado == null
                    ? Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _abrirPesquisaOrcamento,
                              icon: const Icon(Icons.search),
                              label: const Text('Pesquisar orcamento para importar'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(child: _buildPainelStatusCaixa(context)),
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
                                  label: const Text('Pesquisar orcamento'),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Orcamento #${selecionado.numeroOrcamento}',
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
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Pagamento: ${_rotuloFormaPagamento(selecionado.formaPagamento)}'
                                                    '${selecionado.formaPagamento == 'cartao_credito' ? ' | ${selecionado.quantidadeParcelas}x' : ''}',
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
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              'Entrega: ${_rotuloTipoEntrega(selecionado.tipoEntrega)}',
                                              if (selecionado.tipoEntrega == 'entrega_loja')
                                                'Frete: ${_formatarMoeda(selecionado.valorFrete)}',
                                              if (selecionado.tipoEntrega == 'entrega_loja' &&
                                                  selecionado.enderecoEntrega.trim().isNotEmpty)
                                                'Endereco: ${selecionado.enderecoEntrega}',
                                              if (selecionado.tipoEntrega == 'entrega_loja')
                                                'Status: ${_rotuloStatusEntrega(selecionado.statusEntrega)}',
                                              if (selecionado.tipoEntrega == 'entrega_loja' &&
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
                                          SizedBox(
                                            height: isCompact
                                                ? (constraints.maxHeight * 0.18).clamp(110.0, 165.0)
                                                : (constraints.maxHeight * 0.30).clamp(170.0, 280.0),
                                            child: Row(
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
                                                                            item.nomeProduto,
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
                                          const SizedBox(height: 4),
                                          _buildBotaoGestaoCaixa(context),
                                          const SizedBox(height: 4),
                                          if (!isCompact) ...[
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
                                                        setState(() {});
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
                                            const SizedBox(height: 4),
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
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: _buildResumoCard(
                                                    context,
                                                    label: 'DESCONTO',
                                                    valor: '- ${_formatarMoeda(descontoSelecionado)}',
                                                  ),
                                                ),
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
                                                    label: 'TOTAL RECEBIDO',
                                                    valor: _formatarMoeda(
                                                      _valorRecebido ?? 0,
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
                                            const SizedBox(height: 4),
                                          ],
                                          if (selecionado.formaPagamento ==
                                              'dinheiro')
                                            TextField(
                                              controller:
                                                  _valorRecebidoController,
                                              focusNode:
                                                  _valorRecebidoFocusNode,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Valor recebido (dinheiro)',
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
                                                    'Finalize a venda e, se precisar, marque retirada futura.',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: ElevatedButton.icon(
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
                                                  const SizedBox(height: 4),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: TextButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          _mostrarCampoSenhaRetirada =
                                                              !_mostrarCampoSenhaRetirada;
                                                          if (!_mostrarCampoSenhaRetirada) {
                                                            _senhaRetiradaController
                                                                .clear();
                                                          }
                                                        });
                                                      },
                                                      style: TextButton.styleFrom(
                                                        visualDensity:
                                                            VisualDensity.compact,
                                                        minimumSize: const Size(
                                                          0,
                                                          32,
                                                        ),
                                                        tapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        'Retirada futura',
                                                      ),
                                                    ),
                                                  ),
                                                  if (_mostrarCampoSenhaRetirada) ...[
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextField(
                                                            controller:
                                                                _senhaRetiradaController,
                                                            maxLength: 4,
                                                            keyboardType:
                                                                TextInputType
                                                                    .number,
                                                            decoration:
                                                                const InputDecoration(
                                                                  labelText:
                                                                      'Senha do dia',
                                                                  counterText: '',
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        ElevatedButton(
                                                          onPressed: () =>
                                                              _solicitarRetiradaFutura(
                                                                selecionado,
                                                              ),
                                                          child: const Text(
                                                            'Confirmar',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            )
                                          else
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed: () =>
                                                    _finalizarOrcamento(selecionado),
                                                icon: const Icon(Icons.check_circle_outline),
                                                label: const Text('Finalizar venda (Enter)'),
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

  Widget _buildPainelStatusCaixa(BuildContext context, {bool compact = false}) {
    final aberturaFmt = _aberturaCaixaEm == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(_aberturaCaixaEm!.toLocal());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gestao de Caixa',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(_caixaAberto ? 'Status: Aberto' : 'Status: Fechado'),
            Text('Operador: ${_operadorCaixa.trim().isEmpty ? '-' : _operadorCaixa}'),
            Text('Abertura: $aberturaFmt'),
            const SizedBox(height: 4),
            Text('Fundo inicial: ${_formatarMoeda(_fundoTrocoAbertura)}'),
            Text('Suprimentos: ${_formatarMoeda(_totalSuprimentos)}'),
            Text('Sangrias: ${_formatarMoeda(_totalSangrias)}'),
            const SizedBox(height: 10),
            Wrap(
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
                  onPressed: _abrirHistoricoAuditoria,
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
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'Use "Pesquisar orcamento" para importar um atendimento no caixa.',
                  style: Theme.of(context).textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
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

  Widget _buildAcoesCaixaCompact(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          OutlinedButton.icon(
            onPressed: _caixaAberto ? null : _abrirCaixa,
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Abrir caixa'),
          ),
          OutlinedButton.icon(
            onPressed: _caixaAberto ? () => _registrarMovimentoCaixa(suprimento: true) : null,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Suprimento'),
          ),
          OutlinedButton.icon(
            onPressed: _caixaAberto ? () => _registrarMovimentoCaixa(suprimento: false) : null,
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Sangria'),
          ),
          OutlinedButton.icon(
            onPressed: _caixaAberto ? _fecharCaixa : null,
            icon: const Icon(Icons.task_alt_outlined),
            label: const Text('Fechamento'),
          ),
          OutlinedButton.icon(
            onPressed: _abrirHistoricoAuditoria,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Auditoria'),
          ),
        ],
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

  Widget _buildListaOrcamentos(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              'Orcamentos pendentes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _orcamentos.isEmpty
                ? const Center(child: Text('Nenhum orcamento pendente.'))
                : RawScrollbar(
                    controller: _orcamentosScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _orcamentosScrollController,
                      padding: const EdgeInsets.only(right: 10, bottom: 8),
                      itemCount: _orcamentos.length,
                      itemBuilder: (context, index) {
                        final orc = _orcamentos[index];
                        final vendOrc = _vendedorDaVenda(orc);
                        final sufV = vendOrc != null
                            ? ' · ${_rotuloVendedorUmLinha(orc)}'
                            : '';
                        return ListTile(
                          selected: _selecionado?.id == orc.id,
                          leading: CircleAvatar(
                            child: Text('${orc.numeroOrcamento}'),
                          ),
                          title: Text('Orcamento #${orc.numeroOrcamento}'),
                          subtitle: Text(
                            'Itens: ${orc.itens.length} | Total: ${_formatarMoeda(orc.total)}$sufV',
                          ),
                          onTap: () {
                            setState(() {
                              _selecionado = orc;
                              _valorRecebidoController.clear();
                              _valorRecebido = null;
                              _descontoController.clear();
                              _tipoDesconto = 'percentual';
                              _itemSelecionadoId = null;
                            });
                            _focarValorRecebidoSeDinheiro();
                          },
                        );
                      },
                    ),
                  ),
          ),
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

class _AumentarQuantidadeIntent extends Intent {
  const _AumentarQuantidadeIntent();
}

class _DiminuirQuantidadeIntent extends Intent {
  const _DiminuirQuantidadeIntent();
}

class _RemoverItemIntent extends Intent {
  const _RemoverItemIntent();
}

class _VincularClienteIntent extends Intent {
  const _VincularClienteIntent();
}
