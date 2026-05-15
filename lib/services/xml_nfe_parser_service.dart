import 'package:xml/xml.dart';

import '../model/item_nota_temporario.dart';

/// Extrai dados principais de um XML de NF-e (modelo 55) para conferencia de entrada.
class XmlParserService {
  XmlParserService._();

  /// Lanca [FormatException] se o documento nao contiver [infNFe] valida ou se o XML for invalido.
  static NfeXmlParseResult parseNfeXmlString(String xmlText) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException catch (e, st) {
      Error.throwWithStackTrace(
        FormatException('XML invalido (parser): ${e.message}'),
        st,
      );
    } on Object catch (e, st) {
      // XmlDocument.parse pode lancar outros erros em conteudo extremamente malformado.
      Error.throwWithStackTrace(
        FormatException('XML invalido: $e'),
        st,
      );
    }

    try {
      return _parseNfeXmlDocument(doc);
    } on FormatException {
      rethrow;
    } on StateError catch (e, st) {
      Error.throwWithStackTrace(FormatException(e.message), st);
    } on Object catch (e, st) {
      Error.throwWithStackTrace(
        FormatException('Falha ao interpretar NF-e: $e'),
        st,
      );
    }
  }

  static NfeXmlParseResult _parseNfeXmlDocument(XmlDocument doc) {
    final root = doc.rootElement;

    XmlElement? infNFe;
    for (final el in root.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'infNFe') {
        infNFe = el;
        break;
      }
    }
    if (infNFe == null) {
      throw const FormatException(
        'XML invalido: nao foi encontrado o elemento infNFe.',
      );
    }

    final chaveBruta = _extrairChaveAcesso(infNFe);
    final chaveAcesso = chaveBruta.replaceAll(RegExp(r'\D'), '');
    if (chaveAcesso.length != 44) {
      throw FormatException(
        'Chave de acesso invalida (${chaveAcesso.length} digitos; esperado 44).',
      );
    }
    final emitente = _extrairEmitente(infNFe);
    final ideInfo = _extrairIde(infNFe);
    final itens = _extrairItens(infNFe);

    if (emitente.cnpj.length != 11 && emitente.cnpj.length != 14) {
      throw FormatException(
        'CNPJ/CPF do emitente invalido (${emitente.cnpj.length} digitos).',
      );
    }

    return NfeXmlParseResult(
      chaveAcesso: chaveAcesso,
      numeroNota: ideInfo.numeroNota,
      dataEmissao: ideInfo.dataEmissao,
      emitente: emitente,
      itens: itens,
    );
  }

  static ({int numeroNota, DateTime dataEmissao}) _extrairIde(
    XmlElement infNFe,
  ) {
    XmlElement? ide;
    for (final c in infNFe.childElements) {
      if (c.name.local == 'ide') {
        ide = c;
        break;
      }
    }
    var numeroNota = 0;
    var dataEmissao = DateTime.now().toUtc();
    if (ide != null) {
      final nnf = _primeiroTexto(ide, 'nNF');
      numeroNota = int.tryParse(nnf?.trim() ?? '') ?? 0;
      final dh =
          _primeiroTexto(ide, 'dhEmi') ?? _primeiroTexto(ide, 'dEmi') ?? '';
      final parsed = DateTime.tryParse(dh.trim());
      if (parsed != null) {
        dataEmissao = parsed.toUtc();
      }
    }
    return (numeroNota: numeroNota, dataEmissao: dataEmissao);
  }

  static String _extrairChaveAcesso(XmlElement infNFe) {
    final id = infNFe.getAttribute('Id')?.trim() ?? '';
    if (id.length >= 44) {
      if (id.toUpperCase().startsWith('NFE')) {
        return id.substring(3, 3 + 44);
      }
      return id.substring(0, 44);
    }
    for (final el in infNFe.descendants.whereType<XmlElement>()) {
      if (el.name.local == 'chNFe') {
        final t = el.innerText.trim();
        if (t.length == 44) return t;
      }
    }
    return id.replaceAll(RegExp(r'\D'), '');
  }

  static EmitenteNfeTemporario _extrairEmitente(XmlElement infNFe) {
    XmlElement? emit;
    for (final el in infNFe.childElements) {
      if (el.name.local == 'emit') {
        emit = el;
        break;
      }
    }
    if (emit == null) {
      throw const FormatException('XML invalido: elemento emit ausente.');
    }

    final cnpj = _somenteDigitos(
      _primeiroTexto(emit, 'CNPJ') ?? _primeiroTexto(emit, 'CPF') ?? '',
    );
    final razao = _primeiroTexto(emit, 'xNome') ?? '';
    final fantasia = _primeiroTexto(emit, 'xFant') ?? '';

    return EmitenteNfeTemporario(
      cnpj: cnpj,
      razaoSocial: razao.trim(),
      nomeFantasia: fantasia.trim(),
    );
  }

  static List<ItemNotaTemporario> _extrairItens(XmlElement infNFe) {
    final itens = <ItemNotaTemporario>[];
    for (final el in infNFe.childElements) {
      if (el.name.local != 'det') continue;
      final nAttr = el.getAttribute('nItem');
      final nItem = int.tryParse(nAttr ?? '') ?? itens.length + 1;
      XmlElement? prod;
      for (final c in el.childElements) {
        if (c.name.local == 'prod') {
          prod = c;
          break;
        }
      }
      if (prod == null) continue;

      final codigo = _primeiroTexto(prod, 'cProd') ?? '';
      final descricao = _primeiroTexto(prod, 'xProd') ?? '';
      final uCom = _primeiroTexto(prod, 'uCom') ?? '';
      final qCom = _parseDecimal(_primeiroTexto(prod, 'qCom') ?? '0');
      final vUnCom = _parseDecimal(_primeiroTexto(prod, 'vUnCom') ?? '0');
      if (qCom < 0) {
        throw FormatException(
          'Quantidade comercial negativa no item $nItem (cProd ${codigo.trim()}).',
        );
      }
      if (vUnCom < 0) {
        throw FormatException(
          'Valor unitario negativo no item $nItem (cProd ${codigo.trim()}).',
        );
      }
      final cEan = _normalizarEan(_primeiroTexto(prod, 'cEAN'));
      final cEanTrib = _normalizarEan(_primeiroTexto(prod, 'cEANTrib'));
      final ean = cEan.isNotEmpty ? cEan : cEanTrib;
      final ncm = _primeiroTexto(prod, 'NCM') ?? '';

      itens.add(
        ItemNotaTemporario(
          numeroItem: nItem,
          codigo: codigo.trim(),
          descricao: descricao.trim(),
          unidadeComercial: uCom.trim(),
          quantidadeComercial: qCom,
          valorUnitarioComercial: vUnCom,
          codigoBarras: ean,
          ncm: ncm.trim(),
        ),
      );
    }

    if (itens.isEmpty) {
      throw const FormatException(
        'XML invalido: nenhum item (det/prod) encontrado na nota.',
      );
    }

    return itens;
  }

  static String? _primeiroTexto(XmlElement parent, String localName) {
    for (final c in parent.childElements) {
      if (c.name.local == localName) {
        return c.innerText;
      }
    }
    return null;
  }

  static String _somenteDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _normalizarEan(String? raw) {
    if (raw == null) return '';
    final t = raw.trim();
    if (t.isEmpty ||
        t.toUpperCase() == 'SEM GTIN' ||
        t == '0' ||
        t.startsWith('SEM')) {
      return '';
    }
    return t;
  }

  static double _parseDecimal(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) {
      return 0;
    }
    final v = double.tryParse(t);
    if (v == null) {
      throw FormatException('Numero decimal invalido: "$raw"');
    }
    if (!v.isFinite) {
      throw FormatException('Numero decimal nao finito: "$raw"');
    }
    return v;
  }
}
