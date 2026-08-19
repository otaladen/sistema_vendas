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
import '../../../domain/chat_interno_parser.dart';
import '../../../model/mensagem_interna.dart';
import '../../../services/lan_api_server.dart';

/// Estado global do chat/mural interno (badge + lista + som + fila).
class ChatInternoHub extends ChangeNotifier {
  ChatInternoHub._();
  static final instance = ChatInternoHub._();

  MensagemInternaRepository? _localRepo;
  ChatApiRepository? _apiRepo;
  String _autorPadrao = '';
  String _perfilUsuario = '';
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
  bool get painelAberto => _painelAberto;
  int get ultimoIdVisto => _ultimoIdVisto;
  bool get temPendentes => _pendentes.isNotEmpty;

  void configurar({
    MensagemInternaRepository? localRepo,
    ChatApiRepository? apiRepo,
    required String autorPadrao,
    String perfilUsuario = '',
  }) {
    _localRepo = localRepo;
    _apiRepo = apiRepo;
    _autorPadrao = autorPadrao.trim();
    _perfilUsuario = perfilUsuario.trim();
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
    if (type != 'novo_recado_chat') return;
    final itemRaw = payload['item'];
    if (itemRaw is Map) {
      final msg = MensagemInterna.fromMap(
        Map<String, dynamic>.from(itemRaw),
      );
      _aplicarMensagem(msg, tocarSom: !_painelAberto);
    } else {
      unawaited(carregarHistorico(tocarSomSeNovo: !_painelAberto));
    }
  }

  void _onWs() {
    final online = LanApiEventHub.instance.online;
    if (online && !_onlineAntes) {
      unawaited(carregarHistorico(tocarSomSeNovo: !_painelAberto));
      unawaited(flushOutbox());
    }
    _onlineAntes = online;

    final tipo = LanApiEventHub.instance.ultimoEventoTipo;
    if (tipo == 'novo_recado_chat') {
      final payload = LanApiEventHub.instance.ultimoEventoPayload;
      final itemRaw = payload?['item'];
      if (itemRaw is Map) {
        final msg = MensagemInterna.fromMap(
          Map<String, dynamic>.from(itemRaw),
        );
        _aplicarMensagem(msg, tocarSom: !_painelAberto);
      } else {
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
    return MensagemInterna(
      id: 0,
      vendedor: p.vendedor,
      texto: p.texto,
      dataHora: p.criadoEm,
      clientId: p.clientId,
      pedidoNumero: parsed.pedidoNumero ?? 0,
      mencoes: parsed.mencoes.toList(),
      pendenteLocal: true,
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
      );
    }
    if (local != null) {
      final criada = await local.enviar(
        vendedor: p.vendedor,
        texto: p.texto,
        clientId: p.clientId,
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
