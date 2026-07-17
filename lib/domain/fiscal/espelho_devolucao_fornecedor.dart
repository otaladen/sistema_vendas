import '../../config/fiscal_config.dart';
import '../../model/item_nota_temporario.dart';
import '../../model/produto.dart';
import 'nfe_cfop_devolucao_fornecedor_resolver.dart';

/// Valores fiscais editaveis para bater com o espelho enviado pela fabrica.
class EspelhoDevolucaoFornecedorItem {
  EspelhoDevolucaoFornecedorItem({
    required this.cfop,
    required this.valorUnitario,
    this.icmsOrigem = '0',
    this.icmsSituacaoTributaria = '',
    this.icmsBaseCalculo = 0,
    this.icmsAliquota = 0,
    this.icmsValor = 0,
    this.icmsBaseCalculoSt = 0,
    this.icmsAliquotaSt = 0,
    this.icmsValorSt = 0,
    this.ipiValor = 0,
    this.cfopCompraOrigem = '',
  });

  String cfop;
  double valorUnitario;
  String icmsOrigem;
  String icmsSituacaoTributaria;
  double icmsBaseCalculo;
  double icmsAliquota;
  double icmsValor;
  double icmsBaseCalculoSt;
  double icmsAliquotaSt;
  double icmsValorSt;
  double ipiValor;

  /// CFOP da NF-e de compra (referencia para conferencia).
  final String cfopCompraOrigem;

  EspelhoDevolucaoFornecedorItem copy() => EspelhoDevolucaoFornecedorItem(
        cfop: cfop,
        valorUnitario: valorUnitario,
        icmsOrigem: icmsOrigem,
        icmsSituacaoTributaria: icmsSituacaoTributaria,
        icmsBaseCalculo: icmsBaseCalculo,
        icmsAliquota: icmsAliquota,
        icmsValor: icmsValor,
        icmsBaseCalculoSt: icmsBaseCalculoSt,
        icmsAliquotaSt: icmsAliquotaSt,
        icmsValorSt: icmsValorSt,
        ipiValor: ipiValor,
        cfopCompraOrigem: cfopCompraOrigem,
      );

  void aplicarDoItemXml(ItemNotaTemporario item) {
    final cfopXml = item.cfop.replaceAll(RegExp(r'\D'), '');
    if (cfopXml.length == 4) {
      cfop = cfopXml;
    }
    if (item.valorUnitarioComercial > 0) {
      valorUnitario = item.valorUnitarioComercial;
    }
    if (item.icmsOrigem.trim().isNotEmpty) {
      icmsOrigem = item.icmsOrigem.trim();
    }
    if (item.icmsSituacaoTributaria.trim().isNotEmpty) {
      icmsSituacaoTributaria = item.icmsSituacaoTributaria.trim();
    }
    icmsAliquota = item.icmsAliquota;
    icmsBaseCalculo = item.icmsBaseCalculo;
    icmsValor = item.icmsValor;
    icmsBaseCalculoSt = item.icmsBaseCalculoSt;
    icmsAliquotaSt = item.icmsAliquotaSt;
    icmsValorSt = item.icmsValorSt;
    ipiValor = item.ipiValor;
  }
}

/// Resultado da aplicacao automatica do XML do espelho da fabrica.
class AplicacaoEspelhoXmlResultado {
  const AplicacaoEspelhoXmlResultado({
    required this.itensCasados,
    required this.itensXmlSemPar,
    required this.linhasSemPar,
  });

  final int itensCasados;
  final int itensXmlSemPar;
  final int linhasSemPar;

  bool get teveMatch => itensCasados > 0;

  String get mensagemResumo {
    if (itensCasados <= 0) {
      return 'Nenhum item do XML bateu com a NF de compra. '
          'Confira EAN/codigo ou ajuste manualmente.';
    }
    final buf = StringBuffer(
      '$itensCasados item(ns) preenchido(s) pelo espelho.',
    );
    if (itensXmlSemPar > 0) {
      buf.write(' $itensXmlSemPar do XML sem correspondente.');
    }
    if (linhasSemPar > 0) {
      buf.write(' $linhasSemPar da compra sem espelho.');
    }
    return buf.toString();
  }
}

/// Sugere CFOP/valores proporcionais a partir da compra (espelho tecnico).
abstract final class EspelhoDevolucaoFornecedorHelper {
  EspelhoDevolucaoFornecedorHelper._();

  /// CFOP de saida tipico a partir do CFOP de entrada da compra.
  static String cfopDevolucaoDeCompra(
    String cfopCompra, {
    required Produto produto,
    required String ufFornecedor,
    String ufEmitente = FiscalConfig.ufEmitente,
  }) {
    final c = cfopCompra.replaceAll(RegExp(r'\D'), '');
    const mapa = <String, String>{
      '1101': '5201',
      '1102': '5202',
      '1401': '5401',
      '1403': '5403',
      '1409': '5411',
      '1411': '5411',
      '2101': '6201',
      '2102': '6202',
      '2401': '6401',
      '2403': '6403',
      '2409': '6411',
      '2411': '6411',
    };
    final mapeado = mapa[c];
    if (mapeado != null) return mapeado;
    return NfeCfopDevolucaoFornecedorResolver.resolver(
      produto: produto,
      ufDestinatario: ufFornecedor,
      ufEmitente: ufEmitente,
    );
  }

  static double proporcao({
    required int quantidadeDevolver,
    required int quantidadeEntradaOriginal,
  }) {
    if (quantidadeDevolver <= 0 || quantidadeEntradaOriginal <= 0) return 0;
    final p = quantidadeDevolver / quantidadeEntradaOriginal;
    return p.clamp(0, 1).toDouble();
  }

  static double _arred2(double v) =>
      (v * 100).roundToDouble() / 100;

  /// Ajusta bases/valores do espelho quando a quantidade muda (mantem aliquota).
  static void recalcularProporcional({
    required EspelhoDevolucaoFornecedorItem espelho,
    required int quantidadeDevolver,
    required int quantidadeEntradaOriginal,
    required double icmsBaseOrigem,
    required double icmsValorOrigem,
    required double icmsBaseStOrigem,
    required double icmsValorStOrigem,
    required double ipiValorOrigem,
  }) {
    final f = proporcao(
      quantidadeDevolver: quantidadeDevolver,
      quantidadeEntradaOriginal: quantidadeEntradaOriginal,
    );
    espelho.icmsBaseCalculo = _arred2(icmsBaseOrigem * f);
    espelho.icmsValor = _arred2(icmsValorOrigem * f);
    espelho.icmsBaseCalculoSt = _arred2(icmsBaseStOrigem * f);
    espelho.icmsValorSt = _arred2(icmsValorStOrigem * f);
    espelho.ipiValor = _arred2(ipiValorOrigem * f);
  }

  /// Converte qtd comercial do espelho para unidades de estoque da entrada.
  static int quantidadeEstoqueDoEspelho({
    required double quantidadeComercialXml,
    required double quantidadeFornecedorEntrada,
    required int quantidadeEstoqueEntrada,
    required int quantidadeMaxima,
  }) {
    if (quantidadeComercialXml <= 0) return 0;
    int q;
    if (quantidadeFornecedorEntrada > 0 && quantidadeEstoqueEntrada > 0) {
      q = (quantidadeComercialXml /
              quantidadeFornecedorEntrada *
              quantidadeEstoqueEntrada)
          .round();
    } else {
      q = quantidadeComercialXml.round();
    }
    if (q <= 0 && quantidadeComercialXml > 0) q = 1;
    return q.clamp(0, quantidadeMaxima);
  }

  /// Score de casamento XML ↔ produto/historico (maior = melhor).
  static int scoreMatchItem({
    required ItemNotaTemporario xml,
    required Produto produto,
    required double precoCustoNota,
    required double quantidadeFornecedor,
  }) {
    var score = 0;
    final eanProd = produto.codigoBarras.replaceAll(RegExp(r'\D'), '');
    final eanXml = xml.codigoBarras.replaceAll(RegExp(r'\D'), '');
    if (eanProd.isNotEmpty && eanXml.isNotEmpty && eanProd == eanXml) {
      score += 100;
    }
    final codProd = produto.codigoInterno.trim().toLowerCase();
    final codXml = xml.codigo.trim().toLowerCase();
    if (codProd.isNotEmpty && codXml.isNotEmpty && codProd == codXml) {
      score += 80;
    }
    final nome = produto.nome.trim().toLowerCase();
    final desc = xml.descricao.trim().toLowerCase();
    if (nome.isNotEmpty && desc.isNotEmpty) {
      if (nome == desc) {
        score += 60;
      } else if (desc.contains(nome) || nome.contains(desc)) {
        score += 35;
      }
    }
    if (precoCustoNota > 0 &&
        (xml.valorUnitarioComercial - precoCustoNota).abs() < 0.02) {
      score += 20;
    }
    if (quantidadeFornecedor > 0 &&
        (xml.quantidadeComercial - quantidadeFornecedor).abs() < 0.01) {
      score += 15;
    }
    return score;
  }

  /// Casa cada item do XML a no maximo uma linha (guloso por melhor score).
  static Map<int, ItemNotaTemporario> casarItensXmlComLinhas({
    required List<ItemNotaTemporario> itensXml,
    required List<({int index, Produto produto, double preco, double qtdForn})>
        linhas,
  }) {
    final usadosXml = <int>{};
    final resultado = <int, ItemNotaTemporario>{};
    final candidatos = <({int linhaIdx, int xmlIdx, int score})>[];

    for (var li = 0; li < linhas.length; li++) {
      final l = linhas[li];
      for (var xi = 0; xi < itensXml.length; xi++) {
        final s = scoreMatchItem(
          xml: itensXml[xi],
          produto: l.produto,
          precoCustoNota: l.preco,
          quantidadeFornecedor: l.qtdForn,
        );
        if (s >= 35) {
          candidatos.add((linhaIdx: li, xmlIdx: xi, score: s));
        }
      }
    }
    candidatos.sort((a, b) => b.score.compareTo(a.score));
    final linhasUsadas = <int>{};
    for (final c in candidatos) {
      if (linhasUsadas.contains(c.linhaIdx) || usadosXml.contains(c.xmlIdx)) {
        continue;
      }
      linhasUsadas.add(c.linhaIdx);
      usadosXml.add(c.xmlIdx);
      resultado[c.linhaIdx] = itensXml[c.xmlIdx];
    }
    return resultado;
  }
}
