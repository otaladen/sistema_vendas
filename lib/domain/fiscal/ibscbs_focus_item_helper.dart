/// Campos IBS/CBS por item para API Focus NFe (Reforma Tributaria / NT 2025.002).
///
/// A Focus monta o grupo XML `IBSCBS` a partir destes campos JSON.
/// Defaults: CST `000` + cClassTrib `000001` (tributacao integral) e aliquotas
/// de testes da fase de transicao 2026 (CBS 0,9% + IBS-UF 0,1% + IBS-mun 0%),
/// conforme guia Focus. Validar com o contador da loja para monofasico/isento/ST.
abstract final class IbscbsFocusItemHelper {
  IbscbsFocusItemHelper._();

  /// Tributacao integral IBS/CBS.
  static const String cstTributacaoIntegral = '000';

  /// Classificacao tributária padrão (tributado integralmente).
  static const String classTribIntegral = '000001';

  /// Aliquota CBS de testes 2026 (%).
  static const double cbsAliquotaPadrao = 0.9;

  /// Aliquota IBS estadual de testes 2026 (%).
  static const double ibsUfAliquotaPadrao = 0.1;

  /// Aliquota IBS municipal de testes 2026 (%).
  static const double ibsMunAliquotaPadrao = 0.0;

  /// Monta campos IBS/CBS do item na ordem usada nos exemplos Focus.
  static Map<String, dynamic> camposItem({
    required double baseCalculo,
    String cst = cstTributacaoIntegral,
    String classTrib = classTribIntegral,
    double cbsAliquota = cbsAliquotaPadrao,
    double ibsUfAliquota = ibsUfAliquotaPadrao,
    double ibsMunAliquota = ibsMunAliquotaPadrao,
  }) {
    final base = _arred2(baseCalculo < 0 ? 0 : baseCalculo);
    final cbsValor = _arred2(base * cbsAliquota / 100.0);
    final ibsUfValor = _arred2(base * ibsUfAliquota / 100.0);
    final ibsMunValor = _arred2(base * ibsMunAliquota / 100.0);
    final ibsTotal = _arred2(ibsUfValor + ibsMunValor);

    return {
      'ibs_cbs_situacao_tributaria': cst,
      'ibs_cbs_classificacao_tributaria': classTrib,
      'ibs_cbs_base_calculo': base,
      'cbs_aliquota': _fmtAliquota(cbsAliquota),
      'cbs_valor': _fmtValor(cbsValor),
      'ibs_uf_aliquota': _fmtAliquota(ibsUfAliquota),
      'ibs_uf_valor': _fmtValor(ibsUfValor),
      'ibs_mun_aliquota': _fmtAliquota(ibsMunAliquota),
      'ibs_mun_valor': _fmtValor(ibsMunValor),
      'ibs_valor_total': _fmtValor(ibsTotal),
    };
  }

  static double _arred2(double v) => (v * 100).roundToDouble() / 100.0;

  static String _fmtValor(double v) => v.toStringAsFixed(2);

  static String _fmtAliquota(double v) {
    final s = v.toStringAsFixed(4);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
