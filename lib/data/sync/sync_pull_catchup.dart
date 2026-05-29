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

/// Aplica todas as paginas do pull ate [hasMore] ser falso.
Future<int> executarPullCatchup({
  required int sinceInicial,
  required Future<SyncPullPage> Function(int since) buscarPagina,
  required Future<void> Function(List<dynamic> changes) aplicarAlteracoes,
  required Future<void> Function(int revision) salvarRevision,
}) async {
  var since = sinceInicial;
  while (true) {
    final pagina = await buscarPagina(since);
    if (pagina.changes.isNotEmpty) {
      await aplicarAlteracoes(pagina.changes);
    }
    if (pagina.lastRevision > since) {
      await salvarRevision(pagina.lastRevision);
      since = pagina.lastRevision;
    }
    if (!pagina.hasMore) break;
  }
  return since;
}
