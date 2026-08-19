import 'package:flutter/material.dart';

import '../../model/usuario_sistema.dart';

/// Credenciais informadas no dialogo de autorizacao do gerente.
class CredenciaisGerenteCaixa {
  const CredenciaisGerenteCaixa({required this.login, required this.senha});

  final String login;
  final String senha;
}

bool _podeAutorizarComoGerenteCaixa(UsuarioSistema? usuario) {
  return usuario != null &&
      usuario.ativo &&
      (usuario.admin || usuario.podeFinanceiro);
}

/// Pede login e senha de gerente/supervisor (admin ou financeiro).
Future<bool> solicitarAutorizacaoGerenteCaixa(
  BuildContext context,
  dynamic usuarioRepository,
) async {
  final cred = await solicitarCredenciaisGerenteCaixa(
    context,
    usuarioRepository,
  );
  return cred != null;
}

/// Igual a [solicitarAutorizacaoGerenteCaixa], mas devolve as credenciais
/// para revalidacao no servidor.
Future<CredenciaisGerenteCaixa?> solicitarCredenciaisGerenteCaixa(
  BuildContext context,
  dynamic usuarioRepository,
) async {
  final credenciais = await showDialog<CredenciaisGerenteCaixa>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => const _DialogoAutorizacaoGerenteCaixa(),
  );

  if (credenciais == null || !context.mounted) {
    return null;
  }

  if (credenciais.login.isEmpty || credenciais.senha.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preencha login e senha.')),
    );
    return null;
  }

  final usuario = await usuarioRepository.autenticar(
    credenciais.login,
    credenciais.senha,
  );
  final ok = _podeAutorizarComoGerenteCaixa(usuario);

  if (!context.mounted) return null;

  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Login invalido, usuario inativo ou sem permissao de gerente '
          '(administrador ou financeiro).',
        ),
      ),
    );
    return null;
  }

  return credenciais;
}

class _DialogoAutorizacaoGerenteCaixa extends StatefulWidget {
  const _DialogoAutorizacaoGerenteCaixa();

  @override
  State<_DialogoAutorizacaoGerenteCaixa> createState() =>
      _DialogoAutorizacaoGerenteCaixaState();
}

class _DialogoAutorizacaoGerenteCaixaState
    extends State<_DialogoAutorizacaoGerenteCaixa> {
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
      CredenciaisGerenteCaixa(
        login: _loginController.text.trim(),
        senha: _senhaController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autorizacao do gerente'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Alterar a forma de pagamento do orcamento exige senha de '
              'gerente (administrador ou usuario com permissao financeira).',
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
