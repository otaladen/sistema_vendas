/// Revisao monotona do catalogo de produtos no PC servidor (LanApi).
///
/// Incrementada a cada mudanca de estoque/cadastro notificada aos terminais.
/// O Terminal Leve compara com a revisao local para decidir se precisa hidratar.
abstract final class CatalogoProdutoRevision {
  CatalogoProdutoRevision._();

  static int _revisao = 0;
  static DateTime _atualizadoEm = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static int get revisao => _revisao;

  static DateTime get atualizadoEm => _atualizadoEm;

  static int bump() {
    _revisao += 1;
    _atualizadoEm = DateTime.now().toUtc();
    return _revisao;
  }

  static Map<String, dynamic> paraMap({required int quantidadeProdutos}) => {
        'revision': _revisao,
        'atualizadoEm': _atualizadoEm.toIso8601String(),
        'count': quantidadeProdutos,
      };
}
