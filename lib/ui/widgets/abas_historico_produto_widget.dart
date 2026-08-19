import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/produto_api_repository.dart';
import '../../model/historico_entrada.dart';
import '../theme/app_semantic_helper.dart';
import 'lan_api_feedback.dart';

/// Aba com historico de compras (NF-e) do produto, mais recente primeiro.
class AbasHistoricoProdutoWidget extends StatefulWidget {
  const AbasHistoricoProdutoWidget({
    super.key,
    required this.produtoRepository,
    required this.produtoId,
  });

  /// [ProdutoRepository] local ou API no terminal leve.
  final dynamic produtoRepository;
  final int? produtoId;

  @override
  State<AbasHistoricoProdutoWidget> createState() =>
      _AbasHistoricoProdutoWidgetState();
}

class _AbasHistoricoProdutoWidgetState extends State<AbasHistoricoProdutoWidget> {
  static final _nfData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _nfQtd = NumberFormat('#,##0.###', 'pt_BR');

  List<HistoricoEntrada> _lista = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  @override
  void didUpdateWidget(covariant AbasHistoricoProdutoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produtoId != widget.produtoId) {
      _recarregar();
    }
  }

  void _recarregar() {
    final id = widget.produtoId;
    if (id == null || id == 0) {
      setState(() {
        _lista = const [];
        _carregando = false;
      });
      return;
    }
    setState(() => _carregando = true);
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) {
      () async {
        try {
          final itens = await repo.listarHistoricoEntradaPorProdutoRemoto(id);
          if (!mounted) return;
          setState(() {
            _lista = itens;
            _carregando = false;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _lista = const [];
            _carregando = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanApiFeedback.mensagem(e))),
          );
        }
      }();
      return;
    }
    List<HistoricoEntrada> itens = const [];
    try {
      final raw = repo.listarHistoricoEntradaPorProduto(id);
      if (raw is List<HistoricoEntrada>) {
        itens = raw;
      } else if (raw is List) {
        itens = raw.whereType<HistoricoEntrada>().toList();
      }
    } catch (_) {
      itens = const [];
    }
    setState(() {
      _lista = itens;
      _carregando = false;
    });
  }

  /// [lista] ordenada do mais recente para o mais antigo; compara com a compra anterior (mais antiga).
  Widget _celulaVariacao(List<HistoricoEntrada> lista, int index) {
    if (index >= lista.length - 1) {
      return Text(
        '—',
        style: TextStyle(color: Colors.grey.shade600),
      );
    }
    final atual = lista[index];
    final anterior = lista[index + 1];
    if (anterior.precoCustoUnitarioNota <= 0) {
      return Text('—', style: TextStyle(color: Colors.grey.shade600));
    }
    final pct =
        (atual.precoCustoUnitarioNota - anterior.precoCustoUnitarioNota) /
            anterior.precoCustoUnitarioNota *
            100;
    final texto =
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}% vs compra anterior';
    final semantic = context.semanticColors;
    final cor = pct > 0.5
        ? semantic.errorFg
        : pct < -0.5
            ? semantic.successFg
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      texto,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: cor,
        fontSize: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.produtoId == null || widget.produtoId == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Salve o produto ou pesquise um cadastro existente para ver o historico de compras.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhuma entrada por NF-e registrada para este produto.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final larga = constraints.maxWidth >= 880;
        if (larga) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth - 24),
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 88,
                columns: const [
                  DataColumn(label: Text('Emissao')),
                  DataColumn(label: Text('NF')),
                  DataColumn(label: Text('Fornecedor')),
                  DataColumn(label: Text('Qtd NF')),
                  DataColumn(label: Text('Fator')),
                  DataColumn(label: Text('Estoque +')),
                  DataColumn(label: Text('Custo unit. (nota)')),
                  DataColumn(label: Text('Variacao custo')),
                ],
                rows: [
                  for (var i = 0; i < _lista.length; i++)
                    DataRow(
                      cells: [
                        DataCell(Text(_nfData.format(_lista[i].dataEmissao.toLocal()))),
                        DataCell(Text(
                          '${_lista[i].numeroNota > 0 ? "#${_lista[i].numeroNota}" : "—"}\n${_lista[i].chaveAcesso.length >= 8 ? _lista[i].chaveAcesso.substring(_lista[i].chaveAcesso.length - 8) : _lista[i].chaveAcesso}',
                          style: const TextStyle(fontSize: 11),
                        )),
                        DataCell(Text(
                          _lista[i].nomeFornecedor,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )),
                        DataCell(Text(
                          '${_nfQtd.format(_lista[i].quantidadeFornecedor)} ${_lista[i].unidadeFornecedor}',
                        )),
                        DataCell(Text(_nfQtd.format(_lista[i].fatorConversaoUtilizado))),
                        DataCell(Text('${_lista[i].quantidadeEntradaEstoque}')),
                        DataCell(Text('R\$ ${_nfMoeda.format(_lista[i].precoCustoUnitarioNota)}')),
                        DataCell(_celulaVariacao(_lista, i)),
                      ],
                    ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _lista.length,
          separatorBuilder: (_, i) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final h = _lista[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _nfData.format(h.dataEmissao.toLocal()),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (h.numeroNota > 0)
                          Chip(
                            label: Text('NF ${h.numeroNota}'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      h.nomeFornecedor,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'CNPJ/CPF ${h.cnpjFornecedor}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Nota: ${_nfQtd.format(h.quantidadeFornecedor)} ${h.unidadeFornecedor} · '
                      'Fator ${_nfQtd.format(h.fatorConversaoUtilizado)} · '
                      '+${h.quantidadeEntradaEstoque} no estoque',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Custo unitario (interno): R\$ ${_nfMoeda.format(h.precoCustoUnitarioNota)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    _celulaVariacao(_lista, i),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
