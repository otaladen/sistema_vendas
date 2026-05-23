import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';
import '../domain/usuario_permissao_helper.dart';

/// Credenciais informadas no dialogo de autorizacao.
class CredenciaisSegundaVia {
  const CredenciaisSegundaVia({required this.login, required this.senha});

  final String login;
  final String senha;
}

/// Pede login e senha de um usuario com [UsuarioSistema.podeAutorizarSegundaViaCupom]
/// ativo (admin tambem pode, pois tem controle total no cadastro).
Future<bool> solicitarSenhaAutorizacaoSegundaViaCupom(
  BuildContext context,
  UsuarioRepository usuarioRepository,
) async {
  final credenciais = await showDialog<CredenciaisSegundaVia>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => const _DialogoAutorizacaoSegundaVia(),
  );

  if (credenciais == null || !context.mounted) {
    return false;
  }

  if (credenciais.login.isEmpty || credenciais.senha.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preencha login e senha.')),
    );
    return false;
  }

  final usuario = await usuarioRepository.autenticar(
    credenciais.login,
    credenciais.senha,
  );
  final ok = usuario != null &&
      UsuarioPermissaoHelper.podeAutorizarSegundaViaCupom(usuario);

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
}

/// Controllers vivem apenas enquanto o dialogo esta aberto (evita dispose prematuro).
class _DialogoAutorizacaoSegundaVia extends StatefulWidget {
  const _DialogoAutorizacaoSegundaVia();

  @override
  State<_DialogoAutorizacaoSegundaVia> createState() =>
      _DialogoAutorizacaoSegundaViaState();
}

class _DialogoAutorizacaoSegundaViaState
    extends State<_DialogoAutorizacaoSegundaVia> {
  late final TextEditingController _loginController;
  late final TextEditingController _senhaController;

  @override
  void initState() {
    super.initState();
    _loginController = TextEditingController();
    _senhaController = TextEditingController();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _autorizar() {
    Navigator.of(context).pop(
      CredenciaisSegundaVia(
        login: _loginController.text.trim(),
        senha: _senhaController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              controller: _loginController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Login'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _senhaController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _autorizar(),
              decoration: const InputDecoration(labelText: 'Senha'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _autorizar,
          child: const Text('Autorizar'),
        ),
      ],
    );
  }
}
