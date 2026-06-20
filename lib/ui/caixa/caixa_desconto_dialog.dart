import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Valor de desconto adicional informado no caixa (em reais).
class CaixaDescontoDialogResult {
  const CaixaDescontoDialogResult({required this.valorReais});

  final double valorReais;
}

/// Dialogo rapido de desconto no caixa (F6). Enter aplica, Esc cancela.
Future<CaixaDescontoDialogResult?> mostrarDialogoDescontoCaixa(
  BuildContext context, {
  required double totalAtual,
  required double descontoPdv,
  required double descontoCaixaAtual,
  required double maximoAdicionalReais,
  required double maximoPercentual,
  required String Function(double) formatarMoeda,
}) {
  return showDialog<CaixaDescontoDialogResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => _CaixaDescontoDialog(
      totalAtual: totalAtual,
      descontoPdv: descontoPdv,
      descontoCaixaAtual: descontoCaixaAtual,
      maximoAdicionalReais: maximoAdicionalReais,
      maximoPercentual: maximoPercentual,
      formatarMoeda: formatarMoeda,
    ),
  );
}

class _CaixaDescontoDialog extends StatefulWidget {
  const _CaixaDescontoDialog({
    required this.totalAtual,
    required this.descontoPdv,
    required this.descontoCaixaAtual,
    required this.maximoAdicionalReais,
    required this.maximoPercentual,
    required this.formatarMoeda,
  });

  final double totalAtual;
  final double descontoPdv;
  final double descontoCaixaAtual;
  final double maximoAdicionalReais;
  final double maximoPercentual;
  final String Function(double) formatarMoeda;

  @override
  State<_CaixaDescontoDialog> createState() => _CaixaDescontoDialogState();
}

class _CaixaDescontoDialogState extends State<_CaixaDescontoDialog> {
  final _valorController = TextEditingController();
  final _focusValor = FocusNode();
  String _tipo = 'valor';
  String? _erro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusValor.requestFocus();
    });
  }

  @override
  void dispose() {
    _valorController.dispose();
    _focusValor.dispose();
    super.dispose();
  }

  double? _parseEntrada(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'[^\d,.-]'), '');
    if (t.isEmpty) return null;
    if (t.contains(',')) {
      return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(t);
  }

  double _descontoInformadoReais() {
    final bruto = _parseEntrada(_valorController.text);
    if (bruto == null || bruto <= 0) return 0;
    if (_tipo == 'percentual') {
      return (widget.totalAtual * bruto / 100).clamp(0, widget.totalAtual);
    }
    return bruto.clamp(0, widget.totalAtual);
  }

  void _aplicar() {
    final valor = _descontoInformadoReais();
    if (valor <= 0.009) {
      setState(() => _erro = 'Informe um desconto maior que zero.');
      return;
    }
    if (valor > widget.totalAtual + 0.009) {
      setState(
        () => _erro =
            'Desconto nao pode ser maior que ${widget.formatarMoeda(widget.totalAtual)}.',
      );
      return;
    }
    Navigator.pop(context, CaixaDescontoDialogResult(valorReais: valor));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _descontoInformadoReais();
    final novoTotal =
        (widget.totalAtual - preview).clamp(0, double.infinity).toDouble();

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _aplicar();
              return null;
            },
          ),
        },
        child: AlertDialog(
          title: const Text('Desconto no caixa'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Total atual: ${widget.formatarMoeda(widget.totalAtual)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.descontoPdv > 0.009) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Desconto PDV: -${widget.formatarMoeda(widget.descontoPdv)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (widget.descontoCaixaAtual > 0.009) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Desconto caixa: -${widget.formatarMoeda(widget.descontoCaixaAtual)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'valor', label: Text('R\$')),
                        ButtonSegment(value: 'percentual', label: Text('%')),
                      ],
                      selected: {_tipo},
                      onSelectionChanged: (v) {
                        if (v.isEmpty) return;
                        setState(() {
                          _tipo = v.first;
                          _erro = null;
                        });
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _valorController,
                        focusNode: _focusValor,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                        ],
                        decoration: InputDecoration(
                          labelText: _tipo == 'percentual'
                              ? 'Desconto adicional %'
                              : 'Desconto adicional R\$',
                          helperText:
                              'Max. ${widget.formatarMoeda(widget.maximoAdicionalReais)} '
                              '(${widget.maximoPercentual.toStringAsFixed(1)}%) · '
                              'acima exige gerente · Enter aplica · Esc cancela',
                          errorText: _erro,
                          isDense: true,
                        ),
                        onChanged: (_) {
                          if (_erro != null) setState(() => _erro = null);
                          setState(() {});
                        },
                        onSubmitted: (_) => _aplicar(),
                      ),
                    ),
                  ],
                ),
                if (preview > 0.009) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Novo total: ${widget.formatarMoeda(novoTotal)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar (Esc)'),
            ),
            FilledButton(
              onPressed: _aplicar,
              child: const Text('Aplicar (Enter)'),
            ),
          ],
        ),
      ),
    );
  }
}
