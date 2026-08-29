/// Totais da leitura parcial do caixa (desde a abertura, sem fechar).
///
/// Vale, fiado e transferencia nao entram na gaveta: o dinheiro ja entrou
/// na compra original ou ainda nao entrou. [dinheiroGaveta] e o fisico
/// esperado (fundo + vendas/quitacoes em dinheiro + suprimentos - sangrias).
class LeituraParcialCaixaSnapshot {
  const LeituraParcialCaixaSnapshot({
    required this.dinheiroGaveta,
    required this.pix,
    required this.debito,
    required this.credito,
    required this.vale,
    required this.fundoTroco,
    required this.suprimentos,
    required this.sangrias,
    required this.totalVendas,
    required this.quantidadeVendas,
    required this.recebimentosFiadoTotal,
    required this.recebimentosFiadoQuantidade,
    this.aberturaEm,
    this.terminalId = '',
    this.operador = '',
  });

  final double dinheiroGaveta;
  final double pix;
  final double debito;
  final double credito;
  final double vale;
  final double fundoTroco;
  final double suprimentos;
  final double sangrias;
  final double totalVendas;
  final int quantidadeVendas;
  final double recebimentosFiadoTotal;
  final int recebimentosFiadoQuantidade;
  final DateTime? aberturaEm;
  final String terminalId;
  final String operador;

  /// NaN/Infinity quebram [jsonEncode] (auditoria e API) e derrubam a tela.
  static double finitoNaoNegativo(num? v) {
    final n = (v ?? 0).toDouble();
    if (!n.isFinite || n < 0) return 0;
    return n;
  }

  static double finito(num? v) {
    final n = (v ?? 0).toDouble();
    return n.isFinite ? n : 0;
  }

  static int inteiroNaoNegativo(num? v) {
    final n = (v ?? 0).toInt();
    return n < 0 ? 0 : n;
  }

  static LeituraParcialCaixaSnapshot montar({
    required double fundoTroco,
    required double suprimentos,
    required double sangrias,
    required double vendasDinheiro,
    required double vendasPix,
    required double vendasDebito,
    required double vendasCredito,
    double vendasVale = 0,
    double recDinheiro = 0,
    double recPix = 0,
    double recDebito = 0,
    double recCredito = 0,
    double recTotal = 0,
    int recQuantidade = 0,
    required double totalVendas,
    required int quantidadeVendas,
    DateTime? aberturaEm,
    String terminalId = '',
    String operador = '',
  }) {
    final fundo = finitoNaoNegativo(fundoTroco);
    final sup = finitoNaoNegativo(suprimentos);
    final san = finitoNaoNegativo(sangrias);
    final dinheiroMeios =
        finitoNaoNegativo(finito(vendasDinheiro) + finito(recDinheiro));
    return LeituraParcialCaixaSnapshot(
      dinheiroGaveta: finitoNaoNegativo(fundo + dinheiroMeios + sup - san),
      pix: finitoNaoNegativo(finito(vendasPix) + finito(recPix)),
      debito: finitoNaoNegativo(finito(vendasDebito) + finito(recDebito)),
      credito: finitoNaoNegativo(finito(vendasCredito) + finito(recCredito)),
      vale: finitoNaoNegativo(vendasVale),
      fundoTroco: fundo,
      suprimentos: sup,
      sangrias: san,
      totalVendas: finitoNaoNegativo(totalVendas),
      quantidadeVendas: inteiroNaoNegativo(quantidadeVendas),
      recebimentosFiadoTotal: finitoNaoNegativo(recTotal),
      recebimentosFiadoQuantidade: inteiroNaoNegativo(recQuantidade),
      aberturaEm: aberturaEm,
      terminalId: terminalId,
      operador: operador,
    );
  }

  /// True se o mapa da API tem os campos numericos da leitura.
  static bool respostaValida(Map<String, dynamic> data) {
    if (data.containsKey('error') && '${data['error']}'.trim().isNotEmpty) {
      return false;
    }
    for (final k in const ['dinheiroGaveta', 'pix', 'debito', 'credito']) {
      if (data[k] is! num) return false;
    }
    return true;
  }

  static LeituraParcialCaixaSnapshot? fromJson(Map<String, dynamic> data) {
    if (!respostaValida(data)) return null;
    DateTime? abertura;
    final raw = data['aberturaEm']?.toString().trim();
    if (raw != null && raw.isNotEmpty) {
      abertura = DateTime.tryParse(raw);
    }
    return LeituraParcialCaixaSnapshot(
      dinheiroGaveta: finitoNaoNegativo(data['dinheiroGaveta'] as num?),
      pix: finitoNaoNegativo(data['pix'] as num?),
      debito: finitoNaoNegativo(data['debito'] as num?),
      credito: finitoNaoNegativo(data['credito'] as num?),
      vale: finitoNaoNegativo(data['vale'] as num?),
      fundoTroco: finitoNaoNegativo(data['fundoTroco'] as num?),
      suprimentos: finitoNaoNegativo(data['suprimentos'] as num?),
      sangrias: finitoNaoNegativo(data['sangrias'] as num?),
      totalVendas: finitoNaoNegativo(data['totalVendas'] as num?),
      quantidadeVendas: inteiroNaoNegativo(data['quantidadeVendas'] as num?),
      recebimentosFiadoTotal:
          finitoNaoNegativo(data['recebimentosFiadoTotal'] as num?),
      recebimentosFiadoQuantidade:
          inteiroNaoNegativo(data['recebimentosFiadoQuantidade'] as num?),
      aberturaEm: abertura,
      terminalId: (data['terminalId'] ?? '').toString(),
      operador: (data['operador'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'terminalId': terminalId,
        'aberturaEm': aberturaEm?.toUtc().toIso8601String(),
        'operador': operador,
        'totalVendas': totalVendas,
        'quantidadeVendas': quantidadeVendas,
        'recebimentosFiadoTotal': recebimentosFiadoTotal,
        'recebimentosFiadoQuantidade': recebimentosFiadoQuantidade,
        'dinheiro': finitoNaoNegativo(
          dinheiroGaveta - fundoTroco - suprimentos + sangrias,
        ),
        'pix': pix,
        'debito': debito,
        'credito': credito,
        'vale': vale,
        'dinheiroGaveta': dinheiroGaveta,
        'fundoTroco': fundoTroco,
        'suprimentos': suprimentos,
        'sangrias': sangrias,
      };

  Map<String, dynamic> toAuditoriaDetalhes() => {
        'totalVendas': totalVendas,
        'quantidadeVendas': quantidadeVendas,
        'recebimentosFiado': recebimentosFiadoTotal,
        'quantidadeRecebimentosFiado': recebimentosFiadoQuantidade,
        'esperadoDinheiro': dinheiroGaveta,
        'esperadoPix': pix,
        'esperadoDebito': debito,
        'esperadoCredito': credito,
        'esperadoVale': vale,
      };
}
