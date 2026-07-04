import 'package:flutter/material.dart';

import '../widgets/operacao_feedback.dart';

/// Feedback sonoro/haptico e SnackBar padronizado no caixa.
class CaixaFeedback {
  CaixaFeedback._();

  static void sucesso(BuildContext context, String mensagem) =>
      OperacaoFeedback.sucesso(context, mensagem);

  static void erro(BuildContext context, String mensagem) =>
      OperacaoFeedback.erro(context, mensagem);

  static void aviso(BuildContext context, String mensagem) =>
      OperacaoFeedback.aviso(context, mensagem);
}
