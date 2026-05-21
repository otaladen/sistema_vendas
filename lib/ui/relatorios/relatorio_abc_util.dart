/// Item classificado na curva ABC (regra 80/15/5 acumulado em valor).
class RelatorioAbcItem {
  RelatorioAbcItem({
    required this.chave,
    required this.nome,
    required this.valor,
    required this.participacaoPct,
    required this.acumuladoPct,
    required this.classe,
    this.detalheExtra = '',
  });

  final String chave;
  final String nome;
  final double valor;
  final double participacaoPct;
  final double acumuladoPct;
  final String classe;
  final String detalheExtra;
}

List<RelatorioAbcItem> relatorioClassificarAbc({
  required List<({String chave, String nome, double valor, String detalheExtra})> itens,
}) {
  if (itens.isEmpty) return [];
  final ordenado = List<({String chave, String nome, double valor, String detalheExtra})>.from(
    itens,
  )..sort((a, b) => b.valor.compareTo(a.valor));
  final total = ordenado.fold<double>(0, (s, e) => s + e.valor);
  if (total <= 0) return [];

  var acum = 0.0;
  final saida = <RelatorioAbcItem>[];
  for (final e in ordenado) {
    if (e.valor <= 0) continue;
    final part = e.valor / total * 100;
    acum += part;
    final classe = acum <= 80
        ? 'A'
        : acum <= 95
            ? 'B'
            : 'C';
    saida.add(
      RelatorioAbcItem(
        chave: e.chave,
        nome: e.nome,
        valor: e.valor,
        participacaoPct: part,
        acumuladoPct: acum,
        classe: classe,
        detalheExtra: e.detalheExtra,
      ),
    );
  }
  return saida;
}
