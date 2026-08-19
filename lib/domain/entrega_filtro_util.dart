import 'filtro_listagem_entregas.dart';
import 'venda_relacao_safe.dart';
import '../model/venda.dart';

/// Filtros de data marcada / resumo (atrasadas, hoje) compartilhados entre UI e repositorio.
abstract final class EntregaFiltroUtil {
  /// Pedidos ainda no patio (com ou sem motorista).
  /// [roteirizada] e status interno — na tela entra no mesmo balde que pendente.
  static const statusesNoPatio = {'pendente', 'roteirizada'};

  /// Status gravados que o chip/filtro da tela deve incluir. Null = todos.
  static Set<String>? statusesDoFiltro(String statusEntrega) {
    final s = statusEntrega.trim();
    if (s.isEmpty || s == 'todos') return null;
    if (s == 'pendente' || s == 'roteirizada') return statusesNoPatio;
    return {s};
  }

  static bool atendeStatusFiltro(String statusVenda, String filtro) {
    final set = statusesDoFiltro(filtro);
    if (set == null) return true;
    return set.contains(statusVenda.trim());
  }

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

  /// Filtros em memoria (terminal API e ObjectBox apos consulta).
  static List<Venda> aplicarEmMemoria(
    List<Venda> candidatas,
    FiltroListagemEntregas filtro, {
    dynamic vendedorRepository,
  }) {
    final termo = filtro.bairroTermo.trim().toLowerCase();
    final motorista = filtro.filtroMotorista.trim().toLowerCase();
    final vendedor = filtro.filtroVendedor.trim().toLowerCase();

    var out = candidatas.where((venda) {
      if (!atendeStatusFiltro(venda.statusEntrega, filtro.statusEntrega)) {
        return false;
      }
      final iniMarcada = filtro.dataMarcadaInicio;
      final fimMarcada = filtro.dataMarcadaFim;
      if (iniMarcada != null || fimMarcada != null) {
        final marcada = venda.dataEntregaMarcada?.toLocal();
        if (marcada == null) return false;
        final d = DateTime(marcada.year, marcada.month, marcada.day);
        if (iniMarcada != null) {
          final i = DateTime(
            iniMarcada.year,
            iniMarcada.month,
            iniMarcada.day,
          );
          if (d.isBefore(i)) return false;
        }
        if (fimMarcada != null) {
          final f = DateTime(
            fimMarcada.year,
            fimMarcada.month,
            fimMarcada.day,
          );
          if (d.isAfter(f)) return false;
        }
      } else if (!filtro.dataMarcadaFiltradaNoBanco &&
          !atendeFiltroDataMarcada(venda, filtro.filtroDataMarcada)) {
        return false;
      }
      if (termo.isNotEmpty &&
          !venda.enderecoEntrega.toLowerCase().contains(termo)) {
        return false;
      }
      if (motorista != 'todos' && motorista.isNotEmpty) {
        final m = venda.motoristaEntrega.trim().toLowerCase();
        if (m != motorista) return false;
      }
      if (vendedor != 'todos' && vendedor.isNotEmpty) {
        final nomeExib = VendaRelacaoSafe.nomeVendedor(
          venda,
          vendedorRepository: vendedorRepository,
          fallback: '',
        ).trim().toLowerCase();
        if (nomeExib != vendedor) return false;
      }
      if (filtro.apenasAtrasadas && !ehAtrasada(venda)) {
        return false;
      }
      if (filtro.apenasPendentesHoje && !ehAgendaHoje(venda)) {
        return false;
      }
      return true;
    }).toList();

    return filtrarPorNumeroNota(out, filtro.numeroNota);
  }
}
