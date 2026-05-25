import '../model/venda.dart';

/// Filtros de data marcada / resumo (atrasadas, hoje) compartilhados entre UI e repositorio.
abstract final class EntregaFiltroUtil {
  /// Mesma regra da aba Entregas para contadores atrasadas / hoje.
  static bool _bloqueiaResumoAtrasadaOuHoje(String status) {
    return status == 'entregue' || status == 'cancelada';
  }

  static bool ehAtrasada(Venda venda) {
    if (_bloqueiaResumoAtrasadaOuHoje(venda.statusEntrega)) return false;
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    final hoje = DateTime.now();
    final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final baseMarcada = DateTime(marcada.year, marcada.month, marcada.day);
    return baseMarcada.isBefore(baseHoje);
  }

  static bool ehAgendaHoje(Venda venda) {
    if (_bloqueiaResumoAtrasadaOuHoje(venda.statusEntrega)) return false;
    final marcada = venda.dataEntregaMarcada?.toLocal();
    if (marcada == null) return false;
    final hoje = DateTime.now();
    final baseHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final baseMarcada = DateTime(marcada.year, marcada.month, marcada.day);
    return baseMarcada == baseHoje;
  }

  static bool atendeFiltroDataMarcada(Venda venda, String filtroDataMarcada) {
    switch (filtroDataMarcada) {
      case 'sem_data':
        return venda.dataEntregaMarcada == null;
      case 'hoje':
        final marcada = venda.dataEntregaMarcada?.toLocal();
        if (marcada == null) return false;
        final hoje = DateTime.now();
        final base = DateTime(hoje.year, hoje.month, hoje.day);
        final d = DateTime(marcada.year, marcada.month, marcada.day);
        return d == base;
      case 'amanha':
        final marcada = venda.dataEntregaMarcada?.toLocal();
        if (marcada == null) return false;
        final hoje = DateTime.now();
        final base = DateTime(hoje.year, hoje.month, hoje.day);
        final d = DateTime(marcada.year, marcada.month, marcada.day);
        return d == base.add(const Duration(days: 1));
      case 'todos':
      default:
        return true;
    }
  }

  static List<Venda> filtrarPorNumeroNota(List<Venda> entregas, String numeroNotaRaw) {
    var raw = numeroNotaRaw.trim();
    if (raw.isEmpty) return entregas;
    if (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }
    final n = int.tryParse(raw);
    if (n == null) return <Venda>[];
    return entregas
        .where(
          (v) =>
              (v.numeroOrcamento > 0 && v.numeroOrcamento == n) || v.id == n,
        )
        .toList();
  }
}
