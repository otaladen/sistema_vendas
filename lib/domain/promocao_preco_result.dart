import 'promocao_cadastro.dart';

/// Resultado da resolucao de preco com promocao.
class PromocaoPrecoResult {
  const PromocaoPrecoResult({
    required this.precoFinal,
    required this.precoBasePreco1,
    required this.precoTipo,
    this.promocaoId = 0,
    this.promocaoNome = '',
    this.tipoCampanha = PromocaoCadastro.tipoProduto,
    this.margemMinimaPercentual = 0,
    this.quantidadeMaximaPorVenda = 0,
    this.quantidadeRestanteGlobal = 0,
    this.leveQuantidade = 0,
    this.pagueQuantidade = 0,
    this.observacao = '',
  });

  final double precoFinal;
  final double precoBasePreco1;
  final String precoTipo;
  final int promocaoId;
  final String promocaoNome;
  final String tipoCampanha;
  final double margemMinimaPercentual;
  final int quantidadeMaximaPorVenda;
  final int quantidadeRestanteGlobal;
  final int leveQuantidade;
  final int pagueQuantidade;
  final String observacao;

  bool get emPromocao => promocaoId > 0;

  factory PromocaoPrecoResult.semPromocao({
    required double precoFinal,
    required String precoTipo,
    required double precoBasePreco1,
  }) {
    return PromocaoPrecoResult(
      precoFinal: precoFinal,
      precoBasePreco1: precoBasePreco1,
      precoTipo: precoTipo,
    );
  }

  factory PromocaoPrecoResult.comPromocao({
    required double precoFinal,
    required double precoBasePreco1,
    required int promocaoId,
    required String promocaoNome,
    String tipoCampanha = PromocaoCadastro.tipoProduto,
    double margemMinimaPercentual = 0,
    int quantidadeMaximaPorVenda = 0,
    int quantidadeRestanteGlobal = 0,
    int leveQuantidade = 0,
    int pagueQuantidade = 0,
    String observacao = '',
  }) {
    return PromocaoPrecoResult(
      precoFinal: precoFinal,
      precoBasePreco1: precoBasePreco1,
      precoTipo: PromocaoCadastro.precoTipoPromo,
      promocaoId: promocaoId,
      promocaoNome: promocaoNome,
      tipoCampanha: tipoCampanha,
      margemMinimaPercentual: margemMinimaPercentual,
      quantidadeMaximaPorVenda: quantidadeMaximaPorVenda,
      quantidadeRestanteGlobal: quantidadeRestanteGlobal,
      leveQuantidade: leveQuantidade,
      pagueQuantidade: pagueQuantidade,
      observacao: observacao,
    );
  }
}
