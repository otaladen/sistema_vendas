import 'package:objectbox/objectbox.dart';

/// Periodicidade de [ObrigacaoMensalFixa].
abstract final class ObrigacaoPeriodicidade {
  static const semanal = 'semanal';
  static const mensal = 'mensal';
  static const anual = 'anual';

  static const todas = [semanal, mensal, anual];

  static String normalizar(String? raw) {
    final p = (raw ?? '').trim().toLowerCase();
    if (p == semanal || p == anual) return p;
    return mensal;
  }

  static String rotulo(String? raw) {
    switch (normalizar(raw)) {
      case semanal:
        return 'Semanal';
      case anual:
        return 'Anual';
      default:
        return 'Mensal';
    }
  }
}

/// Despesa fixa da loja que gera [ContaPagar] periodicamente.
@Entity()
class ObrigacaoMensalFixa {
  ObrigacaoMensalFixa({
    this.id = 0,
    required this.descricao,
    required this.valor,
    this.periodicidade = ObrigacaoPeriodicidade.mensal,
    this.diaVencimento = 10,
    this.mesVencimento = 1,
    this.cnpj = '',
    this.ativo = true,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now().toUtc();

  @Id(assignable: true)
  int id;

  /// Nome da despesa / favorecido (ex.: Aluguel loja).
  String descricao;

  double valor;

  /// [ObrigacaoPeriodicidade]: semanal | mensal | anual.
  String periodicidade;

  /// Mensal/anual: dia do mes (1–28).
  /// Semanal: dia da semana Dart (1=seg … 7=dom).
  int diaVencimento;

  /// Somente anual: mes (1–12).
  int mesVencimento;

  /// CNPJ opcional do favorecido (somente digitos ou vazio).
  String cnpj;

  bool ativo;

  @Property(type: PropertyType.dateUtc)
  DateTime criadoEm;
}
