import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Calculadora compacta para uso no balcao (PDV).
class PdvCalculadoraPanel extends StatefulWidget {
  const PdvCalculadoraPanel({
    super.key,
    required this.onFechar,
    this.onPanDelta,
  });

  static const double largura = 272;
  static const double alturaEstimada = 380;

  final VoidCallback onFechar;
  final void Function(Offset delta)? onPanDelta;

  @override
  State<PdvCalculadoraPanel> createState() => _PdvCalculadoraPanelState();
}

class _PdvCalculadoraPanelState extends State<PdvCalculadoraPanel> {
  final FocusNode _focus = FocusNode();
  String _buffer = '0';
  double? _accumulator;
  String? _pendingOp;
  bool _waitingForOperand = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double _parseBuffer() =>
      double.tryParse(_buffer.replaceAll(',', '.')) ?? 0;

  String _formatNum(double v) {
    if (v.isNaN || v.isInfinite) return 'Erro';
    final rounded = (v * 1e10).roundToDouble() / 1e10;
    if ((rounded - rounded.roundToDouble()).abs() < 1e-9) {
      return rounded.round().toString();
    }
    var s = rounded.toStringAsFixed(6);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  double _compute(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '*':
        return a * b;
      case '/':
        return b == 0 ? double.nan : a / b;
      default:
        return b;
    }
  }

  void _inputDigit(String d) {
    setState(() {
      if (_waitingForOperand || _buffer == '0' || _buffer == 'Erro') {
        _buffer = d;
        _waitingForOperand = false;
      } else {
        _buffer += d;
      }
    });
  }

  void _inputDecimal() {
    setState(() {
      if (_waitingForOperand || _buffer == 'Erro') {
        _buffer = '0,';
        _waitingForOperand = false;
        return;
      }
      if (!_buffer.contains(',')) _buffer += ',';
    });
  }

  void _inputOp(String op) {
    setState(() {
      final v = _parseBuffer();
      if (_accumulator != null &&
          _pendingOp != null &&
          !_waitingForOperand &&
          _buffer != 'Erro') {
        _accumulator = _compute(_accumulator!, v, _pendingOp!);
        _buffer = _formatNum(_accumulator!);
      } else {
        _accumulator = v;
      }
      _pendingOp = op;
      _waitingForOperand = true;
    });
  }

  void _equals() {
    setState(() {
      if (_pendingOp == null || _accumulator == null) return;
      final v = _parseBuffer();
      final r = _compute(_accumulator!, v, _pendingOp!);
      _buffer = _formatNum(r);
      _accumulator = null;
      _pendingOp = null;
      _waitingForOperand = true;
    });
  }

  void _clear() {
    setState(() {
      _buffer = '0';
      _accumulator = null;
      _pendingOp = null;
      _waitingForOperand = false;
    });
  }

  void _backspace() {
    setState(() {
      if (_waitingForOperand) return;
      if (_buffer.length <= 1 || _buffer == 'Erro') {
        _buffer = '0';
        return;
      }
      _buffer = _buffer.substring(0, _buffer.length - 1);
      if (_buffer.isEmpty) _buffer = '0';
    });
  }

  void _percentual() {
    setState(() {
      final v = _parseBuffer() / 100;
      _buffer = _formatNum(v);
      _waitingForOperand = false;
    });
  }

  Future<void> _copiarResultado() async {
    final texto = _buffer.replaceAll(',', '.');
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Valor copiado'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  String? _digitoTecla(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      return '0';
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return '1';
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return '2';
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return '3';
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return '4';
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return '5';
    }
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      return '6';
    }
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      return '7';
    }
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      return '8';
    }
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      return '9';
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _equals();
      return KeyEventResult.handled;
    }

    final dig = _digitoTecla(key);
    if (dig != null) {
      _inputDigit(dig);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.comma ||
        key == LogicalKeyboardKey.period ||
        key == LogicalKeyboardKey.numpadDecimal) {
      _inputDecimal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) {
      _inputOp('+');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _inputOp('-');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.asterisk ||
        key == LogicalKeyboardKey.numpadMultiply) {
      _inputOp('*');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.slash ||
        key == LogicalKeyboardKey.numpadDivide) {
      _inputOp('/');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: SizedBox(
        width: PdvCalculadoraPanel.largura,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanUpdate: (d) => widget.onPanDelta?.call(d.delta),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Calculadora (F11)',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar valor',
                        visualDensity: VisualDensity.compact,
                        onPressed: _copiarResultado,
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Fechar (Esc)',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onFechar,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_pendingOp != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_formatNum(_accumulator ?? 0)} $_pendingOp',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _buffer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _gradeBotoes(theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradeBotoes(ThemeData theme) {
    Widget btn(
      String rotulo, {
      VoidCallback? onTap,
      Color? fundo,
      Color? texto,
      int flex = 1,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: EdgeInsets.zero,
              backgroundColor: fundo,
              foregroundColor: texto,
            ),
            onPressed: onTap,
            child: Text(
              rotulo,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> children) => Row(children: children);

    return Column(
      children: [
        row([
          btn('C', onTap: _clear),
          btn('⌫', onTap: _backspace),
          btn('%', onTap: _percentual),
          btn('÷', onTap: () => _inputOp('/')),
        ]),
        row([
          btn('7', onTap: () => _inputDigit('7')),
          btn('8', onTap: () => _inputDigit('8')),
          btn('9', onTap: () => _inputDigit('9')),
          btn('×', onTap: () => _inputOp('*')),
        ]),
        row([
          btn('4', onTap: () => _inputDigit('4')),
          btn('5', onTap: () => _inputDigit('5')),
          btn('6', onTap: () => _inputDigit('6')),
          btn('−', onTap: () => _inputOp('-')),
        ]),
        row([
          btn('1', onTap: () => _inputDigit('1')),
          btn('2', onTap: () => _inputDigit('2')),
          btn('3', onTap: () => _inputDigit('3')),
          btn('+', onTap: () => _inputOp('+')),
        ]),
        row([
          btn('0', onTap: () => _inputDigit('0'), flex: 2),
          btn(',', onTap: _inputDecimal),
          btn(
            '=',
            onTap: _equals,
            fundo: theme.colorScheme.primary,
            texto: theme.colorScheme.onPrimary,
          ),
        ]),
      ],
    );
  }
}
