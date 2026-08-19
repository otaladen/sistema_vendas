/// Estado da sessao de caixa de um terminal (balcao/PDV).
class CaixaSessao {
  const CaixaSessao({
    required this.terminalId,
    this.aberto = false,
    this.operador = '',
    this.aberturaEm,
    this.fundoTroco = 0,
    this.suprimentos = 0,
    this.sangrias = 0,
    this.atualizadoEm,
  });

  final String terminalId;
  final bool aberto;
  final String operador;
  final DateTime? aberturaEm;
  final double fundoTroco;
  final double suprimentos;
  final double sangrias;
  final DateTime? atualizadoEm;

  CaixaSessao copyWith({
    String? terminalId,
    bool? aberto,
    String? operador,
    DateTime? aberturaEm,
    bool limparAbertura = false,
    double? fundoTroco,
    double? suprimentos,
    double? sangrias,
    DateTime? atualizadoEm,
  }) {
    return CaixaSessao(
      terminalId: terminalId ?? this.terminalId,
      aberto: aberto ?? this.aberto,
      operador: operador ?? this.operador,
      aberturaEm: limparAbertura ? null : (aberturaEm ?? this.aberturaEm),
      fundoTroco: fundoTroco ?? this.fundoTroco,
      suprimentos: suprimentos ?? this.suprimentos,
      sangrias: sangrias ?? this.sangrias,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
    );
  }

  Map<String, dynamic> toMap() => {
        'terminalId': terminalId,
        'aberto': aberto,
        'operador': operador,
        if (aberturaEm != null) 'aberturaEm': aberturaEm!.toIso8601String(),
        'fundoTroco': fundoTroco,
        'suprimentos': suprimentos,
        'sangrias': sangrias,
        if (atualizadoEm != null) 'atualizadoEm': atualizadoEm!.toIso8601String(),
      };

  static CaixaSessao fromMap(Map<String, dynamic> map) {
    return CaixaSessao(
      terminalId: (map['terminalId'] ?? '').toString(),
      aberto: boolFrom(map['aberto']),
      operador: (map['operador'] ?? '').toString(),
      aberturaEm: DateTime.tryParse((map['aberturaEm'] ?? '').toString()),
      fundoTroco: ((map['fundoTroco'] as num?) ?? 0).toDouble(),
      suprimentos: ((map['suprimentos'] as num?) ?? 0).toDouble(),
      sangrias: ((map['sangrias'] as num?) ?? 0).toDouble(),
      atualizadoEm: DateTime.tryParse((map['atualizadoEm'] ?? '').toString()),
    );
  }

  /// Aceita bool, 1/0 e "true"/"false" (prefs / JSON legados).
  static bool boolFrom(Object? v) {
    if (v == true || v == 1) return true;
    if (v == false || v == 0 || v == null) return false;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'sim';
  }

  static CaixaSessao vazia(String terminalId) => CaixaSessao(terminalId: terminalId);
}
