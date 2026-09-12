import 'filtro_listagem_entregas.dart';
import 'venda_documento_rotulo_helper.dart';
import 'venda_relacao_safe.dart';
import '../model/venda.dart';

/// Filtros de data marcada / resumo (atrasadas, hoje) compartilhados entre UI e repositorio.
abstract final class EntregaFiltroUtil {
  /// Pedidos ainda no patio (com ou sem motorista).
  /// [roteirizada] e status interno — na tela entra no mesmo balde que pendente.
  static const statusesNoPatio = {'pendente', 'roteirizada'};

  /// Status que nao ocupam mais a agenda do dia (carreto ja realizado ou cancelado).
  static const statusesConcluidosAgenda = {'entregue', 'cancelada'};

  static bool ehConcluidaNaAgenda(String statusEntrega) {
    return statusesConcluidosAgenda.contains(statusEntrega.trim().toLowerCase());
  }

  /// Pendente, agendada, em rota ou complemento pendente.
  static bool ehAtivaNaAgenda(Venda venda) =>
      !ehConcluidaNaAgenda(venda.statusEntrega);

  static DateTime soDia(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Consulta de agenda do dia: por padrao so carretos pendentes de realizacao.
  static List<Venda> agendaDoDia(
    Iterable<Venda> candidatas,
    DateTime dia, {
    bool incluirConcluidas = false,
  }) {
    final base = soDia(dia);
    return candidatas.where((venda) {
      if (!incluirConcluidas && ehConcluidaNaAgenda(venda.statusEntrega)) {
        return false;
      }
      final marcada = venda.dataEntregaMarcada?.toLocal();
      if (marcada == null) return false;
      return soDia(marcada) == base;
    }).toList();
  }

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
        .where((v) => VendaDocumentoRotuloHelper.vendaAtendeBuscaNumeroEntrega(v, n))
        .toList();
  }

  /// Filtros em memoria (terminal API e ObjectBox apos consulta).
  static List<Venda> aplicarEmMemoria(
    List<Venda> candidatas,
    FiltroListagemEntregas filtro, {
    dynamic vendedorRepository,
    dynamic clienteRepository,
  }) {
    final termo = filtro.bairroTermo.trim().toLowerCase();
    final motorista = filtro.filtroMotorista.trim().toLowerCase();
    final vendedor = filtro.filtroVendedor.trim().toLowerCase();

    var out = candidatas.where((venda) {
      if (!atendeStatusFiltro(venda.statusEntrega, filtro.statusEntrega)) {
        return false;
      }
      if (!filtro.incluirEntregasConcluidas &&
          statusesDoFiltro(filtro.statusEntrega) == null &&
          ehConcluidaNaAgenda(venda.statusEntrega)) {
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
      if (termo.isNotEmpty) {
        final enderecoOk =
            venda.enderecoEntrega.toLowerCase().contains(termo);
        final clienteOk = VendaRelacaoSafe.nomeCliente(
          venda,
          clienteRepository: clienteRepository,
          fallback: '',
        ).trim().toLowerCase().contains(termo);
        var numeroOk = false;
        final termoNumero = termo.startsWith('#') ? termo.substring(1) : termo;
        final parsed = int.tryParse(termoNumero);
        if (parsed != null) {
          numeroOk = VendaDocumentoRotuloHelper.vendaAtendeBuscaNumeroEntrega(
            venda,
            parsed,
          );
        }
        if (!enderecoOk && !clienteOk && !numeroOk) return false;
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
