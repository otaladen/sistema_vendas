import '../../data/nfe_inutilizacao_store.dart';
import '../../data/nfe_saida_fiscal_store.dart';

/// Conflito entre faixa de inutilizacao e numeros ja usados no historico fiscal.
class NfeNumeracaoConflito {
  const NfeNumeracaoConflito({
    required this.numero,
    required this.situacao,
    required this.referenciaFocus,
  });

  final int numero;
  final String situacao;
  final String referenciaFocus;
}

abstract final class NfeNumeracaoFiscalHelper {
  NfeNumeracaoFiscalHelper._();

  static int? parseNumeroNota(String numero) {
    final n = int.tryParse(numero.replaceAll(RegExp(r'\D'), ''));
    if (n == null || n <= 0) return null;
    return n;
  }

  static String normalizarSerie(String serie) {
    final s = serie.trim();
    return s.isEmpty ? '1' : s;
  }

  static List<NfeNumeracaoConflito> conflitosNaFaixa({
    required NfeSaidaFiscalStore store,
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
  }) {
    final serieNorm = normalizarSerie(serie);
    final conflitos = <NfeNumeracaoConflito>[];
    for (final reg in store.listar()) {
      if (normalizarSerie(reg.serie) != serieNorm) continue;
      final n = parseNumeroNota(reg.numero);
      if (n == null) continue;
      if (n < numeroInicial || n > numeroFinal) continue;
      final situacao = reg.cancelada
          ? 'cancelada'
          : reg.autorizada
              ? 'autorizada'
              : reg.processando
                  ? 'processando'
                  : reg.rejeitada
                      ? 'rejeitada'
                      : reg.rotuloStatus.toLowerCase();
      conflitos.add(
        NfeNumeracaoConflito(
          numero: n,
          situacao: situacao,
          referenciaFocus: reg.referenciaFocus,
        ),
      );
    }
    conflitos.sort((a, b) => a.numero.compareTo(b.numero));
    return conflitos;
  }

  static String? validarInutilizacao({
    required NfeSaidaFiscalStore store,
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    NfeInutilizacaoStore? inutilizacaoStore,
  }) {
    if (numeroInicial <= 0 || numeroFinal < numeroInicial) {
      return 'Faixa invalida: numero inicial deve ser <= final e ambos > 0.';
    }
    if (numeroFinal - numeroInicial > 9999) {
      return 'Faixa maxima de 10.000 numeros por pedido (SEFAZ).';
    }
    final conflitos = conflitosNaFaixa(
      store: store,
      serie: serie,
      numeroInicial: numeroInicial,
      numeroFinal: numeroFinal,
    );
    if (conflitos.isNotEmpty) {
      final amostra = conflitos
          .take(5)
          .map((c) => '${c.numero} (${c.situacao})')
          .join(', ');
      final extra = conflitos.length > 5 ? '...' : '';
      return 'Conflito: ja existe NF-e na faixa ($amostra$extra). '
          'Inutilize apenas numeros nunca emitidos.';
    }
    final inutStore = inutilizacaoStore;
    if (inutStore != null) {
      final serieNorm = normalizarSerie(serie);
      for (final inut in inutStore.listar()) {
        if (!inut.sucesso || normalizarSerie(inut.serie) != serieNorm) continue;
        final sobrepoe = numeroInicial <= inut.numeroFinal &&
            numeroFinal >= inut.numeroInicial;
        if (sobrepoe) {
          return 'Faixa sobrepoe inutilizacao ja registrada '
              '(${inut.numeroInicial}-${inut.numeroFinal} serie ${inut.serie}).';
        }
      }
    }
    return null;
  }

  /// Lacunas entre numeros emitidos na serie (indicador operacional).
  static int contarLacunasNaSerie({
    required NfeSaidaFiscalStore store,
    required String serie,
  }) {
    final serieNorm = normalizarSerie(serie);
    final numeros = <int>{};
    for (final reg in store.listar()) {
      if (normalizarSerie(reg.serie) != serieNorm) continue;
      if (reg.rejeitada) continue;
      final n = parseNumeroNota(reg.numero);
      if (n != null) numeros.add(n);
    }
    if (numeros.length < 2) return 0;
    final sorted = numeros.toList()..sort();
    var lacunas = 0;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1] - 1;
      if (gap > 0) lacunas += gap;
    }
    return lacunas;
  }
}
