/// Origem da mercadoria na expedicao (loja local vs cross-docking).
///
/// Padrao do carreto nesta operacao: a outra loja manda o material.
/// So baixa o fisico daqui quando o item estiver marcado como loja local.
abstract final class LojaOrigemMercadoria {
  LojaOrigemMercadoria._();

  /// Sentinel gravado quando o produto saiu desta loja (baixa fisico).
  static const local = 'loja_atual';

  static const depositoCentral = 'Depósito Central';

  /// Padrao do carreto: outra loja atende; nao baixa a prateleira local.
  static const outraLoja = 'Outra loja';

  /// Resumo no cabecalho da venda quando ha origens diferentes nos itens.
  static const misto = 'Misto';

  static const saidaLojaAtual = 'Desta loja';

  static bool ehLocal(String? origem) {
    final t = (origem ?? '').trim();
    if (t.isEmpty) return false;
    final n = t.toLowerCase();
    return n == local ||
        n == 'local' ||
        n == 'loja atual' ||
        n == 'loja local' ||
        n == 'lojaatual' ||
        n == 'saída da loja atual' ||
        n == 'saida da loja atual' ||
        n == 'desta loja' ||
        n == 'desta loja (baixa estoque)';
  }

  static bool ehMisto(String? origem) =>
      (origem ?? '').trim().toLowerCase() == 'misto';

  static String normalizar(String? origem) {
    if (ehLocal(origem)) return local;
    if (ehMisto(origem)) return misto;
    return outraLoja;
  }

  /// Origem efetiva do item.
  ///
  /// Item vazio: antes da saida = [outraLoja] (padrao carreto).
  /// Depois da saida, item vazio e legado (baixava fisico local).
  static String origemEfetiva({
    required String origemItem,
    required String origemVenda,
    bool cargaSaiu = false,
  }) {
    final raw = (origemItem ?? '').trim();
    if (raw.isEmpty) {
      return cargaSaiu ? local : outraLoja;
    }
    return normalizar(origemItem);
  }

  static String resumo(Iterable<String> origens) {
    final n = origens.map(normalizar).toList();
    if (n.isEmpty) return outraLoja;
    final first = n.first;
    if (n.every((e) => e == first)) return first;
    return misto;
  }

  static String rotulo(String? origem, {String nomeLojaAtual = ''}) {
    if (ehMisto(origem)) {
      return 'Misto (desta loja + outra loja)';
    }
    if (ehLocal(origem)) {
      final n = nomeLojaAtual.trim();
      return n.isEmpty ? 'Desta loja (baixa estoque)' : 'Desta loja ($n)';
    }
    return 'Outra loja (sem baixa)';
  }

  static String rotuloCaixa(String? origem) {
    if (ehMisto(origem)) return misto;
    if (ehLocal(origem)) return saidaLojaAtual;
    return 'Outra loja (sem baixa)';
  }

  static String motivoKardex({
    required String origem,
    required int vendaId,
    int numeroOrcamento = 0,
  }) {
    final n = numeroOrcamento > 0 ? numeroOrcamento : vendaId;
    if (ehLocal(origem)) {
      return 'Saida carreto (desta loja) - Venda #$n';
    }
    if (ehMisto(origem)) {
      return 'Saida carreto (misto: desta loja + outra loja) - Venda #$n';
    }
    return 'Entrega Efetuada via Transferência - Venda #$n';
  }

  static List<String> opcoesPadrao({
    String nomeLojaAtual = '',
    List<String> extras = const [],
  }) {
    final visto = <String>{};
    final out = <String>[];
    void add(String raw) {
      final n = normalizar(raw);
      if (n.isEmpty || ehMisto(n) || ehLocal(n)) return;
      final key = n.toLowerCase();
      if (visto.contains(key)) return;
      visto.add(key);
      out.add(n);
    }

    for (final e in extras) {
      add(e);
    }
    final loja = nomeLojaAtual.trim();
    if (loja.isNotEmpty) {
      out.removeWhere((e) => e.toLowerCase() == loja.toLowerCase());
    }
    return out;
  }

  static Map<int, String> mapOrigemItensDeJson(dynamic raw) {
    if (raw is! Map) return {};
    final out = <int, String>{};
    raw.forEach((k, v) {
      final id = int.tryParse(k.toString()) ?? 0;
      if (id <= 0) return;
      out[id] = normalizar(v?.toString());
    });
    return out;
  }

  static Map<String, String> mapOrigemItensParaJson(Map<int, String> origens) {
    return {
      for (final e in origens.entries) '${e.key}': normalizar(e.value),
    };
  }
}
