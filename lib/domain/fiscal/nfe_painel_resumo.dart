import '../../data/nfe_inutilizacao_store.dart';
import '../../data/nfe_saida_fiscal_store.dart';
import 'nfe_numeracao_fiscal_helper.dart';

/// Indicadores do painel NF-e (visao operacional + fiscal robusto v2).
class NfePainelResumo {
  const NfePainelResumo({
    required this.totalRegistros,
    required this.autorizadas,
    required this.processando,
    required this.rejeitadas,
    required this.canceladas,
    required this.vendasSemNfeAutorizada,
    required this.totalCartasCorrecao,
    required this.cartasCorrecaoProcessando,
    required this.lacunasNumeracaoSerie1,
    required this.inutilizacoesRegistradas,
  });

  final int totalRegistros;
  final int autorizadas;
  final int processando;
  final int rejeitadas;
  final int canceladas;
  final int vendasSemNfeAutorizada;
  final int totalCartasCorrecao;
  final int cartasCorrecaoProcessando;
  final int lacunasNumeracaoSerie1;
  final int inutilizacoesRegistradas;
}

abstract final class NfePainelResumoBuilder {
  NfePainelResumoBuilder._();

  static NfePainelResumo calcular({
    required List<NfeSaidaFiscalRegistro> historico,
    required int vendasSemNfe,
    NfeInutilizacaoStore? inutilizacaoStore,
    NfeSaidaFiscalStore? nfeStore,
  }) {
    var auth = 0;
    var proc = 0;
    var rej = 0;
    var canc = 0;
    var totalCce = 0;
    var cceProc = 0;
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
      totalCce += r.totalCartasCorrecao;
      cceProc += r.cartasCorrecaoProcessando;
    }

    final lacunas = nfeStore == null
        ? 0
        : NfeNumeracaoFiscalHelper.contarLacunasNaSerie(
            store: nfeStore,
            serie: '1',
          );

    return NfePainelResumo(
      totalRegistros: historico.length,
      autorizadas: auth,
      processando: proc,
      rejeitadas: rej,
      canceladas: canc,
      vendasSemNfeAutorizada: vendasSemNfe,
      totalCartasCorrecao: totalCce,
      cartasCorrecaoProcessando: cceProc,
      lacunasNumeracaoSerie1: lacunas,
      inutilizacoesRegistradas: inutilizacaoStore?.listar().length ?? 0,
    );
  }
}
