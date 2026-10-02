/// Unidades de medida permitidas no cadastro, NF-e e PDV.
abstract final class ProdutoUnidadesCatalogo {
  ProdutoUnidadesCatalogo._();

  static const List<String> unidadesVenda = [
    'UN',
    'PC',
    'PAR',
    'M',
    'MTS',
    'M2',
    'M3',
    'KG',
    'G',
    'TON',
    'LT',
    'ML',
    'SC',
    'CX',
    'FD',
    'RL',
    'PCT',
    'DZ',
  ];

  /// Mesma lista usada na conferencia de entrada (unidade interna).
  static const List<String> unidadesInternasValidas = unidadesVenda;

  /// Embalagens comuns na unidade de compra (NF-e / fator de conversao).
  static const List<String> unidadesCompraSugeridas = [
    'CX',
    'SC',
    'FD',
    'RL',
    'PCT',
    'DZ',
    'UN',
    'PC',
    'KG',
    'G',
    'TON',
    'LT',
    'ML',
    'M',
    'MTS',
    'M2',
    'M3',
  ];

  static const Map<String, String> rotuloLongo = {
    'UN': 'UN - Unidade',
    'PC': 'PC - Peca',
    'PAR': 'PAR - Par',
    'M': 'M - Metro',
    'MTS': 'MTS - Metros',
    'M2': 'M2 - Metro quadrado',
    'M3': 'M3 - Metro cubico',
    'KG': 'KG - Quilograma',
    'G': 'G - Grama',
    'TON': 'TON - Tonelada',
    'LT': 'LT - Litro',
    'ML': 'ML - Mililitro',
    'SC': 'SC - Saco',
    'CX': 'CX - Caixa',
    'FD': 'FD - Fardo',
    'RL': 'RL - Rolo',
    'PCT': 'PCT - Pacote',
    'DZ': 'DZ - Duzia',
  };

  static bool unidadeVendaValida(String unidade) {
    return unidadesVenda.contains(unidade.trim().toUpperCase());
  }

  static String normalizarUnidadeVenda(String? unidade) {
    if (unidade == null || unidade.trim().isEmpty) return 'UN';
    var u = unidade.trim().toUpperCase();
    switch (u) {
      case 'METRO':
      case 'MT':
        return 'M';
      case 'L':
        return 'LT';
      case 'DUZ':
      case 'DUZIA':
      case 'DOZ':
        return 'DZ';
      case 'PAC':
      case 'PACOTE':
        return 'PCT';
      case 'FARDO':
        return 'FD';
      case 'ROLO':
        return 'RL';
      default:
        if (unidadesVenda.contains(u)) return u;
        return 'UN';
    }
  }

  /// Unidade de compra cadastrada (vazio = igual a venda).
  static String? normalizarUnidadeCompraOpcional(String? unidade) {
    if (unidade == null || unidade.trim().isEmpty) return null;
    final u = unidade.trim().toUpperCase();
    if (u == 'METRO') return 'M';
    if (u == 'MT') return 'M';
    if (unidadesCompraSugeridas.contains(u) || unidadesVenda.contains(u)) {
      return u;
    }
    for (final opt in unidadesCompraSugeridas) {
      if (u.contains(opt)) return opt;
    }
    return null;
  }
}
