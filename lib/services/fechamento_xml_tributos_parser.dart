import 'package:xml/xml.dart';

import '../config/fiscal_config.dart';
import '../domain/fiscal/fechamento_tributos_xml.dart';

/// Extrai CFOP e totais de impostos de XML NF-e/NFC-e para o fechamento contabil.
class FechamentoXmlTributosParser {
  FechamentoXmlTributosParser._();

  static FechamentoTributosXml parse(String xmlText) {
    try {
      final doc = XmlDocument.parse(xmlText);
      return _parseDocument(doc);
    } catch (_) {
      return const FechamentoTributosXml(
        cfopPredominante: FiscalConfig.cfopPadraoVendaInterna,
      );
    }
  }

  static FechamentoTributosXml parseBytes(List<int> bytes) {
    try {
      return parse(String.fromCharCodes(bytes));
    } catch (_) {
      return FechamentoTributosXml.vazio;
    }
  }

  static FechamentoTributosXml _parseDocument(XmlDocument doc) {
    XmlElement? infNFe;
    for (final el in doc.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'infNFe') {
        infNFe = el;
        break;
      }
    }
    if (infNFe == null) return FechamentoTributosXml.vazio;

    final cfops = <String>{};
    for (final det in infNFe.descendants.whereType<XmlElement>()) {
      if (det.name.local != 'det') continue;
      final prod = _filho(det, 'prod');
      if (prod == null) continue;
      final cfop = _texto(prod, 'CFOP');
      if (cfop.isNotEmpty) cfops.add(cfop);
    }

    var cfopPred = cfops.isNotEmpty
        ? cfops.first
        : FiscalConfig.cfopPadraoVendaInterna;
    if (cfops.length > 1) {
      cfopPred = '${cfops.first} (+${cfops.length - 1})';
    }

    double vBC = 0, vICMS = 0, vPIS = 0, vCOFINS = 0;
    for (final el in infNFe.descendants.whereType<XmlElement>()) {
      if (el.name.local != 'ICMSTot') continue;
      vBC = _decimal(_texto(el, 'vBC'));
      vICMS = _decimal(_texto(el, 'vICMS'));
      vPIS = _decimal(_texto(el, 'vPIS'));
      vCOFINS = _decimal(_texto(el, 'vCOFINS'));
      break;
    }

    return FechamentoTributosXml(
      cfopPredominante: cfopPred,
      baseIcms: vBC,
      valorIcms: vICMS,
      valorPis: vPIS,
      valorCofins: vCOFINS,
    );
  }

  static XmlElement? _filho(XmlElement parent, String local) {
    for (final c in parent.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static String _texto(XmlElement parent, String local) {
    final el = _filho(parent, local);
    return el?.innerText.trim() ?? '';
  }

  static double _decimal(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }
}
