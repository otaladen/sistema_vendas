import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/venda_repository.dart';
import '../../model/venda.dart';
import 'nfe_pendencias_service.dart';

/// Pendencias que podem afetar o fechamento contabil do mes.
class FiscalBloqueiosFechamento {
  const FiscalBloqueiosFechamento({
    required this.mes,
    required this.ano,
    required this.vendasNfceProcessando,
    required this.nfeProcessando,
    required this.nfeRejeitadas,
  });

  final int mes;
  final int ano;
  final List<Venda> vendasNfceProcessando;
  final List<NfeSaidaFiscalRegistro> nfeProcessando;
  final List<NfeSaidaFiscalRegistro> nfeRejeitadas;

  int get qtdNfceProcessando => vendasNfceProcessando.length;
  int get qtdNfeProcessando => nfeProcessando.length;
  int get qtdNfeRejeitadas => nfeRejeitadas.length;

  /// Bloqueia exportacao do fechamento (NFC-e sem chave no periodo).
  bool get bloqueiaExportacao => qtdNfceProcessando > 0;

  bool get temBloqueioCritico =>
      bloqueiaExportacao || qtdNfeProcessando > 0;

  bool get temAviso => temBloqueioCritico || qtdNfeRejeitadas > 0;
}

abstract final class FiscalBloqueiosFechamentoService {
  FiscalBloqueiosFechamentoService._();

  static FiscalBloqueiosFechamento avaliar({
    required VendaRepository vendaRepository,
    required int mes,
    required int ano,
  }) {
    final periodo = _periodoDoMesAno(mes, ano);

    final nfce = vendaRepository.listarNfcePendenteFocusNoPeriodo(
      inicio: periodo.inicio,
      fim: periodo.fim,
    );

    final storePath = vendaRepository.objectBox.storeDirectoryPath;
    final nfeStore = NfeSaidaFiscalStore(storePath);
    final inicioUtc = DateTime(
      periodo.inicio.year,
      periodo.inicio.month,
      periodo.inicio.day,
    ).toUtc();
    final fimUtc = DateTime(
      periodo.fim.year,
      periodo.fim.month,
      periodo.fim.day,
      23,
      59,
      59,
      999,
    ).toUtc();

    final nfeProc = NfePendenciasService.listarProcessando(
      nfeStore,
      vendaRepository: vendaRepository,
    ).where((r) {
      final em = r.emitidaEm.toUtc();
      return !em.isBefore(inicioUtc) && !em.isAfter(fimUtc);
    }).toList();

    final nfeRej = NfePendenciasService.listarRejeitadasRecentes(
      nfeStore,
      vendaRepository: vendaRepository,
      limit: 500,
    ).where((r) {
      final em = r.emitidaEm.toUtc();
      return !em.isBefore(inicioUtc) && !em.isAfter(fimUtc);
    }).toList();

    return FiscalBloqueiosFechamento(
      mes: mes,
      ano: ano,
      vendasNfceProcessando: nfce,
      nfeProcessando: nfeProc,
      nfeRejeitadas: nfeRej,
    );
  }

  static ({DateTime inicio, DateTime fim}) _periodoDoMesAno(int mes, int ano) {
    final m = mes.clamp(1, 12);
    final inicio = DateTime(ano, m, 1);
    final fim = DateTime(ano, m + 1, 0);
    return (inicio: inicio, fim: fim);
  }
}
