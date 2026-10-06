import '../model/venda.dart';

/// Texto livre da venda/orcamento (material, cor, pedido do cliente).
///
/// Diferente de [Venda.observacaoEntrega], usada so para carreto/patio.
abstract final class ObservacaoNota {
  static const String tituloImpressao = 'OBSERVAÇÕES DA NOTA';

  /// Titulo do bloco no cupom/DANFE NFC-e (apos pagamento, antes do fiscal).
  static const String tituloCupomDanfe = 'OBSERVAÇÃO DA VENDA:';

  static const int limiteCaracteres = 500;

  static const List<String> sugestoesRapidas = [
    'Cor conforme amostra do cliente',
    'Marca/modelo especifico',
    'Medida ou espessura especial',
    'Cliente pediu conferir na retirada',
    'Substituir por produto equivalente se faltar',
    'Separar de outro pedido do mesmo cliente',
  ];

  static String normalizar(String texto) => texto
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n');

  static List<String> linhasDigitadas(String gravada) =>
      normalizar(gravada).split('\n').where((l) => l.isNotEmpty).toList();

  static List<String> linhasImpressao(Venda venda) =>
      linhasDigitadas(venda.observacaoNota).map((l) => l.toUpperCase()).toList();

  /// Rodape do cupom/NFC-e: texto natural, sem caixa alta nem bloco destacado.
  static List<String> linhasRodapeCupom(Venda venda) =>
      linhasDigitadas(venda.observacaoNota);

  static String paraCampoFiscal(Venda venda) => normalizar(venda.observacaoNota);

  /// Primeira linha encurtada para listagens.
  static String resumoLista(String gravada, {int maxCaracteres = 88}) {
    final linhas = linhasDigitadas(gravada);
    if (linhas.isEmpty) return '';
    final first = linhas.first;
    if (first.length <= maxCaracteres) return first;
    return '${first.substring(0, maxCaracteres - 1)}…';
  }
}
