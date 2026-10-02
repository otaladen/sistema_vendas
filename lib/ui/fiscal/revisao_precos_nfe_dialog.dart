import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/api/produto_api_repository.dart';
import '../../domain/nfe_revisao_preco.dart';
import '../../model/produto.dart';
import '../../services/configuracoes_service.dart';
import '../../services/gondola_etiqueta_pdf.dart';
import '../../services/print_service.dart';
import '../layout/app_layout.dart';
import '../theme/app_semantic_colors.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/operacao_feedback.dart';
import 'nfe_revisao_precificacao_store.dart';

/// Abre a revisao de precos apos a NF-e ja ter sido gravada.
///
/// Retorna `true` se aplicou novos precos, `false` se manteve os atuais.
Future<bool> mostrarRevisaoPrecosNfeDialog(
  BuildContext context, {
  required List<NfeRevisaoPrecoItem> itens,
  required dynamic produtoRepository,
  int? numeroNota,
  String emitente = '',
  double margemMinimaPadrao = 20,
  ConfiguracoesService? configuracoesService,
}) async {
  if (itens.isEmpty) return false;
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => RevisaoPrecosNfeDialog(
      itens: itens,
      produtoRepository: produtoRepository,
      numeroNota: numeroNota,
      emitente: emitente,
      margemMinimaPadrao: margemMinimaPadrao,
      configuracoesService: configuracoesService,
    ),
  );
  return r == true;
}

class RevisaoPrecosNfeDialog extends StatefulWidget {
  const RevisaoPrecosNfeDialog({
    super.key,
    required this.itens,
    required this.produtoRepository,
    this.numeroNota,
    this.emitente = '',
    this.margemMinimaPadrao = 20,
    this.configuracoesService,
  });

  final List<NfeRevisaoPrecoItem> itens;
  final dynamic produtoRepository;
  final int? numeroNota;
  final String emitente;
  final double margemMinimaPadrao;
  final ConfiguracoesService? configuracoesService;

  @override
  State<RevisaoPrecosNfeDialog> createState() => _RevisaoPrecosNfeDialogState();
}

class _RevisaoPrecosNfeDialogState extends State<RevisaoPrecosNfeDialog> {
  late final NfeRevisaoPrecificacaoStore _store;
  late final List<FocusNode> _preco1Focus;
  final _aplicarFocus = FocusNode();
  bool _imprimirEtiquetas = false;
  bool _aplicando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _store = NfeRevisaoPrecificacaoStore(
      itens: widget.itens,
      margemMinimaLoja: widget.margemMinimaPadrao.clamp(0, 99),
    );
    _preco1Focus = [
      for (var i = 0; i < widget.itens.length; i++)
        FocusNode(debugLabel: 'revisao_preco1_$i'),
    ];
    for (var i = 0; i < _preco1Focus.length; i++) {
      final node = _preco1Focus[i];
      final ctrl = _store.controllerPreco1(i);
      node.addListener(() {
        if (node.hasFocus) {
          ctrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: ctrl.text.length,
          );
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _preco1Focus.isEmpty) return;
      _preco1Focus.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _store.dispose();
    for (final f in _preco1Focus) {
      f.dispose();
    }
    _aplicarFocus.dispose();
    super.dispose();
  }

  void _focarProximoPreco1(int index) {
    if (index + 1 < _preco1Focus.length) {
      _preco1Focus[index + 1].requestFocus();
    } else {
      _aplicarFocus.requestFocus();
    }
  }

  Future<Produto?> _obterProduto(int id) async {
    final local = widget.produtoRepository.obterPorId(id);
    if (local != null) return local as Produto;
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) {
      try {
        return await repo.obterPorIdRemoto(id);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _salvarProduto(Produto p) async {
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) {
      await repo.salvarRemoto(p);
    } else {
      repo.salvar(p);
    }
  }

  Future<void> _aplicar() async {
    if (_aplicando) return;
    if (!_store.linhasValidas()) {
      setState(
        () => _erro =
            'Informe precos validos (Preco 1, 2 e 3) em todas as linhas.',
      );
      return;
    }
    setState(() {
      _aplicando = true;
      _erro = null;
    });
    final linhas = _store.linhasParaAplicar();
    final reajustadosEtiqueta = <({Produto produto, double preco})>[];
    try {
      for (final linha in linhas) {
        final p = await _obterProduto(linha.item.produtoId);
        if (p == null) {
          throw StateError(
            'Produto ${linha.item.codigoInterno} nao encontrado para atualizar o preco.',
          );
        }
        final novo1 = linha.preco1;
        final novo2 = linha.preco2;
        final novo3 = linha.preco3;
        p.precoVenda = novo1;
        if ((p.preco1 - linha.item.precoVendaAtual).abs() < 0.009 ||
            p.preco1 <= 0) {
          p.preco1 = novo1;
        }
        if ((novo2 - linha.item.preco2Atual).abs() > 0.009 || p.preco2 <= 0) {
          p.preco2 = novo2;
        }
        if ((novo3 - linha.item.preco3Atual).abs() > 0.009 || p.preco3 <= 0) {
          p.preco3 = novo3;
        }
        await _salvarProduto(p);
        if ((novo1 - linha.item.precoVendaAtual).abs() > 0.009) {
          reajustadosEtiqueta.add((produto: p, preco: novo1));
        }
      }
      try {
        widget.produtoRepository.invalidarCacheBusca();
      } catch (_) {}
      if (_imprimirEtiquetas && reajustadosEtiqueta.isNotEmpty) {
        await _imprimirGondola(reajustadosEtiqueta);
      }
      if (!mounted) return;
      OperacaoFeedback.sucesso(
        context,
        reajustadosEtiqueta.isEmpty
            ? 'Precos conferidos. Nenhum valor de venda (Preco 1) foi alterado.'
            : '${reajustadosEtiqueta.length} preco(s) de venda atualizado(s).',
      );
      Navigator.of(context).pop(true);
    } on LanApiException catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = false);
      LanApiFeedback.snackErro(context, e, prefixo: 'Revisao de precos');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aplicando = false;
        _erro = '$e';
      });
    }
  }

  Future<void> _imprimirGondola(
    List<({Produto produto, double preco})> itens,
  ) async {
    final payload = [
      for (final e in itens)
        (
          nome: e.produto.nome,
          codigo: e.produto.codigoBarras.trim().isNotEmpty
              ? e.produto.codigoBarras
              : e.produto.codigoInterno,
          preco: e.preco,
        ),
    ];
    final bytes = await gerarPdfEtiquetasGondolaProdutos(payload);
    final cfg = widget.configuracoesService;
    if (cfg != null) {
      final printService = PrintService(cfg);
      final nomeSalvo = await printService.obterNomeImpressoraSalva();
      if (nomeSalvo.isNotEmpty) {
        final printer = await printService.resolverImpressoraPorNome(nomeSalvo);
        if (printer != null) {
          await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) async => bytes,
            name: 'Etiquetas gondola NF-e',
          );
          return;
        }
      }
    }
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Etiquetas gondola NF-e',
    );
  }

  void _manterAtuais() {
    if (_aplicando) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sem = context.semanticColors;
    final compact = context.isCompactLayout;
    final aumentos = widget.itens.where((e) => e.custoAumentou).length;
    final nota = widget.numeroNota != null && widget.numeroNota! > 0
        ? 'NF-e ${widget.numeroNota}'
        : 'NF-e';
    final emitente = widget.emitente.trim();
    final size = MediaQuery.sizeOf(context);

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _manterAtuais,
            const SingleActivator(LogicalKeyboardKey.f10): () {
              if (!_aplicando) _aplicar();
            },
          },
          child: Focus(
            autofocus: true,
            child: Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 28,
                vertical: compact ? 16 : 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _store.mostrarPreco2Preco3 ? 1480 : 1180,
                  maxHeight: size.height * 0.92,
                  minWidth: compact ? 0 : 720,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.price_change_outlined, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Revisao de Precos e Custos da Nota',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  emitente.isEmpty
                                      ? '$nota · a entrada ja foi gravada. Ajuste a precificacao de venda.'
                                      : '$nota · $emitente · a entrada ja foi gravada. Ajuste a precificacao de venda.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Tab/Enter · F10 aplicar · Esc manter',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _aplicando
                                ? null
                                : _store.aplicarSugeridoEmTodos,
                            icon: const Icon(Icons.auto_fix_high, size: 18),
                            label: const Text('Aplicar sugerido em todos'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _aplicando
                                ? null
                                : _store.repassarAumentoExatoEmTodos,
                            icon: const Icon(Icons.trending_up, size: 18),
                            label: const Text('Repassar aumento exato (R\$)'),
                          ),
                          FilterChip(
                            label: const Text('Preco 2 e 3 (Atacado / Obra)'),
                            selected: _store.mostrarPreco2Preco3,
                            onSelected: _aplicando
                                ? null
                                : (v) => _store.setMostrarTabelasExtras(v),
                          ),
                        ],
                      ),
                      if (aumentos > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: sem.warningBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: sem.warningBorder),
                            ),
                            child: Text(
                              '$aumentos item(ns) com aumento de custo (destacado em amarelo). '
                              'Margem % reage ao Preco 1; minimo da loja: '
                              '${widget.margemMinimaPadrao.toStringAsFixed(0)}% sobre venda.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: sem.warningFg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (_erro != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _erro!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Expanded(
                        child: compact
                            ? _listaCompacta(theme, sem)
                            : _tabela(theme, sem),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _imprimirEtiquetas,
                        onChanged: _aplicando
                            ? null
                            : (v) =>
                                  setState(() => _imprimirEtiquetas = v == true),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'Gerar/imprimir etiquetas de gondola (somente Preco 1 alterado)',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _aplicando ? null : _manterAtuais,
                              child: const Text('Manter precos atuais'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              focusNode: _aplicarFocus,
                              onPressed: _aplicando ? null : _aplicar,
                              icon: _aplicando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check),
                              label: Text(
                                _aplicando
                                    ? 'Aplicando...'
                                    : 'Aplicar novos precos (F10)',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tabela(ThemeData theme, AppSemanticColors sem) {
    final cols = <DataColumn>[
      const DataColumn(label: Text('Codigo / Produto')),
      const DataColumn(label: Text('Custo antigo x novo'), numeric: true),
      const DataColumn(label: Text('Margem %'), numeric: true),
      const DataColumn(label: Text('Preco 1 atual'), numeric: true),
      const DataColumn(label: Text('Sugerido'), numeric: true),
      const DataColumn(label: Text('Novo Preco 1')),
    ];
    if (_store.mostrarPreco2Preco3) {
      cols.addAll(const [
        DataColumn(label: Text('Preco 2 atual'), numeric: true),
        DataColumn(label: Text('Sug. 2'), numeric: true),
        DataColumn(label: Text('Novo Preco 2')),
        DataColumn(label: Text('Preco 3 atual'), numeric: true),
        DataColumn(label: Text('Sug. 3'), numeric: true),
        DataColumn(label: Text('Novo Preco 3')),
      ]);
    }
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 72,
            columnSpacing: 14,
            headingTextStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            columns: cols,
            rows: [
              for (var i = 0; i < widget.itens.length; i++)
                _linhaTabela(i, theme, sem),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _linhaTabela(int i, ThemeData theme, AppSemanticColors sem) {
    final item = widget.itens[i];
    final aumento = item.custoAumentou;
    final cells = <DataCell>[
      DataCell(
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.codigoInterno,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                item.nome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      DataCell(_custoComparacao(item, theme, aumento, sem)),
      DataCell(_celulaMargem(i, theme, sem)),
      DataCell(Text(NfeRevisaoPrecificacaoStore.formatarReais(item.precoVendaAtual))),
      DataCell(Text(NfeRevisaoPrecificacaoStore.formatarReais(item.precoVendaSugerido))),
      DataCell(_campoPreco(_store.controllerPreco1(i), focus: _preco1Focus[i], index: i)),
    ];
    if (_store.mostrarPreco2Preco3) {
      cells.addAll([
        DataCell(Text(NfeRevisaoPrecificacaoStore.formatarReais(item.preco2Atual))),
        DataCell(Text(NfeRevisaoPrecificacaoStore.formatarReais(item.preco2Sugerido))),
        DataCell(_campoPreco(_store.controllerPreco2(i))),
        DataCell(Text(NfeRevisaoPrecificacaoStore.formatarReais(item.preco3Atual))),
        DataCell(Text(NfeRevisaoPrecificacaoStore.formatarReais(item.preco3Sugerido))),
        DataCell(_campoPreco(_store.controllerPreco3(i))),
      ]);
    }
    return DataRow(
      color: aumento ? WidgetStatePropertyAll(sem.warningBg) : null,
      cells: cells,
    );
  }

  Widget _listaCompacta(ThemeData theme, AppSemanticColors sem) {
    return ListView.separated(
      itemCount: widget.itens.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = widget.itens[i];
        final aumento = item.custoAumentou;
        return Card(
          color: aumento ? sem.warningBg : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${item.codigoInterno} · ${item.nome}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                _custoComparacao(item, theme, aumento, sem),
                const SizedBox(height: 4),
                _celulaMargem(i, theme, sem),
                const SizedBox(height: 6),
                Text(
                  'Preco 1 · Atual ${NfeRevisaoPrecificacaoStore.formatarReais(item.precoVendaAtual)} · '
                  'Sugerido ${NfeRevisaoPrecificacaoStore.formatarReais(item.precoVendaSugerido)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                _campoPreco(
                  _store.controllerPreco1(i),
                  label: 'Novo Preco 1',
                  focus: _preco1Focus[i],
                  index: i,
                ),
                if (_store.mostrarPreco2Preco3) ...[
                  const SizedBox(height: 10),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Preco 2 (Atacado) e Preco 3 (Obra/Especial)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      Text(
                        'Preco 2 · Atual ${NfeRevisaoPrecificacaoStore.formatarReais(item.preco2Atual)} · '
                        'Sugerido ${NfeRevisaoPrecificacaoStore.formatarReais(item.preco2Sugerido)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      _campoPreco(
                        _store.controllerPreco2(i),
                        label: 'Novo Preco 2',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Preco 3 · Atual ${NfeRevisaoPrecificacaoStore.formatarReais(item.preco3Atual)} · '
                        'Sugerido ${NfeRevisaoPrecificacaoStore.formatarReais(item.preco3Sugerido)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      _campoPreco(
                        _store.controllerPreco3(i),
                        label: 'Novo Preco 3',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _celulaMargem(int i, ThemeData theme, AppSemanticColors sem) {
    final margem = _store.margemPreco1Reativa(i);
    final alerta = _store.alertaMargemPreco1(i);
    Color? cor;
    switch (alerta) {
      case NfeRevisaoMargemAlerta.prejuizo:
        cor = theme.colorScheme.error;
      case NfeRevisaoMargemAlerta.abaixoMinimo:
        cor = const Color(0xFFE65100);
      case NfeRevisaoMargemAlerta.ok:
        cor = null;
    }
    return Text(
      '${margem.toStringAsFixed(1)}%',
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: cor,
      ),
    );
  }

  Widget _chipVariacaoCusto(NfeRevisaoPrecoItem item, AppSemanticColors sem) {
    final pct = item.variacaoCustoPercentual;
    if (pct == null || pct.abs() < 0.05) {
      return const SizedBox.shrink();
    }
    Color bg;
    Color fg;
    if (pct > 0) {
      bg = sem.warningBg;
      fg = sem.warningFg;
    } else {
      bg = sem.successBg;
      fg = sem.successFg;
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: bg,
      side: BorderSide(color: fg.withValues(alpha: 0.35)),
      label: Text(
        NfeRevisaoPrecificacaoStore.formatarVariacaoCusto(pct),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _custoComparacao(
    NfeRevisaoPrecoItem item,
    ThemeData theme,
    bool aumento,
    AppSemanticColors sem,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: aumento
              ? BoxDecoration(
                  color: const Color(0xFFFFF3B0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: sem.warningBorder),
                )
              : null,
          child: Text(
            '${NfeRevisaoPrecificacaoStore.formatarReais(item.custoAntigo)}  →  '
            '${NfeRevisaoPrecificacaoStore.formatarReais(item.custoNovo)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: aumento ? FontWeight.w800 : FontWeight.w500,
              color: aumento ? const Color(0xFF8A5B00) : null,
            ),
          ),
        ),
        _chipVariacaoCusto(item, sem),
      ],
    );
  }

  Widget _campoPreco(
    TextEditingController controller, {
    String? label,
    FocusNode? focus,
    int? index,
  }) {
    return SizedBox(
      width: 124,
      child: TextField(
        controller: controller,
        focusNode: focus,
        enabled: !_aplicando,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: index != null && index == widget.itens.length - 1
            ? TextInputAction.done
            : TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          prefixText: 'R\$ ',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: focus != null && index != null
            ? (_) => _focarProximoPreco1(index)
            : null,
      ),
    );
  }
}
