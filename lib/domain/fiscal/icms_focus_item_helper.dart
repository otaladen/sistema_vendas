/// Campos ICMS por item para API Focus NFe (ordem exigida no XML).
///
/// CST 00 exige `icms_modalidade_base_calculo` (modBC) antes de `vBC` no XML.
/// Sem modBC a Focus tenta montar vBC sozinha e a SEFAZ rejeita o schema.
/// Base, aliquota e valor do ICMS ficam com o motor da Focus (totais do documento).
abstract final class IcmsFocusItemHelper {
  IcmsFocusItemHelper._();

  /// 3 = valor da operacao (balcao / varejo).
  static const String modalidadeBaseValorOperacao = '3';

  /// CSTs que exigem modBC no XML (Regime Normal).
  static bool cstExigeModalidadeBaseCalculo(String cst) {
    switch (cst.trim()) {
      case '00':
        return true;
      default:
        return false;
    }
  }

  /// Monta campos ICMS do item na ordem esperada pela Focus.
  static Map<String, String> camposIcmsItem({
    required String icmsOrigem,
    required String icmsSituacaoTributaria,
  }) {
    final map = <String, String>{
      'icms_origem': icmsOrigem,
    };

    if (cstExigeModalidadeBaseCalculo(icmsSituacaoTributaria)) {
      map['icms_modalidade_base_calculo'] = modalidadeBaseValorOperacao;
    }

    map['icms_situacao_tributaria'] = icmsSituacaoTributaria;
    return map;
  }
}
