import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/venda_repository.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../model/venda.dart';
import 'nfe_pendencias_service.dart';

/// Linha leve de NFC-e pendente (API / terminal sem entidade Venda).
class FiscalBloqueioNfcePreview {
  const FiscalBloqueioNfcePreview({
    required this.vendaId,
    required this.rotulo,
    required this.dataIso,
    required this.total,
  });

  final int vendaId;
  final String rotulo;
  final String dataIso;
  final double total;

  Map<String, dynamic> toJson() => {
        'vendaId': vendaId,
        'rotulo': rotulo,
        'data': dataIso,
        'total': total,
      };

  factory FiscalBloqueioNfcePreview.fromJson(Map<String, dynamic> m) {
    return FiscalBloqueioNfcePreview(
      vendaId: (m['vendaId'] as num?)?.toInt() ?? 0,
      rotulo: (m['rotulo'] ?? '').toString(),
      dataIso: (m['data'] ?? '').toString(),
      total: (m['total'] as num?)?.toDouble() ?? 0,
    );
  }

  factory FiscalBloqueioNfcePreview.fromVenda(Venda v) {
    return FiscalBloqueioNfcePreview(
      vendaId: v.id,
      rotulo: VendaDocumentoRotuloHelper.rotuloIdentificacaoLista(v),
      dataIso: v.data.toUtc().toIso8601String(),
      total: v.total,
    );
  }
}

/// Pendencias que podem afetar o fechamento contabil do mes.
class FiscalBloqueiosFechamento {
  const FiscalBloqueiosFechamento({
    required this.mes,
    required this.ano,
    required this.vendasNfceProcessando,
    required this.nfeProcessando,
    required this.nfeRejeitadas,
    this.qtdNfceProcessandoOverride,
    this.qtdNfeProcessandoOverride,
    this.qtdNfeRejeitadasOverride,
    this.bloqueiaExportacaoOverride,
    this.nfceProcessandoPreview = const [],
  });

  final int mes;
  final int ano;
  final List<Venda> vendasNfceProcessando;
  final List<NfeSaidaFiscalRegistro> nfeProcessando;
  final List<NfeSaidaFiscalRegistro> nfeRejeitadas;

  /// Contagens vindas da API (terminal leve) quando as listas locais estao vazias.
  final int? qtdNfceProcessandoOverride;
  final int? qtdNfeProcessandoOverride;
  final int? qtdNfeRejeitadasOverride;
  final bool? bloqueiaExportacaoOverride;

  /// Detalhe das NFC-e processando (servidor local ou payload da API).
  final List<FiscalBloqueioNfcePreview> nfceProcessandoPreview;

  int get qtdNfceProcessando =>
      qtdNfceProcessandoOverride ?? vendasNfceProcessando.length;
  int get qtdNfeProcessando =>
      qtdNfeProcessandoOverride ?? nfeProcessando.length;
  int get qtdNfeRejeitadas =>
      qtdNfeRejeitadasOverride ?? nfeRejeitadas.length;

  /// Bloqueia exportacao do fechamento (NFC-e sem chave no periodo).
  bool get bloqueiaExportacao =>
      bloqueiaExportacaoOverride ?? qtdNfceProcessando > 0;

  bool get temBloqueioCritico =>
      bloqueiaExportacao || qtdNfeProcessando > 0;

  bool get temAviso => temBloqueioCritico || qtdNfeRejeitadas > 0;

  List<FiscalBloqueioNfcePreview> get nfcePreviewEfetivo {
    if (nfceProcessandoPreview.isNotEmpty) return nfceProcessandoPreview;
    if (vendasNfceProcessando.isEmpty) return const [];
    return [
      for (final v in vendasNfceProcessando)
        FiscalBloqueioNfcePreview.fromVenda(v),
    ];
  }
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
      nfceProcessandoPreview: [
        for (final v in nfce) FiscalBloqueioNfcePreview.fromVenda(v),
      ],
    );
  }

  static ({DateTime inicio, DateTime fim}) _periodoDoMesAno(int mes, int ano) {
    final m = mes.clamp(1, 12);
    final inicio = DateTime(ano, m, 1);
    final fim = DateTime(ano, m + 1, 0);
    return (inicio: inicio, fim: fim);
  }
}
