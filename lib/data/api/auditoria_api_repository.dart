import '../auditoria_repository.dart';
import '../sync/sync_entity_codec_operacional.dart';
import '../../model/auditoria_evento.dart';
import 'lan_api_client.dart';

/// Auditoria central via API (cache em memoria para relatorios).
class AuditoriaApiRepository {
  AuditoriaApiRepository(this._client);

  final LanApiClient _client;
  List<AuditoriaEvento> _eventos = [];
  int _total = 0;

  Future<void> hidratar({
    DateTime? desde,
    DateTime? ate,
    int limit = 5000,
  }) async {
    final raw = await _client.listarAuditoria(
      desde: desde,
      ate: ate,
      limit: limit,
    );
    _eventos = raw
        .map(SyncEntityCodecOperacional.auditoriaEventoDeMap)
        .toList(growable: false);
    _total = _eventos.length;
  }

  List<AuditoriaEvento> listar({AuditoriaFiltro filtro = const AuditoriaFiltro()}) {
    Iterable<AuditoriaEvento> it = _eventos;
    final inicio = filtro.inicio;
    final fim = filtro.fim;
    if (inicio != null) {
      it = it.where((e) => !e.dataHora.isBefore(inicio.toUtc()));
    }
    if (fim != null) {
      final fimUtc = DateTime(
        fim.year,
        fim.month,
        fim.day,
        23,
        59,
        59,
        999,
      ).toUtc();
      it = it.where((e) => !e.dataHora.isAfter(fimUtc));
    }
    final modulo = filtro.modulo?.trim();
    if (modulo != null && modulo.isNotEmpty) {
      it = it.where((e) => e.modulo == modulo);
    }
    final usuario = filtro.usuarioLogin?.trim();
    if (usuario != null && usuario.isNotEmpty) {
      it = it.where((e) => e.usuarioLogin == usuario);
    }
    final termo = filtro.termoBusca?.trim().toLowerCase();
    if (termo != null && termo.isNotEmpty) {
      it = it.where((e) {
        return e.resumo.toLowerCase().contains(termo) ||
            e.acao.toLowerCase().contains(termo) ||
            e.entidade.toLowerCase().contains(termo) ||
            e.detalhesJson.toLowerCase().contains(termo);
      });
    }
    final lista = it.toList()
      ..sort((a, b) => b.dataHora.compareTo(a.dataHora));
    if (lista.length > filtro.limite) {
      return lista.take(filtro.limite).toList(growable: false);
    }
    return lista;
  }

  List<String> listarUsuariosDistintos() {
    final set = <String>{};
    for (final e in _eventos) {
      final u = e.usuarioLogin.trim();
      if (u.isNotEmpty) set.add(u);
    }
    final lista = set.toList()..sort();
    return lista;
  }

  int contarTotal() => _total;
}
