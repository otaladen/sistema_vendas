import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  final int novaQuantidadeFisica;
  final String motivo;
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
  ModoAjusteEstoque _modo = ModoAjusteEstoque.quantidadeFinal;

  @override
  void initState() {
    super.initState();
    _valorController.text = '${widget.produto.estoqueReal}';
  }

  @override
  void dispose() {
    _valorController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  int? _parseInt(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  int? _quantidadeFinalCalculada() {
    final parsed = _parseInt(_valorController.text);
    if (parsed == null) return null;
    if (_modo == ModoAjusteEstoque.quantidadeFinal) return parsed;
    return widget.produto.estoqueReal + parsed;
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
            'Novo fisico ($finalQtd) menor que o reservado '
            '(${widget.produto.estoqueReservado}). Libere reservas antes.',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _quantidadeFinalCalculada();
    return AlertDialog(
      title: const Text('Ajustar estoque'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
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
                'Fisico atual: ${widget.produto.estoqueReal} · '
                'Reservado: ${widget.produto.estoqueReservado} · '
                'Livre: ${widget.produto.estoqueLivreParaVenda}',
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
                      _valorController.text = '${widget.produto.estoqueReal}';
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
                      ? 'Nova quantidade fisica'
                      : 'Variacao (+ entrada / - saida)',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d+'))],
                validator: (v) {
                  if (_parseInt(v ?? '') == null) {
                    return 'Informe um numero valido';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Resultado: $preview un. fisicas',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
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
