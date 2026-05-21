import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/caixa_auditoria_repository.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioHistoricoFechamentoPage extends StatefulWidget {
  const RelatorioHistoricoFechamentoPage({super.key});

  @override
  State<RelatorioHistoricoFechamentoPage> createState() =>
      _RelatorioHistoricoFechamentoPageState();
}

class _RelatorioHistoricoFechamentoPageState
    extends State<RelatorioHistoricoFechamentoPage> {
  final _repo = CaixaAuditoriaRepository();
  final _fmtData = DateFormat('dd/MM/yyyy HH:mm');
  final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  List<CaixaAuditoriaRegistro> _fechamentos = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lista = await _repo.listarFechamentos();
    if (!mounted) return;
    setState(() {
      _fechamentos = lista;
      _carregando = false;
    });
  }

  double _num(Map<String, dynamic> d, String k) {
    final v = d[k];
    if (v is num) return v.toDouble();
    return 0;
  }

  List<List<String>> _linhasCsv() => [
        [
          'Data',
          'Operador',
          'Diferenca total',
          'Esp. dinheiro',
          'Dec. dinheiro',
          'Observacao',
        ],
        ..._fechamentos.map((r) {
          final d = r.detalhes;
          return [
            _fmtData.format(r.em.toLocal()),
            d['operador']?.toString() ?? r.operadorCaixa,
            _fmtMoeda.format(r.diferencaTotal ?? 0),
            _fmtMoeda.format(_num(d, 'esperadoDinheiro')),
            _fmtMoeda.format(_num(d, 'declaradoDinheiro')),
            d['observacao']?.toString() ?? '',
          ];
        }),
      ];

  List<String> _paginasPdf() {
    return relatorioMontarPaginasTabela(
      titulo: 'HISTORICO FECHAMENTO DE CAIXA',
      subtitulo: '${_fechamentos.length} registro(s)',
      cabecalho: ['Data', 'Operador', 'Diferenca', 'Obs'],
      linhas: _fechamentos
          .map(
            (r) => [
              _fmtData.format(r.em.toLocal()),
              r.detalhes['operador']?.toString() ?? '-',
              _fmtMoeda.format(r.diferencaTotal ?? 0),
              (r.detalhes['observacao']?.toString() ?? '').toString(),
            ],
          )
          .toList(),
    );
  }

  Future<void> _detalhe(CaixaAuditoriaRegistro r) async {
    final d = r.detalhes;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Fechamento ${_fmtData.format(r.em.toLocal())}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Operador: ${d['operador'] ?? r.operadorCaixa}'),
                Text('Usuario registro: ${r.usuario}'),
                const Divider(),
                Text('Fundo troco: ${_fmtMoeda.format(_num(d, 'fundoTroco'))}'),
                Text('Suprimentos: ${_fmtMoeda.format(_num(d, 'suprimentos'))}'),
                Text('Sangrias: ${_fmtMoeda.format(_num(d, 'sangrias'))}'),
                const SizedBox(height: 8),
                const Text('Conferencia por forma',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  'Dinheiro: esp ${_fmtMoeda.format(_num(d, 'esperadoDinheiro'))} · '
                  'dec ${_fmtMoeda.format(_num(d, 'declaradoDinheiro'))}',
                ),
                Text(
                  'PIX: esp ${_fmtMoeda.format(_num(d, 'esperadoPix'))} · '
                  'dec ${_fmtMoeda.format(_num(d, 'declaradoPix'))}',
                ),
                Text(
                  'Debito: esp ${_fmtMoeda.format(_num(d, 'esperadoDebito'))} · '
                  'dec ${_fmtMoeda.format(_num(d, 'declaradoDebito'))}',
                ),
                Text(
                  'Credito: esp ${_fmtMoeda.format(_num(d, 'esperadoCredito'))} · '
                  'dec ${_fmtMoeda.format(_num(d, 'declaradoCredito'))}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Diferenca total: ${_fmtMoeda.format(r.diferencaTotal ?? 0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (r.diferencaTotal ?? 0).abs() > 0.01
                        ? Theme.of(ctx).colorScheme.error
                        : null,
                  ),
                ),
                if ((d['observacao']?.toString() ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Obs: ${d['observacao']}'),
                ],
                const SizedBox(height: 12),
                Text(
                  'Para gerar PDF novamente, feche um novo turno no Caixa ou '
                  'exporte esta lista em CSV/PDF.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historico de fechamento'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'historico_fechamento_caixa',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
            mensagemSeVazio: 'Nenhum fechamento registrado.',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _fechamentos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhum fechamento de caixa na auditoria local.\n'
                      'Os registros aparecem apos fechar o caixa em Vendas > Caixa.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _fechamentos.length,
                  itemBuilder: (context, i) {
                    final r = _fechamentos[i];
                    final dif = r.diferencaTotal ?? 0;
                    final operador =
                        r.detalhes['operador']?.toString() ?? r.operadorCaixa;
                    return ListTile(
                      leading: Icon(
                        dif.abs() > 0.01
                            ? Icons.warning_amber
                            : Icons.check_circle_outline,
                        color: dif.abs() > 0.01
                            ? Theme.of(context).colorScheme.error
                            : Colors.green.shade700,
                      ),
                      title: Text(_fmtData.format(r.em.toLocal())),
                      subtitle: Text('Operador: $operador'),
                      trailing: Text(
                        _fmtMoeda.format(dif),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: dif.abs() > 0.01
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      onTap: () => _detalhe(r),
                    );
                  },
                ),
    );
  }
}
