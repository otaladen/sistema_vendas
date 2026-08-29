/// Prioridade de sincronizacao LAN por entidade de negocio.
enum SyncPrioridade {
  /// Venda, estoque, caixa — push imediato apos gravar.
  alta,

  /// Entregas, cadastros do dia — timer curto / debounce medio.
  media,

  /// Produtos, precos, config fria — sob demanda ou timer lento.
  baixa,
}

/// Modo de execucao do ciclo de sync.
enum SyncModo {
  /// Timer / WS: checa versao, puxa so se atrasado, empurra dirty.
  periodico,

  /// Apos venda/estoque: prioriza push; pull so se versao mudou.
  prioritario,

  /// Botao manual / bootstrap: pull + push completos.
  completo,
}

/// Classifica entidades para filas de sync (evita trafego desnecessario).
abstract final class SyncPriorityCatalogo {
  SyncPriorityCatalogo._();

  static const alta = <String>{
    'venda',
    'orcamento', // alias de auditoria/legado; sync usa entity venda
    'movimento_estoque',
    'lote_produto',
    'titulo_receber',
    'recebimento_fiado',
    'caixa_sessoes',
    'registro_devolucao',
    // Dinheiro na mao do cliente: o vale precisa chegar antes dele andar
    // ate outro terminal para gastar.
    'vale_credito',
    'historico_entrada',
    'nfe_importada',
  };

  static const media = <String>{
    'cliente',
    'funcionario',
    'lancamento_funcionario',
    'fechamento_rh_funcionario',
    'vendedor',
    'motorista',
    'historico_entrega',
    'conferencia_carga_romaneio',
    'conta_pagar',
    'fornecedor_nfe',
    'vinculo_fornecedor',
    'recado_loja',
    'usuarios_sistema',
    // Preco/cadastro de produto: precisa subir rapido; baixa + pull-first
    // descartava dirty e o PC nunca recebia a alteracao.
    'produto',
  };

  static const baixa = <String>{
    'kit_orcamento',
    'promocao',
    'reajuste_preco',
    'empresa_config',
    'auditoria_evento',
    'item_lista_compra',
    'produto_sugestao_venda',
    'sugestao_venda_metrica',
  };

  static SyncPrioridade de(String? entity) {
    final e = (entity ?? '').trim();
    if (e.isEmpty) return SyncPrioridade.media;
    if (alta.contains(e)) return SyncPrioridade.alta;
    if (baixa.contains(e)) return SyncPrioridade.baixa;
    if (media.contains(e)) return SyncPrioridade.media;
    // Entidade desconhecida: trata como media (segura).
    return SyncPrioridade.media;
  }

  static bool isAlta(String? entity) => de(entity) == SyncPrioridade.alta;
  static bool isBaixa(String? entity) => de(entity) == SyncPrioridade.baixa;
}
