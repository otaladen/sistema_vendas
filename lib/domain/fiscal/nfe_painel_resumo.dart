import '../../data/nfe_saida_fiscal_store.dart';

/// Indicadores do painel NF-e (Fase 4 — visao operacional).
class NfePainelResumo {
  const NfePainelResumo({
    required this.totalRegistros,
    required this.autorizadas,
    required this.processando,
    required this.rejeitadas,
    required this.canceladas,
    required this.vendasSemNfeAutorizada,
  });

  final int totalRegistros;
  final int autorizadas;
  final int processando;
  final int rejeitadas;
  final int canceladas;

  /// Vendas finalizadas recentes ainda sem NF-e 55 autorizada.
  final int vendasSemNfeAutorizada;
}

abstract final class NfePainelResumoBuilder {
  NfePainelResumoBuilder._();

  static NfePainelResumo calcular({
    required List<NfeSaidaFiscalRegistro> historico,
    required int vendasSemNfe,
  }) {
    var auth = 0;
    var proc = 0;
    var rej = 0;
    var canc = 0;
    for (final r in historico) {
      if (r.cancelada) {
        canc++;
      } else if (r.autorizada) {
        auth++;
      } else if (r.processando) {
        proc++;
      } else if (r.rejeitada) {
        rej++;
      }
    }
    return NfePainelResumo(
      totalRegistros: historico.length,
      autorizadas: auth,
      processando: proc,
      rejeitadas: rej,
      canceladas: canc,
      vendasSemNfeAutorizada: vendasSemNfe,
    );
  }
}
