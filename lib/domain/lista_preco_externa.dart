/// Item de tabela de precos de loja concorrente (ex.: Comprou Levou / Itinga).
class ItemListaPrecoExterna {
  const ItemListaPrecoExterna({
    required this.codigo,
    required this.nome,
    required this.preco,
  });

  final String codigo;
  final String nome;
  final double preco;

  String get nomeBusca =>
      '$codigo ${normalizarBusca(nome)}'.toLowerCase();

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        'nome': nome,
        'preco': preco,
      };

  factory ItemListaPrecoExterna.fromJson(Map<String, dynamic> m) {
    return ItemListaPrecoExterna(
      codigo: (m['codigo'] ?? '').toString(),
      nome: (m['nome'] ?? '').toString(),
      preco: (m['preco'] as num?)?.toDouble() ?? 0,
    );
  }

  static String normalizarBusca(String raw) {
    var s = raw.toLowerCase().trim();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'ê': 'e',
      'è': 'e',
      'í': 'i',
      'ì': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    for (final e in mapa.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }
}

/// Lista importada (uma importacao = um PDF).
class ListaPrecoExterna {
  ListaPrecoExterna({
    required this.id,
    required this.nomeLoja,
    required this.dataLista,
    required this.importadoEm,
    required this.arquivoOrigem,
    required this.itens,
    this.linhasIgnoradas = 0,
  });

  final String id;
  final String nomeLoja;
  final DateTime dataLista;
  final DateTime importadoEm;
  final String arquivoOrigem;
  final List<ItemListaPrecoExterna> itens;
  final int linhasIgnoradas;

  int get quantidade => itens.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nomeLoja': nomeLoja,
        'dataLista': dataLista.toIso8601String(),
        'importadoEm': importadoEm.toIso8601String(),
        'arquivoOrigem': arquivoOrigem,
        'linhasIgnoradas': linhasIgnoradas,
        'itens': itens.map((e) => e.toJson()).toList(),
      };

  factory ListaPrecoExterna.fromJson(Map<String, dynamic> m) {
    final rawItens = m['itens'];
    final itens = <ItemListaPrecoExterna>[];
    if (rawItens is List) {
      for (final e in rawItens) {
        if (e is Map) {
          itens.add(
            ItemListaPrecoExterna.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return ListaPrecoExterna(
      id: (m['id'] ?? '').toString(),
      nomeLoja: (m['nomeLoja'] ?? 'Lista externa').toString(),
      dataLista: DateTime.tryParse((m['dataLista'] ?? '').toString()) ??
          DateTime.now(),
      importadoEm: DateTime.tryParse((m['importadoEm'] ?? '').toString()) ??
          DateTime.now(),
      arquivoOrigem: (m['arquivoOrigem'] ?? '').toString(),
      linhasIgnoradas: (m['linhasIgnoradas'] as num?)?.toInt() ?? 0,
      itens: itens,
    );
  }

  /// Busca por codigo ou trechos do nome (AND entre palavras).
  List<ItemListaPrecoExterna> buscar(String termo, {int limite = 200}) {
    final t = ItemListaPrecoExterna.normalizarBusca(termo);
    if (t.isEmpty) {
      return itens.take(limite).toList(growable: false);
    }
    final palavras = t.split(' ').where((p) => p.isNotEmpty).toList();
    final out = <ItemListaPrecoExterna>[];
    for (final item in itens) {
      final alvo = item.nomeBusca;
      var ok = true;
      for (final p in palavras) {
        if (!alvo.contains(p)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        out.add(item);
        if (out.length >= limite) break;
      }
    }
    return out;
  }
}
