import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/motorista_repository.dart';
import '../data/venda_repository.dart';
import '../model/item_venda.dart';
import '../model/venda.dart';

/// Filtro rapido pelos contadores de resumo (atrasadas / pendentes hoje).
enum _FiltroResumoEntregas { nenhum, atrasadas, pendentesHoje }

class EntregasPage extends StatefulWidget {
  const EntregasPage({
    super.key,
    required this.vendaRepository,
    required this.motoristaRepository,
    required this.usuarioAtual,
    required this.podeGerenciarStatusEntrega,
  });

  final VendaRepository vendaRepository;
  final MotoristaRepository motoristaRepository;
  final String usuarioAtual;
  final bool podeGerenciarStatusEntrega;

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final _bairroController = TextEditingController();
  final _numeroNotaController = TextEditingController();
  final _statuses = const [
    'todos',
    'pendente',
    'roteirizada',
    'saiu_entrega',
    'entregue',
    'reagendada',
    'cancelada',
  ];

  List<Venda> _entregas = [];
  String _statusSelecionado = 'todos';
  String _filtroMotorista = 'todos';
  String _filtroVendedor = 'todos';
  List<String> _vendedoresDisponiveis = const [];
  String _agrupamento = 'bairro'; // bairro | motorista
  String _filtroDataMarcada = 'todos'; // todos | hoje | amanha | sem_data
  DateTime? _inicio;
  DateTime? _fim;
  bool _modoAgruparMesmoCarro = false;
  final Set<int> _idsEntregasSelecionadas = {};
  /// Incrementado ao usar "Limpar tudo" para remontar dropdowns (initialValue vale apenas no primeiro build).
  int _filtrosDropdownNonce = 0;
  _FiltroResumoEntregas _filtroResumoLista = _FiltroResumoEntregas.nenhum;
  /// Chave igual a [resumoPorDia] (`dd/MM/yyyy` ou `Sem data marcada`); filtra so a lista.
  String? _chaveDiaPlanejamentoSelecionado;

  @override
  void initState() {
    super.initState();
    _inicio = null;
    _fim = null;
    _carregarEntregas();
  }

  @override
  void dispose() {
    _bairroController.dispose();
    _numeroNotaController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  bool _vendaUsaItensCarretoMigrado(Venda v) {
    return v.tipoEntrega == 'entrega_loja' &&
        v.itens.any((i) => i.quantidadeNoCarreto > 0);
  }

  int _quantidadeExibicaoEntrega(Venda v, ItemVenda item) {
    return item.quantidadeParaExibicaoEntrega(_vendaUsaItensCarretoMigrado(v));
  }

  double _subtotalExibicaoEntrega(Venda v, ItemVenda item) {
    return _quantidadeExibicaoEntrega(v, item) * item.precoUnitario;
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

  String _rotuloStatusFiltro(String status) {
    if (status == 'todos') return 'Todos';
    return _rotuloStatusEntrega(status);
  }

  Color _corStatus(ColorScheme scheme, String status) {
    switch (status) {
      case 'entregue':
        return Colors.green.shade700;
      case 'saiu_entrega':
        return Colors.blue.shade700;
      case 'reagendada':
        return Colors.orange.shade700;
      case 'cancelada':
        return scheme.error;
      case 'roteirizada':
        return Colors.purple.shade700;
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

  /// Filtro opcional: numero do cupom ([Venda.numeroOrcamento]) ou id interno ([Venda.id]).
  List<Venda> _filtrarPorNumeroNotaSeInformado(List<Venda> entregas) {
    var raw = _numeroNotaController.text.trim();
    if (raw.isEmpty) return entregas;
    if (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }
    final n = int.tryParse(raw);
    if (n == null) return <Venda>[];
    return entregas.where((v) {
      if (v.numeroOrcamento > 0 && v.numeroOrcamento == n) return true;
      return v.id == n;
    }).toList();
  }

  bool _vendaEhAtrasada(Venda venda) {
    if (_statusFinalizado(venda.statusEntrega)) return false;
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    final hoje = DateTime.now();
    final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final baseMarcada = DateTime(marcada.year, marcada.month, marcada.day);
    return baseMarcada.isBefore(baseHoje);
  }

  bool _vendaEhAgendaHoje(Venda venda) {
    if (_statusFinalizado(venda.statusEntrega)) return false;
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    final hoje = DateTime.now();
    final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final baseMarcada = DateTime(marcada.year, marcada.month, marcada.day);
    return baseMarcada == baseHoje;
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

  void _carregarEntregas() {
    // Periodo da venda no repositorio ignora data marcada; para ver atrasadas/agendas
    // de pedidos antigos, nao restringimos por [_inicio]/[_fim] com filtro de resumo ativo.
    final usarPeriodoVenda = _filtroResumoLista == _FiltroResumoEntregas.nenhum;
    var entregas = widget.vendaRepository.listarEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: usarPeriodoVenda ? _inicio : null,
      fim: usarPeriodoVenda ? _fim : null,
    );
    entregas = entregas.where(_atendeFiltroDataMarcada).toList();
    entregas = _filtrarPorNumeroNotaSeInformado(entregas);
    final vendedoresDisponiveis = (entregas
            .map(_nomeVendedor)
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    if (_filtroMotorista != 'todos') {
      entregas = entregas
          .where((v) => _nomeMotorista(v).toLowerCase() == _filtroMotorista)
          .toList();
    }
    if (_filtroVendedor != 'todos') {
      entregas = entregas
          .where((v) => _nomeVendedor(v).toLowerCase() == _filtroVendedor)
          .toList();
    }
    if (_filtroResumoLista == _FiltroResumoEntregas.atrasadas) {
      entregas = entregas.where(_vendaEhAtrasada).toList();
    } else if (_filtroResumoLista == _FiltroResumoEntregas.pendentesHoje) {
      entregas = entregas.where(_vendaEhAgendaHoje).toList();
    }
    entregas.sort((a, b) {
      final pa = _pesoPrioridade(a.prioridadeEntrega);
      final pb = _pesoPrioridade(b.prioridadeEntrega);
      final byPri = pb.compareTo(pa);
      if (byPri != 0) return byPri;
      return b.data.compareTo(a.data);
    });
    setState(() {
      _entregas = entregas;
      _vendedoresDisponiveis = vendedoresDisponiveis;
      if (_chaveDiaPlanejamentoSelecionado != null) {
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
    if (_idsEntregasSelecionadas.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos duas entregas do mesmo cliente.'),
        ),
      );
      return;
    }
    try {
      widget.vendaRepository.definirGrupoEntregaLogistica(
        Set<int>.from(_idsEntregasSelecionadas),
      );
      await _carregarEntregasSyncState();
      if (!mounted) return;
      setState(() {
        _idsEntregasSelecionadas.clear();
        _modoAgruparMesmoCarro = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pedidos marcados para o mesmo carro. A lista foi atualizada.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _removerAgrupamentoSelecionadas() async {
    if (_idsEntregasSelecionadas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione as entregas para tirar do grupo.'),
        ),
      );
      return;
    }
    try {
      widget.vendaRepository.limparGrupoEntregaLogisticaEm(
        Set<int>.from(_idsEntregasSelecionadas),
      );
      await _carregarEntregasSyncState();
      if (!mounted) return;
      setState(() => _idsEntregasSelecionadas.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrupamento removido das selecionadas.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  /// Mesma logica de [_carregarEntregas] sem segundo setState no fim (evita piscar).
  Future<void> _carregarEntregasSyncState() async {
    final usarPeriodoVenda = _filtroResumoLista == _FiltroResumoEntregas.nenhum;
    var entregas = widget.vendaRepository.listarEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: usarPeriodoVenda ? _inicio : null,
      fim: usarPeriodoVenda ? _fim : null,
    );
    entregas = entregas.where(_atendeFiltroDataMarcada).toList();
    entregas = _filtrarPorNumeroNotaSeInformado(entregas);
    final vendedoresDisponiveis = (entregas
            .map(_nomeVendedor)
            .map((n) => n.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    if (_filtroMotorista != 'todos') {
      entregas = entregas
          .where((v) => _nomeMotorista(v).toLowerCase() == _filtroMotorista)
          .toList();
    }
    if (_filtroVendedor != 'todos') {
      entregas = entregas
          .where((v) => _nomeVendedor(v).toLowerCase() == _filtroVendedor)
          .toList();
    }
    if (_filtroResumoLista == _FiltroResumoEntregas.atrasadas) {
      entregas = entregas.where(_vendaEhAtrasada).toList();
    } else if (_filtroResumoLista == _FiltroResumoEntregas.pendentesHoje) {
      entregas = entregas.where(_vendaEhAgendaHoje).toList();
    }
    entregas.sort((a, b) {
      final pa = _pesoPrioridade(a.prioridadeEntrega);
      final pb = _pesoPrioridade(b.prioridadeEntrega);
      final byPri = pb.compareTo(pa);
      if (byPri != 0) return byPri;
      return b.data.compareTo(a.data);
    });
    if (!mounted) return;
    setState(() {
      _entregas = entregas;
      _vendedoresDisponiveis = vendedoresDisponiveis;
      if (_chaveDiaPlanejamentoSelecionado != null) {
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
  }

  bool _atendeFiltroDataMarcada(Venda venda) {
    final filtro = _filtroDataMarcada;
    if (filtro == 'todos') return true;
    if (filtro == 'sem_data') return venda.dataEntregaMarcada == null;
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final d = DateTime(marcada.year, marcada.month, marcada.day);
    if (filtro == 'hoje') return d == base;
    if (filtro == 'amanha') return d == base.add(const Duration(days: 1));
    return true;
  }

  /// Mantem a ordem de [ordenadas]; vendas com o mesmo [grupoEntregaFreteId] > 0 ficam no mesmo bloco.
  List<List<Venda>> _blocosEntregaComCarretoAgrupado(List<Venda> ordenadas) {
    final vistos = <int>{};
    final blocos = <List<Venda>>[];
    for (final v in ordenadas) {
      final g = v.grupoEntregaFreteId;
      if (g <= 0) {
        blocos.add([v]);
        continue;
      }
      if (vistos.contains(g)) {
        continue;
      }
      vistos.add(g);
      blocos.add(
        ordenadas.where((x) => x.grupoEntregaFreteId == g).toList(),
      );
    }
    return blocos;
  }

  String _rotuloGrupoLogistica(List<Venda> bloco) {
    final nums = bloco.map((v) {
      if (v.numeroOrcamento > 0) return '#${v.numeroOrcamento}';
      return 'id ${v.id}';
    }).join(', ');
    return 'Mesmo carro · $nums';
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
          '#${venda.numeroOrcamento} · ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
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
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        ..._linhasItensEntrega(venda).map(
          (linha) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              '• $linha',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('Separado'),
              selected: venda.cargaSeparada,
              onSelected: (v) {
                _atualizarChecklistCarga(
                  venda,
                  separado: v,
                );
                setDialogState(() {
                  venda.cargaSeparada = v;
                });
              },
            ),
            FilterChip(
              label: const Text('Carregado'),
              selected: venda.cargaCarregada,
              onSelected: (v) {
                _atualizarChecklistCarga(
                  venda,
                  carregado: v,
                );
                setDialogState(() {
                  venda.cargaCarregada = v;
                });
              },
            ),
            FilterChip(
              label: const Text('Saiu'),
              selected: venda.cargaSaiu,
              onSelected: (v) {
                _atualizarChecklistCarga(venda, saiu: v);
                setDialogState(() {
                  venda.cargaSaiu = v;
                });
              },
            ),
          ],
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
      final scheme = Theme.of(context).colorScheme;
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
              _rotuloGrupoLogistica(bloco),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text('${bloco.length} pedidos no mesmo veiculo'),
            const Divider(height: 16),
            for (var i = 0; i < bloco.length; i++) ...[
              _conteudoRomaneioUmaVenda(context, bloco[i], setDialogState),
              if (i < bloco.length - 1) const Divider(height: 12),
            ],
          ],
        ),
      );
    }
    return _conteudoRomaneioUmaVenda(context, bloco.single, setDialogState);
  }

  Future<void> _abrirRomaneioDoDia() async {
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final doDia = _entregasDoDia(base);
    final blocosRom = _blocosEntregaComCarretoAgrupado(doDia);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Romaneio do dia'),
              content: SizedBox(
                width: 700,
                child: doDia.isEmpty
                    ? const Text('Nao ha entregas marcadas para hoje.')
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
    }).toList()
      ..sort((a, b) {
        final pa = _pesoPrioridade(a.prioridadeEntrega);
        final pb = _pesoPrioridade(b.prioridadeEntrega);
        final byP = pb.compareTo(pa);
        if (byP != 0) return byP;
        return (a.janelaEntrega).compareTo(b.janelaEntrega);
      });
  }

  List<String> _linhasItensEntrega(Venda venda) {
    if (venda.itens.isEmpty) return const ['Sem itens cadastrados'];
    final usa = _vendaUsaItensCarretoMigrado(venda);
    final linhas = venda.itens
        .map((item) {
          final q = item.quantidadeParaExibicaoEntrega(usa);
          return q > 0 ? '${q}x ${item.nomeProduto}' : null;
        })
        .whereType<String>()
        .toList();
    return linhas.isEmpty ? const ['Sem itens para esta entrega'] : linhas;
  }

  pw.Widget _pdfRomaneioUmaEntrega(Venda venda) {
    final cliente = venda.cliente.target?.nomeRazao ?? 'Sem cliente';
    final dataMarcada = venda.dataEntregaMarcada == null
        ? 'Sem data'
        : DateFormat('dd/MM/yyyy').format(venda.dataEntregaMarcada!.toLocal());
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '#${venda.numeroOrcamento} - $cliente',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Bairro: ${_extrairBairro(venda)} | Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)} | Prioridade: ${_rotuloPrioridade(venda.prioridadeEntrega)}',
          ),
          pw.Text('Motorista: ${_nomeMotorista(venda)}'),
          pw.Text('Vendedor: ${_nomeVendedor(venda)}'),
          pw.Text('Data marcada: $dataMarcada'),
          pw.Text('Endereco: ${venda.enderecoEntrega}'),
          if (_observacaoSemMotorista(venda).trim().isNotEmpty)
            pw.Text('Obs: ${_observacaoSemMotorista(venda)}'),
          pw.SizedBox(height: 3),
          pw.Text(
            'Itens:',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          ..._linhasItensEntrega(venda).map(
            (linha) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Text(
                '• $linha',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '[${venda.cargaSeparada ? 'x' : ' '}] Separado    '
            '[${venda.cargaCarregada ? 'x' : ' '}] Carregado    '
            '[${venda.cargaSaiu ? 'x' : ' '}] Saiu',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _gerarRomaneioHojePdfBytes(List<Venda> entregasDia) async {
    final doc = pw.Document();
    final agora = DateTime.now();
    final dataHoje = DateFormat('dd/MM/yyyy').format(agora);
    final horaEmissao = DateFormat('dd/MM/yyyy HH:mm').format(agora);
    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Romaneio de Entregas - $dataHoje',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text('Emitido em: $horaEmissao'),
              pw.Text('Total de entregas: ${entregasDia.length}'),
              pw.SizedBox(height: 10),
              pw.Divider(),
              ..._blocosEntregaComCarretoAgrupado(entregasDia).expand((bloco) {
                if (bloco.length >= 2 &&
                    bloco.first.grupoEntregaFreteId > 0) {
                  return [
                    pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 0.7),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _rotuloGrupoLogistica(bloco),
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          pw.Text(
                            '${bloco.length} pedidos no mesmo veiculo',
                            style: const pw.TextStyle(fontSize: 9.5),
                          ),
                          pw.SizedBox(height: 4),
                          ...bloco.map(_pdfRomaneioUmaEntrega),
                        ],
                      ),
                    ),
                  ];
                }
                return bloco.map(_pdfRomaneioUmaEntrega);
              }),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _exportarOuImprimirRomaneioHoje() async {
    final base = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final entregasDia = _entregasDoDia(base);
    if (entregasDia.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha entregas para hoje.')),
      );
      return;
    }
    final pdfBytes = await _gerarRomaneioHojePdfBytes(entregasDia);
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Romaneio de hoje'),
        content: const Text('Deseja imprimir ou exportar em PDF?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'fechar'),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Exportar PDF'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'imprimir'),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir'),
          ),
        ],
      ),
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    if (acao == 'imprimir') {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
      return;
    }
    final arquivo = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar romaneio em PDF',
      fileName:
          'romaneio_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (arquivo == null) return;
    final path = arquivo.toLowerCase().endsWith('.pdf') ? arquivo : '$arquivo.pdf';
    await File(path).writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Romaneio salvo em: $path')));
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
    final partesPipe = endereco.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (partesPipe.length >= 2) return partesPipe[1];
    final partesVirgula = endereco.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (partesVirgula.length >= 2) return partesVirgula[1];
    return partesPipe.isNotEmpty ? partesPipe.first : 'Sem bairro';
  }

  String _nomeMotorista(Venda venda) {
    if (venda.motoristaEntrega.trim().isNotEmpty) {
      return venda.motoristaEntrega.trim();
    }
    // Compatibilidade com dados legados salvos em observacao.
    final linhas = venda.observacaoEntrega.split('\n');
    for (final linha in linhas) {
      final limpa = linha.trim();
      if (limpa.startsWith('Motorista:')) {
        final nome = limpa.substring('Motorista:'.length).trim();
        if (nome.isNotEmpty) return nome;
      }
    }
    return 'Nao definido';
  }

  String _nomeVendedor(Venda venda) {
    final vendedor = venda.vendedor.target;
    final nome = vendedor?.apelido.trim().isNotEmpty == true
        ? vendedor!.apelido.trim()
        : (vendedor?.nomeCompleto.trim() ?? '');
    if (nome.isNotEmpty) return nome;
    return 'Nao definido';
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
    widget.vendaRepository.atualizarPrioridadeEntrega(venda.id, novaPrioridade);
    _carregarEntregas();
  }

  Future<void> _editarMotoristaEntrega(Venda venda) async {
    if (!mounted) return;
    final motoristas = widget.motoristaRepository.listarAtivos();
    final atual = venda.motoristaEntrega.trim();
    String selecionado = atual;
    final nome = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Motorista #${venda.numeroOrcamento}'),
          content: motoristas.isEmpty
              ? const Text(
                  'Nenhum motorista ativo cadastrado. Cadastre em Cadastros > Motoristas.',
                )
              : DropdownButtonFormField<String>(
                  initialValue: selecionado.isEmpty ? null : selecionado,
                  decoration: const InputDecoration(
                    labelText: 'Motorista',
                  ),
                  items: motoristas
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m.nome.trim(),
                          child: Text(
                            m.telefone.trim().isEmpty
                                ? m.nome
                                : '${m.nome} · ${m.telefone}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selecionado = v ?? ''),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Limpar'),
            ),
            ElevatedButton(
              onPressed: motoristas.isEmpty
                  ? null
                  : () => Navigator.pop(context, selecionado.trim()),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (nome == null) return;
    try {
      widget.vendaRepository.atualizarMotoristaEntrega(venda.id, nome);
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motorista atualizado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar motorista: $e')));
    }
  }

  void _aplicarPeriodoMarcadasParaHoje() {
    setState(() {
      _filtrosDropdownNonce++;
      _inicio = null;
      _fim = null;
      _filtroDataMarcada = 'hoje';
    });
    _carregarEntregas();
  }

  /// Volta filtros, periodo e texto de busca ao padrao amplo ("Todos" em tudo aplicavel).
  void _redefinirFiltrosPadrao() {
    setState(() {
      _filtrosDropdownNonce++;
      _filtroResumoLista = _FiltroResumoEntregas.nenhum;
      _chaveDiaPlanejamentoSelecionado = null;
      _statusSelecionado = 'todos';
      _filtroMotorista = 'todos';
      _filtroVendedor = 'todos';
      _agrupamento = 'bairro';
      _filtroDataMarcada = 'todos';
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

  bool _statusFinalizado(String status) {
    return status == 'entregue' || status == 'cancelada';
  }

  bool _transicaoStatusPermitida(String atual, String novo) {
    if (atual == novo) return true;
    if (_statusFinalizado(atual)) return false;
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
    // Permite manter, avançar uma etapa por vez ou voltar para pendente via reagendamento.
    return iNovo == iAtual + 1 || (iNovo == 0 && atual == 'reagendada');
  }

  String _mensagemBloqueioTransicao(String atual, String novo) {
    return 'Nao foi possivel mudar de "${_rotuloStatusEntrega(atual)}" para '
        '"${_rotuloStatusEntrega(novo)}". Siga a sequencia: '
        'Pendente -> Roteirizada -> Saiu para entrega -> Entregue.';
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

  /// Total no banco (respeitando status/bairro/nota/motorista/vendedor; sem recorte por periodo de venda).
  int _contagemAtrasadasProjetada() {
    var entregas = widget.vendaRepository.listarEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: null,
      fim: null,
    );
    entregas = entregas.where(_atendeFiltroDataMarcada).toList();
    entregas = _filtrarPorNumeroNotaSeInformado(entregas);
    if (_filtroMotorista != 'todos') {
      entregas = entregas
          .where((v) => _nomeMotorista(v).toLowerCase() == _filtroMotorista)
          .toList();
    }
    if (_filtroVendedor != 'todos') {
      entregas = entregas
          .where((v) => _nomeVendedor(v).toLowerCase() == _filtroVendedor)
          .toList();
    }
    return entregas.where(_vendaEhAtrasada).length;
  }

  int _contagemPendentesHojeProjetada() {
    var entregas = widget.vendaRepository.listarEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: null,
      fim: null,
    );
    entregas = entregas.where(_atendeFiltroDataMarcada).toList();
    entregas = _filtrarPorNumeroNotaSeInformado(entregas);
    if (_filtroMotorista != 'todos') {
      entregas = entregas
          .where((v) => _nomeMotorista(v).toLowerCase() == _filtroMotorista)
          .toList();
    }
    if (_filtroVendedor != 'todos') {
      entregas = entregas
          .where((v) => _nomeVendedor(v).toLowerCase() == _filtroVendedor)
          .toList();
    }
    return entregas.where(_vendaEhAgendaHoje).length;
  }

  Future<void> _abrirHistoricoEntrega(Venda venda) async {
    final historico = widget.vendaRepository.listarHistoricoEntrega(venda.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Historico da entrega #${venda.numeroOrcamento}'),
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
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${_rotuloStatusEntrega(item.statusAnterior)} -> ${_rotuloStatusEntrega(item.statusNovo)}',
                        ),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(item.dataHora.toLocal())} · ${item.usuario}',
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

  Future<void> _atualizarStatusEntrega(Venda venda, String novoStatus) async {
    try {
      if (!widget.podeGerenciarStatusEntrega) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensagemSemPermissaoStatus())),
        );
        return;
      }
      final statusAnterior = venda.statusEntrega;
      if (!_transicaoStatusPermitida(statusAnterior, novoStatus)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensagemBloqueioTransicao(statusAnterior, novoStatus)),
          ),
        );
        return;
      }
      if (novoStatus == 'entregue' && _progressoCarga(venda) < 3) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checklist de carga incompleto. Finalize Separado, Carregado e Saiu antes de entregar.',
            ),
          ),
        );
        return;
      }
      String? motivo;
      if (novoStatus == 'reagendada' || novoStatus == 'cancelada') {
        motivo = await _solicitarMotivoMudancaStatus(novoStatus);
        if (motivo == null) return;
      }
      widget.vendaRepository.atualizarStatusEntrega(venda.id, novoStatus);
      widget.vendaRepository.registrarHistoricoStatusEntrega(
        vendaId: venda.id,
        statusAnterior: statusAnterior,
        statusNovo: novoStatus,
        usuario: widget.usuarioAtual,
      );
      if (motivo != null) {
        widget.vendaRepository.registrarOcorrenciaEntrega(
          vendaId: venda.id,
          status: novoStatus,
          motivo: motivo,
          usuario: widget.usuarioAtual,
        );
      }
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status de entrega atualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar status: $e')),
      );
    }
  }

  Future<String?> _solicitarMotivoMudancaStatus(String novoStatus) async {
    if (!mounted) return null;
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Motivo da ${_rotuloStatusEntrega(novoStatus).toLowerCase()}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo (obrigatorio)',
            hintText: 'Descreva o motivo desta alteracao',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final texto = controller.text.trim();
              if (texto.isEmpty) return;
              Navigator.pop(context, texto);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (motivo == null || motivo.trim().isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Motivo obrigatorio para reagendar ou cancelar entrega.'),
        ),
      );
      return null;
    }
    return motivo.trim();
  }

  void _atualizarChecklistCarga(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    try {
      if (!_checklistPodeAtualizar(
        venda,
        separado: separado,
        carregado: carregado,
        saiu: saiu,
      )) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensagemChecklistInvalido())),
        );
        return;
      }
      widget.vendaRepository.atualizarChecklistCargaEntrega(
        venda.id,
        separado: separado,
        carregado: carregado,
        saiu: saiu,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar checklist: $e')),
      );
    }
  }

  Future<void> _abrirDetalhesItensVenda(Venda venda) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final usaMigrado = _vendaUsaItensCarretoMigrado(venda);
        final itensLista = venda.itens
            .where((i) => _quantidadeExibicaoEntrega(venda, i) > 0)
            .toList();
        return AlertDialog(
          title: Text(
            usaMigrado
                ? 'Itens para entrega #${venda.numeroOrcamento}'
                : 'Itens do pedido #${venda.numeroOrcamento}',
          ),
          content: SizedBox(
            width: 620,
            child: itensLista.isEmpty
                ? const Text('Nenhum item encontrado para esta entrega.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
                      ),
                      Text('Vendedor: ${_nomeVendedor(venda)}'),
                      if (usaMigrado) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Somente o que segue no carreto (cliente ja pode ter retirado parte na loja).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: itensLista.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 10),
                          itemBuilder: (context, index) {
                            final item = itensLista[index];
                            final q = _quantidadeExibicaoEntrega(venda, item);
                            final sub = _subtotalExibicaoEntrega(venda, item);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    '${q}x',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.nomeProduto,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 170,
                                  child: Text(
                                    '${_formatarMoeda(item.precoUnitario)} / un',
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    _formatarMoeda(sub),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Total na carga: ${_formatarMoeda(
                          itensLista.fold<double>(
                            0,
                            (s, i) => s + _subtotalExibicaoEntrega(venda, i),
                          ),
                        )}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (usaMigrado)
                        Text(
                          'Total da venda (produtos): ${_formatarMoeda(venda.total)}',
                          style: Theme.of(context).textTheme.bodySmall,
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
  }

  Future<void> _abrirChecklistCargaEntrega(Venda venda) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Checklist de carga #${venda.numeroOrcamento}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}'),
                  Text('Vendedor: ${_nomeVendedor(venda)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Separado'),
                        selected: venda.cargaSeparada,
                        onSelected: (v) {
                          _atualizarChecklistCarga(venda, separado: v);
                          setDialogState(() {
                            venda.cargaSeparada = v;
                          });
                          _carregarEntregas();
                        },
                      ),
                      FilterChip(
                        label: const Text('Carregado'),
                        selected: venda.cargaCarregada,
                        onSelected: (v) {
                          _atualizarChecklistCarga(venda, carregado: v);
                          setDialogState(() {
                            venda.cargaCarregada = v;
                          });
                          _carregarEntregas();
                        },
                      ),
                      FilterChip(
                        label: const Text('Saiu'),
                        selected: venda.cargaSaiu,
                        onSelected: (v) {
                          _atualizarChecklistCarga(venda, saiu: v);
                          setDialogState(() {
                            venda.cargaSaiu = v;
                          });
                          _carregarEntregas();
                        },
                      ),
                    ],
                  ),
                ],
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

  Widget _buildCardEntrega(
    Venda venda,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt, {
    bool dentroDeGrupoCarreto = false,
    bool modoSelecao = false,
    bool selecionada = false,
  }) {
    final statusCor = _corStatus(
      Theme.of(context).colorScheme,
      venda.statusEntrega,
    );
    final progressoCarga = _progressoCarga(venda);
    final corCarga = _corProgressoCarga(
      context,
      progressoCarga,
    );
    final prioridade = venda.prioridadeEntrega;
    final historico = widget.vendaRepository.listarHistoricoEntrega(venda.id);
    final ultimoEvento = historico.isEmpty ? null : historico.last;
    return Card(
      elevation: dentroDeGrupoCarreto ? 0 : null,
      margin: dentroDeGrupoCarreto ? EdgeInsets.zero : null,
      color: dentroDeGrupoCarreto
          ? Theme.of(context).colorScheme.surface
          : null,
      child: ListTile(
        leading: modoSelecao
            ? Checkbox(
                value: selecionada,
                onChanged: (_) => _alternarSelecaoEntrega(venda.id),
              )
            : null,
        onTap: modoSelecao
            ? () => _alternarSelecaoEntrega(venda.id)
            : () => _abrirDetalhesItensVenda(venda),
        title: Text(
          'Venda #${venda.numeroOrcamento} - ${_formatarMoeda(venda.total)}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
            ),
            Text('Vendedor: ${_nomeVendedor(venda)}'),
            Text('Endereco: ${venda.enderecoEntrega}'),
            Text(
              'Frete: ${_formatarMoeda(venda.valorFrete)}',
            ),
            Text(
              'Criado em: ${dateFormat.format(venda.data.toLocal())}',
            ),
            Text(
              'Entrega marcada: ${venda.dataEntregaMarcada == null ? 'Sem data definida' : dataMarcadaFmt.format(venda.dataEntregaMarcada!.toLocal())}',
            ),
            Text('Motorista: ${_nomeMotorista(venda)}'),
            if (ultimoEvento != null)
              Text(
                'Ultima mudanca: ${dateFormat.format(ultimoEvento.dataHora.toLocal())} por ${ultimoEvento.usuario}',
              ),
            if (_observacaoSemMotorista(venda).trim().isNotEmpty)
              Text(
                'Obs: ${_observacaoSemMotorista(venda)}',
              ),
            const SizedBox(height: 4),
            const Text(
              'Clique no pedido para ver os itens comprados',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: statusCor.withValues(
                      alpha: 0.12,
                    ),
                    border: Border.all(
                      color: statusCor.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Text(
                    _rotuloStatusEntrega(
                      venda.statusEntrega,
                    ),
                    style: TextStyle(
                      color: statusCor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Text(
                    'Prioridade: ${_rotuloPrioridade(prioridade)}',
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    'Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)}',
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(
                    99,
                  ),
                  onTap: () => _abrirChecklistCargaEntrega(
                    venda,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: corCarga.withValues(
                        alpha: 0.12,
                      ),
                      border: Border.all(
                        color: corCarga.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    child: Text(
                      'Carga: $progressoCarga/3',
                      style: TextStyle(
                        color: corCarga,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: () => _abrirDetalhesItensVenda(venda),
              icon: const Icon(Icons.receipt_long),
              label: const Text('Ver itens'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _abrirHistoricoEntrega(venda),
              icon: const Icon(Icons.history),
              label: const Text('Historico'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: () => _editarMotoristaEntrega(venda),
              icon: const Icon(Icons.person_outline),
              label: const Text('Motorista'),
            ),
            const SizedBox(width: 6),
            if (venda.statusEntrega != 'entregue')
              TextButton.icon(
                onPressed: widget.podeGerenciarStatusEntrega
                    ? () => _atualizarStatusEntrega(
                          venda,
                          'entregue',
                        )
                    : null,
                icon: const Icon(
                  Icons.check_circle_outline,
                ),
                label: const Text('Marcar entregue'),
              ),
            PopupMenuButton<String>(
              tooltip: 'Mais acoes',
              onSelected: (value) {
                if (value.startsWith('prioridade:')) {
                  final p = value.split(':').last;
                  _atualizarPrioridade(venda, p);
                  return;
                }
                _atualizarStatusEntrega(venda, value);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'pendente',
                  child: const Text('Status: Pendente'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'roteirizada',
                  child: const Text('Status: Roteirizada'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'saiu_entrega',
                  child: const Text(
                    'Status: Saiu para entrega',
                  ),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'entregue',
                  child: const Text('Status: Entregue'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'reagendada',
                  child: const Text('Status: Reagendada'),
                ),
                PopupMenuItem(
                  enabled: widget.podeGerenciarStatusEntrega,
                  value: 'cancelada',
                  child: const Text('Status: Cancelada'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'prioridade:normal',
                  child: Text('Prioridade: Normal'),
                ),
                const PopupMenuItem(
                  value: 'prioridade:urgente',
                  child: Text('Prioridade: Urgente'),
                ),
                const PopupMenuItem(
                  value: 'prioridade:agendada',
                  child: Text('Prioridade: Agendada'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelGrupoCarretoLista(
    List<Venda> bloco,
    DateFormat dateFormat,
    DateFormat dataMarcadaFmt,
  ) {
    final scheme = Theme.of(context).colorScheme;
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
            leading: Icon(Icons.local_shipping_outlined, color: scheme.tertiary),
            title: Text(
              _rotuloGrupoLogistica(bloco),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${bloco.length} pedidos no mesmo veiculo'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < bloco.length; i++) ...[
                  _buildCardEntrega(
                    bloco[i],
                    dateFormat,
                    dataMarcadaFmt,
                    dentroDeGrupoCarreto: true,
                    modoSelecao: _modoAgruparMesmoCarro,
                    selecionada:
                        _idsEntregasSelecionadas.contains(bloco[i].id),
                  ),
                  if (i < bloco.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final dataMarcadaFmt = DateFormat('dd/MM/yyyy');
    final atrasadas = _contagemAtrasadasProjetada();
    final pendentesHoje = _contagemPendentesHojeProjetada();
    final mostrarChipsResumo = _entregas.isNotEmpty ||
        atrasadas > 0 ||
        pendentesHoje > 0 ||
        _filtroResumoLista != _FiltroResumoEntregas.nenhum;
    final motoristasAtivos = widget.motoristaRepository.listarAtivos();
    final resumoPorDia = <String, int>{};
    for (final venda in _entregas) {
      final dataKey = venda.dataEntregaMarcada == null
          ? 'Sem data marcada'
          : dataMarcadaFmt.format(venda.dataEntregaMarcada!.toLocal());
      resumoPorDia.update(dataKey, (atual) => atual + 1, ifAbsent: () => 1);
    }
    final diasResumo = resumoPorDia.keys.toList()
      ..sort((a, b) {
        if (a == 'Sem data marcada') return 1;
        if (b == 'Sem data marcada') return -1;
        final da = dataMarcadaFmt.parse(a);
        final db = dataMarcadaFmt.parse(b);
        return da.compareTo(db);
      });
    final listaExibicao = _chaveDiaPlanejamentoSelecionado == null
        ? _entregas
        : _entregas
            .where(
              (v) => _vendaNaChaveDiaPlanejamento(
                v,
                _chaveDiaPlanejamentoSelecionado!,
                dataMarcadaFmt,
              ),
            )
            .toList();
    final groupedLista = <String, List<Venda>>{};
    for (final venda in listaExibicao) {
      final chaveGrupo = _agrupamento == 'motorista'
          ? _nomeMotorista(venda)
          : _extrairBairro(venda);
      groupedLista.putIfAbsent(chaveGrupo, () => <Venda>[]).add(venda);
    }
    final gruposLista = groupedLista.keys.toList()..sort((a, b) => a.compareTo(b));
    return Scaffold(
      appBar: AppBar(title: const Text('Entregas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      key: ValueKey('f_status_$_filtrosDropdownNonce'),
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusSelecionado,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: _statuses
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s,
                                child: Text(_rotuloStatusFiltro(s)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _statusSelecionado = value);
                          _carregarEntregas();
                        },
                      ),
                    ),
                    SizedBox(
                      key: ValueKey('f_motorista_$_filtrosDropdownNonce'),
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        initialValue: _filtroMotorista,
                        decoration: const InputDecoration(
                          labelText: 'Motorista',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          ...motoristasAtivos.map(
                            (m) => DropdownMenuItem(
                              value: m.nome.trim().toLowerCase(),
                              child: Text(m.nome),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _filtroMotorista = value);
                          _carregarEntregas();
                        },
                      ),
                    ),
                    SizedBox(
                      key: ValueKey('f_vendedor_$_filtrosDropdownNonce'),
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        initialValue: _filtroVendedor,
                        decoration: const InputDecoration(
                          labelText: 'Vendedor',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          ..._vendedoresDisponiveis.map(
                            (nome) => DropdownMenuItem(
                              value: nome.toLowerCase(),
                              child: Text(nome),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _filtroVendedor = value);
                          _carregarEntregas();
                        },
                      ),
                    ),
                    SizedBox(
                      key: ValueKey('f_agrup_$_filtrosDropdownNonce'),
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _agrupamento,
                        decoration: const InputDecoration(
                          labelText: 'Agrupar por',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'bairro',
                            child: Text('Bairro'),
                          ),
                          DropdownMenuItem(
                            value: 'motorista',
                            child: Text('Motorista'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _agrupamento = value);
                        },
                      ),
                    ),
                    SizedBox(
                      key: ValueKey('f_dataMarc_$_filtrosDropdownNonce'),
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _filtroDataMarcada,
                        decoration: const InputDecoration(
                          labelText: 'Data marcada',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todas'),
                          ),
                          DropdownMenuItem(
                            value: 'hoje',
                            child: Text('Hoje'),
                          ),
                          DropdownMenuItem(
                            value: 'amanha',
                            child: Text('Amanha'),
                          ),
                          DropdownMenuItem(
                            value: 'sem_data',
                            child: Text('Sem data marcada'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _filtroDataMarcada = value);
                          _carregarEntregas();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _numeroNotaController,
                        decoration: const InputDecoration(
                          labelText: 'N. da nota',
                          hintText: 'ex: 1234 ou #1234',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _carregarEntregas(),
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _bairroController,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por bairro/endereco',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        onSubmitted: (_) => _carregarEntregas(),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _carregarEntregas,
                      child: const Text('Aplicar filtro'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _redefinirFiltrosPadrao,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Limpar tudo'),
                    ),
                    OutlinedButton(
                      onPressed: _aplicarPeriodoMarcadasParaHoje,
                      child: const Text('Hoje'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _selecionarPeriodoPersonalizado,
                      icon: const Icon(Icons.date_range_outlined),
                      label: const Text('Periodo personalizado'),
                    ),
                    Chip(label: Text(_rotuloPeriodoSelecionado())),
                    FilterChip(
                      avatar: Icon(
                        Icons.merge_type_outlined,
                        color: _modoAgruparMesmoCarro
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      label: Text(
                        _modoAgruparMesmoCarro
                            ? 'Mesmo carro (${_idsEntregasSelecionadas.length} sel.)'
                            : 'Agrupar mesmo carro',
                      ),
                      selected: _modoAgruparMesmoCarro,
                      onSelected: (v) {
                        setState(() {
                          _modoAgruparMesmoCarro = v;
                          if (!v) _idsEntregasSelecionadas.clear();
                        });
                      },
                    ),
                    if (_modoAgruparMesmoCarro) ...[
                      Tooltip(
                        message:
                            'Somente carreto, mesmo cliente. Marque 2+ entregas.',
                        child: FilledButton.icon(
                          onPressed: _idsEntregasSelecionadas.length >= 2
                              ? _confirmarAgrupamentoMesmoCarro
                              : null,
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Confirmar agrupamento'),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            setState(_idsEntregasSelecionadas.clear),
                        child: const Text('Limpar selecao'),
                      ),
                      OutlinedButton(
                        onPressed: _removerAgrupamentoSelecionadas,
                        child: const Text('Tirar agrupamento'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (mostrarChipsResumo)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        avatar: Icon(
                          Icons.warning_amber_outlined,
                          color: atrasadas > 0
                              ? Colors.red.shade700
                              : Colors.grey,
                        ),
                        label: Text('Atrasadas: $atrasadas'),
                        selected:
                            _filtroResumoLista == _FiltroResumoEntregas.atrasadas,
                        onSelected: (ligar) {
                          setState(() {
                            _filtroResumoLista = ligar
                                ? _FiltroResumoEntregas.atrasadas
                                : _FiltroResumoEntregas.nenhum;
                          });
                          _carregarEntregas();
                        },
                      ),
                      FilterChip(
                        avatar: Icon(
                          Icons.today_outlined,
                          color: pendentesHoje > 0
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        label: Text('Pendentes hoje: $pendentesHoje'),
                        selected: _filtroResumoLista ==
                            _FiltroResumoEntregas.pendentesHoje,
                        onSelected: (ligar) {
                          setState(() {
                            _filtroResumoLista = ligar
                                ? _FiltroResumoEntregas.pendentesHoje
                                : _FiltroResumoEntregas.nenhum;
                          });
                          _carregarEntregas();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (mostrarChipsResumo) const SizedBox(height: 10),
            if (_entregas.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Planejamento por dia',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: diasResumo
                            .map(
                              (dia) => FilterChip(
                                label: Text('$dia: ${resumoPorDia[dia]}'),
                                selected: _chaveDiaPlanejamentoSelecionado == dia,
                                onSelected: (ligar) {
                                  setState(() {
                                    _chaveDiaPlanejamentoSelecionado =
                                        ligar ? dia : null;
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _abrirRomaneioDoDia,
                              icon: const Icon(Icons.assignment_outlined),
                              label: const Text('Ver romaneio de hoje'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _exportarOuImprimirRomaneioHoje,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Imprimir/Exportar romaneio'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_entregas.isNotEmpty) const SizedBox(height: 10),
            Expanded(
              child: _entregas.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhuma entrega encontrada para os filtros.',
                      ),
                    )
                  : listaExibicao.isEmpty
                  ? Center(
                      child: Text(
                        _chaveDiaPlanejamentoSelecionado == null
                            ? 'Nenhuma entrega encontrada para os filtros.'
                            : 'Nenhuma entrega para o dia selecionado no planejamento.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: gruposLista.length,
                      itemBuilder: (context, bairroIndex) {
                        final grupo = gruposLista[bairroIndex];
                        final vendasBairro =
                            groupedLista[grupo] ?? const <Venda>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                              child: Text(
                                '${_agrupamento == 'motorista' ? 'Motorista' : 'Bairro'}: $grupo (${vendasBairro.length})',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            for (final bloco in _blocosEntregaComCarretoAgrupado(
                              vendasBairro,
                            ))
                              if (bloco.length >= 2 &&
                                  bloco.first.grupoEntregaFreteId > 0)
                                _buildPainelGrupoCarretoLista(
                                  bloco,
                                  dateFormat,
                                  dataMarcadaFmt,
                                )
                              else
                                ...bloco.map(
                                  (v) => _buildCardEntrega(
                                    v,
                                    dateFormat,
                                    dataMarcadaFmt,
                                    modoSelecao: _modoAgruparMesmoCarro,
                                    selecionada:
                                        _idsEntregasSelecionadas.contains(v.id),
                                  ),
                                ),
                          ],
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
