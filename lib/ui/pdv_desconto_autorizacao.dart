import 'package:flutter/material.dart';

import '../domain/auditoria_catalogo.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';

class AutorizacaoDescontoResultado {
  const AutorizacaoDescontoResultado({
    required this.login,
    required this.senha,
  });

  final String login;
  final String senha;
}

class _CredenciaisAutorizacao {
  const _CredenciaisAutorizacao({required this.login, required this.senha});

  final String login;
  final String senha;
}

bool usuarioPodeAutorizarDescontoAcimaTetoPdv(UsuarioSistema u) {
  return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.alterarPrecoPdv);
}

/// Login/senha de gerente para desconto acima do teto configurado no PDV.
///
/// [usuarioRepository] aceita [UsuarioRepository] ou [UsuarioApiRepository]
/// (Terminal Leve) — ambos expoe `autenticar`.
Future<AutorizacaoDescontoResultado?> solicitarAutorizacaoDescontoAcimaTetoPdv(
  BuildContext context,
  dynamic usuarioRepository, {
  required UsuarioSistema usuarioLogado,
  required double maximoPermitidoReais,
  required double descontoSolicitadoReais,
  required String Function(double) formatarMoeda,
}) async {
  final cred = await showDialog<_CredenciaisAutorizacao>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoAutorizacaoDescontoPdv(
      maximoPermitidoReais: maximoPermitidoReais,
      descontoSolicitadoReais: descontoSolicitadoReais,
      formatarMoeda: formatarMoeda,
    ),
  );

  if (cred == null || !context.mounted) return null;
  if (cred.login.isEmpty || cred.senha.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preencha login e senha.')),
    );
    return null;
  }

  final usuario = await usuarioRepository.autenticar(cred.login, cred.senha);
  if (!context.mounted) return null;
  if (usuario == null || !usuarioPodeAutorizarDescontoAcimaTetoPdv(usuario)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem permissao. Ative "Desconto manual no PDV" no cadastro de '
          'usuarios ou use um administrador.',
        ),
      ),
    );
    return null;
  }

  AuditoriaRegistrar.registrar(
    modulo: AuditoriaModulo.orcamento,
    acao: AuditoriaAcao.autorizacaoDescontoAcimaTeto,
    usuarioLogin: usuarioLogado.login,
    resumo: 'Autorizacao desconto acima do teto no PDV',
    detalhes: {
      'maximoPermitido': maximoPermitidoReais,
      'descontoSolicitado': descontoSolicitadoReais,
      'autorizadoPor': usuario.login,
    },
  );
  return AutorizacaoDescontoResultado(
    login: cred.login,
    senha: cred.senha,
  );
}

class _DialogoAutorizacaoDescontoPdv extends StatefulWidget {
  const _DialogoAutorizacaoDescontoPdv({
    required this.maximoPermitidoReais,
    required this.descontoSolicitadoReais,
    required this.formatarMoeda,
  });

  final double maximoPermitidoReais;
  final double descontoSolicitadoReais;
  final String Function(double) formatarMoeda;

  @override
  State<_DialogoAutorizacaoDescontoPdv> createState() =>
      _DialogoAutorizacaoDescontoPdvState();
}

class _DialogoAutorizacaoDescontoPdvState
    extends State<_DialogoAutorizacaoDescontoPdv> {
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
      _CredenciaisAutorizacao(
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
              'Desconto solicitado: ${widget.formatarMoeda(widget.descontoSolicitadoReais)}\n'
              'Maximo sem autorizacao: ${widget.formatarMoeda(widget.maximoPermitidoReais)}',
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
