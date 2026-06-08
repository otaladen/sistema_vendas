/// Municipios mais usados no cadastro de clientes (regiao da loja — BA).
class MunicipioIbgeFrequente {
  const MunicipioIbgeFrequente({
    required this.rotulo,
    required this.codigo,
    required this.nomesCidade,
  });

  final String rotulo;
  final String codigo;

  /// Nomes normalizados para sugerir o IBGE a partir do campo cidade.
  final List<String> nomesCidade;
}

abstract final class MunicipiosIbgeFrequentes {
  MunicipiosIbgeFrequentes._();

  static const String valorManual = '__manual__';

  static const List<MunicipioIbgeFrequente> opcoes = [
    MunicipioIbgeFrequente(
      rotulo: 'Salvador — BA',
      codigo: '2927408',
      nomesCidade: ['salvador'],
    ),
    MunicipioIbgeFrequente(
      rotulo: 'Lauro de Freitas — BA',
      codigo: '2919207',
      nomesCidade: ['lauro de freitas', 'lauro'],
    ),
    MunicipioIbgeFrequente(
      rotulo: 'Camacari — BA',
      codigo: '2905701',
      nomesCidade: ['camacari', 'camaçari'],
    ),
  ];

  static MunicipioIbgeFrequente? porCodigo(String codigo) {
    final digits = codigo.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 7) return null;
    for (final o in opcoes) {
      if (o.codigo == digits) return o;
    }
    return null;
  }

  /// Retorna o codigo IBGE do preset ou [valorManual] se for codigo customizado.
  static String selecaoParaCodigo(String codigo) {
    final digits = codigo.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return porCodigo(digits)?.codigo ?? valorManual;
  }

  static MunicipioIbgeFrequente? sugerirPorNomeCidade(String cidade) {
    final norm = _normalizarCidade(cidade);
    if (norm.isEmpty) return null;
    for (final o in opcoes) {
      for (final nome in o.nomesCidade) {
        if (norm == _normalizarCidade(nome)) return o;
      }
    }
    for (final o in opcoes) {
      for (final nome in o.nomesCidade) {
        final n = _normalizarCidade(nome);
        if (n.length >= 4 && norm.contains(n)) return o;
      }
    }
    return null;
  }

  static String _normalizarCidade(String valor) {
    return valor
        .trim()
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u');
  }
}
