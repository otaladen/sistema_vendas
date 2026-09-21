import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_semantic_colors.dart';

const EdgeInsets _acaoBotaoPadding = EdgeInsets.symmetric(vertical: 12);
const Size _acaoBotaoMinSize = Size(double.infinity, 48);

/// Acoes retornadas ao fechar o dialogo (atalhos de teclado incluidos).
Future<String?> mostrarDialogOrcamentoSalvo(
  BuildContext context, {
  required int numOrcamento,
  required bool modoEscPos,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _OrcamentoSalvoDialog(
      numOrcamento: numOrcamento,
      modoEscPos: modoEscPos,
    ),
  );
}

KeyEventResult atalhoDialogoOrcamentoSalvo(
  KeyEvent event,
  void Function(String acao) fechar,
) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.digit1 ||
      key == LogicalKeyboardKey.numpad1) {
    fechar('fechar');
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
    fechar('pdf');
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
    fechar('direto');
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
    fechar('imprimir');
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    fechar('imprimir');
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.f10) {
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

class _OrcamentoSalvoDialog extends StatelessWidget {
  const _OrcamentoSalvoDialog({
    required this.numOrcamento,
    required this.modoEscPos,
  });

  final int numOrcamento;
  final bool modoEscPos;

  String get _acaoImprimir => modoEscPos ? 'escpos' : 'imprimir';

  Future<void> _copiarNumero(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: '$numOrcamento'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Número do orçamento copiado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic =
        theme.extension<AppSemanticColors>() ?? AppSemanticColors.claro;

    void fechar(String valor) {
      if (!context.mounted) return;
      Navigator.pop(context, valor);
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) =>
          atalhoDialogoOrcamentoSalvo(event, fechar),
      child: AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 48,
              color: semantic.successFg,
            ),
            const SizedBox(height: 12),
            Text(
              'Orçamento Salvo com Sucesso!',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 1,
              shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.12),
              color: semantic.successBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: semantic.successBorder.withValues(
                  alpha: 0.65,
                )),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                child: Column(
                  children: [
                    Text(
                      'NÚMERO DO ORÇAMENTO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            '$numOrcamento',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                              color: semantic.successFg,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar número',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _copiarNumero(context),
                          icon: Icon(
                            Icons.copy,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Informe este número ao cliente ou utilize no caixa para '
              'resgatar os itens.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: semantic.successFg,
                  foregroundColor: Colors.white,
                  padding: _acaoBotaoPadding,
                  minimumSize: _acaoBotaoMinSize,
                ),
                onPressed: () => fechar(_acaoImprimir),
                icon: const Icon(Icons.print),
                label: const Text('Imprimir Comprovante (Enter)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: _acaoBotaoPadding,
                  minimumSize: _acaoBotaoMinSize,
                ),
                onPressed: () => fechar('pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Gerar PDF (2)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: _acaoBotaoPadding,
                  minimumSize: _acaoBotaoMinSize,
                ),
                onPressed: () => fechar('fechar'),
                child: const Text('Fechar (Esc)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
