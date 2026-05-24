import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Feedback sonoro/haptico e SnackBar padronizado no caixa.
class CaixaFeedback {
  CaixaFeedback._();

  static void sucesso(BuildContext context, String mensagem) {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    _mostrar(context, mensagem, Colors.green.shade700, Icons.check_circle_outline);
  }

  static void erro(BuildContext context, String mensagem) {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _mostrar(context, mensagem, Colors.red.shade700, Icons.error_outline);
  }

  static void aviso(BuildContext context, String mensagem) {
    HapticFeedback.lightImpact();
    _mostrar(context, mensagem, Colors.orange.shade800, Icons.info_outline);
  }

  static void _mostrar(
    BuildContext context,
    String mensagem,
    Color cor,
    IconData icone,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cor,
        content: Row(
          children: [
            Icon(icone, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(mensagem)),
          ],
        ),
      ),
    );
  }
}
