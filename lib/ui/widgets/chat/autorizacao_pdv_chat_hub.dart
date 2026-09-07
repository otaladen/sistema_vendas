import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/api/lan_api_event_hub.dart';
import '../../../domain/autorizacao_pdv_chat.dart';
import '../../../domain/uuid_v4.dart';
import '../../../services/lan_api_server.dart';

/// Aguarda a resposta do gerente no chat e entrega o resultado ao modal do PDV.
class AutorizacaoPdvChatHub extends ChangeNotifier {
  AutorizacaoPdvChatHub._();
  static final instance = AutorizacaoPdvChatHub._();

  final Map<String, Completer<AutorizacaoPdvChatResposta>> _espera = {};
  String _origemLocal = '';
  bool _ouvindo = false;

  String origemId() {
    final s = LanApiEventHub.instance.stationId.trim();
    if (s.isNotEmpty) return s;
    if (_origemLocal.isEmpty) _origemLocal = gerarUuidV4();
    return _origemLocal;
  }

  void garantirOuvintes() {
    if (_ouvindo) return;
    _ouvindo = true;
    LanApiEventHub.instance.addListener(_onWs);
    LanApiServerHub.instance.addEventoListener(_onServidor);
  }

  void _onWs() {
    if (LanApiEventHub.instance.ultimoEventoTipo !=
        kEventoAutorizacaoPdvResposta) {
      return;
    }
    final payload = LanApiEventHub.instance.ultimoEventoPayload;
    if (payload == null) return;
    aplicarResposta(AutorizacaoPdvChatResposta.fromMap(payload));
  }

  void _onServidor(String type, Map<String, dynamic> payload) {
    if (type != kEventoAutorizacaoPdvResposta) return;
    aplicarResposta(AutorizacaoPdvChatResposta.fromMap(payload));
  }

  void aplicarResposta(AutorizacaoPdvChatResposta resposta) {
    if (resposta.solicitacaoId.isEmpty) return;
    final c = _espera.remove(resposta.solicitacaoId);
    if (c != null && !c.isCompleted) {
      c.complete(resposta);
    }
    notifyListeners();
  }

  Future<AutorizacaoPdvChatResposta> aguardar(String solicitacaoId) {
    garantirOuvintes();
    final existente = _espera[solicitacaoId];
    if (existente != null) return existente.future;
    final c = Completer<AutorizacaoPdvChatResposta>();
    _espera[solicitacaoId] = c;
    return c.future;
  }

  void abortarLocal(String solicitacaoId) {
    if (solicitacaoId.isEmpty) return;
    final c = _espera.remove(solicitacaoId);
    if (c != null && !c.isCompleted) {
      c.complete(
        AutorizacaoPdvChatResposta(
          solicitacaoId: solicitacaoId,
          status: AutorizacaoPdvChatStatus.cancelada,
          respondidoPor: '',
          motivo: 'Cancelado no PDV',
        ),
      );
    }
  }
}
