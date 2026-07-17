import '../produto_nome_titulo_normalizer.dart';

/// Utilitarios compartilhados entre importacao CSV e Chacal.
abstract final class ProdutoImportacaoUtil {
  ProdutoImportacaoUtil._();

  static String normalizarNome(String nome) =>
      ProdutoNomeTituloNormalizer.normalizar(nome);

  static String normalizarNcm(String? valor) {
    final digitos = (valor ?? '').replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 8) return '';
    return digitos;
  }

  static String normalizarCodigoBarras({
    String? gtin,
    String? codigoBarras,
    String? codigoInterno,
  }) {
    for (final bruto in [codigoBarras, gtin]) {
      final t = (bruto ?? '').trim();
      if (t.isEmpty) continue;
      final digitos = t.replaceAll(RegExp(r'\D'), '');
      if (digitos.length == 8 ||
          digitos.length == 12 ||
          digitos.length == 13 ||
          digitos.length == 14) {
        return digitos;
      }
    }
    return '';
  }

  static bool ativoDeFlagLegado(String? inativo) {
    final t = (inativo ?? '').trim().toUpperCase();
    if (t == 'S' || t == '1' || t == 'SIM' || t == 'TRUE') {
      return false;
    }
    return true;
  }

  static double parseMonetario(String? texto) {
    if (texto == null) return 0;
    var t = texto.trim();
    if (t.isEmpty) return 0;
    t = t.replaceAll(RegExp(r'[Rr]\$\s*'), '');
    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (t.contains(',')) {
      t = t.replaceAll(',', '.');
    }
    final v = double.tryParse(t);
    if (v == null || v.isNaN) return 0;
    return v < 0 ? 0 : v;
  }

  static int parseQuantidade(String? texto) {
    if (texto == null || texto.trim().isEmpty) return 0;
    final v = parseMonetario(texto);
    if (v.isNaN) return 0;
    final arred = v.round();
    return arred < 0 ? 0 : arred;
  }

  /// Codigo interno Chacal: ignora vazio e GTIN/EAN (ficam no codigo de barras).
  /// SKU curto (1, 2, 3...) e atribuido na gravacao.
  static String codigoInternoChacal({
    required String codigoInternoBruto,
    String gtin = '',
  }) {
    final bruto = codigoInternoBruto.trim();
    if (bruto.isEmpty) return '';
    final gtinDig = gtin.replaceAll(RegExp(r'\D'), '');
    final brutoDig = bruto.replaceAll(RegExp(r'\D'), '');
    if (gtinDig.isNotEmpty && brutoDig == gtinDig) return '';
    if (RegExp(r'^\d+$').hasMatch(bruto) && brutoDig.length >= 8) {
      return '';
    }
    return bruto;
  }
}
