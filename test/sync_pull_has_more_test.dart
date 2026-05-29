import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_pull_catchup.dart';

void main() {
  test('executarPullCatchup percorre todas as paginas ate hasMore false', () async {
    var since = 0;
    final revisionsSalvas = <int>[];
    final paginasAplicadas = <int>[];

    final sinceFinal = await executarPullCatchup(
      sinceInicial: since,
      buscarPagina: (atual) async {
        if (atual == 0) {
          return const SyncPullPage(
            changes: [{'entity': 'produto', 'id': 1}],
            lastRevision: 100,
            hasMore: true,
          );
        }
        if (atual == 100) {
          return const SyncPullPage(
            changes: [{'entity': 'cliente', 'id': 2}],
            lastRevision: 250,
            hasMore: false,
          );
        }
        fail('since inesperado: $atual');
      },
      aplicarAlteracoes: (changes) async {
        paginasAplicadas.add(changes.length);
      },
      salvarRevision: (revision) async {
        revisionsSalvas.add(revision);
        since = revision;
      },
    );

    expect(sinceFinal, 250);
    expect(revisionsSalvas, [100, 250]);
    expect(paginasAplicadas, [1, 1]);
  });

  test('executarPullCatchup nao faz push quando nao ha alteracoes', () async {
    var buscas = 0;
    final sinceFinal = await executarPullCatchup(
      sinceInicial: 10,
      buscarPagina: (_) async {
        buscas++;
        return const SyncPullPage(
          changes: [],
          lastRevision: 10,
          hasMore: false,
        );
      },
      aplicarAlteracoes: (_) async {
        fail('nao deveria aplicar alteracoes');
      },
      salvarRevision: (_) async {
        fail('nao deveria salvar revision');
      },
    );

    expect(buscas, 1);
    expect(sinceFinal, 10);
  });
}
