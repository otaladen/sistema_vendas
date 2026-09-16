import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/venda_repository.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import 'cliente_fiscal_helper.dart';
import 'venda_documento_fiscal_mutex.dart';

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

  /// NFC-e autorizada ou em processamento ja ocupa o documento de saida.
  static bool ocultaPorNfce(Venda venda) =>
      VendaDocumentoFiscalMutex.bloqueiaNovaNfe55(venda);

  /// Fila NF-e 55: cliente CNPJ/PJ, sem NFC-e e sem NF-e 55.
  /// Dinheiro (cupom) e consumidor com NFC-e nao entram nesta tela.
  static bool entraNaFilaVendasSemNfe55(
    Venda venda, {
    Cliente? cliente,
  }) {
    if (venda.nfe55Autorizada) return false;
    if (ocultaPorNfce(venda)) return false;
    if (_pagamentoEmDinheiro(venda)) return false;
    return ClienteFiscalHelper.clienteExigeNfe55(
      cliente ?? venda.cliente.target,
    );
  }

  static bool _pagamentoEmDinheiro(Venda venda) =>
      venda.formaPagamento.trim().toLowerCase() == 'dinheiro';

  /// Vendas finalizadas de cliente CNPJ/PJ, sem NF-e 55 autorizada no periodo.
  /// Nao inclui NFC-e, pagamento em dinheiro nem cupom de consumidor (PF).
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
      limit: limit * 10,
    );
    for (final v in vendas) {
      if (comAuth.contains(v.id)) continue;
      final cliente = v.cliente.target;
      if (somenteComCliente && cliente == null) continue;
      if (!entraNaFilaVendasSemNfe55(v, cliente: cliente)) continue;
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

  /// Registro de tentativa falha/processando que ja foi resolvido com NF-e autorizada.
  static bool registroSuperadoPorNfeAutorizada(
    NfeSaidaFiscalRegistro registro, {
    required Set<int> vendasComNfeAutorizada,
  }) =>
      registro.vendaId > 0 &&
      vendasComNfeAutorizada.contains(registro.vendaId);

  static List<NfeSaidaFiscalRegistro> listarProcessando(
    NfeSaidaFiscalStore store, {
    VendaRepository? vendaRepository,
  }) {
    final comAuth = idsVendasComNfeAutorizada(
      store,
      vendaRepository: vendaRepository,
    );
    return store
        .listar()
        .where(
          (r) =>
              r.processando &&
              !registroSuperadoPorNfeAutorizada(
                r,
                vendasComNfeAutorizada: comAuth,
              ),
        )
        .toList();
  }

  static List<NfeSaidaFiscalRegistro> listarRejeitadasRecentes(
    NfeSaidaFiscalStore store, {
    VendaRepository? vendaRepository,
    int limit = 20,
  }) {
    final comAuth = idsVendasComNfeAutorizada(
      store,
      vendaRepository: vendaRepository,
    );
    return store
        .listar()
        .where(
          (r) =>
              r.rejeitada &&
              !registroSuperadoPorNfeAutorizada(
                r,
                vendasComNfeAutorizada: comAuth,
              ),
        )
        .take(limit)
        .toList();
  }
}
