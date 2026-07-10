import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/produto_repository.dart';
import '../data/sugestao_compra_repository.dart';
import '../domain/produto_embalagem.dart';
import '../main.dart';
import '../services/compras_preditivas_service.dart';

/// Relatorio de reposicao: giro recente, minimo, ponto de pedido e ultima entrada por NF-e.
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
      'SKU;Nome;Unidade;Atual;Livre;Minimo;PP;Critico PP;Media dia;Lead time;Seguranca;Vendido periodo;Cobertura dias;Ultima NF-e;Sugerido comprar;Sugerido PP',
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
        ProdutoEmbalagem.formatarEstoque(pr, pr.estoqueAtual, comUnidade: true),
        ProdutoEmbalagem.formatarEstoque(
          pr,
          pr.estoqueLivreParaVenda,
          comUnidade: true,
        ),
        '${pr.quantidadeMinima}',
        _dec1.format(l.pontoPedido).replaceAll('.', ','),
        l.estoqueCritico ? 'SIM' : 'NAO',
        _dec1.format(l.mediaUnidadesPorDia).replaceAll('.', ','),
        '${pr.leadTimeDias}',
        '${pr.estoqueSeguranca}',
        '${l.consumoNoPeriodoUnidades}',
        diasStr.replaceAll('.', ','),
        ult,
        '${l.quantidadeSugerida}',
        '${l.quantidadeSugeridaPorPp}',
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

  Future<void> _recalcularMediasTodosProdutos() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text('Recalculando medias de venda (60 dias)...'),
              ),
            ],
          ),
        ),
      ),
    );

    final svc = ComprasPreditivasService(widget.produtoRepository.objectBox);
    final atualizados = await svc.recalcularTodosProdutosAtivosAsync();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          'Medias recalculadas para $atualizados produto(s) ativo(s).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _repo.montarLinhas(
      diasPeriodoConsumo: _diasPeriodo,
      diasCoberturaAlvo: _diasCoberturaAlvo,
      apenasComSugestaoOuRisco: _apenasPrioritarios,
    );
    final qtdCriticosPp =
        linhas.where((l) => l.estoqueCritico).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestao de compra'),
        actions: [
          IconButton(
            tooltip: 'Recalcular media diaria de todos os produtos',
            onPressed: () => _recalcularMediasTodosProdutos(),
            icon: const Icon(Icons.refresh_outlined),
          ),
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
                  'Usa vendas finalizadas, estoque minimo, ponto de pedido (PP) e meta de cobertura. '
                  'PP = (media diaria x lead time) + estoque seguranca.',
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
                  '${linhas.length} produto(s) · $qtdCriticosPp em PP critico',
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
                      final livre = pr.estoqueLivreExibicao;
                      final abaixoMin = livre <= pr.quantidadeMinima;
                      final dias = l.diasCoberturaComEstoqueAtual;
                      final giroBaixo =
                          dias != null && dias < _diasCoberturaAlvo;
                      final semantic =
                          Theme.of(context).extension<AppSemanticColors>();

                      return Card(
                        color: l.estoqueCritico
                            ? (semantic?.errorBg ?? Theme.of(context)
                                    .colorScheme.errorContainer)
                                .withValues(alpha: 0.25)
                            : null,
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
                                  if (l.estoqueCritico)
                                    Chip(
                                      label: Text(
                                        l.alertaPorEstoqueSeguranca
                                            ? 'Seguranca'
                                            : 'PP critico',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                    ),
                                  if (!l.estoqueCritico && abaixoMin)
                                    Chip(
                                      label: const Text('Minimo'),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                    ),
                                  if (!l.estoqueCritico &&
                                      !abaixoMin &&
                                      giroBaixo)
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
                                'Atual ${ProdutoEmbalagem.formatarEstoque(pr, pr.estoqueAtual, comUnidade: true)} · '
                                'Livre ${ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(pr, livre)} ${pr.unidade} · '
                                'Min ${pr.quantidadeMinima}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l.alertaPorEstoqueSeguranca
                                    ? 'Limiar seguranca: ${_dec1.format(l.pontoPedido)} un '
                                        '(produto novo ou sem giro no periodo)'
                                    : 'PP ${_dec1.format(l.pontoPedido)} un '
                                        '(media ${_dec1.format(l.mediaUnidadesPorDia)}/dia x '
                                        '${pr.leadTimeDias}d + seg ${pr.estoqueSeguranca})',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'Vendido ($_diasPeriodo d): ${l.consumoNoPeriodoUnidades} un',
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
                                'Sugerido comprar: ${l.quantidadeSugerida} ${pr.unidade}'
                                '${l.quantidadeSugeridaPorPp > 0 ? ' (ate PP: ${l.quantidadeSugeridaPorPp})' : ''}',
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
