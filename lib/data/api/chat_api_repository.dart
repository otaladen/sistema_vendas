import '../../model/mensagem_interna.dart';
import 'lan_api_client.dart';

/// Cache/API do chat interno no Terminal Leve.
class ChatApiRepository {
  ChatApiRepository(this._client);

  final LanApiClient _client;
  List<MensagemInterna> _lista = [];

  List<MensagemInterna> listarHistorico() =>
      List<MensagemInterna>.unmodifiable(_lista);

  Future<List<MensagemInterna>> hidratar() async {
    final items = await _client.chatHistorico();
    _lista = items;
    return listarHistorico();
  }

  Future<MensagemInterna> enviar({
    required String vendedor,
    required String texto,
    String clientId = '',
    String tipo = '',
    Map<String, dynamic>? payload,
    List<String>? mencoes,
  }) async {
    final criada = await _client.chatEnviar(
      vendedor: vendedor,
      texto: texto,
      clientId: clientId,
      tipo: tipo,
      payload: payload,
      mencoes: mencoes,
    );
    aplicarEvento(criada);
    return criada;
  }

  Future<MensagemInterna> responderAutorizacaoPdv({
    required String solicitacaoId,
    required String acao,
    required String login,
    String motivo = '',
  }) async {
    final atualizada = await _client.chatAutorizacaoResponder(
      solicitacaoId: solicitacaoId,
      acao: acao,
      login: login,
      motivo: motivo,
    );
    aplicarEvento(atualizada);
    return atualizada;
  }

  void aplicarEvento(MensagemInterna msg) {
    final idx = _lista.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      _lista[idx] = msg;
    } else {
      _lista = [..._lista, msg];
    }
  }

  void removerIds(Iterable<int> ids) {
    final set = ids.toSet();
    if (set.isEmpty) return;
    _lista = _lista.where((m) => !set.contains(m.id)).toList();
  }

  void aplicarLimpezaNormais() {
    _lista = _lista.where((m) => m.preservarNaRetencao).toList();
  }

  Future<void> apagarMensagem({
    required int id,
    required String login,
    required String nomeOperador,
  }) async {
    await _client.chatApagar(
      id: id,
      login: login,
      nomeOperador: nomeOperador,
    );
    removerIds([id]);
  }

  Future<List<int>> limparMural({required String login}) async {
    final ids = await _client.chatLimparMural(login: login);
    aplicarLimpezaNormais();
    return ids;
  }
}
