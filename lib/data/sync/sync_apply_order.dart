/// Ordem de aplicacao no pull para respeitar FKs (cliente antes de venda, etc.).
abstract final class SyncApplyOrder {
  SyncApplyOrder._();

  static const _prioridade = <String, int>{
    'empresa_config': 5,
    'fornecedor_nfe': 10,
    'produto': 20,
    'produto_sugestao_venda': 25,
    'sugestao_venda_metrica': 26,
    'cliente': 30,
    'vendedor': 40,
    'funcionario': 50,
    'motorista': 60,
    'lancamento_funcionario': 70,
    'fechamento_rh_funcionario': 75,
    'vinculo_fornecedor': 80,
    'historico_entrada': 90,
    'nfe_importada': 100,
    'kit_orcamento': 110,
    'promocao': 120,
    'venda': 200,
    'titulo_receber': 210,
    'recebimento_fiado': 220,
    'historico_entrega': 230,
    'conferencia_carga_romaneio': 240,
    'registro_devolucao': 250,
    'mensageria_templates': 900,
    'usuarios_sistema': 910,
    'caixa_sessoes': 920,
  };

  static int prioridadeDe(String? entity) =>
      _prioridade[entity ?? ''] ?? 500;

  static void ordenarAlteracoes(List<dynamic> changes) {
    changes.sort((a, b) {
      final ea = a is Map ? a['entity']?.toString() : null;
      final eb = b is Map ? b['entity']?.toString() : null;
      final pa = prioridadeDe(ea);
      final pb = prioridadeDe(eb);
      if (pa != pb) return pa.compareTo(pb);
      final ra = a is Map ? (a['revision'] as num?)?.toInt() ?? 0 : 0;
      final rb = b is Map ? (b['revision'] as num?)?.toInt() ?? 0 : 0;
      return ra.compareTo(rb);
    });
  }
}
