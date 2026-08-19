import 'package:flutter/material.dart';

import '../domain/auditoria_catalogo.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';

class CredenciaisMargemPromocao {
  const CredenciaisMargemPromocao({required this.login, required this.senha});

  final String login;
  final String senha;
}

bool usuarioPodeAutorizarMargemPromocao(UsuarioSistema u) {
  return UsuarioPermissaoHelper.podeAutorizarMargemPromocao(u);
}

/// Login/senha de gerente para venda abaixo da margem minima da promocao.
Future<bool> solicitarAutorizacaoMargemPromocao(
  BuildContext context,
  dynamic usuarioRepository, {
  required double margemAtual,
  required double margemMinima,
  required String nomeProduto,
}) async {
  final cred = await showDialog<CredenciaisMargemPromocao>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoMargemPromocao(
      margemAtual: margemAtual,
      margemMinima: margemMinima,
      nomeProduto: nomeProduto,
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
  final ok = usuario != null && usuarioPodeAutorizarMargemPromocao(usuario);

  if (!context.mounted) return false;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissao. Ative "Autorizar margem promocional" no cadastro de usuarios '
          'ou use um administrador.',
        ),
      ),
    );
    return false;
  }
  AuditoriaRegistrar.registrar(
    modulo: AuditoriaModulo.orcamento,
    acao: AuditoriaAcao.autorizacaoMargemPromocao,
    usuarioLogin: usuario.login,
    resumo: 'Autorizacao margem promocional: $nomeProduto',
    detalhes: {
      'produto': nomeProduto,
      'margemAtual': margemAtual,
      'margemMinima': margemMinima,
      'autorizadoPor': usuario.login,
    },
  );
  return true;
}

class _DialogoMargemPromocao extends StatefulWidget {
  const _DialogoMargemPromocao({
    required this.margemAtual,
    required this.margemMinima,
    required this.nomeProduto,
  });

  final double margemAtual;
  final double margemMinima;
  final String nomeProduto;

  @override
  State<_DialogoMargemPromocao> createState() => _DialogoMargemPromocaoState();
}

class _DialogoMargemPromocaoState extends State<_DialogoMargemPromocao> {
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
      CredenciaisMargemPromocao(
        login: _login.text.trim(),
        senha: _senha.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autorizacao de gerente'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.nomeProduto}\n'
              'Margem ${widget.margemAtual.toStringAsFixed(1)}% · '
              'minimo ${widget.margemMinima.toStringAsFixed(1)}%',
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
