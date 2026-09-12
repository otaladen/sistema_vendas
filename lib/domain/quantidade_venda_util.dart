import '../model/produto.dart';

/// Conversao entre quantidade digitada no PDV e [ItemVenda.quantidade] (int).
///
/// Decimais na unidade de venda gravam milésimos (ex.: 0,5 -> 500; 4,5 -> 4500).
/// Inteiros continuam literais (ex.: 5 -> 5). [Produto.permiteQuantidadeFracionada]
/// e legado de cadastro e so afeta leitura de dados antigos.
class QuantidadeVendaUtil {
  QuantidadeVendaUtil._();

  static const int escalaFracionada = 1000;

  /// Casas decimais aceitas na digitacao (bate com milésimos).
  static const int casasDecimaisFracionada = 3;

  /// Passo dos botoes +/- no PDV: 0,01 na unidade de venda (10 milésimos).
  static const int passoFracionadoArmazenado = escalaFracionada ~/ 100;

  /// PDV/orcamento: digitacao decimal na unidade de venda (nao na embalagem CX).
  static bool pdvAceitaDecimalDigitacao({required bool emUnidadeCompra}) =>
      !emUnidadeCompra;

  /// Grava milésimos quando a quantidade de venda tem parte decimal.
  static bool pdvArmazenaEmMilesimos({
    required bool emUnidadeCompra,
    required double quantidadeVenda,
    bool legadoCadastroFracionado = false,
  }) {
    if (emUnidadeCompra) return false;
    if (legadoCadastroFracionado) return true;
    return quantidadeVenda != quantidadeVenda.roundToDouble();
  }

  /// Inteiro persistido usa escala de milésimos (ex.: 500 = 0,5 un.).
  static bool armazenadoEmMilesimos(
    int armazenado, {
    bool legadoCadastroFracionado = false,
  }) {
    if (armazenado <= 0) return false;
    if (armazenado >= escalaFracionada) {
      if (armazenado % escalaFracionada != 0) return true;
      return legadoCadastroFracionado;
    }
    if (armazenado >= passoFracionadoArmazenado &&
        armazenado % passoFracionadoArmazenado == 0) {
      if (legadoCadastroFracionado) return true;
      final emUnidade = armazenado / escalaFracionada;
      if (emUnidade > 0 && emUnidade < 1) return true;
    }
    return false;
  }

  /// Parse PT-BR da coluna QTD do carrinho (`0,50` / `0.5` → 0.5).
  static double parseQuantidadeTextoCarrinho(String inputTexto) {
    final textoLimpo = inputTexto
        .trim()
        .replaceAll(RegExp(r'[\s\u00A0\u202F]'), '')
        .replaceAll(',', '.');
    return double.tryParse(textoLimpo) ?? 1.0;
  }

  /// Texto digitado no carrinho → quantidade na unidade de venda (nao milésimos).
  static double? parseEntradaCarrinho(
    String inputTexto, {
    required bool aceitaDecimal,
  }) {
    if (inputTexto.trim().isEmpty) return null;
    final v = parseQuantidadeTextoCarrinho(inputTexto);
    if (!v.isFinite || v <= 0) return null;
    if (!aceitaDecimal && v != v.roundToDouble()) return null;
    return v;
  }

  /// Quantidade de venda (ex.: 0,5) → inteiro persistido no item (ex.: 500).
  static ({int armazenado, bool gravadoEmMilesimosPdv})
      armazenarQuantidadeVendaNoCarrinho({
    required Produto produto,
    required double quantidadeVenda,
    required bool emUnidadeCompra,
  }) {
    if (emUnidadeCompra && produto.pdvPodeVenderEmUnidadeCompra) {
      return (
        armazenado: quantidadeVenda.round(),
        gravadoEmMilesimosPdv: false,
      );
    }
    final emMilesimos = pdvArmazenaEmMilesimos(
      emUnidadeCompra: false,
      quantidadeVenda: quantidadeVenda,
    );
    return (
      armazenado: paraArmazenamento(quantidadeVenda, fracionada: emMilesimos),
      gravadoEmMilesimosPdv: emMilesimos,
    );
  }

  /// Interpreta texto do PDV (aceita vírgula ou ponto).
  static double? parseEntradaPdv(String texto, {required bool fracionada}) {
    return parseEntradaCarrinho(texto, aceitaDecimal: fracionada);
  }

  static String formatarExibicao(
    double quantidade, {
    required bool fracionada,
  }) {
    if (!fracionada) return quantidade.round().toString();
    final arred = (quantidade * escalaFracionada).round() / escalaFracionada;
    if (arred == arred.roundToDouble()) {
      return arred.toStringAsFixed(0);
    }
    var s = arred.toStringAsFixed(3);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s.replaceAll('.', ',');
  }

  static double valorExibicao(int armazenado, {required bool fracionada}) {
    if (!fracionada) return armazenado.toDouble();
    return armazenado / escalaFracionada;
  }

  static int paraArmazenamento(double quantidade, {required bool fracionada}) {
    if (!fracionada) return quantidade.round();
    return (quantidade * escalaFracionada).round();
  }

  /// Quantidade inteira para baixa de estoque / promocao.
  static int paraEstoqueInteiro(Produto produto, int quantidadeArmazenada) {
    final escala = armazenadoEmMilesimos(
          quantidadeArmazenada,
          legadoCadastroFracionado: produto.permiteQuantidadeFracionada,
        ) ||
        _leituraEmbalagemUsaEscala(produto, quantidadeArmazenada);
    final q = valorExibicao(
      quantidadeArmazenada,
      fracionada: escala,
    );
    if (q <= 0) return 0;
    final milesimos = escala;
    if (milesimos) {
      // round(0,24) virava 0 e o PDV descartava a linha em silencio.
      if (q < 1) return 1;
      return q.ceil().toInt();
    }
    return q.round();
  }

  /// Texto ainda em digitacao no campo de quantidade (vazio, "5," ou "5,75").
  static bool textoQuantidadeValido(String texto, {required bool fracionada}) {
    final t = texto.trim();
    if (t.isEmpty) return true;
    if (!fracionada) return RegExp(r'^\d{1,8}$').hasMatch(t);
    return RegExp(r'^\d{1,8}([.,]\d{0,3})?$').hasMatch(t);
  }

  /// True se o texto parece quantidade decimal (ex.: 1,5 ou 2.75).
  static bool textoPareceQuantidadeDecimal(String texto) {
    final t = texto.trim().replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    if (t.isEmpty) return false;
    if (t.contains(',')) return true;
    final ponto = t.indexOf('.');
    if (ponto <= 0) return false;
    final depois = t.substring(ponto + 1);
    return depois.isNotEmpty && RegExp(r'^\d+$').hasMatch(depois);
  }

  static bool _leituraEmbalagemUsaEscala(
    Produto produto,
    int quantidadeArmazenada,
  ) {
    if (quantidadeArmazenada < escalaFracionada) return false;
    final f = produto.quantidadePorEmbalagem;
    if (f <= 0 || (f - 1).abs() < 0.0001) return false;
    final uCompra = produto.unidadeCompra.trim().toUpperCase();
    final uVenda = produto.unidade.trim().toUpperCase();
    if (uCompra.isEmpty || uCompra == uVenda) return false;
    final emUnidadeVenda =
        valorExibicao(quantidadeArmazenada, fracionada: true);
    if (emUnidadeVenda != emUnidadeVenda.roundToDouble()) return true;
    if (f != f.roundToDouble()) return true;
    return false;
  }
}
