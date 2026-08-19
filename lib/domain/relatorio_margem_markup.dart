/// Linha de margem bruta / markup (produto ou categoria).
class RelatorioMargemLinha {
  RelatorioMargemLinha({
    required this.chave,
    required this.nome,
    this.produtoId = 0,
  });

  final String chave;
  final String nome;
  final int produtoId;
  double receita = 0;
  double cmv = 0;

  double get lucro => receita - cmv;

  double get margemPct =>
      receita.abs() < 0.01 ? 0 : (lucro / receita) * 100;

  double get markup => cmv <= 0.01 ? 0 : (receita / cmv) - 1;

  double get markupPct => markup * 100;
}

/// Agrega receita liquida, CMV e markup a partir de linhas ja normalizadas.
abstract final class RelatorioMargemMarkup {
  RelatorioMargemMarkup._();

  static RelatorioMargemLinha acumular(
    Map<String, RelatorioMargemLinha> map, {
    required String chave,
    required String nome,
    int produtoId = 0,
    required double receita,
    required double cmv,
  }) {
    final cur = map.putIfAbsent(
      chave,
      () => RelatorioMargemLinha(
        chave: chave,
        nome: nome,
        produtoId: produtoId,
      ),
    );
    cur.receita += receita;
    cur.cmv += cmv;
    return cur;
  }

  static List<RelatorioMargemLinha> ordenarPorLucro(
    Iterable<RelatorioMargemLinha> linhas,
  ) {
    final lista = linhas.where((l) => l.receita.abs() >= 0.01).toList()
      ..sort((a, b) => b.lucro.compareTo(a.lucro));
    return lista;
  }
}
