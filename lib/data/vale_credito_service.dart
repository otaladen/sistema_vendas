import '../domain/vale_credito.dart';
import '../model/vale_credito.dart';
import 'api/lan_api_client.dart';
import 'api/lan_api_event_hub.dart';
import 'vale_credito_repository.dart';
import 'venda_repository.dart';

/// Vale no formato que a tela precisa, sem depender de onde ele mora.
///
/// No terminal leve o vale chega por JSON e nao existe como entidade local,
/// entao a UI conversa sempre com este resumo.
class ValeCreditoResumo {
  ValeCreditoResumo({
    required this.id,
    required this.codigo,
    required this.valorOriginal,
    required this.valorUtilizado,
    required this.cancelado,
    required this.dataEmissao,
    this.dataValidade,
    this.clienteNome = '',
    this.numeroVendaOrigem = 0,
    this.observacao = '',
  });

  factory ValeCreditoResumo.deEntidade(ValeCredito v) => ValeCreditoResumo(
        id: v.id,
        codigo: v.codigo,
        valorOriginal: v.valorOriginal,
        valorUtilizado: v.valorUtilizado,
        cancelado: v.cancelado,
        dataEmissao: v.dataEmissao,
        dataValidade: v.dataValidade,
        clienteNome: v.cliente.target?.rotuloExibicao() ?? '',
        numeroVendaOrigem: v.numeroVendaOrigem,
        observacao: v.observacao,
      );

  factory ValeCreditoResumo.deMap(Map<String, dynamic> m) => ValeCreditoResumo(
        id: (m['id'] as num?)?.toInt() ?? 0,
        codigo: (m['codigo'] ?? '').toString(),
        valorOriginal: (m['valorOriginal'] as num?)?.toDouble() ?? 0,
        valorUtilizado: (m['valorUtilizado'] as num?)?.toDouble() ?? 0,
        cancelado: m['cancelado'] == true,
        dataEmissao:
            DateTime.tryParse((m['dataEmissao'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
        dataValidade:
            DateTime.tryParse((m['dataValidade'] ?? '').toString())?.toLocal(),
        clienteNome: (m['clienteNome'] ?? '').toString(),
        numeroVendaOrigem: (m['numeroVendaOrigem'] as num?)?.toInt() ?? 0,
        observacao: (m['observacao'] ?? '').toString(),
      );

  final int id;
  final String codigo;
  final double valorOriginal;
  final double valorUtilizado;
  final bool cancelado;
  final DateTime dataEmissao;
  final DateTime? dataValidade;
  final String clienteNome;
  final int numeroVendaOrigem;
  final String observacao;

  String get codigoFormatado => ValeCreditoCodigo.formatar(codigo);

  double get saldo => ValeCreditoRegras.saldo(
        valorOriginal: valorOriginal,
        valorUtilizado: valorUtilizado,
      );

  ValeCreditoSituacao get situacao => ValeCreditoRegras.situacao(
        valorOriginal: valorOriginal,
        valorUtilizado: valorUtilizado,
        cancelado: cancelado,
        validade: dataValidade,
      );

  ValeCreditoAvaliacao avaliar(double totalAPagar) =>
      ValeCreditoRegras.avaliarResgate(
        valorOriginal: valorOriginal,
        valorUtilizado: valorUtilizado,
        cancelado: cancelado,
        totalAPagar: totalAPagar,
        validade: dataValidade,
      );
}

/// Fala com o vale no PC servidor (ObjectBox direto) ou pela LAN (terminal).
class ValeCreditoService {
  ValeCreditoService._({ValeCreditoRepository? local, LanApiClient? api})
      : _local = local,
        _api = api;

  /// Resolve o caminho a partir do repositorio de venda que a tela ja recebe.
  factory ValeCreditoService.deVendaRepository(dynamic vendaRepository) {
    if (vendaRepository is VendaRepository) {
      return ValeCreditoService._(
        local: ValeCreditoRepository(vendaRepository.objectBox),
      );
    }
    return ValeCreditoService._(api: LanApiEventHub.instance.client);
  }

  final ValeCreditoRepository? _local;
  final LanApiClient? _api;

  bool get disponivel => _local != null || _api != null;

  LanApiClient _exigirApi() {
    final api = _api;
    if (api == null) {
      throw StateError('Sem conexao com o servidor para tratar o vale.');
    }
    return api;
  }

  Future<ValeCreditoResumo?> buscarPorCodigo(String codigo) async {
    final local = _local;
    if (local != null) {
      final v = local.buscarPorCodigo(codigo);
      return v == null ? null : ValeCreditoResumo.deEntidade(v);
    }
    final m = await _exigirApi().buscarValePorCodigo(
      ValeCreditoCodigo.normalizar(codigo),
    );
    return m == null ? null : ValeCreditoResumo.deMap(m);
  }

  Future<List<ValeCreditoResumo>> listarGastaveisDoCliente(
    int clienteId,
  ) async {
    if (clienteId <= 0) return const [];
    final local = _local;
    if (local != null) {
      return local
          .listarGastaveisDoCliente(clienteId)
          .map(ValeCreditoResumo.deEntidade)
          .toList();
    }
    final itens = await _exigirApi().listarValesDoCliente(clienteId);
    return itens.map(ValeCreditoResumo.deMap).toList();
  }

  Future<ValeCreditoResumo> emitir({
    required double valor,
    required String emitidoPor,
    int vendaOrigemId = 0,
    int registroDevolucaoId = 0,
    int clienteId = 0,
    int numeroVendaOrigem = 0,
    String observacao = '',
    int? validadeDias = ValeCreditoRepository.validadeDiasPadrao,
  }) async {
    final local = _local;
    if (local != null) {
      final v = local.emitir(
        valor: valor,
        emitidoPor: emitidoPor,
        vendaOrigemId: vendaOrigemId,
        registroDevolucaoId: registroDevolucaoId,
        clienteId: clienteId,
        numeroVendaOrigem: numeroVendaOrigem,
        observacao: observacao,
        validadeDias: validadeDias,
      );
      return ValeCreditoResumo.deEntidade(v);
    }
    final m = await _exigirApi().emitirVale({
      'valor': valor,
      'emitidoPor': emitidoPor,
      'vendaOrigemId': vendaOrigemId,
      'registroDevolucaoId': registroDevolucaoId,
      'clienteId': clienteId,
      'numeroVendaOrigem': numeroVendaOrigem,
      'observacao': observacao,
      'validadeDias': validadeDias,
    });
    final item = m['item'];
    if (item is! Map) {
      throw StateError('Servidor nao devolveu o vale emitido.');
    }
    return ValeCreditoResumo.deMap(Map<String, dynamic>.from(item));
  }

  Future<void> resgatar({
    required int valeId,
    required double valor,
    required String registradoPor,
    int vendaId = 0,
    int numeroVenda = 0,
  }) async {
    final local = _local;
    if (local != null) {
      local.resgatar(
        valeId: valeId,
        valor: valor,
        registradoPor: registradoPor,
        vendaId: vendaId,
        numeroVenda: numeroVenda,
      );
      return;
    }
    await _exigirApi().resgatarVale(valeId, {
      'valor': valor,
      'registradoPor': registradoPor,
      'vendaId': vendaId,
      'numeroVenda': numeroVenda,
    });
  }

  Future<void> cancelar({
    required int valeId,
    required String motivo,
    required String canceladoPor,
  }) async {
    final local = _local;
    if (local != null) {
      local.cancelar(
        valeId: valeId,
        motivo: motivo,
        canceladoPor: canceladoPor,
      );
      return;
    }
    await _exigirApi().cancelarVale(
      valeId,
      motivo: motivo,
      canceladoPor: canceladoPor,
    );
  }

  Future<void> estornarUsosDaVenda(int vendaId) async {
    final local = _local;
    if (local != null) {
      local.estornarUsosDaVenda(vendaId);
      return;
    }
    await _exigirApi().estornarValesDaVenda(vendaId);
  }
}
