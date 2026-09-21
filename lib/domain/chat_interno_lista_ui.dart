import 'package:intl/intl.dart';

import '../model/mensagem_interna.dart';

sealed class ChatInternoItemLista {
  const ChatInternoItemLista();
}

final class ChatInternoSeparadorData extends ChatInternoItemLista {
  const ChatInternoSeparadorData(this.rotulo);

  final String rotulo;
}

final class ChatInternoLinhaMensagem extends ChatInternoItemLista {
  const ChatInternoLinhaMensagem(this.mensagem);

  final MensagemInterna mensagem;
}

abstract final class ChatInternoListaUi {
  ChatInternoListaUi._();

  static String rotuloDataLocal(DateTime dataHoraUtc) {
    final local = dataHoraUtc.toLocal();
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(local.year, local.month, local.day);
    if (dia == hoje) return 'Hoje';
    if (dia == hoje.subtract(const Duration(days: 1))) return 'Ontem';
    return DateFormat('dd/MM/yyyy').format(local);
  }

  static List<ChatInternoItemLista> montar(List<MensagemInterna> mensagens) {
    if (mensagens.isEmpty) return const [];
    final out = <ChatInternoItemLista>[];
    String? ultimaData;
    for (final m in mensagens) {
      final rotulo = rotuloDataLocal(m.dataHora);
      if (rotulo != ultimaData) {
        out.add(ChatInternoSeparadorData(rotulo));
        ultimaData = rotulo;
      }
      out.add(ChatInternoLinhaMensagem(m));
    }
    return out;
  }
}
