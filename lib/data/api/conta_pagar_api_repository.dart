import 'package:flutter/foundation.dart';

import '../../data/models/conta_pagar.dart';
import '../sync/sync_entity_codec_operacional.dart';
import 'lan_api_client.dart';

/// Contas a pagar via API (cache em memoria).
class ContaPagarApiRepository extends ChangeNotifier {
  ContaPagarApiRepository(this._client);

  final LanApiClient _client;
  LanApiClient get client => _client;
  List<ContaPagar> _lista = [];
  final Map<int, String> _nomeFornecedorPorId = {};

  Future<void> hidratar({String? status}) async {
    final raw = await _client.listarContasPagar(status: status);
    _nomeFornecedorPorId.clear();
    final lista = <ContaPagar>[];
    for (final m in raw) {
      final c = SyncEntityCodecOperacional.contaPagarDeMap(m);
      lista.add(c);
      final nome = (m['nomeFornecedor'] ?? '').toString().trim();
      if (nome.isNotEmpty) {
        _nomeFornecedorPorId[c.id] = nome;
      }
    }
    _lista = List.unmodifiable(lista);
    notifyListeners();
  }

  /// Nome do fornecedor sem depender de ToOne ObjectBox (Terminal Leve).
  String nomeFornecedorDe(ContaPagar c) {
    final snap = _nomeFornecedorPorId[c.id]?.trim() ?? '';
    if (snap.isNotEmpty) return snap;
    try {
      final f = c.fornecedor.target;
      if (f != null) {
        final nome = f.nomeFantasia.trim().isNotEmpty
            ? f.nomeFantasia
            : f.razaoSocial;
        if (nome.trim().isNotEmpty) return nome.trim();
      }
    } catch (_) {}
    return '—';
  }

  void sincronizarPendenteParaAtrasado() {
    final hoje = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    for (final c in _lista) {
      if (c.status != ContaPagarStatus.pendente) continue;
      final venc = DateTime(
        c.dataVencimento.year,
        c.dataVencimento.month,
        c.dataVencimento.day,
      );
      if (venc.isBefore(hoje)) c.status = ContaPagarStatus.atrasado;
    }
  }

  List<ContaPagar> listar({String? status, bool ordenarDesc = false}) {
    var base = List<ContaPagar>.from(_lista);
    if (status != null && status.isNotEmpty) {
      base = base.where((c) => c.status == status).toList();
    }
    base.sort((a, b) => ordenarDesc
        ? b.dataVencimento.compareTo(a.dataVencimento)
        : a.dataVencimento.compareTo(b.dataVencimento));
    return base;
  }

  double somaPorStatus(String status) {
    var t = 0.0;
    for (final c in _lista) {
      if (c.status == status) t += c.valorParcela;
    }
    return t;
  }

  double somaTotalPago() {
    var t = 0.0;
    for (final c in _lista) {
      if (c.status == ContaPagarStatus.pago) {
        t += c.valorPago ?? c.valorParcela;
      }
    }
    return t;
  }

  Future<ContaPagar> registrarBaixa({
    required ContaPagar conta,
    required double valorPago,
    required DateTime dataPagamento,
  }) async {
    final m = await _client.baixarContaPagar(
      conta.id,
      valorPago: valorPago,
      dataPagamento: dataPagamento,
    );
    final item = m['item'];
    await hidratar();
    if (item is Map) {
      return SyncEntityCodecOperacional.contaPagarDeMap(
        Map<String, dynamic>.from(item),
      );
    }
    return conta;
  }

  Future<ContaPagar> criarManual({
    required String nomeFornecedor,
    String? cnpj,
    required double valor,
    required DateTime vencimento,
    String numeroParcela = '001/001',
    DateTime? emissao,
    String? observacaoNota,
  }) async {
    final m = await _client.criarContaPagar({
      'nomeFornecedor': nomeFornecedor,
      'cnpj': cnpj,
      'valor': valor,
      'vencimento': vencimento.toUtc().toIso8601String(),
      'numeroParcela': numeroParcela,
      if (emissao != null) 'emissao': emissao.toUtc().toIso8601String(),
      'observacaoNota': observacaoNota,
    });
    await hidratar();
    final item = m['item'];
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      final c = SyncEntityCodecOperacional.contaPagarDeMap(map);
      final nome = (map['nomeFornecedor'] ?? nomeFornecedor).toString().trim();
      if (nome.isNotEmpty) _nomeFornecedorPorId[c.id] = nome;
      return c;
    }
    throw StateError('Falha ao criar conta a pagar.');
  }

  /// Remove titulo no PC1 (pendente/atrasado). Atualiza o cache local.
  Future<void> removerContaPagarRemoto(int contaId) async {
    if (contaId <= 0) {
      throw LanApiException('ID da conta a pagar invalido.');
    }
    ContaPagar? local;
    for (final c in _lista) {
      if (c.id == contaId) {
        local = c;
        break;
      }
    }
    if (local != null && local.status == ContaPagarStatus.pago) {
      throw LanApiException(
        'Nao e possivel remover: titulo ja esta quitado/pago. '
        'Estorne o pagamento antes de excluir.',
      );
    }
    final ok = await _client.removerContaPagar(contaId);
    if (!ok) {
      throw LanApiException('Falha ao remover conta a pagar.');
    }
    _lista = List.unmodifiable(_lista.where((c) => c.id != contaId));
    _nomeFornecedorPorId.remove(contaId);
    notifyListeners();
  }

  Future<int> garantirObrigacoesMensais() async {
    final m = await _client.gerarObrigacoesMensais();
    return (m['criadas'] as num?)?.toInt() ?? 0;
  }

  /// Preferir [removerContaPagarRemoto] no Terminal Leve.
  bool remover(int id) {
    throw StateError(
      'Remocao de conta a pagar no terminal: use removerContaPagarRemoto.',
    );
  }
}
