/// Resultado de uma pagina do pull LAN (testavel sem HTTP).
class SyncPullPage {
  const SyncPullPage({
    required this.changes,
    required this.lastRevision,
    required this.hasMore,
  });

  final List<dynamic> changes;
  final int lastRevision;
  final bool hasMore;
}

/// Aplica paginas do pull ate [hasMore] ser falso ou [maxPaginas] (se informado).
Future<int> executarPullCatchup({
  required int sinceInicial,
  required Future<SyncPullPage> Function(int since) buscarPagina,
  required Future<void> Function(List<dynamic> changes) aplicarAlteracoes,
  required Future<void> Function(int revision) salvarRevision,
  int? maxPaginas,
  void Function(SyncPullCatchupProgresso progresso)? onProgresso,
  Duration delayEntrePaginas = const Duration(milliseconds: 50),
}) async {
  var since = sinceInicial;
  var paginas = 0;
  var registrosAcumulados = 0;
  while (true) {
    final pagina = await buscarPagina(since);
    paginas++;
    final n = pagina.changes.length;
    if (pagina.changes.isNotEmpty) {
      await aplicarAlteracoes(pagina.changes);
      registrosAcumulados += n;
    }
    if (pagina.lastRevision > since) {
      await salvarRevision(pagina.lastRevision);
      since = pagina.lastRevision;
    }
    onProgresso?.call(
      SyncPullCatchupProgresso(
        pagina: paginas,
        registrosPagina: n,
        registrosAcumulados: registrosAcumulados,
        revision: since,
        hasMore: pagina.hasMore,
      ),
    );
    if (!pagina.hasMore) break;
    if (maxPaginas != null && paginas >= maxPaginas) break;
    if (delayEntrePaginas > Duration.zero) {
      await Future<void>.delayed(delayEntrePaginas);
    }
  }
  return since;
}

/// Snapshot de progresso entre paginas do pull.
class SyncPullCatchupProgresso {
  const SyncPullCatchupProgresso({
    required this.pagina,
    required this.registrosPagina,
    required this.registrosAcumulados,
    required this.revision,
    required this.hasMore,
  });

  final int pagina;
  final int registrosPagina;
  final int registrosAcumulados;
  final int revision;
  final bool hasMore;
}
