/// Opcoes de lancamento na conferencia de entrada NF-e (XML).
class ConferenciaNfeOpcoes {
  const ConferenciaNfeOpcoes({
    this.lancarEstoque = true,
    this.gerarContasPagar = true,
    this.atualizarPrecoCusto = false,
    this.atualizarPrecosVenda = false,
  });

  final bool lancarEstoque;
  final bool gerarContasPagar;
  final bool atualizarPrecoCusto;
  final bool atualizarPrecosVenda;

  ConferenciaNfeOpcoes copyWith({
    bool? lancarEstoque,
    bool? gerarContasPagar,
    bool? atualizarPrecoCusto,
    bool? atualizarPrecosVenda,
  }) {
    return ConferenciaNfeOpcoes(
      lancarEstoque: lancarEstoque ?? this.lancarEstoque,
      gerarContasPagar: gerarContasPagar ?? this.gerarContasPagar,
      atualizarPrecoCusto: atualizarPrecoCusto ?? this.atualizarPrecoCusto,
      atualizarPrecosVenda: atualizarPrecosVenda ?? this.atualizarPrecosVenda,
    );
  }
}
