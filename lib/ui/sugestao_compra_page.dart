import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/produto_repository.dart';
import '../data/sugestao_compra_repository.dart';

/// Relatorio de reposicao: giro recente, minimo e ultima entrada por NF-e.
class SugestaoCompraPage extends StatefulWidget {
  const SugestaoCompraPage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  @override
  State<SugestaoCompraPage> createState() => _SugestaoCompraPageState();
}

class _SugestaoCompraPageState extends State<SugestaoCompraPage> {
  int _diasPeriodo = 60;
  int _diasCoberturaAlvo = 30;
  bool _apenasPrioritarios = true;
  static final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dec1 = NumberFormat('#,##0.0', 'pt_BR');

  SugestaoCompraRepository get _repo =>
      SugestaoCompraRepository(widget.produtoRepository.objectBox);

  String _csvSeguro(String valor) {
    final texto = valor.replaceAll('"', '""');
    return '"$texto"';
  }

  Future<void> _exportarCsv() async {
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para salvar o CSV de sugestao de compra',
    );
    if (pasta == null || pasta.trim().isEmpty) return;

    final linhas = _repo.montarLinhas(
      diasPeriodoConsumo: _diasPeriodo,
      diasCoberturaAlvo: _diasCoberturaAlvo,
      apenasComSugestaoOuRisco: _apenasPrioritarios,
    );
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final arquivo = File(p.join(pasta, 'sugestao_compra_$ts.csv'));

    final out = <String>[
      'SKU;Nome;Unidade;Livre;Minimo;Vendido no periodo;Media dia;Dias cobertura;Ultima NF-e;Sugerido comprar',
    ];
    for (final l in linhas) {
      final pr = l.produto;
      final dias = l.diasCoberturaComEstoqueAtual;
      final diasStr = dias == null ? '' : _dec1.format(dias);
      final ult = l.ultimaEntradaNfe == null
          ? ''
          : _dataFmt.format(l.ultimaEntradaNfe!.toLocal());
      out.add([
        _csvSeguro(pr.codigoInterno),
        _csvSeguro(pr.nome),
        _csvSeguro(pr.unidade),
        '${pr.estoqueLivreParaVenda}',
        '${pr.quantidadeMinima}',
        '${l.consumoNoPeriodoUnidades}',
        _dec1.format(l.mediaUnidadesPorDia).replaceAll('.', ','),
        diasStr.replaceAll('.', ','),
        ult,
        '${l.quantidadeSugerida}',
      ].join(';'));
    }

    try {
      await arquivo.writeAsString('\uFEFF${out.join('\n')}', encoding: utf8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV salvo em: ${arquivo.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _repo.montarLinhas(
      diasPeriodoConsumo: _diasPeriodo,
      diasCoberturaAlvo: _diasCoberturaAlvo,
      apenasComSugestaoOuRisco: _apenasPrioritarios,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestao de compra'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            onPressed: linhas.isEmpty ? null : _exportarCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usa vendas finalizadas no periodo, estoque minimo e meta de cobertura em dias. '
                  'Ultima NF-e vem do historico de importacao XML.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Periodo de venda:'),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 30, label: Text('30 d')),
                        ButtonSegment(value: 60, label: Text('60 d')),
                        ButtonSegment(value: 90, label: Text('90 d')),
                      ],
                      selected: {_diasPeriodo},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setState(() => _diasPeriodo = s.first);
                      },
                    ),
                    const Text('Meta cobertura:'),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 21, label: Text('21 d')),
                        ButtonSegment(value: 30, label: Text('30 d')),
                        ButtonSegment(value: 45, label: Text('45 d')),
                      ],
                      selected: {_diasCoberturaAlvo},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setState(() => _diasCoberturaAlvo = s.first);
                      },
                    ),
                    FilterChip(
                      label: const Text('So prioritarios'),
                      selected: _apenasPrioritarios,
                      onSelected: (s) => setState(() => _apenasPrioritarios = s),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${linhas.length} produto(s) listado(s)',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: linhas.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _apenasPrioritarios
                            ? 'Nenhum produto em alerta com os filtros atuais.\n'
                                'Desative "So prioritarios" para ver todos os cadastros ativos.'
                            : 'Nenhum produto ativo no cadastro.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: linhas.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final l = linhas[i];
                      final pr = l.produto;
                      final livre = pr.estoqueLivreParaVenda;
                      final abaixoMin = livre <= pr.quantidadeMinima;
                      final dias = l.diasCoberturaComEstoqueAtual;
                      final giroBaixo = dias != null && dias < _diasCoberturaAlvo;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      pr.nome,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (abaixoMin)
                                    Chip(
                                      label: const Text('Minimo'),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                    ),
                                  if (!abaixoMin && giroBaixo)
                                    Chip(
                                      label: const Text('Giro'),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .tertiaryContainer,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'SKU ${pr.codigoInterno} · ${pr.unidade} · '
                                'Livre $livre · Min ${pr.quantidadeMinima}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Vendido ($_diasPeriodo d): ${l.consumoNoPeriodoUnidades} un '
                                '· Media/dia ${_dec1.format(l.mediaUnidadesPorDia)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                dias == null
                                    ? 'Cobertura: — (sem venda no periodo)'
                                    : 'Cobertura estimada: ${_dec1.format(dias)} dias de estoque livre',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                l.ultimaEntradaNfe == null
                                    ? 'Ultima NF-e: —'
                                    : 'Ultima NF-e: ${_dataFmt.format(l.ultimaEntradaNfe!.toLocal())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sugerido comprar: ${l.quantidadeSugerida} ${pr.unidade}',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
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
