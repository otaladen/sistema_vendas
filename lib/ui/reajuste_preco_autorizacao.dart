import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';
import '../model/usuario_sistema.dart';
import 'layout/app_layout.dart';

bool usuarioPodeReajustePrecoLote(UsuarioSistema u) {
  return u.ativo && (u.admin || u.podeReajustePrecoLote || u.podeCadastros);
}

bool usuarioPodeAutorizarReajustePreco(UsuarioSistema u) {
  return u.ativo &&
      (u.admin || u.podeAutorizarReajustePreco || u.podeAutorizarMargemVenda);
}

/// Login/senha de gerente para aplicar reajuste com alertas (margem, variacao, custo).
Future<bool> solicitarAutorizacaoReajustePreco(
  BuildContext context,
  UsuarioRepository usuarioRepository, {
  required int itensComAlerta,
  required String resumoRegra,
}) async {
  final cred = await showDialog<_CredenciaisReajuste>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoAutorizacaoReajuste(
      itensComAlerta: itensComAlerta,
      resumoRegra: resumoRegra,
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
  final ok = usuario != null && usuarioPodeAutorizarReajustePreco(usuario);

  if (!context.mounted) return false;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissao. Ative "Autorizar reajuste de precos" no cadastro de '
          'usuarios ou use um administrador.',
        ),
      ),
    );
    return false;
  }
  return true;
}

class _CredenciaisReajuste {
  const _CredenciaisReajuste({required this.login, required this.senha});

  final String login;
  final String senha;
}

class _DialogoAutorizacaoReajuste extends StatefulWidget {
  const _DialogoAutorizacaoReajuste({
    required this.itensComAlerta,
    required this.resumoRegra,
  });

  final int itensComAlerta;
  final String resumoRegra;

  @override
  State<_DialogoAutorizacaoReajuste> createState() =>
      _DialogoAutorizacaoReajusteState();
}

class _DialogoAutorizacaoReajusteState extends State<_DialogoAutorizacaoReajuste> {
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
      _CredenciaisReajuste(
        login: _login.text.trim(),
        senha: _senha.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autorizacao de gerente'),
      content: AdaptiveDialogContent(
        desktopWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.itensComAlerta} item(ns) com alerta de precificacao.\n'
              '${widget.resumoRegra}',
            ),
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
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Autorizar')),
      ],
    );
  }
}
