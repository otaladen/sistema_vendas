import '../model/conferencia_carga_romaneio.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Conferencia de carga no patio / romaneio.
///
/// Concorrencia: [ConferenciaCargaRomaneio.atualizadoEm] e a versao do registro.
/// Gravacao local e sync LAN so substituem um registro existente quando o evento
/// e mais recente ou igual (LWW por timestamp UTC).
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

    _db.store.runInTransaction(TxMode.write, () {
      _gravarConferencia(
        escopo: escopo,
        chave: chave,
        conferido: conferido,
        usuarioLogin: usuarioLogin.trim(),
        atualizadoEm: DateTime.now().toUtc(),
        substituirSeMaisRecente: true,
      );
    });
    notificarAlteracaoParaRede(
      entidade: 'conferencia_carga_romaneio',
      entidadeId: 0,
    );
  }

  /// Aplica payload de sync; ignora eventos mais antigos que o registro local.
  void aplicarConferenciaSync(Map<String, dynamic> payload) {
    final remoto = _conferenciaDeMap(payload);
    final escopo = remoto.escopoViagem.trim();
    final chave = remoto.chaveProduto.trim();
    if (escopo.isEmpty || chave.isEmpty) return;

    _db.store.runInTransaction(TxMode.write, () {
      _gravarConferencia(
        escopo: escopo,
        chave: chave,
        conferido: remoto.conferido,
        usuarioLogin: remoto.usuarioLogin,
        atualizadoEm: remoto.atualizadoEm.toUtc(),
        substituirSeMaisRecente: false,
      );
    });
  }

  void _gravarConferencia({
    required String escopo,
    required String chave,
    required bool conferido,
    required String usuarioLogin,
    required DateTime atualizadoEm,
    required bool substituirSeMaisRecente,
  }) {
    final q = _db.conferenciaCargaRomaneioBox
        .query(
          ConferenciaCargaRomaneio_.escopoViagem
              .equals(escopo)
              .and(ConferenciaCargaRomaneio_.chaveProduto.equals(chave)),
        )
        .build();
    try {
      final existente = q.findFirst();
      if (existente != null) {
        if (!substituirSeMaisRecente &&
            atualizadoEm.isBefore(existente.atualizadoEm.toUtc())) {
          return;
        }
        if (substituirSeMaisRecente ||
            !atualizadoEm.isBefore(existente.atualizadoEm.toUtc())) {
          existente.conferido = conferido;
          existente.usuarioLogin = usuarioLogin;
          existente.atualizadoEm = atualizadoEm;
          _db.conferenciaCargaRomaneioBox.put(existente);
        }
      } else {
        _db.conferenciaCargaRomaneioBox.put(
          ConferenciaCargaRomaneio(
            escopoViagem: escopo,
            chaveProduto: chave,
            conferido: conferido,
            usuarioLogin: usuarioLogin,
            atualizadoEm: atualizadoEm,
          ),
        );
      }
    } finally {
      q.close();
    }
  }

  ConferenciaCargaRomaneio _conferenciaDeMap(Map<String, dynamic> m) {
    return ConferenciaCargaRomaneio(
      id: (m['id'] as num?)?.toInt() ?? 0,
      escopoViagem: (m['escopoViagem'] ?? '').toString(),
      chaveProduto: (m['chaveProduto'] ?? '').toString(),
      conferido: m['conferido'] == true,
      usuarioLogin: (m['usuarioLogin'] ?? '').toString(),
      atualizadoEm:
          DateTime.tryParse((m['atualizadoEm'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
    );
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
