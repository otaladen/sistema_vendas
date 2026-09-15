import 'package:flutter/material.dart';

import '../../services/app_pos_login_startup.dart';

/// Alertas de boot pos-login com opcao de repetir etapas que falharam.
Future<void> mostrarAvisosPosLogin(
  BuildContext context, {
  required List<AppPosLoginAviso> avisos,
  required Future<void> Function() onTentarNovamente,
}) async {
  if (avisos.isEmpty || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Avisos ao iniciar'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'O sistema abriu, mas alguns servicos nao carregaram. '
                'Voce pode continuar ou tentar de novo.',
              ),
              const SizedBox(height: 12),
              for (final a in avisos) ...[
                Text(
                  a.tituloAmigavel,
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.detalhe,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onTentarNovamente();
            },
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    },
  );
}

Future<void> mostrarFalhaPosLoginDialog(
  BuildContext context, {
  required String mensagem,
  required Future<void> Function() onTentarNovamente,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Nao foi possivel abrir o sistema'),
        content: SingleChildScrollView(
          child: Text(mensagem),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onTentarNovamente();
            },
            child: const Text('Tentar novamente'),
          ),
        ],
      );
    },
  );
}
