/// Criterio de ordenacao da lista de vendas finalizadas no caixa.
enum UltimasVendasFinalizadasOrdenacao {
  /// Ordem real do fechamento no caixa ([Venda.finalizadaEm]).
  porFinalizacao('finalizacao', 'Finalizacao caixa'),

  /// Maior numero de controle / orcamento primeiro.
  porControle('controle', 'N. controle');

  const UltimasVendasFinalizadasOrdenacao(this.chave, this.rotuloCurto);

  static const UltimasVendasFinalizadasOrdenacao padrao =
      UltimasVendasFinalizadasOrdenacao.porFinalizacao;

  final String chave;
  final String rotuloCurto;

  String get rotuloMenu =>
      this == padrao ? '$rotuloCurto (padrao)' : rotuloCurto;

  static UltimasVendasFinalizadasOrdenacao? fromChave(String? chave) {
    if (chave == null || chave.trim().isEmpty) return null;
    for (final o in values) {
      if (o.chave == chave) return o;
    }
    return null;
  }
}
