import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/auditoria_catalogo.dart';
import '../domain/autorizacao_pdv_chat.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../domain/uuid_v4.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';
import 'widgets/chat/autorizacao_pdv_chat_hub.dart';
import 'widgets/chat/chat_interno_hub.dart';

class AutorizacaoDescontoResultado {
  const AutorizacaoDescontoResultado({
    required this.login,
    required this.senha,
    this.viaChat = false,
    this.solicitacaoId,
  });

  final String login;
  final String senha;
  final bool viaChat;
  final String? solicitacaoId;
}

class _ResultadoDialogoAutorizacao {
  const _ResultadoDialogoAutorizacao.credenciais({
    required this.login,
    required this.senha,
  })  : viaChat = false,
        solicitacaoId = null;

  const _ResultadoDialogoAutorizacao.chat({
    required this.login,
    required this.solicitacaoId,
  })  : senha = '',
        viaChat = true;

  final String login;
  final String senha;
  final bool viaChat;
  final String? solicitacaoId;
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
  int vendaId = 0,
  String carrinhoId = '',
  String descricaoAcao = '',
  double valorOriginal = 0,
}) async {
  final cred = await showDialog<_ResultadoDialogoAutorizacao>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoAutorizacaoDescontoPdv(
      maximoPermitidoReais: maximoPermitidoReais,
      descontoSolicitadoReais: descontoSolicitadoReais,
      formatarMoeda: formatarMoeda,
      usuarioLogado: usuarioLogado,
      vendaId: vendaId,
      carrinhoId: carrinhoId,
      descricaoAcao: descricaoAcao,
      valorOriginal: valorOriginal,
    ),
  );

  if (cred == null || !context.mounted) return null;

  if (cred.viaChat) {
    return AutorizacaoDescontoResultado(
      login: cred.login,
      senha: '',
      viaChat: true,
      solicitacaoId: cred.solicitacaoId,
    );
  }

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
    required this.usuarioLogado,
    required this.vendaId,
    required this.carrinhoId,
    required this.descricaoAcao,
    required this.valorOriginal,
  });

  final double maximoPermitidoReais;
  final double descontoSolicitadoReais;
  final String Function(double) formatarMoeda;
  final UsuarioSistema usuarioLogado;
  final int vendaId;
  final String carrinhoId;
  final String descricaoAcao;
  final double valorOriginal;

  @override
  State<_DialogoAutorizacaoDescontoPdv> createState() =>
      _DialogoAutorizacaoDescontoPdvState();
}

class _DialogoAutorizacaoDescontoPdvState
    extends State<_DialogoAutorizacaoDescontoPdv> {
  final _login = TextEditingController();
  final _senha = TextEditingController();
  bool _aguardandoChat = false;
  String? _solicitacaoId;
  String? _erroChat;
  bool _enviandoPedido = false;

  @override
  void dispose() {
    final sid = _solicitacaoId;
    if (_aguardandoChat && sid != null) {
      AutorizacaoPdvChatHub.instance.abortarLocal(sid);
      unawaited(() async {
        try {
          await ChatInternoHub.instance.responderAutorizacaoPdv(
            solicitacaoId: sid,
            acao: 'cancelar',
            login: widget.usuarioLogado.login,
            motivo: 'Modal fechado',
          );
        } catch (_) {}
      }());
    }
    _login.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _ok() {
    if (_aguardandoChat) return;
    Navigator.pop(
      context,
      _ResultadoDialogoAutorizacao.credenciais(
        login: _login.text.trim(),
        senha: _senha.text,
      ),
    );
  }

  String _descricaoAcao() {
    if (widget.descricaoAcao.trim().isNotEmpty) {
      return widget.descricaoAcao.trim();
    }
    return 'Desconto de ${widget.formatarMoeda(widget.descontoSolicitadoReais)}';
  }

  Future<void> _solicitarNoChat() async {
    if (_enviandoPedido || _aguardandoChat) return;
    if (!ChatInternoHub.instance.configurado) {
      setState(() => _erroChat = 'Chat interno nao esta disponivel.');
      return;
    }
    setState(() {
      _enviandoPedido = true;
      _erroChat = null;
    });
    final sid = gerarUuidV4();
    final payload = AutorizacaoPdvChatPayload(
      solicitacaoId: sid,
      tipoOperacao: AutorizacaoPdvChatTipo.descontoAcimaTeto,
      operadorLogin: widget.usuarioLogado.login,
      operadorNome: widget.usuarioLogado.nome.trim().isNotEmpty
          ? widget.usuarioLogado.nome.trim()
          : widget.usuarioLogado.login,
      timestamp: DateTime.now().toUtc(),
      vendaId: widget.vendaId,
      carrinhoId: widget.carrinhoId.trim().isEmpty
          ? sid
          : widget.carrinhoId.trim(),
      valorOriginal: widget.valorOriginal > 0
          ? widget.valorOriginal
          : widget.maximoPermitidoReais,
      valorSolicitado: widget.descontoSolicitadoReais,
      descricaoAcao: _descricaoAcao(),
      stationId: AutorizacaoPdvChatHub.instance.origemId(),
    );
    try {
      final future = AutorizacaoPdvChatHub.instance.aguardar(sid);
      await ChatInternoHub.instance.enviarAutorizacaoPdv(payload);
      if (!mounted) return;
      setState(() {
        _aguardandoChat = true;
        _solicitacaoId = sid;
        _enviandoPedido = false;
      });
      final resp = await future;
      if (!mounted) return;
      if (resp.aprovada) {
        _aguardandoChat = false;
        _solicitacaoId = null;
        if (!mounted) return;
        Navigator.pop(
          context,
          _ResultadoDialogoAutorizacao.chat(
            login: resp.respondidoPor,
            solicitacaoId: resp.solicitacaoId,
          ),
        );
        return;
      }
      setState(() {
        _aguardandoChat = false;
        _solicitacaoId = null;
        _erroChat = resp.recusada
            ? (resp.motivo.isEmpty
                ? 'Gerente recusou a liberacao no chat.'
                : 'Recusado: ${resp.motivo}')
            : 'Solicitacao cancelada.';
      });
    } catch (e) {
      if (!mounted) return;
      AutorizacaoPdvChatHub.instance.abortarLocal(sid);
      setState(() {
        _aguardandoChat = false;
        _solicitacaoId = null;
        _enviandoPedido = false;
        _erroChat = '$e';
      });
    }
  }

  Future<void> _cancelarEsperaChat() async {
    final sid = _solicitacaoId;
    AutorizacaoPdvChatHub.instance.abortarLocal(sid ?? '');
    if (sid != null && sid.isNotEmpty) {
      try {
        await ChatInternoHub.instance.responderAutorizacaoPdv(
          solicitacaoId: sid,
          acao: 'cancelar',
          login: widget.usuarioLogado.login,
          motivo: 'Cancelado no PDV',
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _aguardandoChat = false;
      _solicitacaoId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autorizacao de gerente'),
      content: SizedBox(
        width: 400,
        child: _aguardandoChat ? _aguardando() : _formulario(),
      ),
      actions: _aguardandoChat
          ? [
              TextButton(
                onPressed: () => unawaited(_cancelarEsperaChat()),
                child: const Text('Cancelar'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(onPressed: _ok, child: const Text('Autorizar')),
            ],
    );
  }

  Widget _formulario() {
    return Column(
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _enviandoPedido ? null : () => unawaited(_solicitarNoChat()),
          icon: _enviandoPedido
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chat_outlined),
          label: const Text('Solicitar Liberacao no Chat'),
        ),
        if (_erroChat != null) ...[
          const SizedBox(height: 8),
          Text(
            _erroChat!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _aguardando() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 16),
        const Text(
          'Aguardando aprovacao do gerente no chat...',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _descricaoAcao(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
