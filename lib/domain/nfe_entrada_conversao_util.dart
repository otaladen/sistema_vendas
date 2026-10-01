import '../model/item_nota_temporario.dart';
import '../model/produto.dart';
import 'produto_embalagem.dart';
import 'quantidade_venda_util.dart';

/// Severidade de divergencia entre qtd. da nota e entrada calculada.
enum NfeEntradaNivelDiscrepancia { nenhum, atencao, grave }

/// Resultado da checagem de seguranca na conferencia NF-e.
class NfeEntradaDiscrepanciaEntrada {
  const NfeEntradaDiscrepanciaEntrada({
    required this.nivel,
    required this.mensagem,
  });

  final NfeEntradaNivelDiscrepancia nivel;
  final String mensagem;

  bool get bloqueiaConfirmacao => nivel == NfeEntradaNivelDiscrepancia.grave;
}

/// Regras de conversao e custo na entrada de NF-e (conferencia + persistencia).
abstract final class NfeEntradaConversaoUtil {
  static const double _razaoDiscrepanciaAtencao = 10;
  static const double _razaoDiscrepanciaGrave = 100;
  static const double _entradaAltaUn = 1000;

  /// Parse decimal PT-BR/EN para fator e quantidades digitadas (41,9 / 41.9).
  static double parseDecimalTexto(String texto) {
    final t = texto
        .trim()
        .replaceAll(RegExp(r'[\s\u00A0\u202F]'), '')
        .replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t);
    if (v == null || !v.isFinite) return 0;
    return v;
  }

  /// [quantidadeEntrada] = qtd. nota × fator (ou ÷), na unidade de estoque.
  static double quantidadeEntradaUnidadeVenda({
    required double quantidadeNota,
    required double fatorConversao,
    required bool embalagemMultiplica,
  }) {
    return ProdutoEmbalagem.quantidadeNotaParaUnidadeVenda(
      quantidadeComercial: quantidadeNota,
      fator: fatorConversao,
      embalagemMultiplica: embalagemMultiplica,
    );
  }

  /// Detecta fator/quantidade incoerentes (ex.: 41,9 UN virando 41900).
  static NfeEntradaDiscrepanciaEntrada avaliarDiscrepanciaQuantidadeEntrada({
    required double quantidadeNota,
    required double quantidadeEntradaUnidadeVenda,
    required double fatorConversao,
  }) {
    if (!quantidadeNota.isFinite ||
        !quantidadeEntradaUnidadeVenda.isFinite ||
        !fatorConversao.isFinite ||
        quantidadeNota <= 0 ||
        quantidadeEntradaUnidadeVenda <= 0 ||
        fatorConversao <= 0) {
      return const NfeEntradaDiscrepanciaEntrada(
        nivel: NfeEntradaNivelDiscrepancia.nenhum,
        mensagem: '',
      );
    }

    final razao = quantidadeEntradaUnidadeVenda / quantidadeNota;
    final fatorUnitario = (fatorConversao - 1).abs() < 0.0001;
    final escalaMilErrada =
        fatorUnitario && razao >= QuantidadeVendaUtil.escalaFracionada * 0.9;

    if (escalaMilErrada ||
        (razao >= _razaoDiscrepanciaGrave && fatorUnitario)) {
      return NfeEntradaDiscrepanciaEntrada(
        nivel: NfeEntradaNivelDiscrepancia.grave,
        mensagem:
            'Entrada ${quantidadeEntradaUnidadeVenda.toStringAsFixed(3)} '
            'para ${quantidadeNota.toStringAsFixed(3)} na nota '
            '(~${razao.toStringAsFixed(0)}×). Revise fator/conversao.',
      );
    }

    final coerenteComFator =
        (razao - fatorConversao).abs() <= (fatorConversao.abs() * 0.02 + 0.05);
    final entradaAltaDesproporcional =
        quantidadeEntradaUnidadeVenda >= _entradaAltaUn &&
            razao >= _razaoDiscrepanciaAtencao &&
            !coerenteComFator;
    if (!coerenteComFator &&
        (fatorUnitario && razao >= _razaoDiscrepanciaAtencao ||
            entradaAltaDesproporcional)) {
      return NfeEntradaDiscrepanciaEntrada(
        nivel: NfeEntradaNivelDiscrepancia.atencao,
        mensagem:
            'Entrada muito acima da nota (~${razao.toStringAsFixed(1)}×). '
            'Confira qtd. na embalagem.',
      );
    }

    return const NfeEntradaDiscrepanciaEntrada(
      nivel: NfeEntradaNivelDiscrepancia.nenhum,
      mensagem: '',
    );
  }

  /// Fator sugerido na conferencia (vinculo, cadastro, XML uCom/uTrib, unidades conhecidas).
  static double fatorInicialConferencia({
    required ItemNotaTemporario item,
    Produto? produto,
    double fatorVinculo = 1,
  }) {
    final fatorNota = item.fatorComercialParaTributavel;
    if (produto != null && fatorNota > 0) {
      final uTrib = ProdutoEmbalagem.normalizarUnidade(item.unidadeTributavel);
      final uProd = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
      if (ProdutoEmbalagem.unidadesEquivalentes(uTrib, uProd)) {
        return fatorNota;
      }
      final uCom = ProdutoEmbalagem.normalizarUnidade(item.unidadeComercial);
      if (ProdutoEmbalagem.unidadesEquivalentes(uCom, uProd)) {
        return 1;
      }
    }

    if (produto != null) {
      final uCom = _unidadeComercialEfetiva(item);
      final uProd = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
      if (!ProdutoEmbalagem.unidadesEquivalentes(uCom, uProd)) {
        final conv = _fatorUnidadeComercialConhecida(
          unidadeComercial: item.unidadeComercial,
          unidadeDestino: uProd,
        );
        if (conv != null && conv > 0) return conv;
      }
    }

    if (produto != null) {
      final doCadastro = ProdutoEmbalagem.fatorSugeridoNotaParaEstoque(
        produto: produto,
        unidadeNota: item.unidadeComercial,
      );
      if (doCadastro != null && doCadastro > 0) {
        if (fatorVinculo > 0 &&
            (fatorVinculo - 1).abs() > 0.0001 &&
            (fatorVinculo - doCadastro).abs() > 0.0001) {
          return fatorVinculo;
        }
        return doCadastro;
      }
    }

    if (fatorNota > 0) return fatorNota;
    return fatorVinculo > 0 ? fatorVinculo : 1.0;
  }

  /// Unidade interna usada para gravar estoque/custo de produto existente.
  static String unidadeEstoqueProdutoExistente({
    required Produto produto,
    required String unidadeConferencia,
  }) {
    final cadastro = produto.unidade.trim().toUpperCase();
    if (cadastro.isNotEmpty) return cadastro;
    final conf = unidadeConferencia.trim().toUpperCase();
    return conf.isEmpty ? 'UN' : conf;
  }

  /// Custo unitario na unidade de estoque/venda do cadastro.
  ///
  /// Considera fator x/÷ e IPI recuperavel rateado por unidade comercial da nota.
  static double custoUnitarioInterno({
    required ItemNotaTemporario item,
    required double fator,
    required bool embalagemMultiplica,
  }) {
    if (fator <= 0) return 0;
    final qCom = item.quantidadeComercial;
    if (qCom <= 0 || !qCom.isFinite) return 0;

    var vUn = item.valorUnitarioComercial;
    if (!vUn.isFinite || vUn < 0) return 0;

    if (item.ipiValor > 0) {
      vUn += item.ipiValor / qCom;
    }

    final convertido = embalagemMultiplica ? vUn / fator : vUn * fator;
    if (!convertido.isFinite || convertido <= 0) return 0;
    return convertido;
  }

  /// Nota com unidade distinta da interna e fator != 1 exige opt-in para PDV/cadastro.
  static bool notaExigeConfirmacaoEmbalagem({
    required ItemNotaTemporario item,
    required String unidadeInterna,
    required double fator,
  }) {
    if (fator <= 0 || (fator - 1).abs() < 0.0001) return false;
    final uNota = _unidadeComercialEfetiva(item);
    final uVenda = ProdutoEmbalagem.normalizarUnidade(unidadeInterna);
    return !ProdutoEmbalagem.unidadesEquivalentes(uNota, uVenda);
  }

  /// Indica se a nota exige confirmacao explicita para gravar conversao no cadastro.
  static bool precisaConfirmarConversaoEmbalagem({
    required ItemNotaTemporario item,
    required Produto produto,
    required double fator,
  }) {
    if (!notaExigeConfirmacaoEmbalagem(
      item: item,
      unidadeInterna: produto.unidade,
      fator: fator,
    )) {
      return false;
    }
    final uNota = _unidadeComercialEfetiva(item);
    final uVenda = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    if (ProdutoEmbalagem.unidadesEquivalentes(uNota, uVenda)) return false;
    if (produto.temConversaoEmbalagem) {
      final uCompra = ProdutoEmbalagem.normalizarUnidade(
        produto.unidadeCompraEfetiva,
      );
      if (ProdutoEmbalagem.unidadesEquivalentes(uNota, uCompra)) return false;
    }
    return true;
  }

  static String _unidadeComercialEfetiva(ItemNotaTemporario item) {
    return ProdutoEmbalagem.normalizarUnidade(item.unidadeComercial);
  }

  static double? _fatorUnidadeComercialConhecida({
    required String unidadeComercial,
    required String unidadeDestino,
  }) {
    final u = unidadeComercial.trim().toUpperCase();
    if (unidadeDestino == 'UN') {
      const duzia = {'DZ', 'DUZ', 'DUZIA', 'DOZ', 'DZ1', 'DZ.'};
      if (duzia.contains(u)) return 12;
    }
    return null;
  }
}
