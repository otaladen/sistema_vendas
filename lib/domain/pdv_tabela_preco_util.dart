/// Tabelas de preco do PDV (preco1 prazo, preco2 vista, preco3 especial).
abstract final class PdvTabelaPrecoUtil {
  PdvTabelaPrecoUtil._();

  static String normalizar(String? valor) {
    switch (valor) {
      case 'preco2':
      case 'preco3':
        return valor!;
      case 'preco1':
      default:
        return 'preco1';
    }
  }

  static String proxima(String atual) {
    switch (normalizar(atual)) {
      case 'preco1':
        return 'preco2';
      case 'preco2':
        return 'preco3';
      default:
        return 'preco1';
    }
  }

  static String rotuloCurto(String precoTipo) {
    switch (normalizar(precoTipo)) {
      case 'preco2':
        return 'Vista';
      case 'preco3':
        return 'Especial';
      default:
        return 'Prazo';
    }
  }

  static Set<String> tabelasDistintas(Iterable<String> precoTipos) =>
      precoTipos.map(normalizar).toSet();

  static bool carrinhoMisto(Iterable<String> precoTipos) =>
      tabelasDistintas(precoTipos).length > 1;

  /// Uniao ordenada dos meios permitidos para cada tabela presente no carrinho.
  static List<String> meiosPagamentoUniao(
    Iterable<String> tabelasNoCarrinho,
    Map<String, List<String>> meiosPorTabela,
    List<String> ordemPreferida,
  ) {
    final permitidos = <String>{};
    final tabelas = tabelasNoCarrinho.map(normalizar).toSet();
    if (tabelas.isEmpty) {
      permitidos.addAll(meiosPorTabela['preco1'] ?? const []);
    } else {
      for (final t in tabelas) {
        permitidos.addAll(meiosPorTabela[t] ?? meiosPorTabela['preco1']!);
      }
    }
    final resultado = <String>[];
    for (final id in ordemPreferida) {
      if (permitidos.contains(id)) resultado.add(id);
    }
    for (final id in permitidos) {
      if (!resultado.contains(id)) resultado.add(id);
    }
    return resultado;
  }
}
