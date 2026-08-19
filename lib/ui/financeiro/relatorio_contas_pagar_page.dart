import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/conta_pagar_api_repository.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/conta_pagar_repository.dart';
import '../../data/models/conta_pagar.dart';
import '../../data/objectbox.dart';
import '../../domain/filtro_contas_pagar.dart';
import '../relatorios/relatorio_export_util.dart';
import '../relatorios/widgets/relatorio_exportacoes_menu.dart';
import '../widgets/lan_api_feedback.dart';

class _GrupoFornecedorPagar {
  _GrupoFornecedorPagar({
    required this.nome,
    required this.contas,
  });

  final String nome;
  final List<ContaPagar> contas;

  double get total =>
      contas.fold<double>(0, (s, c) => s + c.valorParcela);

  bool get temAtrasado =>
      contas.any((c) => c.status == ContaPagarStatus.atrasado);
}

/// Relatorio de contas a pagar com exportacao PDF/CSV.
class RelatorioContasPagarPage extends StatefulWidget {
  const RelatorioContasPagarPage({
    super.key,
    this.objectBox,
    this.contaPagarRepository,
    this.filtroInicial = FiltroContasPagar.todos,
  }) : assert(
          objectBox != null || contaPagarRepository != null,
          'Informe objectBox ou contaPagarRepository',
        );

  final ObjectBox? objectBox;
  final dynamic contaPagarRepository;
  final FiltroContasPagar filtroInicial;

  @override
  State<RelatorioContasPagarPage> createState() =>
      _RelatorioContasPagarPageState();
}

class _RelatorioContasPagarPageState extends State<RelatorioContasPagarPage> {
  static final _fmtData = DateFormat('dd/MM/yyyy');
  static final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  late dynamic _repo;
  late FiltroContasPagar _filtro;
  bool _agruparFornecedor = true;
  List<ContaPagar> _linhas = [];
  List<_GrupoFornecedorPagar> _grupos = [];

  @override
  void initState() {
    super.initState();
    _repo = widget.contaPagarRepository ??
        (widget.objectBox != null
            ? ContaPagarRepository(widget.objectBox!)
            : null);
    if (_repo == null) {
      throw StateError(
        'Relatorio contas a pagar: informe contaPagarRepository ou objectBox.',
      );
    }
    _filtro = widget.filtroInicial;
    _atualizar();
  }

  String? _statusDe(FiltroContasPagar f) {
    switch (f) {
      case FiltroContasPagar.todos:
        return null;
      case FiltroContasPagar.pendentes:
        return ContaPagarStatus.pendente;
      case FiltroContasPagar.pagos:
        return ContaPagarStatus.pago;
      case FiltroContasPagar.atrasados:
        return ContaPagarStatus.atrasado;
    }
  }

  String _nomeFornecedor(ContaPagar c) {
    try {
      final viaRepo = _repo.nomeFornecedorDe(c) as String?;
      if (viaRepo != null &&
          viaRepo.trim().isNotEmpty &&
          viaRepo.trim() != '—') {
        return viaRepo.trim();
      }
    } catch (_) {}
    try {
      final f = c.fornecedor.target;
      if (f != null) {
        final nome = f.nomeFantasia.trim().isNotEmpty
            ? f.nomeFantasia
            : f.razaoSocial;
        if (nome.trim().isNotEmpty) return nome.trim();
      }
    } catch (_) {}
    return 'Fornecedor';
  }

  Future<void> _atualizar() async {
    if (_repo is ContaPagarApiRepository) {
      if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
        return;
      }
      try {
        await (_repo as ContaPagarApiRepository).hidratar();
      } catch (e) {
        if (mounted) {
          LanApiFeedback.snackErro(
            context,
            e,
            prefixo: 'Falha ao carregar relatorio',
          );
        }
        return;
      }
    }
    try {
      _repo.sincronizarPendenteParaAtrasado();
    } catch (_) {}
    final linhas = _repo.listar(
      status: _statusDe(_filtro),
      ordenarDesc: _filtro == FiltroContasPagar.pagos,
    ) as List<ContaPagar>;
    final map = <String, _GrupoFornecedorPagar>{};
    for (final c in linhas) {
      final nome = _nomeFornecedor(c);
      map.putIfAbsent(
        nome,
        () => _GrupoFornecedorPagar(nome: nome, contas: []),
      );
      map[nome]!.contas.add(c);
    }
    final grupos = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    if (!mounted) return;
    setState(() {
      _linhas = linhas;
      _grupos = grupos;
    });
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case ContaPagarStatus.pago:
        return 'Pago';
      case ContaPagarStatus.atrasado:
        return 'Atrasado';
      default:
        return 'Pendente';
    }
  }

  List<List<String>> _linhasCsv() {
    final cab = [
      'Fornecedor',
      'NF_ref',
      'Parcela',
      'Emissao',
      'Vencimento',
      'Valor',
      'Status',
      'Pago_em',
      'Valor_pago',
    ];
    final rows = <List<String>>[cab];
    for (final c in _linhas) {
      rows.add([
        _nomeFornecedor(c),
        c.numeroNota ?? c.nfeChave ?? '',
        c.numeroParcela,
        _fmtData.format(c.dataEmissao.toLocal()),
        _fmtData.format(c.dataVencimento.toLocal()),
        _fmtMoeda.format(c.valorParcela),
        _rotuloStatus(c.status),
        c.dataPagamento != null
            ? _fmtData.format(c.dataPagamento!.toLocal())
            : '',
        c.valorPago != null ? _fmtMoeda.format(c.valorPago!) : '',
      ]);
    }
    return rows;
  }

  List<String> _paginasPdf() {
    final total = _linhas.fold<double>(0, (s, c) => s + c.valorParcela);
    final linhasTab = _linhas
        .map(
          (c) => [
            _nomeFornecedor(c),
            c.numeroNota ?? '-',
            c.numeroParcela,
            _fmtData.format(c.dataVencimento.toLocal()),
            _rotuloStatus(c.status),
            _fmtMoeda.format(c.valorParcela),
          ],
        )
        .toList();
    return relatorioMontarPaginasTabela(
      titulo: 'CONTAS A PAGAR',
      subtitulo:
          '${_linhas.length} parcela(s) · Total ${_fmtMoeda.format(total)} · ${_filtro.rotulo}',
      cabecalho: [
        'Fornecedor',
        'NF/ref',
        'Parc',
        'Vencimento',
        'Status',
        'Valor',
      ],
      linhas: linhasTab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _linhas.fold<double>(0, (s, c) => s + c.valorParcela);
    final qtdAtrasadas =
        _linhas.where((c) => c.status == ContaPagarStatus.atrasado).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatorio — contas a pagar'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'contas_a_pagar',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
            mensagemSeVazio: 'Nenhuma conta para exportar.',
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_linhas.length} parcela(s) · ${_fmtMoeda.format(total)}'
                    '${qtdAtrasadas > 0 ? ' · $qtdAtrasadas atrasada(s)' : ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                FilterChip(
                  label: const Text('Agrupar fornecedor'),
                  selected: _agruparFornecedor,
                  onSelected: (v) => setState(() => _agruparFornecedor = v),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: FiltroContasPagar.values.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.rotulo),
                    selected: _filtro == f,
                    onSelected: (_) {
                      setState(() => _filtro = f);
                      _atualizar();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma conta neste filtro.'))
                : _agruparFornecedor
                    ? ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _grupos.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final g = _grupos[i];
                          return Card(
                            child: ExpansionTile(
                              leading: Icon(
                                g.temAtrasado
                                    ? Icons.warning_amber_rounded
                                    : Icons.store_outlined,
                                color: g.temAtrasado
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                              title: Text(g.nome),
                              subtitle: Text(
                                '${g.contas.length} parcela(s) · ${_fmtMoeda.format(g.total)}',
                              ),
                              children: g.contas
                                  .map((c) => _tileConta(c))
                                  .toList(),
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _linhas.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            Card(child: _tileConta(_linhas[i])),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tileConta(ContaPagar c) {
    return ListTile(
      dense: true,
      title: Text(_nomeFornecedor(c)),
      subtitle: Text(
        'Parc ${c.numeroParcela} · Venc ${_fmtData.format(c.dataVencimento.toLocal())}'
        '${c.numeroNota != null ? ' · ${c.numeroNota}' : ''}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _fmtMoeda.format(c.valorParcela),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            _rotuloStatus(c.status),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
