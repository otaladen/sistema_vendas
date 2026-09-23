/// Como registrar devolucao/troca: operacional (estoque/caixa) ou fiscal na SEFAZ.
enum DevolucaoTrocaModoFluxo {
  /// Troca rapida de balcao: estoque, caixa e vale — sem NF-e de devolucao.
  estoqueCaixa,

  /// Emite NF-e de devolucao (finalidade 4) quando a venda tem nota autorizada.
  nfDevolucaoSefaz,
}

/// Regras de quando exibir aviso fiscal, bloquear terminal leve ou emitir NF-e.
class DevolucaoTrocaModoPolitica {
  DevolucaoTrocaModoPolitica._();

  static bool vendaComNotaAutorizada({
    required bool nfceAutorizadaAtiva,
    required bool nfe55Autorizada,
  }) =>
      nfceAutorizadaAtiva || nfe55Autorizada;

  /// NF-e de devolucao so quando o operador escolheu fluxo fiscal e a venda tem nota.
  static bool deveEmitirNfeDevolucaoSefaz({
    required DevolucaoTrocaModoFluxo modo,
    required bool nfceAutorizadaAtiva,
    required bool nfe55Autorizada,
  }) =>
      modo == DevolucaoTrocaModoFluxo.nfDevolucaoSefaz &&
      vendaComNotaAutorizada(
        nfceAutorizadaAtiva: nfceAutorizadaAtiva,
        nfe55Autorizada: nfe55Autorizada,
      );

  /// Terminal leve (API) nao emite NF-e localmente — so bloqueia se o operador pediu fiscal.
  static bool bloqueiaRegistroTerminalLevePorFiscal({
    required DevolucaoTrocaModoFluxo modo,
    required bool nfceAutorizadaAtiva,
    required bool nfe55Autorizada,
    required bool repositorioRemoto,
  }) =>
      repositorioRemoto &&
      deveEmitirNfeDevolucaoSefaz(
        modo: modo,
        nfceAutorizadaAtiva: nfceAutorizadaAtiva,
        nfe55Autorizada: nfe55Autorizada,
      );

  static bool exibirAvisoFiscalObrigatorio({
    required DevolucaoTrocaModoFluxo modo,
    required bool nfceAutorizadaAtiva,
    required bool nfe55Autorizada,
  }) =>
      deveEmitirNfeDevolucaoSefaz(
        modo: modo,
        nfceAutorizadaAtiva: nfceAutorizadaAtiva,
        nfe55Autorizada: nfe55Autorizada,
      );
}
