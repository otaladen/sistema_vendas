/// Simulacao de formas de pagamento / parcelamento no orcamento impresso.
///
/// Reutilizada no PDF e no ESC/POS para o cliente ver as opcoes a vista e
/// as parcelas no cartao (mesmo teto do checkout do PDV).
abstract final class OrcamentoCondicoesPagamento {
  OrcamentoCondicoesPagamento._();

  /// Mesmo teto de [_parcelasMaximasCheckoutPdV] no PDV.
  static const int parcelasMaximas = 12;

  static const String tituloSecao = 'FORMAS DE PAGAMENTO';
  static const String subtituloSecao = 'Condicoes de parcelamento';

  /// Titulo + subtitulo + a vista + cabecalho credito + parcelas 2x..N.
  static int quantidadeLinhasLayout({int maxParcelas = parcelasMaximas}) {
    final n = maxParcelas.clamp(1, 24);
    final parcelasCredito = n < 2 ? 0 : n - 1;
    return 2 + 1 + (parcelasCredito > 0 ? 1 + parcelasCredito : 0);
  }

  /// Linhas da simulacao (sem o titulo da secao).
  static List<String> linhas({
    required double total,
    required String Function(double) formatarMoeda,
    int maxParcelas = parcelasMaximas,
  }) {
    final t = total.isNaN || total.isInfinite || total < 0 ? 0.0 : total;
    final out = <String>[
      'A vista (Dinheiro/PIX/Debito): ${formatarMoeda(t)}',
    ];
    final n = maxParcelas.clamp(1, 24);
    if (n < 2) return out;
    out.add('Cartao credito:');
    for (var i = 2; i <= n; i++) {
      out.add('  ${i}x de ${formatarMoeda(t / i)}');
    }
    return out;
  }
}
