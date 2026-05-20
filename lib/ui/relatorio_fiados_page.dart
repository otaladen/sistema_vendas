import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/titulo_receber_repository.dart';
import '../data/venda_repository.dart';

/// Relatório de títulos de fiado em aberto.
class RelatorioFiadosPage extends StatefulWidget {
  const RelatorioFiadosPage({
    super.key,
    required this.vendaRepository,
  });

  final VendaRepository vendaRepository;

  @override
  State<RelatorioFiadosPage> createState() => _RelatorioFiadosPageState();
}

class _RelatorioFiadosPageState extends State<RelatorioFiadosPage> {
  static final _fmtData = DateFormat('dd/MM/yyyy');
  static final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _somenteVencidos = false;
  List<TituloReceberResumoLinha> _linhas = [];

  @override
  void initState() {
    super.initState();
    _atualizar();
  }

  void _atualizar() {
    widget.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    setState(() {
      _linhas = widget.vendaRepository.titulos.listarTodosAbertos(
        somenteVencidos: _somenteVencidos,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalSaldo = _linhas.fold<double>(
      0,
      (s, l) => s + l.titulo.saldo,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiados em aberto'),
        actions: [
          IconButton(
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_linhas.length} título(s) · Total: ${_fmtMoeda.format(totalSaldo)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                FilterChip(
                  label: const Text('Só vencidos'),
                  selected: _somenteVencidos,
                  onSelected: (v) {
                    setState(() => _somenteVencidos = v);
                    _atualizar();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhum título em aberto.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final l = _linhas[i];
                      final t = l.titulo;
                      return ListTile(
                        title: Text(l.nomeCliente),
                        subtitle: Text(
                          'Venda ${l.numeroOrcamento} · '
                          'Parc. ${t.numeroParcela}/${t.totalParcelas} · '
                          'Venc. ${_fmtData.format(t.vencimento.toLocal())}'
                          '${l.diasAtraso > 0 ? ' · ${l.diasAtraso} dia(s) atraso' : ''}',
                        ),
                        trailing: Text(
                          _fmtMoeda.format(t.saldo),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: l.diasAtraso > 0
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
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
