import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../entrega_venda_helper.dart';
import '../produto_embalagem.dart';
import '../produto_unidade_exibicao.dart';
import '../quantidade_venda_util.dart';
import 'loja_origem_mercadoria.dart';

/// Campo numerico do modal "Buscar na nossa loja": o motorista digita na
/// unidade de venda (6,3 M²) e [armazenadoDe] devolve o valor persistido
/// (6300 quando a linha usa milésimos).
class EntradaQuantidadeBuscarNaLoja {
  const EntradaQuantidadeBuscarNaLoja({
    required this.totalArmazenado,
    required this.emMilesimos,
    required this.aceitaDecimal,
    required this.unidade,
    required this.inicialArmazenado,
  });

  final int totalArmazenado;

  /// [totalArmazenado] esta em milésimos (6300 = 6,3).
  final bool emMilesimos;

  /// Campo aceita casas decimais (M², KG...); UN/SC so inteiros.
  final bool aceitaDecimal;

  /// Rotulo legivel (M², UN, SC, KG). Vazio quando o produto nao resolveu.
  final String unidade;

  final int inicialArmazenado;

  double get totalExibicao => exibicaoDe(totalArmazenado);

  double exibicaoDe(int armazenado) => QuantidadeVendaUtil.valorExibicao(
        armazenado,
        fracionada: emMilesimos,
      );

  String textoExibicao(int armazenado) {
    final q = exibicaoDe(armazenado);
    return QuantidadeVendaUtil.formatarExibicao(
      q,
      fracionada: q != q.roundToDouble(),
    );
  }

  String textoComUnidade(int armazenado) {
    final q = textoExibicao(armazenado);
    return unidade.isEmpty ? q : '$q $unidade';
  }

  String get textoTotal => textoExibicao(totalArmazenado);
  String get textoTotalComUnidade => textoComUnidade(totalArmazenado);
  String get textoInicial => textoExibicao(inicialArmazenado);

  /// Texto parcial aceito durante a digitacao (vazio, "3," ou "3,15").
  bool textoDigitacaoValido(String texto) =>
      QuantidadeVendaUtil.textoQuantidadeValido(
        texto,
        fracionada: aceitaDecimal,
      );

  /// Mensagem de erro do campo ou `null` se [texto] for valido.
  String? validar(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return 'Informe a quantidade';
    final v = _parse(t);
    if (v == null) return 'Quantidade inválida';
    if (!aceitaDecimal && v != v.roundToDouble()) {
      return 'Use número inteiro';
    }
    if (v <= 0 || _paraArmazenado(v) <= 0) return 'Quantidade inválida';
    if (v > totalExibicao + 1e-9) {
      return 'Máximo $textoTotalComUnidade';
    }
    return null;
  }

  /// Valor persistido para a API/banco ou `null` se [texto] for invalido.
  int? armazenadoDe(String texto) {
    if (validar(texto) != null) return null;
    final v = _parse(texto.trim())!;
    final arm = _paraArmazenado(v);
    return arm > totalArmazenado ? totalArmazenado : arm;
  }

  int _paraArmazenado(double quantidadeExibicao) =>
      QuantidadeVendaUtil.paraArmazenamento(
        quantidadeExibicao,
        fracionada: emMilesimos,
      );

  static double? _parse(String texto) {
    final t = texto
        .replaceAll(RegExp(r'[\s\u00A0\u202F]'), '')
        .replaceAll(',', '.');
    final v = double.tryParse(t);
    if (v == null || !v.isFinite) return null;
    return v;
  }
}

/// Motorista na outra loja pede para buscar o item nesta prateleira.
///
/// Nao misturar com complemento (falta na casa do cliente).
abstract final class BuscarNaLoja {
  BuscarNaLoja._();

  static const solicitar = 'solicitar';
  static const confirmar = 'confirmar';
  static const cancelar = 'cancelar';

  static const solicitado = 'solicitado';
  static const separado = 'separado';

  static bool ehSolicitado(String? status) =>
      (status ?? '').trim() == solicitado;

  static bool ehSeparado(String? status) => (status ?? '').trim() == separado;

  static bool temPendente(Venda venda, [Iterable<ItemVenda>? itens]) {
    for (final item in itens ?? _itens(venda)) {
      if (ehSolicitado(item.buscarNaLojaStatus)) return true;
    }
    return false;
  }

  static int contarPedidosPendentes(
    Iterable<Venda> vendas, [
    Iterable<ItemVenda> Function(Venda venda)? itensDe,
  ]) {
    var n = 0;
    for (final v in vendas) {
      if (temPendente(v, itensDe?.call(v))) n++;
    }
    return n;
  }

  static List<ItemVenda> pendentesDaVenda(
    Venda venda, [
    Iterable<ItemVenda>? itens,
  ]) {
    return [
      for (final item in itens ?? _itens(venda))
        if (ehSolicitado(item.buscarNaLojaStatus)) item,
    ];
  }

  static String? resumoPendentes(Venda venda, [Iterable<ItemVenda>? itens]) {
    final linhas = <String>[];
    for (final item in pendentesDaVenda(venda, itens)) {
      linhas.add('${rotuloQuantidade(venda, item)} ${item.nomeProduto}');
    }
    if (linhas.isEmpty) return null;
    return 'Buscar nesta loja: ${linhas.join('; ')}';
  }

  static bool podeSolicitarItem(Venda venda, ItemVenda item) {
    if (!_entregaAberta(venda)) return false;
    if (!EntregaVendaHelper.itemEntraNaCargaEntrega(venda, item)) return false;
    if (_qtd(venda, item) <= 0) return false;
    if (ehSeparado(item.buscarNaLojaStatus)) return false;
    final origem = LojaOrigemMercadoria.origemEfetiva(
      origemItem: item.lojaOrigemMercadoria,
      origemVenda: venda.lojaOrigemMercadoria,
      cargaSaiu: venda.cargaSaiu,
    );
    return !LojaOrigemMercadoria.ehLocal(origem);
  }

  static bool podeCancelarItem(Venda venda, ItemVenda item) {
    if (!_entregaAberta(venda)) return false;
    return ehSolicitado(item.buscarNaLojaStatus) ||
        ehSeparado(item.buscarNaLojaStatus);
  }

  static bool _entregaAberta(Venda venda) {
    if (venda.cancelada) return false;
    switch (venda.statusEntrega) {
      case 'entregue':
      case 'entregue_complemento_pendente':
      case 'cancelada':
        return false;
      default:
        return true;
    }
  }

  static int qtdCarga(Venda venda, ItemVenda item) => _qtd(venda, item);

  static int clampQuantidade(Venda venda, ItemVenda item, int quantidade) {
    final max = qtdCarga(venda, item);
    if (max <= 0) return 0;
    if (quantidade < 1) return 1;
    if (quantidade > max) return max;
    return quantidade;
  }

  static String rotuloQuantidade(
    Venda venda,
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
    int? quantidadeArmazenada,
  }) {
    final total = qtdCarga(venda, item);
    final q = quantidadeArmazenada != null
        ? clampQuantidade(venda, item, quantidadeArmazenada)
        : quantidadeEfetiva(venda, item);
    final produto = EntregaVendaHelper.produtoItemEntrega(
      item,
      obterProduto: obterProduto,
    );
    if (produto == null) {
      if (q >= total) return '${total}x';
      return '$q de $total';
    }
    final totalTxt = EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
      item,
      quantidadeArmazenada: total,
      obterProduto: obterProduto,
    );
    if (q >= total) return '${totalTxt}x';
    final qTxt = _textoQuantidadeExibicaoRelativa(
      venda,
      item,
      q,
      obterProduto: obterProduto,
    );
    return '$qTxt de $totalTxt';
  }

  /// Estado inicial do campo numerico do modal (`null` = nada a buscar).
  ///
  /// A escala vem de [ItemVenda.escalaQuantidade]; itens legados usam a
  /// heuristica do romaneio e, em unidades de medida (M², KG...), tratam
  /// valores >= 1000 como milésimos para nunca exibir 6300 no lugar de 6,3.
  static EntradaQuantidadeBuscarNaLoja? entradaQuantidadeModal(
    Venda venda,
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    final totalArm = qtdCarga(venda, item);
    if (totalArm <= 0) return null;
    final produto = EntregaVendaHelper.produtoItemEntrega(
      item,
      obterProduto: obterProduto,
    );
    final emMilesimos = _escalaMilesimos(
      venda,
      item,
      totalArm,
      produto: produto,
      obterProduto: obterProduto,
    );
    final unidadeInteira =
        produto != null && _modalIncrementoInteiroUnidade(produto);
    return EntradaQuantidadeBuscarNaLoja(
      totalArmazenado: totalArm,
      emMilesimos: emMilesimos,
      aceitaDecimal: emMilesimos && !unidadeInteira,
      unidade: produto == null
          ? ''
          : rotuloUnidadeProdutoExibicao(
              ProdutoEmbalagem.normalizarUnidade(produto.unidade),
            ),
      inicialArmazenado: item.quantidadeBuscarNaLoja > 0
          ? clampQuantidade(venda, item, item.quantidadeBuscarNaLoja)
          : totalArm,
    );
  }

  /// Converte quantidade digitada na UI (unidade real) para milésimos/inteiro.
  static int armazenadoDeQuantidadeExibicao(
    Venda venda,
    ItemVenda item,
    double quantidadeExibicao, {
    Produto? Function(int id)? obterProduto,
  }) {
    if (quantidadeExibicao <= 0) return 0;
    final entrada = entradaQuantidadeModal(
      venda,
      item,
      obterProduto: obterProduto,
    );
    if (entrada == null) return 0;
    if (quantidadeExibicao >= entrada.totalExibicao - 1e-9) {
      return entrada.totalArmazenado;
    }
    final arm = QuantidadeVendaUtil.paraArmazenamento(
      quantidadeExibicao,
      fracionada: entrada.emMilesimos,
    );
    return clampQuantidade(venda, item, arm);
  }

  static bool _escalaMilesimos(
    Venda venda,
    ItemVenda item,
    int totalArm, {
    required Produto? produto,
    Produto? Function(int id)? obterProduto,
  }) {
    final persistida = item.quantidadeEmMilesimosPersistida;
    if (persistida != null) return persistida;
    final totalExib = EntregaVendaHelper.quantidadeRomaneioCargaExibicao(
      venda,
      item,
      obterProduto: obterProduto,
    );
    if ((totalExib - totalArm).abs() > 1e-9) return true;
    return produto != null &&
        totalArm >= QuantidadeVendaUtil.escalaFracionada &&
        (produto.permiteQuantidadeFracionada ||
            ProdutoEmbalagem.unidadeVendaTipicamenteFracionada(
              produto.unidade,
            ));
  }

  /// UN/SC/PC etc.: campo so aceita inteiros na unidade de venda.
  static bool _modalIncrementoInteiroUnidade(Produto produto) {
    switch (ProdutoEmbalagem.normalizarUnidade(produto.unidade)) {
      case 'UN':
      case 'SC':
      case 'PC':
      case 'PC1':
      case 'CX':
      case 'PCT':
      case 'RL':
        return true;
      default:
        return false;
    }
  }

  static String _textoQuantidadeExibicaoRelativa(
    Venda venda,
    ItemVenda item,
    int armazenado, {
    Produto? Function(int id)? obterProduto,
  }) {
    final totalArm = qtdCarga(venda, item);
    if (armazenado <= 0 || totalArm <= 0) return '0';
    if (armazenado >= totalArm) {
      return EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
        item,
        quantidadeArmazenada: totalArm,
        obterProduto: obterProduto,
      );
    }
    final totalExib = EntregaVendaHelper.quantidadeRomaneioCargaExibicao(
      venda,
      item,
      obterProduto: obterProduto,
    );
    final qExib = armazenado / totalArm * totalExib;
    final produto = EntregaVendaHelper.produtoItemEntrega(
      item,
      obterProduto: obterProduto,
    );
    if (produto == null) {
      return qExib.round().toString();
    }
    final qTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(produto, qExib);
    final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    return u.isEmpty ? qTxt : '$qTxt $u';
  }

  static int quantidadeEfetiva(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    if (total <= 0) return 0;
    if (item.quantidadeBuscarNaLoja <= 0) return total;
    return item.quantidadeBuscarNaLoja.clamp(1, total);
  }

  /// Confirmar no patio: linha inteira = desta loja; recorte = misto.
  static String origemAposConfirmar(Venda venda, ItemVenda item) {
    final total = qtdCarga(venda, item);
    final q = quantidadeEfetiva(venda, item);
    if (total > 0 && q < total) return LojaOrigemMercadoria.misto;
    return LojaOrigemMercadoria.local;
  }

  static Map<int, int> parseQuantidades(dynamic raw) {
    if (raw is! Map) return {};
    final out = <int, int>{};
    raw.forEach((k, v) {
      final id = int.tryParse(k.toString()) ?? 0;
      if (id <= 0) return;
      final q = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      if (q > 0) out[id] = q;
    });
    return out;
  }

  static int _qtd(Venda venda, ItemVenda item) =>
      EntregaVendaHelper.quantidadeRomaneioCarga(venda, item);

  static Iterable<ItemVenda> _itens(Venda venda) {
    try {
      return venda.itens;
    } catch (_) {
      return const <ItemVenda>[];
    }
  }
}
