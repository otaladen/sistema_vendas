/// Tabelas de preco do PDV (preco 1, preco 2, preco 3).
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

  static String rotulo(String precoTipo) {
    switch (normalizar(precoTipo)) {
      case 'preco2':
        return 'Preco 2';
      case 'preco3':
        return 'Preco 3';
      default:
        return 'Preco 1';
    }
  }

  static String rotuloCurto(String precoTipo) {
    switch (normalizar(precoTipo)) {
      case 'preco2':
        return 'P2';
      case 'preco3':
        return 'P3';
      default:
        return 'P1';
    }
  }

  static Set<String> tabelasDistintas(Iterable<String> precoTipos) =>
      precoTipos.map(normalizar).toSet();

  static bool carrinhoMisto(Iterable<String> precoTipos) =>
      tabelasDistintas(precoTipos).length > 1;
}
