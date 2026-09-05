import 'package:flutter/material.dart';

import 'quantidade_pdv_input_formatter.dart';

/// Campo de quantidade na linha do carrinho (exibicao ou edicao inline com destaque).
class PdvCarrinhoCampoQuantidade extends StatefulWidget {
  const PdvCarrinhoCampoQuantidade({
    super.key,
    required this.quantidadeExibicao,
    required this.editando,
    required this.fracionada,
    required this.onTapEditar,
    required this.onConfirmar,
    this.controller,
    this.focusNode,
    this.textStyle,
  });

  final String quantidadeExibicao;
  final bool editando;
  final bool fracionada;
  final VoidCallback onTapEditar;
  final VoidCallback onConfirmar;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle? textStyle;

  @override
  State<PdvCarrinhoCampoQuantidade> createState() =>
      _PdvCarrinhoCampoQuantidadeState();
}

class _PdvCarrinhoCampoQuantidadeState extends State<PdvCarrinhoCampoQuantidade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    widget.focusNode?.addListener(_onFocusChanged);
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant PdvCarrinhoCampoQuantidade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      widget.focusNode?.addListener(_onFocusChanged);
    }
    if (widget.editando && !oldWidget.editando) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selecionarTexto();
      });
    }
    _syncPulse();
  }

  void _onFocusChanged() => _syncPulse();

  void _syncPulse() {
    if (widget.editando && (widget.focusNode?.hasFocus ?? false)) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController
        ..stop()
        ..value = 0;
    }
    if (mounted) setState(() {});
  }

  void _selecionarTexto() {
    final ctrl = widget.controller;
    if (ctrl == null) return;
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: ctrl.text.length,
    );
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChanged);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baseStyle = widget.textStyle ??
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800);

    if (!widget.editando) {
      return Tooltip(
        message: 'Informar quantidade',
        child: InkWell(
          onTap: widget.onTapEditar,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(widget.quantidadeExibicao, style: baseStyle),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final pulso = _pulseAnimation.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(
              scheme.primaryContainer.withValues(alpha: 0.25),
              scheme.primaryContainer.withValues(alpha: 0.55),
              pulso,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Color.lerp(
                scheme.primary.withValues(alpha: 0.5),
                scheme.primary,
                pulso,
              )!,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.2 * pulso),
                blurRadius: 8,
              ),
            ],
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: 56,
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          textAlign: TextAlign.center,
          style: baseStyle?.copyWith(color: scheme.primary),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            border: InputBorder.none,
          ),
          keyboardType: widget.fracionada
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          inputFormatters: [
            QuantidadePdvInputFormatter(fracionada: widget.fracionada),
          ],
          onSubmitted: (_) => widget.onConfirmar(),
          onTap: _selecionarTexto,
        ),
      ),
    );
  }
}
