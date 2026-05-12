import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';

/// Pede login e senha de um usuario com [UsuarioSistema.podeAutorizarSegundaViaCupom]
/// ativo (admin tambem pode, pois tem controle total no cadastro).
Future<bool> solicitarSenhaAutorizacaoSegundaViaCupom(
  BuildContext context,
  UsuarioRepository usuarioRepository,
) async {
  final loginController = TextEditingController();
  final senhaController = TextEditingController();
  try {
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Autorizacao — segunda via do cupom'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informe login e senha de um usuario com a permissao '
                  '"Autorizar segunda via do cupom" no cadastro de usuarios.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loginController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Login'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: senhaController,
                  obscureText: true,
                  onSubmitted: (_) =>
                      Navigator.of(ctx).pop(true),
                  decoration: const InputDecoration(labelText: 'Senha'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Autorizar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true || !context.mounted) {
      return false;
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    if (login.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha login e senha.')),
      );
      return false;
    }
    final usuario = await usuarioRepository.autenticar(login, senha);
    final ok =
        usuario != null && usuario.ativo && usuario.podeAutorizarSegundaViaCupom;
    if (!context.mounted) return false;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Login invalido, usuario inativo ou sem permissao para segunda via '
            '(ative em Cadastro de usuarios).',
          ),
        ),
      );
      return false;
    }
    return true;
  } finally {
    loginController.dispose();
    senhaController.dispose();
  }
}
