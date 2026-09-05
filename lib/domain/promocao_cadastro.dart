import '../model/produto.dart';
import '../model/promocao.dart';
import 'cliente_cadastro.dart';

/// Constantes do modulo de promocoes.
class PromocaoCadastro {
  PromocaoCadastro._();

  static const precoTipoPromo = 'promo';

  static const segmentoTodos = '';

  static const tipoProduto = 'produto';
  static const tipoLevePague = 'leve_pague';
  static const tipoComboAb = 'combo_ab';

  static const tiposCampanha = [
    (tipoProduto, 'Preco promocional (produto/categoria)'),
    (tipoLevePague, 'Leve X pague Y'),
    (tipoComboAb, 'Combo A + B (preco fechado)'),
  ];

  static const tiposRegra = [
    ('preco_fixo', 'Preco fixo (R\$)'),
    ('desconto_percentual', '% sobre preco 1'),
  ];

  static String rotuloTipoCampanha(String? codigo) {
    for (final t in tiposCampanha) {
      if (t.$1 == codigo) return t.$2;
    }
    return 'Preco promocional';
  }

  static String normalizarTipoCampanha(String? valor) {
    final v = (valor ?? '').trim().toLowerCase();
    if (v == tipoLevePague || v == tipoComboAb) return v;
    return tipoProduto;
  }

  static String rotuloTipoRegra(String? codigo) {
    for (final t in tiposRegra) {
      if (t.$1 == codigo) return t.$2;
    }
    return 'Desconhecido';
  }

  static String normalizarTipoRegra(String? valor) {
    final v = (valor ?? '').trim().toLowerCase();
    if (v == 'desconto_percentual') return v;
    return 'preco_fixo';
  }

  static String rotuloSegmentoCliente(String? codigo) {
    final v = (codigo ?? '').trim();
    if (v.isEmpty) return 'Todos os segmentos';
    return ClienteCadastro.rotuloSegmento(v);
  }

  static String normalizarSegmentoCliente(String? valor) {
    final v = (valor ?? '').trim().toLowerCase();
    if (v.isEmpty) return segmentoTodos;
    for (final s in ClienteCadastro.segmentos) {
      if (s.$1 == v) return v;
    }
    return segmentoTodos;
  }

  static bool promocaoAceitaSegmento(Promocao promo, String? segmentoCliente) {
    final filtro = promo.segmentoCliente.trim().toLowerCase();
    if (filtro.isEmpty) return true;
    final seg = (segmentoCliente ?? '').trim().toLowerCase();
    return seg.isNotEmpty && seg == filtro;
  }

  static double margemSobrePrecoVenda({
    required double precoCusto,
    required double precoVenda,
  }) {
    if (precoVenda <= 0) return 0;
    return ((precoVenda - precoCusto) / precoVenda) * 100;
  }

  /// Mesma base do PDV: preco 1 do produto.
  static double preco1DoProduto(Produto produto) {
    return produto.preco1 > 0 ? produto.preco1 : produto.precoVenda;
  }

  /// Preco unitario da regra (% ou fixo), sem leve/pague.
  static double calcularPrecoBasePromocional({
    required String tipoRegra,
    required double valorRegra,
    required double precoBasePreco1,
  }) {
    return _calcularPrecoRegraInterno(
      tipoRegra: tipoRegra,
      valorRegra: valorRegra,
      precoBasePreco1: precoBasePreco1,
    );
  }

  /// Aplica leve/pague uma unica vez sobre [precoBasePromo].
  static double aplicarLevePagueNoPreco({
    required String tipoCampanha,
    required double precoBasePromo,
    required int quantidade,
    required int leveQuantidade,
    required int pagueQuantidade,
  }) {
    final tipo = normalizarTipoCampanha(tipoCampanha);
    if (tipo != tipoLevePague) return precoBasePromo;
    if (leveQuantidade < 2 || pagueQuantidade < 1) return precoBasePromo;
    if (quantidade < leveQuantidade) return precoBasePromo;
    return precoBasePromo * pagueQuantidade / leveQuantidade;
  }

  /// Preco unitario efetivo no carrinho (base + leve/pague se couber).
  static double calcularPrecoUnitarioEfetivo({
    required String tipoCampanha,
    required String tipoRegra,
    required double valorRegra,
    required double precoBasePreco1,
    int quantidade = 1,
    int leveQuantidade = 0,
    int pagueQuantidade = 0,
  }) {
    if (normalizarTipoCampanha(tipoCampanha) == tipoComboAb) return 0;
    final base = calcularPrecoBasePromocional(
      tipoRegra: tipoRegra,
      valorRegra: valorRegra,
      precoBasePreco1: precoBasePreco1,
    );
    return aplicarLevePagueNoPreco(
      tipoCampanha: tipoCampanha,
      precoBasePromo: base,
      quantidade: quantidade,
      leveQuantidade: leveQuantidade,
      pagueQuantidade: pagueQuantidade,
    );
  }

  /// Total da linha no PDV (quantidade x unitario efetivo).
  static double calcularTotalLinhaPromocional({
    required String tipoCampanha,
    required String tipoRegra,
    required double valorRegra,
    required double precoBasePreco1,
    required int quantidade,
    int leveQuantidade = 0,
    int pagueQuantidade = 0,
  }) {
    final unit = calcularPrecoUnitarioEfetivo(
      tipoCampanha: tipoCampanha,
      tipoRegra: tipoRegra,
      valorRegra: valorRegra,
      precoBasePreco1: precoBasePreco1,
      quantidade: quantidade,
      leveQuantidade: leveQuantidade,
      pagueQuantidade: pagueQuantidade,
    );
    return unit * quantidade;
  }

  static double _calcularPrecoRegraInterno({
    required String tipoRegra,
    required double valorRegra,
    required double precoBasePreco1,
  }) {
    final tipo = normalizarTipoRegra(tipoRegra);
    if (tipo == 'desconto_percentual') {
      final pct = valorRegra.clamp(0, 99.99);
      return (precoBasePreco1 * (1 - pct / 100)).clamp(0, double.infinity);
    }
    return valorRegra.clamp(0, double.infinity);
  }

  /// Texto curto da regra para listagens e simulacao.
  static String resumoRegraPreco({
    required String tipoCampanha,
    required String tipoRegra,
    required double valorRegra,
    int leveQuantidade = 0,
    int pagueQuantidade = 0,
    double precoCombo = 0,
  }) {
    final tipo = normalizarTipoCampanha(tipoCampanha);
    if (tipo == tipoComboAb) {
      return 'Combo por R\$ ${precoCombo.toStringAsFixed(2)} (preco fechado)';
    }
    if (tipo == tipoLevePague) {
      final base = resumoRegraPreco(
        tipoCampanha: tipoProduto,
        tipoRegra: tipoRegra,
        valorRegra: valorRegra,
      );
      return '$base · leve $leveQuantidade pague $pagueQuantidade';
    }
    if (normalizarTipoRegra(tipoRegra) == 'desconto_percentual') {
      return '${valorRegra.toStringAsFixed(1)}% sobre preco 1';
    }
    return 'Preco fixo R\$ ${valorRegra.toStringAsFixed(2)}';
  }

  static String explicacaoTipoCampanha(String tipoCampanha) {
    switch (normalizarTipoCampanha(tipoCampanha)) {
      case tipoLevePague:
        return 'Defina o preco promocional (% ou fixo). Leve 3 pague 2 significa: '
            'a cada 3 unidades o cliente paga só 2 vezes esse preco. '
            'Ex.: preco fixo R\$ 300 e 3 unidades → total R\$ 600 (2 × 300), '
            'equivalente a R\$ 200/un.';
      case tipoComboAb:
        return 'Informe o preco total do pacote. No PDV, quando todos os '
            'produtos do combo estiverem no carrinho, o total da linha sera '
            'rateado entre eles (proporcional ao preco 1 de cada um).';
      default:
        return 'Produtos ou categorias entram com o preco calculado pela regra '
            '(% sobre preco 1 ou preco fixo). Desconto manual do PDV nao '
            'incide em linhas promocionais.';
    }
  }

  /// Erros de validacao do formulario; vazio = OK.
  static List<String> validarFormulario({
    required String nome,
    required String tipoCampanha,
    required String tipoRegra,
    required double valorRegra,
    required double precoCombo,
    required int leveQuantidade,
    required int pagueQuantidade,
    required int qtdItensProduto,
    required int qtdItensCombo,
    required double margemMinima,
    required int limiteGlobal,
  }) {
    final erros = <String>[];
    if (nome.trim().isEmpty) erros.add('Informe o nome da campanha.');
    final tipo = normalizarTipoCampanha(tipoCampanha);
    if (tipo == tipoComboAb) {
      if (qtdItensCombo < 1) {
        erros.add('Inclua ao menos um produto no combo.');
      }
      if (precoCombo <= 0) {
        erros.add('Informe o preco fechado do combo (maior que zero).');
      }
    } else {
      if (qtdItensProduto < 1) {
        erros.add('Inclua ao menos um produto ou categoria.');
      }
      if (normalizarTipoRegra(tipoRegra) == 'desconto_percentual') {
        if (valorRegra <= 0 || valorRegra >= 100) {
          erros.add('Desconto % deve ser entre 0,01 e 99,99.');
        }
      } else if (valorRegra <= 0) {
        erros.add('Informe o preco fixo promocional (maior que zero).');
      }
      if (tipo == tipoLevePague) {
        if (leveQuantidade < 2) {
          erros.add('Leve: minimo 2 unidades.');
        }
        if (pagueQuantidade < 1) {
          erros.add('Pague: minimo 1 unidade.');
        }
        if (pagueQuantidade >= leveQuantidade) {
          erros.add('Pague deve ser menor que Leve (ex.: leve 3 pague 2).');
        }
      }
    }
    if (margemMinima < 0 || margemMinima > 99) {
      erros.add('Margem minima: use entre 0 e 99%.');
    }
    if (limiteGlobal < 0) {
      erros.add('Limite global nao pode ser negativo.');
    }
    return erros;
  }
}
