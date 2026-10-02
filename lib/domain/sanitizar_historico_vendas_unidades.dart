import '../model/item_venda.dart';
import '../model/produto.dart';
import 'produto_embalagem.dart';
import 'quantidade_venda_util.dart';

/// Resultado da passagem de correcao de escala/quantidade em itens UN/PC.
class SanitizarHistoricoVendasUnidadesResultado {
  const SanitizarHistoricoVendasUnidadesResultado({
    required this.itensAnalisados,
    required this.itensCorrigidos,
    required this.detalhes,
  });

  final int itensAnalisados;
  final int itensCorrigidos;
  final List<String> detalhes;
}

/// Limiar de quantidade armazenada suspeita para UN/PC inteiro.
const int kSanitizarQuantidadeArmazenadaMinimaSuspeita = 10000;

/// Detecta e corrige linhas UN/PC gravadas com escala errada (ex.: milésimos
/// interpretados como unidades literais, gerando CMV/lucro astronomicos).
abstract final class SanitizarHistoricoVendasUnidades {
  SanitizarHistoricoVendasUnidades._();

  static bool _unidadeTipicaInteira(Produto produto) {
    final u = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    return u == 'UN' || u == 'PC' || u == 'PÇ' || u == 'PCA';
  }

  static bool _candidatoSanitizacao(ItemVenda item, Produto produto) {
    if (item.quantidade < kSanitizarQuantidadeArmazenadaMinimaSuspeita) {
      return false;
    }
    if (!_unidadeTipicaInteira(produto)) return false;
    if (!ProdutoEmbalagem.produtoLeQuantidadeArmazenadaComoInteiroLiteral(
      produto,
    )) {
      return false;
    }
    return true;
  }

  static bool _valoresProximos(double a, double b, {double tolerancia = 0.05}) {
    if (!a.isFinite || !b.isFinite) return false;
    final ref = a.abs() > b.abs() ? a.abs() : b.abs();
    if (ref < 0.01) return (a - b).abs() < 0.01;
    return (a - b).abs() / ref <= tolerancia;
  }

  /// Retorna alteracoes a aplicar ou `null` se a linha estiver coerente.
  static ({int novaQuantidade, int novaEscala})? proporCorrecao(
    ItemVenda item,
    Produto produto,
  ) {
    if (!_candidatoSanitizacao(item, produto)) return null;
    if (item.precoUnitario <= 0) return null;

    final qArm = item.quantidade;
    final preco = item.precoUnitario;
    final fatLiteral = qArm * preco;
    final qComoMilesimos = qArm / QuantidadeVendaUtil.escalaFracionada;
    final fatMilesimos = qComoMilesimos * preco;

    final leituraAtualMilesimos = ProdutoEmbalagem.leituraArmazenadaEmMilesimos(
      produto: produto,
      quantidadeArmazenada: qArm,
      emMilesimos: item.quantidadeEmMilesimosPersistida,
    );

    final milesimosPlausivel =
        fatMilesimos >= 0.01 && fatMilesimos <= 500000;
    final literalAbsurdo = fatLiteral > fatMilesimos * 50;

    // Escala literal, mas o faturamento coerente e o da leitura em milésimos.
    if (!leituraAtualMilesimos &&
        qArm >= QuantidadeVendaUtil.escalaFracionada &&
        milesimosPlausivel &&
        literalAbsurdo) {
      if (qComoMilesimos == qComoMilesimos.round()) {
        return (
          novaQuantidade: qComoMilesimos.round(),
          novaEscala: ItemVenda.escalaQuantidadeLiteral,
        );
      }
      return (
        novaQuantidade: qArm,
        novaEscala: ItemVenda.escalaQuantidadeMilesimos,
      );
    }

    // Escala milésimos, mas volume comercial inteiro bate com literal.
    if (leituraAtualMilesimos &&
        qArm >= QuantidadeVendaUtil.escalaFracionada &&
        qArm % QuantidadeVendaUtil.escalaFracionada == 0 &&
        fatLiteral <= fatMilesimos * 50 &&
        !_valoresProximos(fatMilesimos, fatLiteral)) {
      return (
        novaQuantidade: qArm ~/ QuantidadeVendaUtil.escalaFracionada,
        novaEscala: ItemVenda.escalaQuantidadeLiteral,
      );
    }

    // Venda avulsa barata com quantidade armazenada desproporcional.
    if (!leituraAtualMilesimos &&
        fatMilesimos < 500 &&
        literalAbsurdo &&
        milesimosPlausivel) {
      return (
        novaQuantidade: qArm,
        novaEscala: ItemVenda.escalaQuantidadeMilesimos,
      );
    }

    return null;
  }

  static SanitizarHistoricoVendasUnidadesResultado executarEmItens(
    Iterable<ItemVenda> itens,
    Produto? Function(int produtoId) obterProduto, {
    void Function(ItemVenda item)? persistir,
  }) {
    var analisados = 0;
    var corrigidos = 0;
    final detalhes = <String>[];

    for (final item in itens) {
      final pid = item.produto.targetId;
      if (pid <= 0) continue;
      final prod = obterProduto(pid);
      if (prod == null) continue;
      if (!_candidatoSanitizacao(item, prod)) continue;
      analisados++;
      final prop = proporCorrecao(item, prod);
      if (prop == null) continue;
      final antesQ = item.quantidade;
      final antesE = item.escalaQuantidade;
      item.quantidade = prop.novaQuantidade;
      item.escalaQuantidade = prop.novaEscala;
      persistir?.call(item);
      corrigidos++;
      detalhes.add(
        'ItemVenda#${item.id} produto#${pid}: q $antesQ→${item.quantidade}, '
        'escala $antesE→${item.escalaQuantidade}',
      );
    }

    return SanitizarHistoricoVendasUnidadesResultado(
      itensAnalisados: analisados,
      itensCorrigidos: corrigidos,
      detalhes: detalhes,
    );
  }
}
