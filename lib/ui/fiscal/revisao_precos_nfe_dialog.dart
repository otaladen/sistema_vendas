import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/api/produto_api_repository.dart';
import '../../domain/nfe_revisao_preco.dart';
import '../../model/produto.dart';
import '../../services/gondola_etiqueta_pdf.dart';
import '../layout/app_layout.dart';
import '../theme/app_semantic_colors.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/operacao_feedback.dart';

/// Abre a revisao de precos apos a NF-e ja ter sido gravada.
///
/// Retorna `true` se aplicou novos precos, `false` se manteve os atuais.
Future<bool> mostrarRevisaoPrecosNfeDialog(
  BuildContext context, {
  required List<NfeRevisaoPrecoItem> itens,
  required dynamic produtoRepository,
  int? numeroNota,
  String emitente = '',
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
  });

  final List<NfeRevisaoPrecoItem> itens;
  final dynamic produtoRepository;
  final int? numeroNota;
  final String emitente;

  @override
  State<RevisaoPrecosNfeDialog> createState() => _RevisaoPrecosNfeDialogState();
}

class _RevisaoPrecosNfeDialogState extends State<RevisaoPrecosNfeDialog> {
  static final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');

  late final List<TextEditingController> _precoCtrls;
  late final List<FocusNode> _precoFocus;
  final _aplicarFocus = FocusNode();
  bool _imprimirEtiquetas = false;
  bool _aplicando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _precoCtrls = [
      for (final item in widget.itens)
        TextEditingController(
          text: _nfMoeda.format(
            item.precoVendaSugerido > 0
                ? item.precoVendaSugerido
                : item.precoVendaAtual,
          ),
        ),
    ];
    _precoFocus = [
      for (var i = 0; i < widget.itens.length; i++)
        FocusNode(debugLabel: 'revisao_preco_$i'),
    ];
    for (var i = 0; i < _precoFocus.length; i++) {
      final node = _precoFocus[i];
      final ctrl = _precoCtrls[i];
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
      if (!mounted || _precoFocus.isEmpty) return;
      _precoFocus.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _precoCtrls) {
      c.dispose();
    }
    for (final f in _precoFocus) {
      f.dispose();
    }
    _aplicarFocus.dispose();
    super.dispose();
  }

  static String _formatarReais(double v) => 'R\$ ${_nfMoeda.format(v)}';

  static double? _parseMoeda(String texto) {
    var valor = texto.trim();
    if (valor.isEmpty) return null;
    valor = valor
        .replaceAll('\u00A0', '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(RegExp(r'r\$', caseSensitive: false), '');
    if (valor.isEmpty) return null;
    final direto = double.tryParse(valor);
    if (direto != null) return direto;
    final limpo = valor.replaceAll(RegExp(r'[^\d.,+\-eE]'), '');
    if (limpo.isEmpty) return null;
    final ultVirg = limpo.lastIndexOf(',');
    final ultPonto = limpo.lastIndexOf('.');
    if (ultVirg > ultPonto) {
      return double.tryParse(limpo.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(limpo.replaceAll(',', '.'));
  }

  void _focarProximoPreco(int index) {
    if (index + 1 < _precoFocus.length) {
      _precoFocus[index + 1].requestFocus();
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

  List<({NfeRevisaoPrecoItem item, double novoPreco})> _linhasComPreco() {
    final out = <({NfeRevisaoPrecoItem item, double novoPreco})>[];
    for (var i = 0; i < widget.itens.length; i++) {
      final novo = _parseMoeda(_precoCtrls[i].text);
      if (novo == null || novo < 0) continue;
      out.add((item: widget.itens[i], novoPreco: novo));
    }
    return out;
  }

  Future<void> _aplicar() async {
    if (_aplicando) return;
    final linhas = _linhasComPreco();
    if (linhas.length != widget.itens.length) {
      setState(
        () => _erro = 'Informe um preco de venda valido em todas as linhas.',
      );
      return;
    }
    setState(() {
      _aplicando = true;
      _erro = null;
    });
    final reajustados = <({Produto produto, double preco})>[];
    try {
      for (final linha in linhas) {
        final p = await _obterProduto(linha.item.produtoId);
        if (p == null) {
          throw StateError(
            'Produto ${linha.item.codigoInterno} nao encontrado para atualizar o preco.',
          );
        }
        final novo = linha.novoPreco;
        p.precoVenda = novo;
        if ((p.preco1 - linha.item.precoVendaAtual).abs() < 0.009 ||
            p.preco1 <= 0) {
          p.preco1 = novo;
        }
        await _salvarProduto(p);
        if ((novo - linha.item.precoVendaAtual).abs() > 0.009) {
          reajustados.add((produto: p, preco: novo));
        }
      }
      try {
        widget.produtoRepository.invalidarCacheBusca();
      } catch (_) {}
      if (_imprimirEtiquetas && reajustados.isNotEmpty) {
        await _imprimirGondola(reajustados);
      }
      if (!mounted) return;
      OperacaoFeedback.sucesso(
        context,
        reajustados.isEmpty
            ? 'Precos conferidos. Nenhum valor de venda foi alterado.'
            : '${reajustados.length} preco(s) de venda atualizado(s).',
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
              maxWidth: 1180,
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
                                  ? '$nota · a entrada ja foi gravada. Ajuste so a precificacao de venda.'
                                  : '$nota · $emitente · a entrada ja foi gravada. Ajuste so a precificacao de venda.',
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
                  if (aumentos > 0)
                    Container(
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
                        'O preco sugerido aplica a margem cadastrada sobre o novo custo.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: sem.warningFg,
                          fontWeight: FontWeight.w600,
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
                        : (v) => setState(() => _imprimirEtiquetas = v == true),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Gerar/imprimir etiquetas de gondola para os itens reajustados',
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
  }

  Widget _tabela(ThemeData theme, AppSemanticColors sem) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 64,
            columnSpacing: 16,
            headingTextStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            columns: const [
              DataColumn(label: Text('Codigo / Produto')),
              DataColumn(label: Text('Custo antigo x novo'), numeric: true),
              DataColumn(label: Text('Margem %'), numeric: true),
              DataColumn(label: Text('Preco atual'), numeric: true),
              DataColumn(label: Text('Sugerido'), numeric: true),
              DataColumn(label: Text('Novo preco de venda')),
            ],
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
    return DataRow(
      color: aumento ? WidgetStatePropertyAll(sem.warningBg) : null,
      cells: [
        DataCell(
          SizedBox(
            width: 260,
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
        DataCell(Text('${item.margemLucroCadastrada.toStringAsFixed(1)}%')),
        DataCell(Text(_formatarReais(item.precoVendaAtual))),
        DataCell(Text(_formatarReais(item.precoVendaSugerido))),
        DataCell(_campoPreco(i)),
      ],
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
                Text(
                  'Margem ${item.margemLucroCadastrada.toStringAsFixed(1)}% · '
                  'Atual ${_formatarReais(item.precoVendaAtual)} · '
                  'Sugerido ${_formatarReais(item.precoVendaSugerido)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _campoPreco(i),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _custoComparacao(
    NfeRevisaoPrecoItem item,
    ThemeData theme,
    bool aumento,
    AppSemanticColors sem,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: aumento
          ? BoxDecoration(
              color: const Color(0xFFFFF3B0),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sem.warningBorder),
            )
          : null,
      child: Text(
        '${_formatarReais(item.custoAntigo)}  →  ${_formatarReais(item.custoNovo)}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: aumento ? FontWeight.w800 : FontWeight.w500,
          color: aumento ? const Color(0xFF8A5B00) : null,
        ),
      ),
    );
  }

  Widget _campoPreco(int index) {
    return SizedBox(
      width: 130,
      child: TextField(
        controller: _precoCtrls[index],
        focusNode: _precoFocus[index],
        enabled: !_aplicando,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: index == widget.itens.length - 1
            ? TextInputAction.done
            : TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: const InputDecoration(
          isDense: true,
          prefixText: 'R\$ ',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _focarProximoPreco(index),
      ),
    );
  }
}
