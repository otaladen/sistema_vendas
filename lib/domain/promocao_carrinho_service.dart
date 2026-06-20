import '../data/promocao_repository.dart';
import '../model/produto.dart';
import '../model/promocao.dart';
import 'promocao_cadastro.dart';

/// Linha minima do carrinho para aplicar combos.
abstract class PromocaoCarrinhoLinha {
  Produto get produto;
  int get quantidadeEstoque;
  int get promocaoId;
  set promocaoId(int value);
  double get precoUnitario;
  set precoUnitario(double value);
  String get precoTipo;
  set precoTipo(String value);
  String get promocaoNome;
  set promocaoNome(String value);
  bool get precoManual => false;
}

/// Ajusta precos de combo A+B e leve/pague no carrinho.
class PromocaoCarrinhoService {
  PromocaoCarrinhoService(this._repo);

  final PromocaoRepository _repo;

  void aplicarRegrasCarrinho(
    List<PromocaoCarrinhoLinha> linhas, {
    required DateTime dataReferencia,
    String? segmentoCliente,
  }) {
    final promos = _repo.listarVigentesNaData(dataReferencia);
    for (final promo in promos) {
      if (!PromocaoCadastro.promocaoAceitaSegmento(promo, segmentoCliente)) {
        continue;
      }
      final tipo = PromocaoCadastro.normalizarTipoCampanha(promo.tipoCampanha);
      if (tipo == PromocaoCadastro.tipoComboAb) {
        _aplicarComboAb(linhas, promo);
      }
    }
    for (final linha in linhas) {
      if (linha.precoManual) continue;
      if (linha.promocaoId <= 0) continue;
      final promo = _repo.obterPorId(linha.promocaoId);
      if (promo == null) continue;
      if (PromocaoCadastro.normalizarTipoCampanha(promo.tipoCampanha) !=
          PromocaoCadastro.tipoLevePague) {
        continue;
      }
      if (promo.leveQuantidade < 2 || promo.pagueQuantidade < 1) continue;
      if (linha.quantidadeEstoque < promo.leveQuantidade) continue;
      linha.precoUnitario = PromocaoCadastro.aplicarLevePagueNoPreco(
        tipoCampanha: promo.tipoCampanha,
        precoBasePromo: linha.precoUnitario,
        quantidade: linha.quantidadeEstoque,
        leveQuantidade: promo.leveQuantidade,
        pagueQuantidade: promo.pagueQuantidade,
      ).clamp(0, double.infinity);
    }
  }

  void _aplicarComboAb(List<PromocaoCarrinhoLinha> linhas, Promocao promo) {
    promo.comboItens.length;
    if (promo.comboItens.isEmpty || promo.precoCombo <= 0) return;

    final requisitos = <int, int>{};
    for (final c in promo.comboItens) {
      if (c.produtoAlvoId <= 0) return;
      requisitos[c.produtoAlvoId] = c.quantidade;
    }

    final linhasCombo = <PromocaoCarrinhoLinha>[];
    for (final l in linhas) {
      if (l.precoManual) continue;
      final req = requisitos[l.produto.id];
      if (req != null && l.quantidadeEstoque >= req) {
        linhasCombo.add(l);
      }
    }
    if (linhasCombo.length != requisitos.length) return;

    var pesoTotal = 0.0;
    for (final l in linhasCombo) {
      pesoTotal += PromocaoPrecoServiceHelper.preco1(l.produto) * l.quantidadeEstoque;
    }
    if (pesoTotal <= 0) return;

    for (final l in linhasCombo) {
      final peso = PromocaoPrecoServiceHelper.preco1(l.produto) * l.quantidadeEstoque;
      final parte = promo.precoCombo * (peso / pesoTotal);
      l.precoUnitario = (parte / l.quantidadeEstoque).clamp(0, double.infinity);
      l.promocaoId = promo.id;
      l.promocaoNome = promo.nome;
      l.precoTipo = PromocaoCadastro.precoTipoPromo;
    }
  }
}

/// Evita import circular com [PromocaoPrecoService].
class PromocaoPrecoServiceHelper {
  static double preco1(Produto p) => p.preco1 > 0 ? p.preco1 : p.precoVenda;
}
