import '../model/produto.dart';
import 'quantidade_venda_util.dart';

/// Regras de conversao entre unidade de compra/embalagem e unidade de estoque/venda.
class ProdutoEmbalagem {
  ProdutoEmbalagem._();

  static String normalizarUnidade(String? unidade) {
    final t = (unidade ?? '').trim().toUpperCase();
    if (t.isEmpty) return 'UN';
    if (t == 'METRO') return 'M';
    // Unidade comercial do fornecedor (peca) → UN de estoque.
    if (t == 'PC' ||
        t == 'PC1' ||
        t == 'PÇ' ||
        t == 'PÇ1' ||
        t == 'PEC' ||
        t == 'PECA' ||
        t == 'PEÇA' ||
        t == 'UNID' ||
        t == 'UND') {
      return 'UN';
    }
    return t;
  }

  static bool unidadesEquivalentes(String? a, String? b) {
    return normalizarUnidade(a) == normalizarUnidade(b);
  }

  /// Ha fator de embalagem configurado (diferente de 1:1).
  static bool temConversao(Produto produto) {
    final f = produto.quantidadePorEmbalagem;
    return f > 0 && (f - 1).abs() > 0.0001;
  }

  /// Unidade de compra distinta da de venda com conversao ativa.
  static bool vendaPodeUsarUnidadeCompra(Produto produto) {
    if (!temConversao(produto)) return false;
    return !unidadesEquivalentes(
      produto.unidadeCompraEfetiva,
      produto.unidade,
    );
  }

  /// Fator sugerido na conferencia NF-e quando a unidade da nota bate com o cadastro.
  static double? fatorSugeridoNotaParaEstoque({
    required Produto produto,
    required String unidadeNota,
  }) {
    if (!temConversao(produto)) return null;
    final uNota = normalizarUnidade(unidadeNota);
    final uVenda = normalizarUnidade(produto.unidade);
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    if (!unidadesEquivalentes(uNota, uCompra) &&
        !unidadesEquivalentes(uNota, uVenda)) {
      return null;
    }
    return produto.quantidadePorEmbalagem > 0
        ? produto.quantidadePorEmbalagem
        : 1;
  }

  /// Quantidade comercial da nota em unidade de venda/estoque (ex.: CX -> m²), sem arredondar.
  static double quantidadeNotaParaUnidadeVenda({
    required double quantidadeComercial,
    required double fator,
    required bool embalagemMultiplica,
  }) {
    if (fator <= 0 ||
        !quantidadeComercial.isFinite ||
        quantidadeComercial < 0) {
      return 0;
    }
    final bruto = embalagemMultiplica
        ? quantidadeComercial * fator
        : quantidadeComercial / fator;
    if (!bruto.isFinite || bruto < 0) return 0;
    return bruto;
  }

  /// Quando nao ha [Produto] vinculado, decide se grava em milésimos (×1000).
  ///
  /// Nao usar so "unidade da nota != unidade interna": PC1/UN com fator 1
  /// virava 6 → 6000. Escala fracionada so para qtd/fator nao inteiros ou
  /// unidades tipicamente fracionadas (M, M2, KG…).
  static bool notaExigeEscalaEstoque({
    required double quantidadeUnidadeVenda,
    required double fator,
    String? unidadeComercial,
    String? unidadeInterna,
  }) {
    if (quantidadeUnidadeVenda != quantidadeUnidadeVenda.roundToDouble()) {
      return true;
    }
    if (fator > 0 &&
        (fator - 1).abs() > 0.0001 &&
        fator != fator.roundToDouble()) {
      return true;
    }
    final uInt = normalizarUnidade(unidadeInterna);
    return uInt == 'M' ||
        uInt == 'M2' ||
        uInt == 'M3' ||
        uInt == 'KG' ||
        uInt == 'LT';
  }

  /// Quantidade da nota convertida para valor armazenado em [Produto.estoqueReal].
  static int quantidadeNotaParaEstoque({
    required double quantidadeComercial,
    required double fator,
    required bool embalagemMultiplica,
    Produto? produto,
    String? unidadeComercial,
    String? unidadeInterna,
  }) {
    final bruto = quantidadeNotaParaUnidadeVenda(
      quantidadeComercial: quantidadeComercial,
      fator: fator,
      embalagemMultiplica: embalagemMultiplica,
    );
    if (bruto <= 0) return 0;
    final fracionada = produto != null
        ? estoqueUsaEscalaFracionada(produto) ||
            exigeQuantidadeDecimalUnidadeVenda(produto, bruto)
        : notaExigeEscalaEstoque(
            quantidadeUnidadeVenda: bruto,
            fator: fator,
            unidadeComercial: unidadeComercial,
            unidadeInterna: unidadeInterna,
          );
    if (fracionada) {
      return QuantidadeVendaUtil.paraArmazenamento(bruto, fracionada: true);
    }
    return bruto.round();
  }

  /// Texto da quantidade convertida da nota para exibicao na conferencia.
  static String formatarQuantidadeNotaEstoque({
    required int estoqueArmazenado,
    required double quantidadeUnidadeVenda,
    Produto? produto,
    String? unidadeInterna,
    bool comUnidade = false,
  }) {
    if (produto != null) {
      return formatarEstoque(
        produto,
        estoqueArmazenado,
        comUnidade: comUnidade,
      );
    }
    final u = normalizarUnidade(unidadeInterna);
    final fracionada = quantidadeUnidadeVenda !=
            quantidadeUnidadeVenda.roundToDouble() ||
        estoqueArmazenado >= QuantidadeVendaUtil.escalaFracionada;
    final txt = QuantidadeVendaUtil.formatarExibicao(
      quantidadeUnidadeVenda,
      fracionada: fracionada,
    );
    if (!comUnidade || u.isEmpty) return txt;
    return '$txt $u';
  }

  /// Quantidade digitada no PDV convertida para estoque.
  static int quantidadeVendaParaEstoque({
    required Produto produto,
    required int quantidadeDigitada,
    required bool emUnidadeCompra,
  }) {
    if (quantidadeDigitada <= 0) return 0;
    if (!emUnidadeCompra || !vendaPodeUsarUnidadeCompra(produto)) {
      return quantidadeDigitada;
    }
    return quantidadeNotaParaEstoque(
      quantidadeComercial: quantidadeDigitada.toDouble(),
      fator: produto.quantidadePorEmbalagem,
      embalagemMultiplica: produto.embalagemMultiplica,
      produto: produto,
      unidadeComercial: produto.unidadeCompraEfetiva,
      unidadeInterna: produto.unidade,
    );
  }

  /// Converte quantidade comercial (ex.: caixas) para a unidade de venda/estoque
  /// (ex.: m²), sem arredondar — use para preco e subtotal no PDV.
  static double quantidadeComercialParaUnidadeVenda({
    required Produto produto,
    required double quantidadeComercial,
  }) {
    if (quantidadeComercial <= 0 || !quantidadeComercial.isFinite) return 0;
    final fator = produto.quantidadePorEmbalagem;
    if (fator <= 0) return quantidadeComercial;
    if (produto.embalagemMultiplica) {
      return quantidadeComercial * fator;
    }
    return quantidadeComercial / fator;
  }

  static bool exigeQuantidadeDecimalUnidadeVenda(
    Produto produto,
    double quantidadeUnidadeVenda,
  ) {
    if (produto.permiteQuantidadeFracionada) return true;
    if (quantidadeUnidadeVenda != quantidadeUnidadeVenda.roundToDouble()) {
      return true;
    }
    if (vendaPodeUsarUnidadeCompra(produto)) {
      final f = produto.quantidadePorEmbalagem;
      if (f > 0 && f != f.roundToDouble()) return true;
    }
    return false;
  }

  static String formatarQuantidadeUnidadeVenda(
    Produto produto,
    double quantidade,
  ) {
    return QuantidadeVendaUtil.formatarExibicao(
      quantidade,
      fracionada: exigeQuantidadeDecimalUnidadeVenda(produto, quantidade),
    );
  }

  /// Mesma regra de escala usada ao gravar [ItemVenda.quantidade] no PDV.
  static bool leituraUsaEscalaFracionada(
    Produto produto,
    int quantidadeArmazenada,
  ) {
    if (produto.permiteQuantidadeFracionada) return true;
    if (!vendaPodeUsarUnidadeCompra(produto)) return false;
    if (quantidadeArmazenada < QuantidadeVendaUtil.escalaFracionada) {
      return false;
    }
    final emUnidadeVenda = QuantidadeVendaUtil.valorExibicao(
      quantidadeArmazenada,
      fracionada: true,
    );
    return exigeQuantidadeDecimalUnidadeVenda(produto, emUnidadeVenda);
  }

  /// Converte [ItemVenda.quantidade] persistido para quantidade do carrinho PDV.
  static ({int quantidadeDigitada, bool emUnidadeCompra})
      quantidadeCarrinhoDeItemPersistido({
    required Produto produto,
    required int quantidadeArmazenada,
  }) {
    if (quantidadeArmazenada <= 0) {
      return (quantidadeDigitada: 0, emUnidadeCompra: false);
    }
    if (vendaPodeUsarUnidadeCompra(produto)) {
      if (quantidadeArmazenada < QuantidadeVendaUtil.escalaFracionada &&
          !produto.permiteQuantidadeFracionada) {
        return (
          quantidadeDigitada: quantidadeArmazenada,
          emUnidadeCompra: true,
        );
      }
      final m2 = quantidadeVendaEfetivaItem(
        produto: produto,
        quantidadeArmazenada: quantidadeArmazenada,
      );
      var comercial = produto.embalagemMultiplica
          ? m2 / produto.quantidadePorEmbalagem
          : m2 * produto.quantidadePorEmbalagem;
      if (!comercial.isFinite || comercial <= 0) {
        comercial = quantidadeArmazenada.toDouble();
      }
      final digitada = comercial.round().clamp(1, 1 << 30);
      return (quantidadeDigitada: digitada, emUnidadeCompra: true);
    }
    if (produto.permiteQuantidadeFracionada ||
        leituraUsaEscalaFracionada(produto, quantidadeArmazenada)) {
      return (
        quantidadeDigitada: quantidadeArmazenada,
        emUnidadeCompra: false,
      );
    }
    return (
      quantidadeDigitada: quantidadeArmazenada,
      emUnidadeCompra: false,
    );
  }

  /// Interpreta [ItemVenda.quantidade] persistido (espelha a gravacao PDV).
  static double quantidadeVendaEfetivaItem({
    required Produto? produto,
    required int quantidadeArmazenada,
  }) {
    if (produto == null) {
      return QuantidadeVendaUtil.valorExibicao(
        quantidadeArmazenada,
        fracionada: false,
      );
    }
    return QuantidadeVendaUtil.valorExibicao(
      quantidadeArmazenada,
      fracionada: leituraUsaEscalaFracionada(produto, quantidadeArmazenada),
    );
  }

  /// Estoque fisico usa milésimos (ex.: 144,62 m² → 144620) para pisos CX/m².
  static bool estoqueUsaEscalaFracionada(Produto produto) {
    if (produto.permiteQuantidadeFracionada) return true;
    return vendaPodeUsarUnidadeCompra(produto);
  }

  /// Converte estoque legado (m² inteiros no banco) para a escala atual.
  static int estoqueLegadoParaArmazenado(Produto produto, int estoqueBruto) {
    if (estoqueBruto == 0 || !estoqueUsaEscalaFracionada(produto)) {
      return estoqueBruto;
    }
    if (estoqueBruto < QuantidadeVendaUtil.escalaFracionada) {
      return estoqueBruto * QuantidadeVendaUtil.escalaFracionada;
    }
    return estoqueBruto;
  }

  /// Migra estoque legado in-place antes de movimentar (primeira baixa/entrada).
  static void garantirEstoqueEmEscalaNoProduto(Produto produto) {
    if (!estoqueUsaEscalaFracionada(produto)) return;
    final fisico = estoqueLegadoParaArmazenado(produto, produto.estoqueReal);
    if (fisico != produto.estoqueReal) {
      produto.estoqueReal = fisico;
      produto.estoqueAtual = fisico;
    }
    if (produto.estoqueReservado > 0 &&
        produto.estoqueReservado < QuantidadeVendaUtil.escalaFracionada) {
      produto.estoqueReservado *= QuantidadeVendaUtil.escalaFracionada;
    }
  }

  /// Valor em [Produto.unidade] para exibicao (ex.: 144,62 m²).
  static double valorEstoqueExibicao(Produto produto, int estoqueArmazenado) {
    if (estoqueArmazenado == 0) return 0;
    if (!estoqueUsaEscalaFracionada(produto)) {
      return estoqueArmazenado.toDouble();
    }
    return estoqueLegadoParaArmazenado(produto, estoqueArmazenado) /
        QuantidadeVendaUtil.escalaFracionada;
  }

  /// Media diaria persistida ([Produto.vendaMediaDiaria]) na unidade de venda.
  ///
  /// A media e gravada na mesma escala de [ItemVenda.quantidade] (raw). Valores
  /// >= 1000 em produto fracionado sao milésimos/dia (2410,33 → 2,41 m²/dia).
  static double valorMediaDiariaExibicao(
    Produto produto,
    double mediaArmazenada,
  ) {
    if (!mediaArmazenada.isFinite || mediaArmazenada <= 0) return 0;
    if (!estoqueUsaEscalaFracionada(produto)) return mediaArmazenada;
    if (mediaArmazenada >= QuantidadeVendaUtil.escalaFracionada) {
      return mediaArmazenada / QuantidadeVendaUtil.escalaFracionada;
    }
    return mediaArmazenada;
  }

  /// Texto da media diaria na unidade de venda (ex.: "2,41").
  static String formatarMediaDiaria(
    Produto produto,
    double mediaArmazenada, {
    bool comUnidade = false,
  }) {
    final v = valorMediaDiariaExibicao(produto, mediaArmazenada);
    if (v <= 0) return '—';
    final txt = formatarQuantidadeUnidadeVenda(produto, v);
    if (!comUnidade) return txt;
    return '$txt ${normalizarUnidade(produto.unidade)}';
  }

  static String formatarEstoque(
    Produto produto,
    int estoqueArmazenado, {
    bool comUnidade = false,
  }) {
    final v = valorEstoqueExibicao(produto, estoqueArmazenado);
    final txt = formatarQuantidadeUnidadeVenda(produto, v);
    if (!comUnidade) return txt;
    return '$txt ${normalizarUnidade(produto.unidade)}';
  }

  /// Texto enriquecido: "144,62 M2 (≈ 55 CX)" quando vende por caixa.
  static String formatarEstoqueDetalhado(
    Produto produto,
    int estoqueArmazenado,
  ) {
    final base = formatarEstoque(produto, estoqueArmazenado, comUnidade: true);
    if (!vendaPodeUsarUnidadeCompra(produto)) return base;
    final m2 = valorEstoqueExibicao(produto, estoqueArmazenado);
    final f = produto.quantidadePorEmbalagem;
    if (f <= 0 || !m2.isFinite || m2 <= 0) return base;
    final cx = m2 / f;
    if (!cx.isFinite || cx <= 0) return base;
    final cxTxt = formatarQuantidadeUnidadeVenda(produto, cx);
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    return '$base (≈ $cxTxt $uCompra)';
  }

  static int? parseEstoqueEntrada(String texto, Produto produto) {
    final fracionada = estoqueUsaEscalaFracionada(produto);
    final v = QuantidadeVendaUtil.parseEntradaPdv(
      texto,
      fracionada: fracionada,
    );
    if (v == null) return null;
    if (!fracionada) return v.round();
    return QuantidadeVendaUtil.paraArmazenamento(v, fracionada: true);
  }

  /// Unidades de estoque a abater/adicionar a partir do valor persistido do item.
  static int unidadeEstoqueDeQuantidadeArmazenada({
    required Produto? produto,
    required int quantidadeArmazenada,
  }) {
    if (quantidadeArmazenada <= 0) return 0;
    if (produto == null) return quantidadeArmazenada;
    if (produto.permiteQuantidadeFracionada ||
        leituraUsaEscalaFracionada(produto, quantidadeArmazenada)) {
      return quantidadeArmazenada;
    }
    return QuantidadeVendaUtil.paraEstoqueInteiro(produto, quantidadeArmazenada);
  }

  /// Texto de quantidade para UI (caixa, listagens) a partir do valor persistido.
  static String textoQuantidadeArmazenada({
    required Produto? produto,
    required int quantidadeArmazenada,
  }) {
    if (produto == null) {
      return quantidadeArmazenada.toString();
    }
    final carrinho = quantidadeCarrinhoDeItemPersistido(
      produto: produto,
      quantidadeArmazenada: quantidadeArmazenada,
    );
    if (carrinho.emUnidadeCompra) {
      return rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: carrinho.quantidadeDigitada,
        emUnidadeCompra: true,
      );
    }
    final qtd = quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: quantidadeArmazenada,
    );
    return formatarQuantidadeUnidadeVenda(produto, qtd);
  }

  /// Incremento/decremento em [ItemVenda.quantidade] (caixa +/-).
  static int passoQuantidadeArmazenada({
    required Produto? produto,
    required int quantidadeArmazenada,
  }) {
    if (produto == null) return 1;
    final carrinho = quantidadeCarrinhoDeItemPersistido(
      produto: produto,
      quantidadeArmazenada: quantidadeArmazenada,
    );
    if (carrinho.emUnidadeCompra && vendaPodeUsarUnidadeCompra(produto)) {
      return quantidadeArmazenadaItemVenda(
        produto: produto,
        quantidadeDigitada: 1,
        emUnidadeCompra: true,
      );
    }
    if (produto.permiteQuantidadeFracionada ||
        leituraUsaEscalaFracionada(produto, quantidadeArmazenada)) {
      return QuantidadeVendaUtil.passoFracionadoArmazenado;
    }
    return 1;
  }

  /// Quantidade armazenada em [ItemVenda.quantidade] a partir do carrinho PDV.
  static int quantidadeArmazenadaItemVenda({
    required Produto produto,
    required int quantidadeDigitada,
    required bool emUnidadeCompra,
  }) {
    if (emUnidadeCompra && vendaPodeUsarUnidadeCompra(produto)) {
      final m2 = quantidadeComercialParaUnidadeVenda(
        produto: produto,
        quantidadeComercial: quantidadeDigitada.toDouble(),
      );
      return QuantidadeVendaUtil.paraArmazenamento(
        m2,
        fracionada: exigeQuantidadeDecimalUnidadeVenda(produto, m2),
      );
    }
    return quantidadeDigitada;
  }

  /// Texto curto para UI (ex.: "1 CX = 12 UN").
  static String rotuloConversao(Produto produto) {
    final fator = produto.quantidadePorEmbalagem;
    if (fator <= 0 || (fator - 1).abs() < 0.0001) return '';
    final fatorTxt = fator == fator.roundToDouble()
        ? fator.toInt().toString()
        : fator.toStringAsFixed(2);
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    final uVenda = normalizarUnidade(produto.unidade);
    if (uCompra == uVenda) {
      return produto.embalagemMultiplica
          ? 'Fator $fatorTxt $uVenda por embalagem'
          : 'Fator $fatorTxt $uVenda por embalagem (divide)';
    }
    return produto.embalagemMultiplica
        ? '1 $uCompra = $fatorTxt $uVenda'
        : '1 $uCompra = 1 $uVenda (÷ $fatorTxt)';
  }

  /// Linha do carrinho PDV com unidade de compra.
  static String rotuloQuantidadeCarrinho({
    required Produto produto,
    required int quantidadeDigitada,
    required bool emUnidadeCompra,
  }) {
    final uVenda = normalizarUnidade(produto.unidade);
    if (!emUnidadeCompra || !vendaPodeUsarUnidadeCompra(produto)) {
      if (produto.permiteQuantidadeFracionada) {
        final qTxt = QuantidadeVendaUtil.formatarExibicao(
          QuantidadeVendaUtil.valorExibicao(
            quantidadeDigitada,
            fracionada: true,
          ),
          fracionada: true,
        );
        return '$qTxt $uVenda';
      }
      return '$quantidadeDigitada $uVenda';
    }
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    final qVenda = quantidadeComercialParaUnidadeVenda(
      produto: produto,
      quantidadeComercial: quantidadeDigitada.toDouble(),
    );
    final qVendaTxt = formatarQuantidadeUnidadeVenda(produto, qVenda);
    return '$quantidadeDigitada $uCompra (= $qVendaTxt $uVenda)';
  }
}
