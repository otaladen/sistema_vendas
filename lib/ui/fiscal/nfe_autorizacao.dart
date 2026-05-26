import 'package:flutter/material.dart';

import '../../data/usuario_repository.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../layout/app_layout.dart';

bool usuarioPodeEmitirNfeSaida(UsuarioSistema u) {
  return UsuarioPermissaoHelper.podeEmitirNfeSaida(u);
}

bool usuarioPodeCancelarNfeSaida(UsuarioSistema u) {
  return UsuarioPermissaoHelper.podeCancelarNfeSaida(u);
}

Future<bool> solicitarAutorizacaoNfeFiscal(
  BuildContext context,
  UsuarioRepository usuarioRepository, {
  required String titulo,
  required String mensagem,
}) async {
  final cred = await showDialog<_CredenciaisNfe>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoAutorizacaoNfe(
      titulo: titulo,
      mensagem: mensagem,
    ),
  );

  if (cred == null || !context.mounted) return false;
  if (cred.login.isEmpty || cred.senha.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preencha login e senha.')),
    );
    return false;
  }

  final usuario = await usuarioRepository.autenticar(cred.login, cred.senha);
  final ok = usuario != null && usuarioPodeCancelarNfeSaida(usuario);

  if (!context.mounted) return false;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissao. Use usuario com "Cancelar NF-e de saida" ou gerente.',
        ),
      ),
    );
    return false;
  }
  return true;
}

class _CredenciaisNfe {
  const _CredenciaisNfe({required this.login, required this.senha});

  final String login;
  final String senha;
}

class _DialogoAutorizacaoNfe extends StatefulWidget {
  const _DialogoAutorizacaoNfe({
    required this.titulo,
    required this.mensagem,
  });

  final String titulo;
  final String mensagem;

  @override
  State<_DialogoAutorizacaoNfe> createState() => _DialogoAutorizacaoNfeState();
}

class _DialogoAutorizacaoNfeState extends State<_DialogoAutorizacaoNfe> {
  final _login = TextEditingController();
  final _senha = TextEditingController();

  @override
  void dispose() {
    _login.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _ok() {
    Navigator.pop(
      context,
      _CredenciaisNfe(login: _login.text.trim(), senha: _senha.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: AdaptiveDialogContent(
        desktopWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.mensagem),
            const SizedBox(height: 12),
            TextField(
              controller: _login,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Login'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _senha,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha'),
              onSubmitted: (_) => _ok(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Autorizar')),
      ],
    );
  }
}
