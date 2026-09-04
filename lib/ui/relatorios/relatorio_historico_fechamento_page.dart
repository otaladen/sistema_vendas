import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/caixa_auditoria_repository.dart';
import '../../data/objectbox.dart';
import '../widgets/lan_api_feedback.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioHistoricoFechamentoPage extends StatefulWidget {
  const RelatorioHistoricoFechamentoPage({
    super.key,
    this.lanApiClient,
    this.objectBox,
  });

  /// Terminal leve: le do PC servidor (`/api/relatorios/historico-fechamento-caixa`).
  final LanApiClient? lanApiClient;
  final ObjectBox? objectBox;

  @override
  State<RelatorioHistoricoFechamentoPage> createState() =>
      _RelatorioHistoricoFechamentoPageState();
}

class _RelatorioHistoricoFechamentoPageState
    extends State<RelatorioHistoricoFechamentoPage> {
  final _fmtData = DateFormat('dd/MM/yyyy HH:mm');
  final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  List<CaixaAuditoriaRegistro> _fechamentos = [];
  bool _carregando = true;
  String? _erro;

  bool get _viaApi =>
      widget.lanApiClient != null && widget.lanApiClient!.configurado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final List<CaixaAuditoriaRegistro> lista;
      if (_viaApi) {
        final raw = await widget.lanApiClient!.listarHistoricoFechamentoCaixa();
        lista = raw.map(CaixaAuditoriaRegistro.fromMap).toList(growable: false);
      } else {
        lista = await CaixaAuditoriaRepository(db: widget.objectBox)
            .listarFechamentos();
      }
      if (!mounted) return;
      setState(() {
        _fechamentos = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fechamentos = [];
        _carregando = false;
        _erro = LanApiFeedback.mensagem(e);
      });
    }
  }

  double _num(Map<String, dynamic> d, String k) {
    final v = d[k];
    if (v is num) return v.toDouble();
    return 0;
  }

  List<List<String>> _linhasCsv() => [
        [
          'Data',
          'Hora',
          'Tipo',
          'Operador',
          'Valor',
          'Diferenca total',
          'Esp. dinheiro',
          'Dec. dinheiro',
          'Observacao',
        ],
        ..._fechamentos.map((r) {
          final d = r.detalhes;
          return [
            d['data']?.toString() ?? _fmtData.format(r.em.toLocal()).split(' ').first,
            d['hora']?.toString() ?? '',
            d['tipo']?.toString() ?? r.evento,
            d['operador']?.toString() ?? r.operadorCaixa,
            _fmtMoeda.format(r.valor),
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
                Text('Tipo: ${d['tipo'] ?? r.evento}'),
                Text(
                  'Data/Hora: ${d['data'] ?? '-'} ${d['hora'] ?? ''}'.trim(),
                ),
                Text('Valor: ${_fmtMoeda.format(r.valor)}'),
                const Divider(),
                Text('Fundo troco: ${_fmtMoeda.format(_num(d, 'fundoTroco'))}'),
                Text('Suprimentos: ${_fmtMoeda.format(_num(d, 'suprimentos'))}'),
                Text('Sangrias: ${_fmtMoeda.format(_num(d, 'sangrias'))}'),
                const SizedBox(height: 8),
                const Text(
                  'Conferencia por forma',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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
            onPressed: _carregando ? null : _carregar,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _carregar,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : _fechamentos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _viaApi
                              ? 'Nenhum fechamento de caixa no PC servidor.\n'
                                  'Os registros aparecem apos fechar o caixa '
                                  '(sincronizado via API).'
                              : 'Nenhum fechamento de caixa na auditoria local.\n'
                                  'Os registros aparecem apos fechar o caixa '
                                  'em Vendas > Caixa.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _fechamentos.length,
                      itemBuilder: (context, i) {
                        final r = _fechamentos[i];
                        final dif = r.diferencaTotal ?? 0;
                        final operador = r.detalhes['operador']?.toString() ??
                            r.operadorCaixa;
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
