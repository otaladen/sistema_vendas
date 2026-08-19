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
  }) async {
    final criada = await _client.chatEnviar(
      vendedor: vendedor,
      texto: texto,
      clientId: clientId,
    );
    final idx = _lista.indexWhere((m) => m.id == criada.id);
    if (idx >= 0) {
      _lista[idx] = criada;
    } else {
      _lista = [..._lista, criada];
    }
    return criada;
  }

  void aplicarEvento(MensagemInterna msg) {
    final idx = _lista.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      _lista[idx] = msg;
    } else {
      _lista = [..._lista, msg];
    }
  }
}
