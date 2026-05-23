import '../model/conferencia_carga_romaneio.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class ConferenciaCargaRepository {
  ConferenciaCargaRepository(this._db);

  final ObjectBox _db;

  Map<String, bool> mapaPorEscopo(String escopoViagem) {
    final escopo = escopoViagem.trim();
    if (escopo.isEmpty) return {};
    final q = _db.conferenciaCargaRomaneioBox
        .query(ConferenciaCargaRomaneio_.escopoViagem.equals(escopo))
        .build();
    try {
      final map = <String, bool>{};
      for (final e in q.find()) {
        map[e.chaveProduto] = e.conferido;
      }
      return map;
    } finally {
      q.close();
    }
  }

  void salvarConferencia({
    required String escopoViagem,
    required String chaveProduto,
    required bool conferido,
    String usuarioLogin = '',
  }) {
    final escopo = escopoViagem.trim();
    final chave = chaveProduto.trim();
    if (escopo.isEmpty || chave.isEmpty) return;

    final q = _db.conferenciaCargaRomaneioBox
        .query(
          ConferenciaCargaRomaneio_.escopoViagem
              .equals(escopo)
              .and(ConferenciaCargaRomaneio_.chaveProduto.equals(chave)),
        )
        .build();
    try {
      final existente = q.findFirst();
      final agora = DateTime.now();
      if (existente != null) {
        existente.conferido = conferido;
        existente.usuarioLogin = usuarioLogin.trim();
        existente.atualizadoEm = agora;
        _db.conferenciaCargaRomaneioBox.put(existente);
      } else {
        _db.conferenciaCargaRomaneioBox.put(
          ConferenciaCargaRomaneio(
            escopoViagem: escopo,
            chaveProduto: chave,
            conferido: conferido,
            usuarioLogin: usuarioLogin.trim(),
            atualizadoEm: agora,
          ),
        );
      }
    } finally {
      q.close();
    }
    notificarAlteracaoParaRede();
  }

  int contarConferidos(String escopoViagem, Iterable<String> chavesProduto) {
    final mapa = mapaPorEscopo(escopoViagem);
    var n = 0;
    for (final c in chavesProduto) {
      if (mapa[c] == true) n++;
    }
    return n;
  }
}
