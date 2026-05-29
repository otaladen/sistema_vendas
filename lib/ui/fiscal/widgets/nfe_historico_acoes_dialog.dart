import 'package:flutter/material.dart';

/// Dialogo para justificativa de cancelamento NF-e (15–255 caracteres).
Future<String?> showNfeCancelamentoDialog(BuildContext context) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Cancelar NF-e'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informe a justificativa (minimo 15 caracteres). '
                  'Em homologacao, use apenas notas de teste.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  maxLines: 4,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Justificativa',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 15) {
                      return 'Minimo 15 caracteres';
                    }
                    if (t.length > 255) return 'Maximo 255 caracteres';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

/// Dialogo para texto da Carta de Correcao (CC-e).
Future<String?> showNfeCartaCorrecaoDialog(BuildContext context) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Carta de Correcao (CC-e)'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Descreva a correcao (minimo 15 caracteres). '
                  'Nao altera valores ou itens da nota.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Texto da correcao',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    counterText: 'Min. 15 · max. 1000 caracteres',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 15) return 'Minimo 15 caracteres';
                    if (t.length > 1000) return 'Maximo 1000 caracteres';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Enviar CC-e'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}
