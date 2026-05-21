import 'promocao_cadastro.dart';

/// Resumo de campanha vigente para exibicao (detalhe F4, etiquetas).
class PromocaoInfoVigente {
  const PromocaoInfoVigente({
    required this.promocaoId,
    required this.nome,
    required this.tipoCampanha,
    required this.tipoRegra,
    required this.valorRegra,
    required this.dataFim,
    required this.precoCalculado,
    required this.precoBasePreco1,
    this.precoUnitarioRegra = 0,
    this.quantidadeReferenciaExibicao = 1,
    this.margemMinimaPercentual = 0,
    this.quantidadeRestanteGlobal = 0,
    this.quantidadeMaximaPorVenda = 0,
    this.leveQuantidade = 0,
    this.pagueQuantidade = 0,
    this.precoCombo = 0,
    this.descricaoCombo = '',
  });

  final int promocaoId;
  final String nome;
  final String tipoCampanha;
  final String tipoRegra;
  final double valorRegra;
  final DateTime dataFim;
  /// Unitario efetivo (com leve/pague se quantidade de referencia >= leve).
  final double precoCalculado;

  final double precoBasePreco1;

  /// Preco da regra (% ou fixo) antes de leve/pague — ex.: R\$ 220.
  final double precoUnitarioRegra;

  /// Quantidade usada na simulacao do banner (ex.: 10 no leve 10 pague 9).
  final int quantidadeReferenciaExibicao;

  final double margemMinimaPercentual;
  final int quantidadeRestanteGlobal;
  final int quantidadeMaximaPorVenda;
  final int leveQuantidade;
  final int pagueQuantidade;
  final double precoCombo;
  final String descricaoCombo;

  String get rotuloTipoCampanha => PromocaoCadastro.rotuloTipoCampanha(tipoCampanha);

  String get resumoRegra {
    switch (tipoCampanha) {
      case PromocaoCadastro.tipoLevePague:
        return 'Leve $leveQuantidade pague $pagueQuantidade';
      case PromocaoCadastro.tipoComboAb:
        return descricaoCombo.isNotEmpty
            ? descricaoCombo
            : 'Combo A+B';
      default:
        return PromocaoCadastro.rotuloTipoRegra(tipoRegra);
    }
  }

  String _fmtMoeda(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  /// Texto para o vendedor explicar a promo ao cliente (modal F4).
  String get textoPrecoParaVendedor {
    if (tipoCampanha == PromocaoCadastro.tipoLevePague &&
        leveQuantidade >= 2 &&
        pagueQuantidade >= 1) {
      final q = quantidadeReferenciaExibicao >= leveQuantidade
          ? quantidadeReferenciaExibicao
          : leveQuantidade;
      final unitRegra = precoUnitarioRegra > 0
          ? precoUnitarioRegra
          : precoCalculado;
      final unitMedio = precoCalculado > 0 && q >= leveQuantidade
          ? precoCalculado
          : PromocaoCadastro.aplicarLevePagueNoPreco(
              tipoCampanha: tipoCampanha,
              precoBasePromo: unitRegra,
              quantidade: q,
              leveQuantidade: leveQuantidade,
              pagueQuantidade: pagueQuantidade,
            );
      final totalPago = pagueQuantidade * unitRegra;
      return 'Leve $q pague $pagueQuantidade: o cliente paga ${_fmtMoeda(totalPago)} '
          '($pagueQuantidade x ${_fmtMoeda(unitRegra)}) — '
          'cada unidade sai por ${_fmtMoeda(unitMedio)} (media nas $q un.)';
    }
    if (tipoCampanha == PromocaoCadastro.tipoComboAb) {
      return 'Combo por ${_fmtMoeda(precoCombo)}';
    }
    return 'Preco promocional: ${_fmtMoeda(precoCalculado)}';
  }

  String? get textoPrecoComplementar {
    if (tipoCampanha != PromocaoCadastro.tipoLevePague) return null;
    if (precoBasePreco1 > precoUnitarioRegra + 0.01) {
      return 'Preco 1 (a prazo): ${_fmtMoeda(precoBasePreco1)} · '
          'tabela promocional: ${_fmtMoeda(precoUnitarioRegra)}/un.';
    }
    return null;
  }
}
