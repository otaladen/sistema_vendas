/// Classificacao de meios de pagamento no fechamento de caixa / gaveta.
///
/// Apenas [dinheiro] entra no saldo fisico esperado. Fiado, transferencia e
/// meios desconhecidos nao caem no fallback de dinheiro.
abstract final class CaixaMeioPagamentoFechamento {
  CaixaMeioPagamentoFechamento._();

  static const bucketDinheiro = 'dinheiro';
  static const bucketPix = 'pix';
  static const bucketDebito = 'debito';
  static const bucketCredito = 'credito';
  static const bucketVale = 'vale';

  /// Bucket do fechamento, ou `null` se nao deve somar em dinheiro/pix/cartao.
  static String? bucket(String? meio) {
    switch ((meio ?? '').trim().toLowerCase()) {
      case 'dinheiro':
        return bucketDinheiro;
      case 'pix':
        return bucketPix;
      case 'cartao_debito':
        return bucketDebito;
      case 'cartao_credito':
        return bucketCredito;
      case 'fiado':
      case 'transferencia':
      case 'outros':
      case 'misto':
        return null;
      // Vale nao entra na gaveta: o dinheiro entrou na compra original.
      case 'vale':
        return bucketVale;
      default:
        // Nao assumir dinheiro — evita inflar a gaveta.
        return null;
    }
  }

  /// True se o meio deve entrar no dinheiro esperado da gaveta.
  static bool entraNaGaveta(String? meio) =>
      bucket(meio) == bucketDinheiro;
}
