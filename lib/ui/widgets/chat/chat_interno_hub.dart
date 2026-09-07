import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/api/chat_api_repository.dart';
import '../../../data/api/lan_api_client.dart';
import '../../../data/api/lan_api_event_hub.dart';
import '../../../data/chat_interno_leitura_storage.dart';
import '../../../data/chat_interno_outbox.dart';
import '../../../data/mensagem_interna_repository.dart';
import '../../../data/usuario_repository.dart';
import '../../../domain/autorizacao_pdv_chat.dart';
import '../../../domain/autorizacao_pdv_chat_servico.dart';
import '../../../domain/chat_interno_parser.dart';
import '../../../model/mensagem_interna.dart';
import '../../../services/lan_api_server.dart';
import 'autorizacao_pdv_chat_hub.dart';

/// Estado global do chat/mural interno (badge + lista + som + fila).
class ChatInternoHub extends ChangeNotifier {
  ChatInternoHub._();
  static final instance = ChatInternoHub._();

  MensagemInternaRepository? _localRepo;
  ChatApiRepository? _apiRepo;
  UsuarioRepository? _usuarioRepo;
  String _autorPadrao = '';
  String _perfilUsuario = '';
  String _loginUsuario = '';
  bool _painelAberto = false;
  int _naoLidos = 0;
  int _ultimoIdVisto = 0;
  List<MensagemInterna> _mensagens = [];
  List<ChatInternoPendente> _pendentes = [];
  bool _ouvindoWs = false;
  bool _ouvindoServidorLocal = false;
  bool _leituraCarregada = false;
  bool _flushing = false;
  bool _onlineAntes = true;
  Timer? _flushTimer;

  int get naoLidos => _naoLidos;
  bool get temMencaoNaoLida => _mensagens.any(_ehMencaoNaoLida);
  List<MensagemInterna> get mensagens => _listaExibicao();
  String get autorPadrao => _autorPadrao;
  String get perfilUsuario => _perfilUsuario;
  String get loginUsuario => _loginUsuario;
  bool get configurado => _localRepo != null || _apiRepo != null;
  bool get painelAberto => _painelAberto;
  int get ultimoIdVisto => _ultimoIdVisto;
  bool get temPendentes => _pendentes.isNotEmpty;

  void configurar({
    MensagemInternaRepository? localRepo,
    ChatApiRepository? apiRepo,
    UsuarioRepository? usuarioRepo,
    required String autorPadrao,
    String perfilUsuario = '',
    String loginUsuario = '',
  }) {
    _localRepo = localRepo;
    _apiRepo = apiRepo;
    _usuarioRepo = usuarioRepo;
    _autorPadrao = autorPadrao.trim();
    _perfilUsuario = perfilUsuario.trim();
    _loginUsuario = loginUsuario.trim();
    AutorizacaoPdvChatHub.instance.garantirOuvintes();
    _garantirOuvinteWs();
    if (localRepo != null) {
      _garantirOuvinteServidorLocal();
    }
    _flushTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(flushOutbox()),
    );
    unawaited(_iniciar());
  }

  Future<void> _iniciar() async {
    if (!_leituraCarregada) {
      _ultimoIdVisto = await ChatInternoLeituraStorage.carregar();
      _pendentes = await ChatInternoOutbox.listar();
      _leituraCarregada = true;
    }
    await carregarHistorico();
    await flushOutbox();
  }

  void _garantirOuvinteWs() {
    if (_ouvindoWs) return;
    _ouvindoWs = true;
    _onlineAntes = LanApiEventHub.instance.online;
    LanApiEventHub.instance.addListener(_onWs);
  }

  void _garantirOuvinteServidorLocal() {
    if (_ouvindoServidorLocal) return;
    _ouvindoServidorLocal = true;
    LanApiServerHub.instance.addEventoListener(_onEventoServidorLocal);
  }

  void _onEventoServidorLocal(String type, Map<String, dynamic> payload) {
    if (type == kEventoAutorizacaoPdvResposta || type == 'novo_recado_chat') {
      final itemRaw = payload['item'];
      if (itemRaw is Map) {
        final msg = MensagemInterna.fromMap(
          Map<String, dynamic>.from(itemRaw),
        );
        _aplicarMensagem(msg, tocarSom: !_painelAberto);
        return;
      }
    }
    if (type != 'novo_recado_chat') return;
    unawaited(carregarHistorico(tocarSomSeNovo: !_painelAberto));
  }

  void _onWs() {
    final online = LanApiEventHub.instance.online;
    if (online && !_onlineAntes) {
      unawaited(carregarHistorico(tocarSomSeNovo: !_painelAberto));
      unawaited(flushOutbox());
    }
    _onlineAntes = online;

    final tipo = LanApiEventHub.instance.ultimoEventoTipo;
    if (tipo == 'novo_recado_chat' || tipo == kEventoAutorizacaoPdvResposta) {
      final payload = LanApiEventHub.instance.ultimoEventoPayload;
      final itemRaw = payload?['item'];
      if (itemRaw is Map) {
        final msg = MensagemInterna.fromMap(
          Map<String, dynamic>.from(itemRaw),
        );
        _aplicarMensagem(msg, tocarSom: !_painelAberto);
      } else if (tipo == 'novo_recado_chat') {
        unawaited(carregarHistorico(tocarSomSeNovo: !_painelAberto));
      }
      return;
    }
    if (LanApiEventHub.instance.ultimaEntidade == 'chat_interno') {
      unawaited(carregarHistorico(tocarSomSeNovo: !_painelAberto));
    }
  }

  Future<void> carregarHistorico({bool tocarSomSeNovo = false}) async {
    try {
      List<MensagemInterna> lista;
      final api = _apiRepo;
      final local = _localRepo;
      if (local != null && !LanApiEventHub.instance.modoTerminal) {
        lista = await local.listarHistorico();
      } else if (api != null) {
        lista = await api.hidratar();
      } else if (local != null) {
        lista = await local.listarHistorico();
      } else {
        return;
      }
      final maiorAntes = _maiorIdConfirmado(_mensagens);
      _mensagens = lista;
      _retirarPendentesConfirmados();
      final maiorAgora = _maiorIdConfirmado(_mensagens);
      if (tocarSomSeNovo &&
          maiorAgora > maiorAntes &&
          maiorAgora > _ultimoIdVisto) {
        _bipe();
      }
      _recalcularNaoLidos();
      notifyListeners();
    } catch (_) {}
  }

  List<MensagemInterna> _listaExibicao() {
    if (_pendentes.isEmpty) {
      return List<MensagemInterna>.unmodifiable(_mensagens);
    }
    final ids = _mensagens.map((m) => m.clientId).where((c) => c.isNotEmpty).toSet();
    final extra = <MensagemInterna>[];
    for (final p in _pendentes) {
      if (ids.contains(p.clientId)) continue;
      extra.add(_pendenteComoMensagem(p));
    }
    if (extra.isEmpty) {
      return List<MensagemInterna>.unmodifiable(_mensagens);
    }
    return List<MensagemInterna>.unmodifiable([..._mensagens, ...extra]);
  }

  MensagemInterna _pendenteComoMensagem(ChatInternoPendente p) {
    final parsed = ChatInternoParser.parse(p.texto);
    final mencoes = p.mencoes.isNotEmpty
        ? p.mencoes
        : parsed.mencoes.toList();
    return MensagemInterna(
      id: 0,
      vendedor: p.vendedor,
      texto: p.texto,
      dataHora: p.criadoEm,
      clientId: p.clientId,
      pedidoNumero: parsed.pedidoNumero ?? 0,
      mencoes: mencoes,
      pendenteLocal: true,
      tipo: p.tipo.isEmpty ? kMensagemInternaTipoTexto : p.tipo,
      payload: p.payload,
    );
  }

  int _maiorIdConfirmado(List<MensagemInterna> lista) {
    var m = 0;
    for (final e in lista) {
      if (e.pendenteLocal) continue;
      if (e.id > m) m = e.id;
    }
    return m;
  }

  void _aplicarMensagem(MensagemInterna msg, {required bool tocarSom}) {
    final idxCid = msg.clientId.isEmpty
        ? -1
        : _mensagens.indexWhere((m) => m.clientId == msg.clientId);
    final idx = idxCid >= 0
        ? idxCid
        : _mensagens.indexWhere((m) => m.id == msg.id && msg.id > 0);
    final eraNova = idx < 0;
    if (idx >= 0) {
      _mensagens = [..._mensagens]..[idx] = msg;
    } else {
      _mensagens = [..._mensagens, msg];
      _apiRepo?.aplicarEvento(msg);
    }
    _retirarPendentesConfirmados(clientId: msg.clientId);
    if (eraNova && tocarSom && msg.id > _ultimoIdVisto) _bipe();
    final auth = msg.autorizacaoPdv;
    if (auth != null && AutorizacaoPdvChatStatus.ehFinal(auth.status)) {
      AutorizacaoPdvChatHub.instance.aplicarResposta(
        AutorizacaoPdvChatResposta(
          solicitacaoId: auth.solicitacaoId,
          status: auth.status,
          respondidoPor: auth.respondidoPor,
          motivo: auth.motivo,
        ),
      );
    }
    _recalcularNaoLidos();
    notifyListeners();
  }

  void _retirarPendentesConfirmados({String clientId = ''}) {
    if (_pendentes.isEmpty) return;
    final confirmados = _mensagens
        .map((m) => m.clientId)
        .where((c) => c.isNotEmpty)
        .toSet();
    final before = _pendentes.length;
    _pendentes = _pendentes
        .where(
          (p) =>
              p.clientId != clientId && !confirmados.contains(p.clientId),
        )
        .toList();
    if (_pendentes.length != before) {
      unawaited(ChatInternoOutbox.salvar(_pendentes));
    }
  }

  void _recalcularNaoLidos() {
    if (_painelAberto) {
      final maxId = _maiorIdConfirmado(_mensagens);
      if (maxId > _ultimoIdVisto) {
        _ultimoIdVisto = maxId;
        unawaited(ChatInternoLeituraStorage.salvar(maxId));
      }
      _naoLidos = 0;
      return;
    }
    _naoLidos = _mensagens
        .where((m) => !m.pendenteLocal && m.id > _ultimoIdVisto)
        .length;
  }

  bool _ehMencaoNaoLida(MensagemInterna m) {
    if (m.pendenteLocal || m.id <= _ultimoIdVisto) return false;
    return ChatInternoParser.mencionadaPara(_perfilUsuario, m.mencoes);
  }

  void _bipe() {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  void marcarPainelAberto(bool aberto) {
    _painelAberto = aberto;
    _recalcularNaoLidos();
    notifyListeners();
  }

  /// Marca como lidas so o que o usuario ja viu (fim da lista).
  Future<void> marcarLidasAte(int id) async {
    if (id <= _ultimoIdVisto) return;
    _ultimoIdVisto = id;
    _recalcularNaoLidos();
    notifyListeners();
    await ChatInternoLeituraStorage.salvar(id);
  }

  Future<void> marcarLidasAteFim() async {
    final maxId = _maiorIdConfirmado(_mensagens);
    await marcarLidasAte(maxId);
  }

  int indicePrimeiraNaoLida() {
    final lista = mensagens;
    for (var i = 0; i < lista.length; i++) {
      final m = lista[i];
      if (!m.pendenteLocal && m.id > _ultimoIdVisto) return i;
    }
    return -1;
  }

  String _novoClientId() {
    final t = DateTime.now().toUtc().microsecondsSinceEpoch;
    final r = Random().nextInt(0x7fffffff);
    return 'c$t-$r';
  }

  Future<void> enviar(String texto) async {
    final autor = _autorPadrao.isEmpty ? 'Equipe' : _autorPadrao;
    final msg = texto.trim();
    if (msg.isEmpty) return;
    final pendente = ChatInternoPendente(
      clientId: _novoClientId(),
      vendedor: autor,
      texto: msg,
      criadoEm: DateTime.now().toUtc(),
    );
    _pendentes = [..._pendentes, pendente];
    await ChatInternoOutbox.salvar(_pendentes);
    notifyListeners();
    await flushOutbox();
  }

  Future<void> enviarAutorizacaoPdv(AutorizacaoPdvChatPayload payload) async {
    if (!configurado) {
      throw StateError('Chat interno nao configurado.');
    }
    final autor = _autorPadrao.isEmpty ? payload.operadorNome : _autorPadrao;
    final pendente = ChatInternoPendente(
      clientId: payload.solicitacaoId.isEmpty
          ? _novoClientId()
          : 'auth-${payload.solicitacaoId}',
      vendedor: autor,
      texto: payload.textoResumoChat(),
      criadoEm: payload.timestamp.toUtc(),
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: payload.toMap(),
      mencoes: const ['gerente', 'dono'],
    );
    _pendentes = [..._pendentes, pendente];
    await ChatInternoOutbox.salvar(_pendentes);
    notifyListeners();
    await flushOutbox();
    final aindaPendente =
        _pendentes.any((p) => p.clientId == pendente.clientId);
    if (aindaPendente) {
      _pendentes =
          _pendentes.where((p) => p.clientId != pendente.clientId).toList();
      await ChatInternoOutbox.salvar(_pendentes);
      notifyListeners();
      throw StateError(
        'Nao foi possivel enviar a solicitacao. Verifique a conexao com o servidor.',
      );
    }
  }

  Future<void> responderAutorizacaoPdv({
    required String solicitacaoId,
    required String acao,
    required String login,
    String motivo = '',
  }) async {
    final api = _apiRepo;
    final local = _localRepo;
    MensagemInterna atualizada;
    if (local != null && !LanApiEventHub.instance.modoTerminal) {
      atualizada = await AutorizacaoPdvChatServico.responder(
        repo: local,
        usuarios: _exigirUsuarioRepo(),
        solicitacaoId: solicitacaoId,
        acao: acao,
        login: login,
        motivo: motivo,
      );
      _notificarRespostaAutorizacao(atualizada);
    } else if (api != null) {
      atualizada = await api.responderAutorizacaoPdv(
        solicitacaoId: solicitacaoId,
        acao: acao,
        login: login,
        motivo: motivo,
      );
    } else if (local != null) {
      atualizada = await AutorizacaoPdvChatServico.responder(
        repo: local,
        usuarios: _exigirUsuarioRepo(),
        solicitacaoId: solicitacaoId,
        acao: acao,
        login: login,
        motivo: motivo,
      );
      _notificarRespostaAutorizacao(atualizada);
    } else {
      throw StateError('Chat interno nao configurado.');
    }
    _aplicarMensagem(atualizada, tocarSom: false);
  }

  UsuarioRepository _exigirUsuarioRepo() {
    final u = _usuarioRepo;
    if (u == null) {
      throw StateError('Repositorio de usuarios nao configurado.');
    }
    return u;
  }

  void _notificarRespostaAutorizacao(MensagemInterna atualizada) {
    LanApiServerHub.instance.notificarEvento('novo_recado_chat', {
      'item': atualizada.toMap(),
      'id': atualizada.id,
    });
    LanApiServerHub.instance.notificar('chat_interno', ids: [atualizada.id]);
    final auth = atualizada.autorizacaoPdv;
    if (auth != null) {
      LanApiServerHub.instance.notificarEvento(kEventoAutorizacaoPdvResposta, {
        'solicitacaoId': auth.solicitacaoId,
        'status': auth.status,
        'respondidoPor': auth.respondidoPor,
        'motivo': auth.motivo,
        'stationId': auth.stationId,
        'item': atualizada.toMap(),
      });
    }
  }

  Future<void> flushOutbox() async {
    if (_flushing) return;
    if (_pendentes.isEmpty) {
      _pendentes = await ChatInternoOutbox.listar();
      if (_pendentes.isEmpty) return;
    }
    _flushing = true;
    try {
      final fila = List<ChatInternoPendente>.from(_pendentes);
      for (final p in fila) {
        try {
          final criada = await _enviarConfirmado(p);
          _pendentes = _pendentes.where((e) => e.clientId != p.clientId).toList();
          await ChatInternoOutbox.salvar(_pendentes);
          _aplicarMensagem(criada, tocarSom: false);
        } catch (_) {
          // Mantem na fila; tenta de novo no timer / volta da rede.
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<MensagemInterna> _enviarConfirmado(ChatInternoPendente p) async {
    final api = _apiRepo;
    final local = _localRepo;
    if (local != null && !LanApiEventHub.instance.modoTerminal) {
      final criada = await local.enviar(
        vendedor: p.vendedor,
        texto: p.texto,
        clientId: p.clientId,
        tipo: p.tipo.isEmpty ? kMensagemInternaTipoTexto : p.tipo,
        payload: p.payload.isEmpty ? null : p.payload,
        mencoes: p.mencoes.isEmpty ? null : p.mencoes,
      );
      LanApiServerHub.instance.notificarEvento('novo_recado_chat', {
        'item': criada.toMap(),
        'id': criada.id,
      });
      LanApiServerHub.instance.notificar('chat_interno', ids: [criada.id]);
      return criada;
    }
    if (api != null) {
      return api.enviar(
        vendedor: p.vendedor,
        texto: p.texto,
        clientId: p.clientId,
        tipo: p.tipo,
        payload: p.payload.isEmpty ? null : p.payload,
        mencoes: p.mencoes.isEmpty ? null : p.mencoes,
      );
    }
    if (local != null) {
      final criada = await local.enviar(
        vendedor: p.vendedor,
        texto: p.texto,
        clientId: p.clientId,
        tipo: p.tipo.isEmpty ? kMensagemInternaTipoTexto : p.tipo,
        payload: p.payload.isEmpty ? null : p.payload,
        mencoes: p.mencoes.isEmpty ? null : p.mencoes,
      );
      LanApiServerHub.instance.notificarEvento('novo_recado_chat', {
        'item': criada.toMap(),
        'id': criada.id,
      });
      LanApiServerHub.instance.notificar('chat_interno', ids: [criada.id]);
      return criada;
    }
    throw StateError('Chat interno nao configurado.');
  }

  /// Atalho para montar API a partir do client HTTP.
  static ChatApiRepository? apiDeClient(LanApiClient? client) {
    if (client == null || !client.configurado) return null;
    return ChatApiRepository(client);
  }
}
