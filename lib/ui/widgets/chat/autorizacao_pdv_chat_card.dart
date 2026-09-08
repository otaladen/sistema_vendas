import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/autorizacao_pdv_chat.dart';
import '../../../model/mensagem_interna.dart';
import '../../../model/usuario_sistema.dart';
import 'chat_interno_hub.dart';

/// Card especial de solicitacao de autorizacao do PDV no mural interno.
class AutorizacaoPdvChatCard extends StatefulWidget {
  const AutorizacaoPdvChatCard({
    super.key,
    required this.mensagem,
    this.usuarioLogado,
  });

  final MensagemInterna mensagem;
  final UsuarioSistema? usuarioLogado;

  @override
  State<AutorizacaoPdvChatCard> createState() => _AutorizacaoPdvChatCardState();
}

class _AutorizacaoPdvChatCardState extends State<AutorizacaoPdvChatCard> {
  bool _ocupado = false;
  String? _erro;
  final _motivo = TextEditingController();
  final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _fmtHora = DateFormat('dd/MM HH:mm');

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  UsuarioSistema? get _usuario =>
      widget.usuarioLogado ?? ChatInternoHub.instance.usuarioLogado;

  Future<void> _responder(bool aprovar) async {
    final payload = widget.mensagem.autorizacaoPdv;
    final usuario = _usuario;
    if (payload == null || usuario == null || _ocupado) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await ChatInternoHub.instance.responderAutorizacaoPdv(
        solicitacaoId: payload.solicitacaoId,
        acao: aprovar ? 'aprovar' : 'recusar',
        login: usuario.login,
        motivo: _motivo.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = widget.mensagem.autorizacaoPdv;
    if (payload == null) {
      return Text(widget.mensagem.texto, style: theme.textTheme.bodyMedium);
    }
    final usuario = _usuario;
    final podePelaPermissao = usuario != null &&
        usuarioPodeResponderAutorizacaoPdvChat(
          usuario,
          tipoOperacao: payload.tipoOperacao,
        );
    final podeResponder = podePelaPermissao && payload.pendente;
    final statusCor = switch (payload.status) {
      AutorizacaoPdvChatStatus.aprovada => Colors.green.shade700,
      AutorizacaoPdvChatStatus.recusada => scheme.error,
      AutorizacaoPdvChatStatus.cancelada => scheme.outline,
      _ => scheme.primary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                payload.tituloCard,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _linha('Operador', payload.operadorNome.isNotEmpty
            ? payload.operadorNome
            : payload.operadorLogin),
        _linha(
          'Tipo de acao',
          payload.descricaoAcao.isNotEmpty
              ? payload.descricaoAcao
              : AutorizacaoPdvChatTipo.rotulo(payload.tipoOperacao),
        ),
        _linha('Valor original', _fmtMoeda.format(payload.valorOriginal)),
        _linha('Valor modificado', _fmtMoeda.format(payload.valorSolicitado)),
        if (payload.vendaId > 0)
          _linha('Venda / orcamento', '#${payload.vendaId}'),
        _linha('Quando', _fmtHora.format(payload.timestamp.toLocal())),
        const SizedBox(height: 6),
        Text(
          _rotuloStatus(payload),
          style: theme.textTheme.labelLarge?.copyWith(
            color: statusCor,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (payload.respondidoPor.isNotEmpty && !payload.pendente)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              payload.motivo.isEmpty
                  ? 'Por ${payload.respondidoPor}'
                  : 'Por ${payload.respondidoPor}: ${payload.motivo}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (payload.pendente && !podeResponder)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              usuario == null
                  ? 'Nao foi possivel identificar o usuario logado para autorizar.'
                  : !podePelaPermissao
                      ? 'Sem permissao para aprovar. Entre com gerente, admin ou dono.'
                      : 'Aguardando confirmacao do recado no servidor...',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        if (podeResponder) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _motivo,
            enabled: !_ocupado,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _ocupado ? null : () => unawaited(_responder(true)),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Aprovar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => unawaited(_responder(false)),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Recusar'),
                ),
              ),
            ],
          ),
        ],
        if (_ocupado)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _erro!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  String _rotuloStatus(AutorizacaoPdvChatPayload p) {
    switch (p.status) {
      case AutorizacaoPdvChatStatus.aprovada:
        return 'Aprovada';
      case AutorizacaoPdvChatStatus.recusada:
        return 'Recusada';
      case AutorizacaoPdvChatStatus.cancelada:
        return 'Cancelada';
      default:
        return 'Aguardando gerente';
    }
  }

  Widget _linha(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$rotulo: ',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            TextSpan(text: valor, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
