import '../model/venda.dart';

/// Remove vendas repetidas na Listagem de Vendas (mesmo `id`, Controle ou NFC-e).
///
/// Cobre tres origens comuns de duplicata:
/// - a mesma entidade aparece mais de uma vez no payload (JOIN / cache);
/// - dois registros locais com o mesmo [Venda.numeroControle];
/// - varios historicos fiscais (mesmo numero/chave de NFC-e) para a mesma venda.
abstract final class ListagemVendasDedupe {
  ListagemVendasDedupe._();

  static List<Venda> sanitizar(Iterable<Venda> vendas) {
    final lista = vendas.toList();
    if (lista.length <= 1) return lista;

    final vencedores = <Venda>[];
    final indiceVencedor = <int>[];

    for (var i = 0; i < lista.length; i++) {
      final candidata = lista[i];
      final conflito = _indiceConflito(vencedores, candidata);
      if (conflito < 0) {
        vencedores.add(candidata);
        indiceVencedor.add(i);
        continue;
      }
      if (_preferir(candidata, vencedores[conflito])) {
        vencedores[conflito] = candidata;
        indiceVencedor[conflito] = i;
      }
    }

    if (vencedores.length == lista.length) return lista;

    final ordem = List<int>.generate(vencedores.length, (i) => i)
      ..sort((a, b) => indiceVencedor[a].compareTo(indiceVencedor[b]));
    return [for (final i in ordem) vencedores[i]];
  }

  static int _indiceConflito(List<Venda> atuais, Venda candidata) {
    for (var i = 0; i < atuais.length; i++) {
      if (_mesmoRegistroListagem(atuais[i], candidata)) return i;
    }
    return -1;
  }

  /// Mesmo id, mesmo Controle ou mesma NFC-e (numero/chave).
  static bool _mesmoRegistroListagem(Venda a, Venda b) {
    if (identical(a, b)) return true;
    if (a.id > 0 && a.id == b.id) return true;

    final controleA = a.numeroControle;
    final controleB = b.numeroControle;
    if (controleA > 0 && controleA == controleB) return true;

    final chaveA = a.nfceChaveAcesso.trim();
    final chaveB = b.nfceChaveAcesso.trim();
    if (chaveA.length >= 40 && chaveA == chaveB) return true;

    final numeroA = _numeroNfceNormalizado(a.nfceNumero);
    final numeroB = _numeroNfceNormalizado(b.nfceNumero);
    if (numeroA.isNotEmpty && numeroA == numeroB) {
      final serieA = a.nfceSerie.trim();
      final serieB = b.nfceSerie.trim();
      if (serieA.isEmpty || serieB.isEmpty || serieA == serieB) return true;
    }

    return false;
  }

  static String _numeroNfceNormalizado(String bruto) {
    return bruto.replaceAll(RegExp(r'\D'), '');
  }

  /// Prefere a linha com NFC-e autorizada / mais completa; empate fica com o id menor.
  static bool _preferir(Venda candidata, Venda atual) {
    final scoreC = _scoreFiscal(candidata);
    final scoreA = _scoreFiscal(atual);
    if (scoreC != scoreA) return scoreC > scoreA;
    if (candidata.id > 0 && atual.id > 0 && candidata.id != atual.id) {
      return candidata.id < atual.id;
    }
    return false;
  }

  static int _scoreFiscal(Venda v) {
    var s = 0;
    if (v.nfceAutorizadaAtiva) s += 100;
    if (v.nfceChaveAcesso.trim().length >= 40) s += 20;
    if (_numeroNfceNormalizado(v.nfceNumero).isNotEmpty) s += 10;
    if (v.nfceProtocolo.trim().isNotEmpty) s += 5;
    if (!v.cancelada) s += 2;
    return s;
  }
}
