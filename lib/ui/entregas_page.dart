import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/venda_repository.dart';
import '../model/historico_entrega.dart';
import '../model/venda.dart';

class EntregasPage extends StatefulWidget {
  const EntregasPage({
    super.key,
    required this.vendaRepository,
    required this.usuarioAtual,
  });

  final VendaRepository vendaRepository;
  final String usuarioAtual;

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final _bairroController = TextEditingController();
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
  String _filtroDataMarcada = 'todos'; // todos | hoje | amanha | sem_data
  DateTime? _inicio;
  DateTime? _fim;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _inicio = DateTime(now.year, now.month, now.day);
    _fim = _inicio!.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    _carregarEntregas();
  }

  @override
  void dispose() {
    _bairroController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

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

  void _carregarEntregas() {
    var entregas = widget.vendaRepository.listarEntregas(
      statusEntrega: _statusSelecionado,
      bairroTermo: _bairroController.text,
      inicio: _inicio,
      fim: _fim,
    );
    entregas = entregas.where(_atendeFiltroDataMarcada).toList();
    entregas.sort((a, b) {
      final pa = _pesoPrioridade(a.prioridadeEntrega);
      final pb = _pesoPrioridade(b.prioridadeEntrega);
      final byPri = pb.compareTo(pa);
      if (byPri != 0) return byPri;
      return b.data.compareTo(a.data);
    });
    setState(() {
      _entregas = entregas;
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

  Future<void> _abrirRomaneioDoDia() async {
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final doDia = _entregasDoDia(base);
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
                        itemCount: doDia.length,
                        separatorBuilder: (_, _) => const Divider(height: 8),
                        itemBuilder: (context, index) {
                          final venda = doDia[index];
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
    return venda.itens
        .map((item) => '${item.quantidade}x ${item.nomeProduto}')
        .toList();
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
              ...entregasDia.map((venda) {
                final cliente = venda.cliente.target?.nomeRazao ?? 'Sem cliente';
                final dataMarcada = venda.dataEntregaMarcada == null
                    ? 'Sem data'
                    : DateFormat(
                        'dd/MM/yyyy',
                      ).format(venda.dataEntregaMarcada!.toLocal());
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
                      pw.Text('Data marcada: $dataMarcada'),
                      pw.Text('Endereco: ${venda.enderecoEntrega}'),
                      if (venda.observacaoEntrega.trim().isNotEmpty)
                        pw.Text('Obs: ${venda.observacaoEntrega}'),
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

  Future<void> _atualizarPrioridade(Venda venda, String novaPrioridade) async {
    widget.vendaRepository.atualizarPrioridadeEntrega(venda.id, novaPrioridade);
    _carregarEntregas();
  }

  void _aplicarPeriodoRapido(String periodo) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    setState(() {
      if (periodo == 'hoje') {
        _inicio = todayStart;
        _fim = todayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      } else if (periodo == '7dias') {
        _inicio = todayStart.subtract(const Duration(days: 6));
        _fim = now;
      } else if (periodo == '30dias') {
        _inicio = todayStart.subtract(const Duration(days: 29));
        _fim = now;
      } else {
        _inicio = null;
        _fim = null;
      }
    });
    _carregarEntregas();
  }

  Future<void> _atualizarStatusEntrega(Venda venda, String novoStatus) async {
    try {
      final statusAnterior = venda.statusEntrega;
      widget.vendaRepository.atualizarStatusEntrega(venda.id, novoStatus);
      widget.vendaRepository.registrarHistoricoStatusEntrega(
        vendaId: venda.id,
        statusAnterior: statusAnterior,
        statusNovo: novoStatus,
        usuario: widget.usuarioAtual,
      );
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

  void _atualizarChecklistCarga(
    Venda venda, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    try {
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
        return AlertDialog(
          title: Text('Itens do pedido #${venda.numeroOrcamento}'),
          content: SizedBox(
            width: 620,
            child: venda.itens.isEmpty
                ? const Text('Nenhum item encontrado para este pedido.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: venda.itens.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 10),
                          itemBuilder: (context, index) {
                            final item = venda.itens[index];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    '${item.quantidade}x',
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
                                    _formatarMoeda(item.subtotal),
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
                        'Total do pedido: ${_formatarMoeda(venda.total)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final dataMarcadaFmt = DateFormat('dd/MM/yyyy');
    final grouped = <String, List<Venda>>{};
    final resumoPorDia = <String, int>{};
    for (final venda in _entregas) {
      final bairro = _extrairBairro(venda);
      grouped.putIfAbsent(bairro, () => <Venda>[]).add(venda);
      final dataKey = venda.dataEntregaMarcada == null
          ? 'Sem data marcada'
          : dataMarcadaFmt.format(venda.dataEntregaMarcada!.toLocal());
      resumoPorDia.update(dataKey, (atual) => atual + 1, ifAbsent: () => 1);
    }
    final bairros = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
    final diasResumo = resumoPorDia.keys.toList()
      ..sort((a, b) {
        if (a == 'Sem data marcada') return 1;
        if (b == 'Sem data marcada') return -1;
        final da = dataMarcadaFmt.parse(a);
        final db = dataMarcadaFmt.parse(b);
        return da.compareTo(db);
      });
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
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('hoje'),
                      child: const Text('Hoje'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('7dias'),
                      child: const Text('7 dias'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('30dias'),
                      child: const Text('30 dias'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('todos'),
                      child: const Text('Todos'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
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
                              (dia) => Chip(
                                label: Text('$dia: ${resumoPorDia[dia]}'),
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
                  ? const Center(child: Text('Nenhuma entrega encontrada para os filtros.'))
                  : ListView.builder(
                      itemCount: bairros.length,
                      itemBuilder: (context, bairroIndex) {
                        final bairro = bairros[bairroIndex];
                        final vendasBairro = grouped[bairro] ?? const <Venda>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                              child: Text(
                                'Bairro: $bairro (${vendasBairro.length})',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            ...vendasBairro.map((venda) {
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
                              final historico = widget.vendaRepository
                                  .listarHistoricoEntrega(venda.id);
                              final ultimoEvento = historico.isEmpty
                                  ? null
                                  : historico.last;
                              return Card(
                                child: ListTile(
                                  onTap: () => _abrirDetalhesItensVenda(venda),
                                  title: Text(
                                    'Orcamento #${venda.numeroOrcamento} - ${_formatarMoeda(venda.total)}',
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}',
                                      ),
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
                                      if (ultimoEvento != null)
                                        Text(
                                          'Ultima mudanca: ${dateFormat.format(ultimoEvento.dataHora.toLocal())} por ${ultimoEvento.usuario}',
                                        ),
                                      if (venda.observacaoEntrega
                                          .trim()
                                          .isNotEmpty)
                                        Text('Obs: ${venda.observacaoEntrega}'),
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
                                              borderRadius:
                                                  BorderRadius.circular(99),
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
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                              color:
                                                  Theme.of(context).colorScheme
                                                      .primaryContainer,
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
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                              color:
                                                  Theme.of(context).colorScheme
                                                      .surfaceContainerHighest,
                                            ),
                                            child: Text(
                                              'Janela: ${_rotuloJanelaEntrega(venda.janelaEntrega)}',
                                            ),
                                          ),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                            onTap: () =>
                                                _abrirChecklistCargaEntrega(
                                                  venda,
                                                ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(99),
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
                                        onPressed: () =>
                                            _abrirDetalhesItensVenda(venda),
                                        icon: const Icon(Icons.receipt_long),
                                        label: const Text('Ver itens'),
                                      ),
                                      const SizedBox(width: 6),
                                      if (venda.statusEntrega != 'entregue')
                                        TextButton.icon(
                                          onPressed: () =>
                                              _atualizarStatusEntrega(
                                                venda,
                                                'entregue',
                                              ),
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
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'pendente',
                                            child: Text('Status: Pendente'),
                                          ),
                                          PopupMenuItem(
                                            value: 'roteirizada',
                                            child: Text('Status: Roteirizada'),
                                          ),
                                          PopupMenuItem(
                                            value: 'saiu_entrega',
                                            child: Text(
                                              'Status: Saiu para entrega',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'entregue',
                                            child: Text('Status: Entregue'),
                                          ),
                                          PopupMenuItem(
                                            value: 'reagendada',
                                            child: Text('Status: Reagendada'),
                                          ),
                                          PopupMenuItem(
                                            value: 'cancelada',
                                            child: Text('Status: Cancelada'),
                                          ),
                                          PopupMenuDivider(),
                                          PopupMenuItem(
                                            value: 'prioridade:normal',
                                            child: Text('Prioridade: Normal'),
                                          ),
                                          PopupMenuItem(
                                            value: 'prioridade:urgente',
                                            child: Text('Prioridade: Urgente'),
                                          ),
                                          PopupMenuItem(
                                            value: 'prioridade:agendada',
                                            child: Text('Prioridade: Agendada'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
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
