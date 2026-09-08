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
    final valorTotalNota = _extrairValorTotalNota(infNFe, itens);
    final duplicatas = _extrairDuplicatas(infNFe);

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
      duplicatas: duplicatas,
      valorTotalNota: valorTotalNota,
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
    final ie = _somenteDigitos(_primeiroTexto(emit, 'IE') ?? '');

    XmlElement? ender;
    for (final c in emit.childElements) {
      if (c.name.local == 'enderEmit') {
        ender = c;
        break;
      }
    }

    return EmitenteNfeTemporario(
      cnpj: cnpj,
      razaoSocial: razao.trim(),
      nomeFantasia: fantasia.trim(),
      inscricaoEstadual: ie,
      logradouro: ender == null ? '' : (_primeiroTexto(ender, 'xLgr') ?? '').trim(),
      numero: ender == null ? '' : (_primeiroTexto(ender, 'nro') ?? '').trim(),
      complemento:
          ender == null ? '' : (_primeiroTexto(ender, 'xCpl') ?? '').trim(),
      bairro: ender == null ? '' : (_primeiroTexto(ender, 'xBairro') ?? '').trim(),
      municipio: ender == null ? '' : (_primeiroTexto(ender, 'xMun') ?? '').trim(),
      codigoMunicipioIbge: ender == null
          ? ''
          : _somenteDigitos(_primeiroTexto(ender, 'cMun') ?? ''),
      uf: ender == null
          ? ''
          : (_primeiroTexto(ender, 'UF') ?? '').trim().toUpperCase(),
      cep: ender == null
          ? ''
          : _somenteDigitos(_primeiroTexto(ender, 'CEP') ?? ''),
      telefone: ender == null
          ? ''
          : _somenteDigitos(_primeiroTexto(ender, 'fone') ?? ''),
      email: (_primeiroTexto(emit, 'email') ?? '').trim(),
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
      final uTrib = _primeiroTexto(prod, 'uTrib') ?? '';
      final qTrib = _parseDecimal(_primeiroTexto(prod, 'qTrib') ?? '0');
      final vUnTrib = _parseDecimal(_primeiroTexto(prod, 'vUnTrib') ?? '0');
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
      final cfop = (_primeiroTexto(prod, 'CFOP') ?? '').trim();
      final imposto = _extrairImpostoItem(el);
      final rastro = _extrairRastro(prod);

      itens.add(
        ItemNotaTemporario(
          numeroItem: nItem,
          codigo: codigo.trim(),
          descricao: descricao.trim(),
          unidadeComercial: uCom.trim(),
          quantidadeComercial: qCom,
          valorUnitarioComercial: vUnCom,
          unidadeTributavel: uTrib.trim(),
          quantidadeTributavel: qTrib > 0 ? qTrib : 0,
          valorUnitarioTributavel: vUnTrib > 0 ? vUnTrib : 0,
          codigoBarras: ean,
          ncm: ncm.trim(),
          cfop: cfop,
          icmsOrigem: imposto.origem,
          icmsSituacaoTributaria: imposto.cst,
          icmsBaseCalculo: imposto.vBc,
          icmsAliquota: imposto.pIcms,
          icmsValor: imposto.vIcms,
          icmsBaseCalculoSt: imposto.vBcSt,
          icmsAliquotaSt: imposto.pIcmsSt,
          icmsValorSt: imposto.vIcmsSt,
          ipiValor: imposto.vIpi,
          numeroLote: rastro.numeroLote,
          dataValidade: rastro.dataValidade,
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

  /// `total/ICMSTot/vNF` ou, se ausente, soma de `qCom * vUnCom` dos itens.
  static double _extrairValorTotalNota(
    XmlElement infNFe,
    List<ItemNotaTemporario> itens,
  ) {
    XmlElement? total;
    for (final c in infNFe.childElements) {
      if (c.name.local == 'total') {
        total = c;
        break;
      }
    }
    if (total != null) {
      for (final c in total.childElements) {
        if (c.name.local != 'ICMSTot') continue;
        final vnf = _primeiroTexto(c, 'vNF');
        if (vnf != null && vnf.trim().isNotEmpty) {
          final v = _parseDecimal(vnf);
          if (v > 0) return v;
        }
      }
    }
    var soma = 0.0;
    for (final it in itens) {
      soma += it.quantidadeComercial * it.valorUnitarioComercial;
    }
    return soma;
  }

  /// Lê `<cobr>` direto em [infNFe] e cada `<dup>` (`nDup`, `dVenc`, `vDup`).
  static List<NfeDuplicataXml> _extrairDuplicatas(XmlElement infNFe) {
    XmlElement? cobr;
    for (final c in infNFe.childElements) {
      if (c.name.local == 'cobr') {
        cobr = c;
        break;
      }
    }
    if (cobr == null) {
      return const [];
    }

    final brutas = <({String nDup, String dVenc, String vDup})>[];
    for (final c in cobr.childElements) {
      if (c.name.local != 'dup') continue;
      final nDup = _primeiroTexto(c, 'nDup')?.trim() ?? '';
      final dVenc = _primeiroTexto(c, 'dVenc')?.trim() ?? '';
      final vDup = _primeiroTexto(c, 'vDup')?.trim() ?? '';
      if (dVenc.isEmpty && vDup.isEmpty && nDup.isEmpty) continue;
      brutas.add((nDup: nDup, dVenc: dVenc, vDup: vDup));
    }
    if (brutas.isEmpty) {
      return const [];
    }

    final total = brutas.length;
    final out = <NfeDuplicataXml>[];
    for (var i = 0; i < brutas.length; i++) {
      final b = brutas[i];
      if (b.dVenc.isEmpty) {
        throw FormatException(
          'Duplicata ${i + 1}: dVenc ausente ou vazio.',
        );
      }
      if (b.vDup.isEmpty) {
        throw FormatException(
          'Duplicata ${i + 1}: vDup ausente ou vazio.',
        );
      }
      final valor = _parseDecimal(b.vDup);
      if (valor < 0) {
        throw FormatException(
          'Duplicata ${i + 1}: valor vDup invalido.',
        );
      }
      final dataVenc = NfeDuplicataXml.parseDataVencimento(b.dVenc);
      final nParcela = b.nDup.isNotEmpty
          ? b.nDup
          : '${(i + 1).toString().padLeft(3, '0')}/'
                '${total.toString().padLeft(3, '0')}';
      out.add(
        NfeDuplicataXml(
          numeroParcela: nParcela,
          dataVencimento: dataVenc,
          valorParcela: valor,
        ),
      );
    }
    return out;
  }

  /// Extrai ICMS/IPI do item (`det/imposto`) para espelhar na devolucao.
  static ({
    String origem,
    String cst,
    double vBc,
    double pIcms,
    double vIcms,
    double vBcSt,
    double pIcmsSt,
    double vIcmsSt,
    double vIpi,
  }) _extrairImpostoItem(XmlElement det) {
    var origem = '';
    var cst = '';
    var vBc = 0.0;
    var pIcms = 0.0;
    var vIcms = 0.0;
    var vBcSt = 0.0;
    var pIcmsSt = 0.0;
    var vIcmsSt = 0.0;
    var vIpi = 0.0;

    XmlElement? imposto;
    for (final c in det.childElements) {
      if (c.name.local == 'imposto') {
        imposto = c;
        break;
      }
    }
    if (imposto == null) {
      return (
        origem: origem,
        cst: cst,
        vBc: vBc,
        pIcms: pIcms,
        vIcms: vIcms,
        vBcSt: vBcSt,
        pIcmsSt: pIcmsSt,
        vIcmsSt: vIcmsSt,
        vIpi: vIpi,
      );
    }

    for (final bloco in imposto.childElements) {
      final nome = bloco.name.local;
      if (nome == 'ICMS') {
        for (final grupo in bloco.childElements) {
          origem = (_primeiroTexto(grupo, 'orig') ?? origem).trim();
          cst = (_primeiroTexto(grupo, 'CST') ??
                  _primeiroTexto(grupo, 'CSOSN') ??
                  cst)
              .trim();
          vBc = _parseDecimalOpcional(_primeiroTexto(grupo, 'vBC')) ?? vBc;
          pIcms = _parseDecimalOpcional(_primeiroTexto(grupo, 'pICMS')) ?? pIcms;
          vIcms = _parseDecimalOpcional(_primeiroTexto(grupo, 'vICMS')) ?? vIcms;
          vBcSt = _parseDecimalOpcional(_primeiroTexto(grupo, 'vBCST')) ?? vBcSt;
          pIcmsSt =
              _parseDecimalOpcional(_primeiroTexto(grupo, 'pICMSST')) ?? pIcmsSt;
          vIcmsSt =
              _parseDecimalOpcional(_primeiroTexto(grupo, 'vICMSST')) ?? vIcmsSt;
        }
      } else if (nome == 'IPI') {
        for (final grupo in bloco.childElements) {
          if (grupo.name.local == 'IPITrib' || grupo.name.local == 'IPI') {
            vIpi = _parseDecimalOpcional(_primeiroTexto(grupo, 'vIPI')) ?? vIpi;
          }
        }
      }
    }

    return (
      origem: origem,
      cst: cst,
      vBc: vBc,
      pIcms: pIcms,
      vIcms: vIcms,
      vBcSt: vBcSt,
      pIcmsSt: pIcmsSt,
      vIcmsSt: vIcmsSt,
      vIpi: vIpi,
    );
  }

  static double? _parseDecimalOpcional(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _parseDecimal(raw);
    } on FormatException {
      return null;
    }
  }

  /// Data de item/lote (`YYYY-MM-DD`, ISO ou `dd/MM/yyyy`) como data civil local.
  static DateTime _parseDataDup(String raw) =>
      NfeDuplicataXml.parseDataVencimento(raw);

  /// Primeiro bloco `rastro` do item (`nLote` / `dVal`).
  static ({String numeroLote, DateTime? dataValidade}) _extrairRastro(
    XmlElement prod,
  ) {
    for (final c in prod.childElements) {
      if (c.name.local != 'rastro') continue;
      final nLote = (_primeiroTexto(c, 'nLote') ?? '').trim();
      final dValRaw = (_primeiroTexto(c, 'dVal') ?? '').trim();
      DateTime? dVal;
      if (dValRaw.isNotEmpty) {
        try {
          dVal = _parseDataDup(dValRaw);
        } on FormatException {
          dVal = null;
        }
      }
      return (numeroLote: nLote, dataValidade: dVal);
    }
    return (numeroLote: '', dataValidade: null);
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
