import '../model/venda.dart';

/// Hidratacao LAN: nunca corta entrega aberta; o limit so vale para ja entregues.
abstract final class EntregaListaApi {
  EntregaListaApi._();

  static const statusesAbertos = {
    'pendente',
    'roteirizada',
    'saiu_entrega',
    'entregue_complemento_pendente',
    'reagendada',
  };

  static bool estaAberta(String statusEntrega) =>
      statusesAbertos.contains(statusEntrega.trim());

  static List<Venda> priorizarParaHidratacao(
    List<Venda> todas, {
    int limitEntregues = 500,
  }) {
    final abertas = <Venda>[];
    final entregues = <Venda>[];
    for (final v in todas) {
      if (v.statusEntrega == 'entregue') {
        entregues.add(v);
      } else {
        abertas.add(v);
      }
    }
    abertas.sort(_porAgendaDepoisVenda);
    entregues.sort((a, b) => b.data.compareTo(a.data));
    final cap = limitEntregues < 0 ? 0 : limitEntregues;
    return [...abertas, ...entregues.take(cap)];
  }

  static int _porAgendaDepoisVenda(Venda a, Venda b) {
    final ma = a.dataEntregaMarcada;
    final mb = b.dataEntregaMarcada;
    if (ma == null && mb != null) return 1;
    if (ma != null && mb == null) return -1;
    if (ma != null && mb != null) {
      final c = ma.compareTo(mb);
      if (c != 0) return c;
    }
    return b.data.compareTo(a.data);
  }
}
