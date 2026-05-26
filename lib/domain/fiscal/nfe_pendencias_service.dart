import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/venda_repository.dart';
import '../../model/venda.dart';

/// Venda finalizada aguardando NF-e modelo 55.
class NfePendenciaVenda {
  const NfePendenciaVenda({
    required this.venda,
    required this.clienteNome,
    this.ultimoStatusNfe = '',
  });

  final Venda venda;
  final String clienteNome;
  final String ultimoStatusNfe;
}

/// Servico de fila operacional NF-e (Fase 4).
abstract final class NfePendenciasService {
  NfePendenciasService._();

  static Set<int> idsVendasComNfeAutorizada(
    NfeSaidaFiscalStore store, {
    VendaRepository? vendaRepository,
  }) {
    final ids = <int>{};
    for (final r in store.listar()) {
      if (r.vendaId > 0 && r.autorizada) ids.add(r.vendaId);
    }
    final repo = vendaRepository;
    if (repo != null) {
      for (final v in repo.listarVendasComDadosNfe55(limit: 500)) {
        if (v.nfe55Autorizada) ids.add(v.id);
      }
    }
    return ids;
  }

  /// Vendas finalizadas com cliente, sem NF-e 55 autorizada no periodo.
  static List<NfePendenciaVenda> listarVendasSemNfeAutorizada({
    required VendaRepository vendaRepository,
    required NfeSaidaFiscalStore nfeStore,
    int dias = 30,
    int limit = 50,
    bool somenteComCliente = true,
  }) {
    if (dias <= 0 || limit <= 0) return const [];
    final desde = DateTime.now().subtract(Duration(days: dias));
    final comAuth = idsVendasComNfeAutorizada(
      nfeStore,
      vendaRepository: vendaRepository,
    );
    final ultimaPorVenda = <int, NfeSaidaFiscalRegistro>{};
    for (final r in nfeStore.listar()) {
      if (r.vendaId <= 0) continue;
      ultimaPorVenda.putIfAbsent(r.vendaId, () => r);
    }

    final out = <NfePendenciaVenda>[];
    final vendas = vendaRepository.listarVendasFinalizadasDesde(
      desde,
      limit: limit * 3,
    );
    for (final v in vendas) {
      if (comAuth.contains(v.id)) continue;
      final cliente = v.cliente.target;
      if (somenteComCliente && cliente == null) continue;
      final ultima = ultimaPorVenda[v.id];
      out.add(
        NfePendenciaVenda(
          venda: v,
          clienteNome: cliente?.nomeRazao ?? 'Sem cliente',
          ultimoStatusNfe: ultima?.rotuloStatus ?? '',
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  static List<NfeSaidaFiscalRegistro> listarProcessando(
    NfeSaidaFiscalStore store,
  ) {
    return store.listar().where((r) => r.processando).toList();
  }

  static List<NfeSaidaFiscalRegistro> listarRejeitadasRecentes(
    NfeSaidaFiscalStore store, {
    int limit = 20,
  }) {
    return store
        .listar()
        .where((r) => r.rejeitada)
        .take(limit)
        .toList();
  }
}
