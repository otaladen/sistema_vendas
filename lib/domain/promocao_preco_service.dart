import '../model/produto.dart';
import '../model/promocao.dart';
import '../model/promocao_combo_item.dart';
import '../model/promocao_item.dart';
import 'promocao_cadastro.dart';
import 'promocao_info_vigente.dart';
import 'promocao_preco_result.dart';

/// Resolve preco promocional (base % sempre em [Produto.preco1]).
///
/// Aceita [PromocaoRepository] ou [PromocaoApiRepository] (duck typing).
class PromocaoPrecoService {
  PromocaoPrecoService(this._repo);

  final dynamic _repo;

  static double preco1Base(Produto produto) {
    return produto.preco1 > 0 ? produto.preco1 : produto.precoVenda;
  }

  static double precoLista(Produto produto, String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
      case 'preco3':
        return produto.preco3 > 0 ? produto.preco3 : produto.precoVenda;
      case 'preco1':
      default:
        return preco1Base(produto);
    }
  }

  List<PromocaoInfoVigente> listarCampanhasVigentesParaProduto(
    Produto produto, {
    required DateTime dataReferencia,
    String? segmentoCliente,
    int quantidade = 1,
  }) {
    final out = <PromocaoInfoVigente>[];
    for (final promo in _repo.listarVigentesNaData(dataReferencia)) {
      if (!PromocaoCadastro.promocaoAceitaSegmento(promo, segmentoCliente)) {
        continue;
      }
      final tipo = PromocaoCadastro.normalizarTipoCampanha(promo.tipoCampanha);
      if (tipo == PromocaoCadastro.tipoComboAb) {
        final combo = _comboDe(promo);
        if (combo.isEmpty) continue;
        final nomes = <String>[];
        for (final c in combo) {
          nomes.add('SKU#${c.produtoAlvoId} x${c.quantidade}');
        }
        out.add(
          PromocaoInfoVigente(
            promocaoId: promo.id,
            nome: promo.nome,
            tipoCampanha: tipo,
            tipoRegra: promo.tipoRegra,
            valorRegra: promo.valorRegra,
            dataFim: promo.dataFim,
            precoCalculado: promo.precoCombo,
            precoBasePreco1: preco1Base(produto),
            margemMinimaPercentual: promo.margemMinimaPercentual,
            quantidadeRestanteGlobal: _restanteGlobal(promo),
            precoCombo: promo.precoCombo,
            descricaoCombo:
                'Combo: ${nomes.join(' + ')} por R\$ ${promo.precoCombo.toStringAsFixed(2)}',
          ),
        );
        continue;
      }
      final item = _itemQueCasa(promo, produto, quantidade);
      if (item == null) continue;
      if (!_passaLimites(promo, item, quantidade)) continue;
      final base = preco1Base(produto);
      final precoRegra = _calcularPrecoPromocional(
        promo: promo,
        precoBasePreco1: base,
      );
      final qtdRef = tipo == PromocaoCadastro.tipoLevePague &&
              promo.leveQuantidade >= 2
          ? (quantidade >= promo.leveQuantidade
              ? quantidade
              : promo.leveQuantidade)
          : quantidade;
      final precoExibicao = PromocaoCadastro.aplicarLevePagueNoPreco(
        tipoCampanha: tipo,
        precoBasePromo: precoRegra,
        quantidade: qtdRef,
        leveQuantidade: promo.leveQuantidade,
        pagueQuantidade: promo.pagueQuantidade,
      );
      out.add(
        PromocaoInfoVigente(
          promocaoId: promo.id,
          nome: promo.nome,
          tipoCampanha: tipo,
          tipoRegra: promo.tipoRegra,
          valorRegra: promo.valorRegra,
          dataFim: promo.dataFim,
          precoCalculado: precoExibicao,
          precoBasePreco1: base,
          precoUnitarioRegra: precoRegra,
          quantidadeReferenciaExibicao: qtdRef,
          margemMinimaPercentual: promo.margemMinimaPercentual,
          quantidadeRestanteGlobal: _restanteGlobal(promo),
          quantidadeMaximaPorVenda: item.quantidadeMaximaPromo,
          leveQuantidade: promo.leveQuantidade,
          pagueQuantidade: promo.pagueQuantidade,
        ),
      );
    }
    return out;
  }

  PromocaoPrecoResult resolver(
    Produto produto, {
    required DateTime dataReferencia,
    int quantidade = 1,
    String precoTipoLista = 'preco1',
    String? segmentoCliente,
  }) {
    final basePreco1 = preco1Base(produto);
    final candidatas = _repo.listarVigentesNaData(dataReferencia);
    Promocao? melhorPromo;
    PromocaoItem? melhorItem;
    double? melhorPreco;

    for (final promo in candidatas) {
      if (!PromocaoCadastro.promocaoAceitaSegmento(promo, segmentoCliente)) {
        continue;
      }
      if (PromocaoCadastro.normalizarTipoCampanha(promo.tipoCampanha) ==
          PromocaoCadastro.tipoComboAb) {
        continue;
      }
      final item = _itemQueCasa(promo, produto, quantidade);
      if (item == null) continue;
      if (!_passaLimites(promo, item, quantidade)) continue;
      final preco = _calcularPrecoPromocional(
        promo: promo,
        precoBasePreco1: basePreco1,
      );
      if (preco <= 0) continue;
      final melhorQueAtual = melhorPreco == null ||
          preco < melhorPreco - 0.0001 ||
          (preco - melhorPreco).abs() < 0.0001 &&
              promo.prioridade > (melhorPromo?.prioridade ?? -1);
      if (melhorQueAtual) {
        melhorPreco = preco;
        melhorPromo = promo;
        melhorItem = item;
      }
    }

    if (melhorPromo != null && melhorPreco != null && melhorItem != null) {
      return PromocaoPrecoResult.comPromocao(
        precoFinal: melhorPreco,
        precoBasePreco1: basePreco1,
        promocaoId: melhorPromo.id,
        promocaoNome: melhorPromo.nome.trim(),
        tipoCampanha: melhorPromo.tipoCampanha,
        margemMinimaPercentual: melhorPromo.margemMinimaPercentual,
        quantidadeMaximaPorVenda: melhorItem.quantidadeMaximaPromo,
        quantidadeRestanteGlobal: _restanteGlobal(melhorPromo),
        leveQuantidade: melhorPromo.leveQuantidade,
        pagueQuantidade: melhorPromo.pagueQuantidade,
      );
    }

    return PromocaoPrecoResult.semPromocao(
      precoFinal: precoLista(produto, precoTipoLista),
      precoTipo: precoTipoLista,
      precoBasePreco1: basePreco1,
    );
  }

  int _restanteGlobal(Promocao promo) {
    if (promo.limiteQuantidadeTotal <= 0) return 0;
    return (promo.limiteQuantidadeTotal - promo.quantidadeVendidaPromo)
        .clamp(0, promo.limiteQuantidadeTotal);
  }

  bool _passaLimites(Promocao promo, PromocaoItem item, int quantidade) {
    if (item.quantidadeMaximaPromo > 0 &&
        quantidade > item.quantidadeMaximaPromo) {
      return false;
    }
    final restante = _restanteGlobal(promo);
    if (promo.limiteQuantidadeTotal > 0 && quantidade > restante) {
      return false;
    }
    return true;
  }

  PromocaoItem? _itemQueCasa(Promocao promo, Produto produto, int quantidade) {
    PromocaoItem? fallback;
    for (final item in _itensDe(promo)) {
      if (quantidade < item.quantidadeMinima) continue;
      if (item.produtoAlvoId > 0) {
        if (item.produtoAlvoId == produto.id) return item;
        continue;
      }
      final cat = item.categoria.trim().toLowerCase();
      final sub = item.subcategoria.trim().toLowerCase();
      if (cat.isEmpty && sub.isEmpty) {
        fallback = item;
        continue;
      }
      final catProd = produto.categoria.trim().toLowerCase();
      final subProd = produto.subcategoria.trim().toLowerCase();
      if (cat.isNotEmpty && catProd != cat) continue;
      if (sub.isNotEmpty && subProd != sub) continue;
      return item;
    }
    return fallback;
  }

  /// Itens sem depender de Backlink ObjectBox (terminal leve).
  List<PromocaoItem> _itensDe(Promocao promo) {
    try {
      final r = _repo.itensDaPromocao(promo);
      if (r is List<PromocaoItem>) return r;
      if (r is Iterable) {
        return r.whereType<PromocaoItem>().toList(growable: false);
      }
    } catch (_) {}
    try {
      return List<PromocaoItem>.from(promo.itens);
    } catch (_) {
      return const [];
    }
  }

  List<PromocaoComboItem> _comboDe(Promocao promo) {
    try {
      final r = _repo.comboItensDaPromocao(promo);
      if (r is List<PromocaoComboItem>) return r;
      if (r is Iterable) {
        return r.whereType<PromocaoComboItem>().toList(growable: false);
      }
    } catch (_) {}
    try {
      return List<PromocaoComboItem>.from(promo.comboItens);
    } catch (_) {
      return const [];
    }
  }

  static double calcularPrecoRegra({
    required String tipoRegra,
    required double valorRegra,
    required double precoBasePreco1,
  }) {
    final tipo = PromocaoCadastro.normalizarTipoRegra(tipoRegra);
    if (tipo == 'desconto_percentual') {
      final pct = valorRegra.clamp(0, 99.99);
      return (precoBasePreco1 * (1 - pct / 100)).clamp(0, double.infinity);
    }
    return valorRegra.clamp(0, double.infinity);
  }

  double _calcularPrecoPromocional({
    required Promocao promo,
    required double precoBasePreco1,
  }) {
    return calcularPrecoRegra(
      tipoRegra: promo.tipoRegra,
      valorRegra: promo.valorRegra,
      precoBasePreco1: precoBasePreco1,
    );
  }
}
