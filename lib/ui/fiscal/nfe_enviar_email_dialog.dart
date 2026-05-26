import 'package:flutter/material.dart';

import '../../data/venda_repository.dart';
import '../../services/focus_nfe_service.dart';
import '../layout/app_layout.dart';

/// Dialogo para enviar DANFE/XML da NF-e por e-mail (Focus).
Future<bool?> showNfeEnviarEmailDialog({
  required BuildContext context,
  required FocusNfeService focusNfe,
  required String referenciaFocus,
  required List<String> emailsSugeridos,
}) {
  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => _NfeEnviarEmailDialog(
      focusNfe: focusNfe,
      referenciaFocus: referenciaFocus,
      emailsSugeridos: emailsSugeridos,
    ),
  );
}

class _NfeEnviarEmailDialog extends StatefulWidget {
  const _NfeEnviarEmailDialog({
    required this.focusNfe,
    required this.referenciaFocus,
    required this.emailsSugeridos,
  });

  final FocusNfeService focusNfe;
  final String referenciaFocus;
  final List<String> emailsSugeridos;

  @override
  State<_NfeEnviarEmailDialog> createState() => _NfeEnviarEmailDialogState();
}

class _NfeEnviarEmailDialogState extends State<_NfeEnviarEmailDialog> {
  late final TextEditingController _emails;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    final unicos = <String>{};
    for (final e in widget.emailsSugeridos) {
      final t = e.trim();
      if (t.contains('@')) unicos.add(t);
    }
    _emails = TextEditingController(text: unicos.join('; '));
  }

  @override
  void dispose() {
    _emails.dispose();
    super.dispose();
  }

  List<String> _parseEmails() {
    final raw = _emails.text
        .split(RegExp(r'[;,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.contains('@'))
        .toList();
    return raw.take(10).toList();
  }

  Future<void> _enviar() async {
    final lista = _parseEmails();
    if (lista.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe ao menos um e-mail.')),
      );
      return;
    }
    setState(() => _enviando = true);
    final r = await widget.focusNfe.enviarEmailNfe(
      widget.referenciaFocus,
      emails: lista,
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (r.sucesso) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.mensagem.isNotEmpty
                ? r.mensagem
                : 'E-mail agendado na Focus.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.mensagem)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar NF-e por e-mail'),
      content: AdaptiveDialogContent(
        desktopWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A Focus envia o DANFE/XML para os destinatarios (max. 10). '
              'Separe varios e-mails com ; ou virgula.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emails,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'E-mails',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }
}

/// E-mails sugeridos do cliente da venda.
List<String> emailsSugeridosDaVenda(VendaRepository repo, int vendaId) {
  if (vendaId <= 0) return const [];
  final v = repo.obterPorId(vendaId);
  final c = v?.cliente.target;
  if (c == null) return const [];
  final e = c.email.trim();
  return e.contains('@') ? [e] : const [];
}
