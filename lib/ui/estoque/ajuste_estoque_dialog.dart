import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/produto_embalagem.dart';
import '../../domain/quantidade_venda_util.dart';
import '../../model/produto.dart';

enum ModoAjusteEstoque { quantidadeFinal, delta }

/// Dialogo para ajuste manual de estoque com motivo obrigatorio.
Future<AjusteEstoqueResultado?> showAjusteEstoqueDialog({
  required BuildContext context,
  required Produto produto,
}) {
  return showDialog<AjusteEstoqueResultado>(
    context: context,
    builder: (ctx) => _AjusteEstoqueDialog(produto: produto),
  );
}

class AjusteEstoqueResultado {
  const AjusteEstoqueResultado({
    required this.novaQuantidadeFisica,
    required this.motivo,
    this.numeroLote = '',
    this.dataValidade,
  });

  final int novaQuantidadeFisica;
  final String motivo;
  final String numeroLote;
  final DateTime? dataValidade;
}

class _AjusteEstoqueDialog extends StatefulWidget {
  const _AjusteEstoqueDialog({required this.produto});

  final Produto produto;

  @override
  State<_AjusteEstoqueDialog> createState() => _AjusteEstoqueDialogState();
}

class _AjusteEstoqueDialogState extends State<_AjusteEstoqueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _valorController = TextEditingController();
  final _motivoController = TextEditingController();
  final _loteController = TextEditingController();
  ModoAjusteEstoque _modo = ModoAjusteEstoque.quantidadeFinal;
  DateTime? _dataValidade;

  bool get _fracionada =>
      ProdutoEmbalagem.estoqueUsaEscalaFracionada(widget.produto);

  bool get _controlaLote => widget.produto.controlaLoteValidade;

  @override
  void initState() {
    super.initState();
    _valorController.text = ProdutoEmbalagem.formatarEstoque(
      widget.produto,
      widget.produto.estoqueReal,
    );
  }

  @override
  void dispose() {
    _valorController.dispose();
    _motivoController.dispose();
    _loteController.dispose();
    super.dispose();
  }

  String _formatarArmazenado(int armazenado) {
    return ProdutoEmbalagem.formatarEstoque(
      widget.produto,
      armazenado,
      comUnidade: true,
    );
  }

  int? _parseArmazenadoEntrada(
    String raw, {
    required bool permiteNegativo,
  }) {
    var t = raw.trim();
    if (t.isEmpty) return null;
    var negativo = false;
    if (t.startsWith('-')) {
      if (!permiteNegativo) return null;
      negativo = true;
      t = t.substring(1).trim();
      if (t.isEmpty) return null;
    }
    int? val;
    if (_fracionada) {
      final v = QuantidadeVendaUtil.parseEntradaPdv(t, fracionada: true);
      if (v != null) {
        val = QuantidadeVendaUtil.paraArmazenamento(v, fracionada: true);
      } else {
        val = int.tryParse(t);
      }
    } else {
      val = int.tryParse(t);
    }
    if (val == null) return null;
    return negativo ? -val : val;
  }

  int? _quantidadeFinalCalculada() {
    if (_modo == ModoAjusteEstoque.quantidadeFinal) {
      return _parseArmazenadoEntrada(
        _valorController.text,
        permiteNegativo: false,
      );
    }
    final delta = _parseArmazenadoEntrada(
      _valorController.text,
      permiteNegativo: true,
    );
    if (delta == null) return null;
    return widget.produto.estoqueReal + delta;
  }

  void _confirmar() {
    if (!_formKey.currentState!.validate()) return;
    final finalQtd = _quantidadeFinalCalculada();
    if (finalQtd == null) return;
    if (finalQtd < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade final nao pode ser negativa.')),
      );
      return;
    }
    if (finalQtd < widget.produto.estoqueReservado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Novo fisico (${_formatarArmazenado(finalQtd)}) menor que o reservado '
            '(${_formatarArmazenado(widget.produto.estoqueReservado)}). '
            'Libere reservas antes.',
          ),
        ),
      );
      return;
    }
    final entrada = finalQtd > widget.produto.estoqueReal;
    if (_controlaLote && entrada && _loteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o numero do lote para entrada (ou SEM-LOTE).',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      AjusteEstoqueResultado(
        novaQuantidadeFisica: finalQtd,
        motivo: _motivoController.text.trim(),
        numeroLote: _controlaLote ? _loteController.text.trim() : '',
        dataValidade: _controlaLote ? _dataValidade : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _quantidadeFinalCalculada();
    final unidade = ProdutoEmbalagem.normalizarUnidade(widget.produto.unidade);
    return AlertDialog(
      title: const Text('Ajustar estoque'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.produto.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fisico atual: ${_formatarArmazenado(widget.produto.estoqueReal)} · '
                  'Reservado: ${_formatarArmazenado(widget.produto.estoqueReservado)} · '
                  'Livre: ${_formatarArmazenado(widget.produto.estoqueLivreParaVenda)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SegmentedButton<ModoAjusteEstoque>(
                  segments: const [
                    ButtonSegment(
                      value: ModoAjusteEstoque.quantidadeFinal,
                      label: Text('Qtd final'),
                    ),
                    ButtonSegment(
                      value: ModoAjusteEstoque.delta,
                      label: Text('+ / - delta'),
                    ),
                  ],
                  selected: {_modo},
                  onSelectionChanged: (s) {
                    setState(() {
                      _modo = s.first;
                      if (_modo == ModoAjusteEstoque.quantidadeFinal) {
                        _valorController.text = ProdutoEmbalagem.formatarEstoque(
                          widget.produto,
                          widget.produto.estoqueReal,
                        );
                      } else {
                        _valorController.text = '0';
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _valorController,
                  decoration: InputDecoration(
                    labelText: _modo == ModoAjusteEstoque.quantidadeFinal
                        ? 'Nova quantidade fisica ($unidade)'
                        : 'Variacao (+ entrada / - saida)',
                    hintText: _fracionada ? 'Ex.: 144,62 ou -2,63' : null,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(
                    signed: _modo == ModoAjusteEstoque.delta,
                    decimal: _fracionada,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(_fracionada ? r'-?[\d.,]+' : r'-?\d+'),
                    ),
                  ],
                  validator: (v) {
                    if (_parseArmazenadoEntrada(
                          v ?? '',
                          permiteNegativo:
                              _modo == ModoAjusteEstoque.delta,
                        ) ==
                        null) {
                      return _fracionada
                          ? 'Informe um numero valido (ex.: 144,62)'
                          : 'Informe um numero valido';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Resultado: ${_formatarArmazenado(preview)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                if (_controlaLote) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Lote / validade (entrada aumenta estoque do lote; saida usa FEFO)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _loteController,
                    decoration: const InputDecoration(
                      labelText: 'Numero do lote',
                      hintText: 'Ex.: L123 ou SEM-LOTE',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _dataValidade == null
                          ? 'Validade (opcional)'
                          : 'Validade: ${DateFormat('dd/MM/yyyy').format(_dataValidade!.toLocal())}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_dataValidade != null)
                          IconButton(
                            tooltip: 'Limpar',
                            onPressed: () =>
                                setState(() => _dataValidade = null),
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          tooltip: 'Escolher data',
                          onPressed: () async {
                            final inicial =
                                _dataValidade?.toLocal() ?? DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: inicial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked == null) return;
                            setState(() {
                              _dataValidade = DateTime.utc(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                            });
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: _motivoController,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (obrigatorio)',
                    hintText: 'Ex.: contagem, quebra, correcao cadastro',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Informe o motivo do ajuste';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar ajuste'),
        ),
      ],
    );
  }
}

/// Abre extrato (kardex) em dialogo ou bottom sheet largo.
Future<void> showExtratoMovimentoEstoque({
  required BuildContext context,
  required Widget child,
  required String tituloProduto,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Movimentacoes — $tituloProduto',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}
