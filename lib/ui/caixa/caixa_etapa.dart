/// Etapas do fluxo operacional do caixa.
enum CaixaEtapa {
  /// Fila de orcamentos pendentes / tela inicial.
  fila,

  /// Conferencia read-only do orcamento importado.
  conferencia,

  /// Cobranca e confirmacao de pagamento.
  cobranca,

  /// Emissao fiscal / cupom apos pagamento confirmado (Fase 3).
  fiscal,
}
