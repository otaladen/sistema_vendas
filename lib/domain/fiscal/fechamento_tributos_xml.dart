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

  Map<String, dynamic> toJson() => {
        'cfopPredominante': cfopPredominante,
        'baseIcms': baseIcms,
        'valorIcms': valorIcms,
        'valorPis': valorPis,
        'valorCofins': valorCofins,
      };

  factory FechamentoTributosXml.fromJson(Map<String, dynamic>? json) {
    if (json == null) return vazio;
    return FechamentoTributosXml(
      cfopPredominante: (json['cfopPredominante'] ?? '').toString(),
      baseIcms: (json['baseIcms'] as num?)?.toDouble() ?? 0,
      valorIcms: (json['valorIcms'] as num?)?.toDouble() ?? 0,
      valorPis: (json['valorPis'] as num?)?.toDouble() ?? 0,
      valorCofins: (json['valorCofins'] as num?)?.toDouble() ?? 0,
    );
  }
}
