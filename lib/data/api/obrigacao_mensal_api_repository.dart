import 'package:flutter/foundation.dart';

import '../../model/obrigacao_mensal_fixa.dart';
import 'lan_api_client.dart';

/// Obrigacoes fixas via Lan API (cache em memoria).
class ObrigacaoMensalApiRepository extends ChangeNotifier {
  ObrigacaoMensalApiRepository(this._client);

  final LanApiClient _client;
  List<ObrigacaoMensalFixa> _lista = [];

  List<ObrigacaoMensalFixa> get lista => List.unmodifiable(_lista);

  static ObrigacaoMensalFixa deMap(Map<String, dynamic> m) =>
      ObrigacaoMensalFixa(
        id: (m['id'] as num?)?.toInt() ?? 0,
        descricao: (m['descricao'] ?? '').toString(),
        valor: (m['valor'] as num?)?.toDouble() ?? 0,
        periodicidade: ObrigacaoPeriodicidade.normalizar(
          (m['periodicidade'] ?? '').toString(),
        ),
        diaVencimento: (m['diaVencimento'] as num?)?.toInt() ?? 10,
        mesVencimento: (m['mesVencimento'] as num?)?.toInt() ?? 1,
        cnpj: (m['cnpj'] ?? '').toString(),
        ativo: m['ativo'] != false,
        criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
      );

  Future<void> hidratar() async {
    final raw = await _client.listarObrigacoesMensais();
    _lista = [for (final m in raw) deMap(m)];
    notifyListeners();
  }

  List<ObrigacaoMensalFixa> listar({bool somenteAtivas = false}) {
    final base = somenteAtivas
        ? _lista.where((o) => o.ativo).toList()
        : List<ObrigacaoMensalFixa>.from(_lista);
    base.sort((a, b) {
      final byPer = ObrigacaoPeriodicidade.normalizar(a.periodicidade)
          .compareTo(ObrigacaoPeriodicidade.normalizar(b.periodicidade));
      if (byPer != 0) return byPer;
      final byDia = a.diaVencimento.compareTo(b.diaVencimento);
      if (byDia != 0) return byDia;
      return a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase());
    });
    return base;
  }

  Future<ObrigacaoMensalFixa> salvar({
    int id = 0,
    required String descricao,
    required double valor,
    String periodicidade = ObrigacaoPeriodicidade.mensal,
    required int diaVencimento,
    int mesVencimento = 1,
    String cnpj = '',
    bool ativo = true,
  }) async {
    final m = await _client.salvarObrigacaoMensal({
      if (id > 0) 'id': id,
      'descricao': descricao,
      'valor': valor,
      'periodicidade': periodicidade,
      'diaVencimento': diaVencimento,
      'mesVencimento': mesVencimento,
      'cnpj': cnpj,
      'ativo': ativo,
    });
    final item = m['item'];
    if (item is! Map) {
      throw StateError('Resposta invalida ao salvar obrigacao.');
    }
    await hidratar();
    return deMap(Map<String, dynamic>.from(item));
  }

  Future<bool> remover(int id) async {
    final ok = await _client.removerObrigacaoMensal(id);
    if (ok) await hidratar();
    return ok;
  }

  Future<int> gerarPendenciasRecentes() async {
    final m = await _client.gerarObrigacoesMensais();
    return (m['criadas'] as num?)?.toInt() ?? 0;
  }
}
