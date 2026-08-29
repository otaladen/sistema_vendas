/// Ligacao produto <-> fornecedor a partir de entradas de NF-e (e vinculos).
class FornecedorEntradaNfeLancamento {
  const FornecedorEntradaNfeLancamento({
    required this.produtoId,
    required this.nomeFornecedor,
    required this.data,
  });

  final int produtoId;
  final String nomeFornecedor;
  final DateTime data;
}

class FornecedorEntradaNfeIndice {
  FornecedorEntradaNfeIndice._({
    required this.nomesOrdenados,
    required Map<String, Set<int>> idsPorChave,
    required Map<int, String> ultimoPorProduto,
    required Map<int, List<String>> nomesPorProduto,
  })  : _idsPorChave = idsPorChave,
        _ultimoPorProduto = ultimoPorProduto,
        _nomesPorProduto = nomesPorProduto;

  final List<String> nomesOrdenados;
  final Map<String, Set<int>> _idsPorChave;
  final Map<int, String> _ultimoPorProduto;
  final Map<int, List<String>> _nomesPorProduto;

  static String chave(String nome) => nome.trim().toLowerCase();

  static FornecedorEntradaNfeIndice vazio() => FornecedorEntradaNfeIndice._(
        nomesOrdenados: const [],
        idsPorChave: const {},
        ultimoPorProduto: const {},
        nomesPorProduto: const {},
      );

  factory FornecedorEntradaNfeIndice.deLancamentos(
    Iterable<FornecedorEntradaNfeLancamento> lancamentos,
  ) {
    final idsPorChave = <String, Set<int>>{};
    final displayPorChave = <String, String>{};
    final ultimaDataPorProduto = <int, DateTime>{};
    final ultimoNomePorProduto = <int, String>{};
    final nomesPorProdutoChave = <int, Map<String, String>>{};

    for (final l in lancamentos) {
      final nome = l.nomeFornecedor.trim();
      if (l.produtoId <= 0 || nome.isEmpty) continue;
      final k = chave(nome);
      displayPorChave.putIfAbsent(k, () => nome);
      idsPorChave.putIfAbsent(k, () => <int>{}).add(l.produtoId);
      nomesPorProdutoChave
          .putIfAbsent(l.produtoId, () => <String, String>{})[k] = nome;
      final prev = ultimaDataPorProduto[l.produtoId];
      if (prev == null || l.data.isAfter(prev)) {
        ultimaDataPorProduto[l.produtoId] = l.data;
        ultimoNomePorProduto[l.produtoId] = nome;
      }
    }

    final nomes = displayPorChave.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final nomesPorProduto = <int, List<String>>{};
    for (final e in nomesPorProdutoChave.entries) {
      final lista = e.value.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      nomesPorProduto[e.key] = lista;
    }

    return FornecedorEntradaNfeIndice._(
      nomesOrdenados: nomes,
      idsPorChave: idsPorChave,
      ultimoPorProduto: ultimoNomePorProduto,
      nomesPorProduto: nomesPorProduto,
    );
  }

  Set<int> produtoIdsDe(String nomeFornecedor) {
    final k = chave(nomeFornecedor);
    if (k.isEmpty) return const {};
    return _idsPorChave[k] ?? const {};
  }

  bool produtoDoFornecedor(int produtoId, String nomeFornecedor) {
    return produtoIdsDe(nomeFornecedor).contains(produtoId);
  }

  String? ultimoFornecedorDe(int produtoId) => _ultimoPorProduto[produtoId];

  List<String> fornecedoresDoProduto(int produtoId) =>
      _nomesPorProduto[produtoId] ?? const [];

  Map<String, dynamic> toApiMap() => {
        'items': nomesOrdenados
            .map(
              (n) => {
                'nome': n,
                'produtoIds': produtoIdsDe(n).toList()..sort(),
              },
            )
            .toList(),
      };

  static FornecedorEntradaNfeIndice deApiMap(Map<String, dynamic> m) {
    final list = m['items'];
    if (list is! List) return FornecedorEntradaNfeIndice.vazio();
    final lancamentos = <FornecedorEntradaNfeLancamento>[];
    var ordem = 0;
    for (final raw in list) {
      if (raw is! Map) continue;
      final im = Map<String, dynamic>.from(raw);
      final nome = (im['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final ids = im['produtoIds'];
      if (ids is! List) continue;
      for (final idRaw in ids) {
        final id = (idRaw as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        lancamentos.add(
          FornecedorEntradaNfeLancamento(
            produtoId: id,
            nomeFornecedor: nome,
            data: DateTime.fromMillisecondsSinceEpoch(ordem++, isUtc: true),
          ),
        );
      }
    }
    return FornecedorEntradaNfeIndice.deLancamentos(lancamentos);
  }
}
