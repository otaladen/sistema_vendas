/// Totais de impostos extraidos do XML da nota (ICMSTot / itens).
class FechamentoTributosXml {
  const FechamentoTributosXml({
    this.cfopPredominante = '',
    this.baseIcms = 0,
    this.valorIcms = 0,
    this.valorPis = 0,
    this.valorCofins = 0,
  });

  final String cfopPredominante;
  final double baseIcms;
  final double valorIcms;
  final double valorPis;
  final double valorCofins;

  static const vazio = FechamentoTributosXml();
}
