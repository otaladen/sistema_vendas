import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/fechamento_fiscal_local_source.dart';
import '../../data/venda_repository.dart';
import '../../domain/fiscal/fechamento_fiscal_resumo.dart';
import '../../services/fechamento_contabil_service.dart';
import 'exportar_fechamento_page.dart';

/// Visao mensal do fiscal (saidas, entradas, totais) sem gerar ZIP.
class RelatorioFiscalMensalPage extends StatefulWidget {
  const RelatorioFiscalMensalPage({
    super.key,
    required this.vendaRepository,
  });

  final VendaRepository vendaRepository;

  @override
  State<RelatorioFiscalMensalPage> createState() =>
      _RelatorioFiscalMensalPageState();
}

class _RelatorioFiscalMensalPageState extends State<RelatorioFiscalMensalPage> {
  late final FechamentoContabilService _service;
  late int _mes;
  late int _ano;
  FechamentoFiscalResumo? _resumo;

  static const _nomesMes = [
    'Janeiro',
    'Fevereiro',
    'Marco',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _mes = agora.month;
    _ano = agora.year;
    _service = FechamentoContabilService(
      localSource: FechamentoFiscalLocalSource.fromVendaRepository(
        widget.vendaRepository,
      ),
    );
    _atualizar();
  }

  void _atualizar() {
    final pacote = _service.listarPacoteFiscal(_mes, _ano);
    setState(() {
      _resumo = FechamentoFiscalResumo.calcular(_mes, _ano, pacote);
    });
  }

  List<int> get _anos {
    final a = DateTime.now().year;
    return List.generate(8, (i) => a - i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _resumo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatorio fiscal do mes'),
        actions: [
          IconButton(
            tooltip: 'Exportar ZIP + Excel',
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ExportarFechamentoPage(
                    vendaRepository: widget.vendaRepository,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _mes,
                      decoration: const InputDecoration(labelText: 'Mes'),
                      items: [
                        for (var i = 1; i <= 12; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(_nomesMes[i - 1]),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _mes = v);
                        _atualizar();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _ano,
                      decoration: const InputDecoration(labelText: 'Ano'),
                      items: [
                        for (final a in _anos)
                          DropdownMenuItem(value: a, child: Text('$a')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _ano = v);
                        _atualizar();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (r == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            const SizedBox(height: 12),
            Text(
              'Periodo: ${_nomesMes[r.mes - 1]}/${r.ano}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _kpiGrid(theme, r),
            if (r.alertasVendaCancelada > 0) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${r.alertasVendaCancelada} nota(s) com venda cancelada no ERP — '
                    'confira com o contador.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kpiGrid(ThemeData theme, FechamentoFiscalResumo r) {
    Widget tile(String titulo, String valor, {Color? cor}) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                valor,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 700 ? 3 : 2;
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: w,
              child: tile('Saidas (total)', '${r.totalSaidas}'),
            ),
            SizedBox(
              width: w,
              child: tile(
                'Autorizadas',
                'R\$ ${_moeda.format(r.valorSaidasAutorizadas)}',
                cor: Colors.green.shade700,
              ),
            ),
            SizedBox(
              width: w,
              child: tile('Canceladas', '${r.saidasCanceladas}'),
            ),
            SizedBox(
              width: w,
              child: tile('Rejeitadas', '${r.saidasRejeitadas}'),
            ),
            SizedBox(
              width: w,
              child: tile('NF-e 55', '${r.nfe55}'),
            ),
            SizedBox(
              width: w,
              child: tile('NFC-e 65', '${r.nfce65}'),
            ),
            SizedBox(
              width: w,
              child: tile('Entradas (compras)', '${r.totalEntradas}'),
            ),
            SizedBox(
              width: w,
              child: tile(
                'Valor entradas',
                'R\$ ${_moeda.format(r.valorEntradas)}',
              ),
            ),
          ],
        );
      },
    );
  }
}
