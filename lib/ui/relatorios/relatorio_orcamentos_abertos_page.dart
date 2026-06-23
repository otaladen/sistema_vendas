import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioOrcamentosAbertosPage extends StatefulWidget {
  const RelatorioOrcamentosAbertosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    this.tituloAppBar = 'Orcamentos em aberto',
    this.textoResumo,
    this.exibirExportacoesRelatorio = true,
    this.podeEditarNoPdv = false,
    this.onEditarNoPdv,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final String tituloAppBar;
  final String? textoResumo;
  final bool exibirExportacoesRelatorio;
  final bool podeEditarNoPdv;
  final Future<void> Function(BuildContext context, Venda venda)? onEditarNoPdv;

  @override
  State<RelatorioOrcamentosAbertosPage> createState() =>
      _RelatorioOrcamentosAbertosPageState();
}

class _RelatorioOrcamentosAbertosPageState
    extends State<RelatorioOrcamentosAbertosPage> {
  List<Venda> _todos = [];
  final _buscaController = TextEditingController();
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  final DateFormat _dataDia = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_onBuscaChanged);
    _carregar();
  }

  @override
  void dispose() {
    _buscaController.removeListener(_onBuscaChanged);
    _buscaController.dispose();
    super.dispose();
  }

  void _onBuscaChanged() => setState(() {});

  void _carregar() {
    setState(() {
      _todos = widget.vendaRepository.listarOrcamentosPendentes();
    });
  }

  List<Venda> get _filtrados {
    var lista = List<Venda>.from(_todos);
    if (_dataInicioFiltro != null || _dataFimFiltro != null) {
      var inicio = _dataInicioFiltro;
      var fim = _dataFimFiltro;
      if (inicio == null && fim != null) {
        inicio = DateTime(fim.year, fim.month, fim.day);
      }
      if (fim == null && inicio != null) {
        fim = DateTime(inicio.year, inicio.month, inicio.day, 23, 59, 59, 999);
      }
      if (inicio != null && fim != null) {
        if (inicio.isAfter(fim)) {
          final t = inicio;
          inicio = DateTime(fim.year, fim.month, fim.day);
          fim = DateTime(t.year, t.month, t.day, 23, 59, 59, 999);
        } else {
          inicio = DateTime(inicio.year, inicio.month, inicio.day);
          fim = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);
        }
        lista = lista
            .where((v) {
              final loc = v.data.toLocal();
              return !loc.isBefore(inicio!) && !loc.isAfter(fim!);
            })
            .toList();
      }
    }
    final termo = _buscaController.text.trim().toLowerCase();
    if (termo.isNotEmpty) {
      lista = lista.where((v) => _correspondeBusca(v, termo)).toList();
    }
    return lista;
  }

  bool _correspondeBusca(Venda v, String termo) {
    if ('${v.numeroOrcamento}'.contains(termo)) return true;
    final soNumero = termo.replaceAll(RegExp(r'[^0-9]'), '');
    if (soNumero.isNotEmpty && '${v.numeroOrcamento}'.contains(soNumero)) {
      return true;
    }
    final c = _cliente(v);
    if (c != null && c.nomeRazao.toLowerCase().contains(termo)) return true;
    final totalFmt = NumberFormat('#,##0.00', 'pt_BR').format(v.total);
    if (totalFmt.contains(termo)) return true;
    final dataFmt = DateFormat('dd/MM/yyyy').format(v.data.toLocal());
    if (dataFmt.contains(termo)) return true;
    return false;
  }

  Future<void> _escolherPeriodoFiltro() async {
    final hoje = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      helpText: 'Periodo do orcamento',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
      firstDate: DateTime(2020),
      lastDate: DateTime(hoje.year + 1, 12, 31),
      initialDateRange: _dataInicioFiltro != null && _dataFimFiltro != null
          ? DateTimeRange(
              start: DateTime(
                _dataInicioFiltro!.year,
                _dataInicioFiltro!.month,
                _dataInicioFiltro!.day,
              ),
              end: DateTime(
                _dataFimFiltro!.year,
                _dataFimFiltro!.month,
                _dataFimFiltro!.day,
              ),
            )
          : null,
    );
    if (range == null || !mounted) return;
    setState(() {
      _dataInicioFiltro = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      _dataFimFiltro = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      );
    });
  }

  void _limparFiltroData() {
    if (_dataInicioFiltro == null && _dataFimFiltro == null) return;
    setState(() {
      _dataInicioFiltro = null;
      _dataFimFiltro = null;
    });
  }

  String _rotuloFiltroPeriodo() {
    if (_dataInicioFiltro == null && _dataFimFiltro == null) {
      return 'Filtrar por periodo';
    }
    final inicio = _dataInicioFiltro ?? _dataFimFiltro!;
    final fim = _dataFimFiltro ?? _dataInicioFiltro!;
    final iniDia = DateTime(inicio.year, inicio.month, inicio.day);
    final fimDia = DateTime(fim.year, fim.month, fim.day);
    if (iniDia == fimDia) {
      return 'Data: ${_dataDia.format(inicio)}';
    }
    return '${_dataDia.format(inicio)} — ${_dataDia.format(fim)}';
  }

  Cliente? _cliente(Venda v) {
    final t = v.cliente.target;
    if (t != null) return t;
    final id = v.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  int _diasAberto(Venda v) {
    final hoje = DateTime.now();
    final d = v.data.toLocal();
    final ref = DateTime(hoje.year, hoje.month, hoje.day);
    final vd = DateTime(d.year, d.month, d.day);
    return ref.difference(vd).inDays;
  }

  int _contarOrcamentosAte(DateTime ate) {
    return widget.vendaRepository.contarOrcamentosPendentesAte(ate);
  }

  bool get _filtrosAtivos =>
      _dataInicioFiltro != null ||
      _dataFimFiltro != null ||
      _buscaController.text.trim().isNotEmpty;

  Future<void> _confirmarApagarOrcamento(Venda venda) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar orcamento'),
        content: Text(
          'Apagar o orcamento ${venda.numeroOrcamento} '
          '(R\$ ${NumberFormat('#,##0.00', 'pt_BR').format(venda.total)})?\n\n'
          'Esta acao nao pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      widget.vendaRepository.cancelarVenda(
        venda.id,
        motivo: 'Exclusao manual na lista de orcamentos em aberto',
      );
      _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orcamento ${venda.numeroOrcamento} apagado.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel apagar: $e')),
      );
    }
  }

  Future<void> _abrirManutencaoOrcamentos() async {
    var dataLimite = DateTime.now();
    final dataController = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(dataLimite),
    );

    final confirmarData = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final qtd = _contarOrcamentosAte(dataLimite);
          return AlertDialog(
            title: const Text('Manutencao'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Apagar orcamentos efetuados ate a data selecionada '
                    '(inclusive).',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dataController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Ate a data',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    onTap: () async {
                      final escolhida = await showDatePicker(
                        context: ctx,
                        initialDate: dataLimite,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (escolhida == null) return;
                      setDialogState(() {
                        dataLimite = escolhida;
                        dataController.text =
                            DateFormat('dd/MM/yyyy').format(escolhida);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    qtd == 0
                        ? 'Nenhum orcamento em aberto ate esta data.'
                        : '$qtd orcamento(s) serao apagados.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: qtd == 0
                              ? Theme.of(ctx).colorScheme.onSurfaceVariant
                              : Theme.of(ctx).colorScheme.error,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: qtd == 0 ? null : () => Navigator.pop(ctx, true),
                child: const Text('Continuar'),
              ),
            ],
          );
        },
      ),
    );
    dataController.dispose();
    if (confirmarData != true || !mounted) return;

    final qtd = _contarOrcamentosAte(dataLimite);
    final dataFmt = DateFormat('dd/MM/yyyy').format(dataLimite);
    final confirmarApagar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar manutencao'),
        content: Text(
          'Apagar $qtd orcamento(s) em aberto com data ate $dataFmt?\n\n'
          'Esta acao nao pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar todos'),
          ),
        ],
      ),
    );
    if (confirmarApagar != true || !mounted) return;

    try {
      final apagados = widget.vendaRepository.cancelarOrcamentosPendentesAte(
        dataLimite,
        motivo: 'Manutencao: orcamentos em aberto ate $dataFmt',
      );
      _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$apagados orcamento(s) apagado(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na manutencao: $e')),
      );
    }
  }

  List<List<String>> _linhasCsv(List<Venda> lista) {
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return [
      ['Orcamento', 'Data', 'Cliente', 'Dias aberto', 'Itens', 'Total'],
      ...lista.map((v) {
        final c = _cliente(v);
        return [
          '${v.numeroOrcamento}',
          DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal()),
          c?.nomeRazao ?? 'Sem cliente',
          '${_diasAberto(v)}',
          '${v.itens.length}',
          moeda.format(v.total),
        ];
      }),
    ];
  }

  List<String> _paginasPdf(List<Venda> lista) {
    final total = lista.fold<double>(0, (s, v) => s + v.total);
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return relatorioMontarPaginasTabela(
      titulo: 'ORCAMENTOS EM ABERTO',
      subtitulo:
          '${lista.length} orcamento(s) · Total R\$ ${moeda.format(total)}',
      cabecalho: ['Orc', 'Data', 'Cliente', 'Dias', 'Total'],
      linhas: lista.map((v) {
        final c = _cliente(v);
        return [
          '${v.numeroOrcamento}',
          DateFormat('dd/MM/yyyy').format(v.data.toLocal()),
          c?.nomeRazao ?? '-',
          '${_diasAberto(v)}',
          'R\$ ${moeda.format(v.total)}',
        ];
      }).toList(),
    );
  }

  Widget _buildBarraFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _buscaController,
            decoration: InputDecoration(
              hintText: 'Pesquisar orcamento, cliente, data ou valor',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _buscaController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: () => _buscaController.clear(),
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _escolherPeriodoFiltro,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    _rotuloFiltroPeriodo(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_dataInicioFiltro != null || _dataFimFiltro != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Limpar filtro de periodo',
                  onPressed: _limparFiltroData,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                ),
              ],
            ],
          ),
          if (_dataInicioFiltro != null || _dataFimFiltro != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Inclui o dia inteiro da data inicial e da final.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat moeda = NumberFormat('#,##0.00', 'pt_BR');
    String fmt(double v) => 'R\$ ${moeda.format(v)}';
    final visiveis = _filtrados;
    final total = visiveis.fold<double>(0, (s, v) => s + v.total);
    final totalGeral = _todos.fold<double>(0, (s, v) => s + v.total);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tituloAppBar),
        actions: [
          TextButton(
            onPressed: _abrirManutencaoOrcamentos,
            child: const Text('Manutencao'),
          ),
          if (widget.exibirExportacoesRelatorio)
            RelatorioExportacoesMenu(
              nomeArquivo: 'orcamentos_abertos',
              paginasPdf: () => _paginasPdf(visiveis),
              linhasCsv: () => _linhasCsv(visiveis),
            ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBarraFiltros(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.textoResumo != null) ...[
                  Text(
                    widget.textoResumo!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  _filtrosAtivos
                      ? '${visiveis.length} de ${_todos.length} orcamento(s) · '
                          'Total filtrado ${fmt(total)}'
                      : '${_todos.length} orcamento(s) · Valor total ${fmt(totalGeral)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_filtrosAtivos && visiveis.length != _todos.length)
                  Text(
                    'Total geral da lista: ${fmt(totalGeral)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visiveis.isEmpty
                ? Center(
                    child: Text(
                      _todos.isEmpty
                          ? 'Nenhum orcamento pendente.'
                          : 'Nenhum orcamento encontrado com os filtros atuais.',
                    ),
                  )
                : ListView.builder(
                    itemCount: visiveis.length,
                    itemBuilder: (context, i) {
                      final v = visiveis[i];
                      final c = _cliente(v);
                      final dias = _diasAberto(v);
                      return ListTile(
                        title: Text.rich(
                          TextSpan(
                            style: Theme.of(context).textTheme.titleMedium,
                            children: [
                              TextSpan(
                                text: 'Orc. ${v.numeroOrcamento} · ',
                              ),
                              TextSpan(
                                text: fmt(v.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal())} · '
                          '${c?.nomeRazao ?? 'Sem cliente'} · '
                          '${v.itens.length} item(ns) · $dias dia(s) em aberto',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (dias >= 7)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Chip(
                                  label: Text('$dias d'),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                ),
                              ),
                            if (widget.podeEditarNoPdv &&
                                widget.onEditarNoPdv != null)
                              IconButton(
                                tooltip: 'Editar no PDV',
                                icon: Icon(
                                  Icons.edit_note_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: () =>
                                    widget.onEditarNoPdv!(context, v),
                              ),
                            IconButton(
                              tooltip: 'Apagar orcamento',
                              icon: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              onPressed: () => _confirmarApagarOrcamento(v),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => mostrarDetalheVendaRelatorio(
                          context,
                          vendaRepository: widget.vendaRepository,
                          vendaId: v.id,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
