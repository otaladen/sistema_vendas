import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../model/cliente.dart';
import '../../model/funcionario.dart';
import '../../model/kit_orcamento.dart';
import '../../model/fornecedor_nfe.dart';
import '../../model/motorista.dart';
import '../../model/nfe_importada_registro.dart';
import '../../model/produto.dart';
import '../../model/promocao.dart';
import '../../model/promocao_combo_item.dart';
import '../../model/promocao_item.dart';
import '../../model/vendedor.dart';
import '../app_config_repository.dart';
import '../mensageria_repository.dart';
import '../objectbox.dart';
import '../caixa_sessao_repository.dart';
import '../conferencia_carga_repository.dart';
import '../usuario_repository.dart';
import '../cliente_repository.dart';
import '../../objectbox.g.dart';
import '../produto_repository.dart';
import '../venda_repository.dart';
import '../vendedor_repository.dart';
import '../../domain/recado_loja_helper.dart';
import '../../domain/produto_estoque_sync.dart';
import '../../domain/sync/fornecedor_nfe_sync_merge.dart';
import 'sync_conflict_log.dart';
import 'sync_cursor_storage.dart';
import 'sync_delete_outbox.dart';
import 'sync_dirty_outbox.dart';
import 'sync_entity_codec.dart';
import 'sync_entity_codec_operacional.dart';
import 'sync_entity_codec_extras.dart';

/// Monta push e aplica pull para todas as entidades de negocio.
class SyncFullSync {
  SyncFullSync({
    required ObjectBox db,
    required AppConfigRepository configRepository,
    required ProdutoRepository produtoRepo,
    required ClienteRepository clienteRepo,
    required VendedorRepository vendedorRepo,
    required VendaRepository vendaRepo,
  })  : _db = db,
        _configRepository = configRepository,
        _produtoRepo = produtoRepo,
        _clienteRepo = clienteRepo,
        _vendedorRepo = vendedorRepo,
        _vendaRepo = vendaRepo;

  final ObjectBox _db;
  final AppConfigRepository _configRepository;
  final ProdutoRepository _produtoRepo;
  final ClienteRepository _clienteRepo;
  final VendedorRepository _vendedorRepo;
  final VendaRepository _vendaRepo;

  static const _kUsuarios = 'usuarios_sistema_v1';
  static const _kTemplates = 'mensageria_templates_v1';

  /// ID remoto (payload) → ID local preservado por unique (CNPJ).
  final Map<int, int> _fornecedorNfeIdAlias = {};

  /// Limpa aliases de unique no inicio de cada lote de pull.
  void prepararLotePull() {
    _fornecedorNfeIdAlias.clear();
  }

  void _add(
    List<Map<String, dynamic>> out,
    String entity,
    int localId,
    Map<String, dynamic> payload,
  ) {
    out.add(<String, dynamic>{
      'entity': entity,
      'op': 'upsert',
      'localId': localId,
      'payload': payload,
    });
  }

  Future<List<Map<String, dynamic>>> montarMutacoes({
    bool evitarSnapshotCompleto = false,
  }) async {
    // Copia tipada: evita List<Map<String, Object>> vinda do outbox de deletes.
    final m = <Map<String, dynamic>>[
      ...await SyncDeleteOutbox.mutacoesParaPush(),
    ];
    final revision = await SyncCursorStorage().carregarUltimaRevision();
    final bootstrap =
        await SyncDirtyOutbox.precisaBootstrap() || revision == 0;

    if (bootstrap) {
      // Celular: snapshot completo congela o app (ANR). Ainda assim envia
      // dirty pontual (orcamento/venda) — senao revision==0 engole o push.
      if (evitarSnapshotCompleto) {
        final dirtyBoot = await SyncDirtyOutbox.listar();
        for (final d in dirtyBoot) {
          if (d.sincronizarTodas) continue;
          await _montarEntidadeId(m, d.entity, d.entityId);
        }
        return m;
      }
      await _montarSnapshotCompleto(m);
      return m;
    }

    final dirty = await SyncDirtyOutbox.listar();
    if (dirty.isEmpty) return m;

    final entidadesInteiras = dirty
        .where((d) => d.sincronizarTodas)
        .map((d) => d.entity)
        .toSet();
    final porId = <String, Set<int>>{};
    for (final d in dirty) {
      if (d.sincronizarTodas) continue;
      porId.putIfAbsent(d.entity, () => {}).add(d.entityId);
    }

    // No celular ignora "sincronizar todas" (remontar entidade inteira).
    if (!evitarSnapshotCompleto) {
      for (final entity in entidadesInteiras) {
        await _montarEntidadeCompleta(m, entity);
      }
    }
    for (final entry in porId.entries) {
      var n = 0;
      for (final id in entry.value) {
        await _montarEntidadeId(m, entry.key, id);
        n++;
        if (evitarSnapshotCompleto && n % 10 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    return m;
  }

  Future<void> _montarSnapshotCompleto(List<Map<String, dynamic>> m) async {
    for (final entity in _entidadesSync) {
      await _montarEntidadeCompleta(m, entity);
    }
  }

  static const _entidadesSync = [
    'fornecedor_nfe',
    'produto',
    'cliente',
    'vendedor',
    'funcionario',
    'lancamento_funcionario',
    'fechamento_rh_funcionario',
    'motorista',
    'vinculo_fornecedor',
    'historico_entrada',
    'nfe_importada',
    'kit_orcamento',
    'promocao',
    'venda',
    'titulo_receber',
    'recebimento_fiado',
    'historico_entrega',
    'conferencia_carga_romaneio',
    'registro_devolucao',
    'empresa_config',
    'mensageria_templates',
    'usuarios_sistema',
    'caixa_sessoes',
    'movimento_estoque',
    'conta_pagar',
    'reajuste_preco',
    'auditoria_evento',
    'item_lista_compra',
    'produto_sugestao_venda',
    'sugestao_venda_metrica',
    'recado_loja',
  ];

  Future<void> _montarEntidadeCompleta(
    List<Map<String, dynamic>> m,
    String entity,
  ) async {
    switch (entity) {
      case 'fornecedor_nfe':
        for (final f in _db.fornecedorNfeBox.getAll()) {
          _add(
            m,
            entity,
            f.id,
            SyncEntityCodecExtras.fornecedorNfeParaMap(f),
          );
        }
      case 'produto':
        for (final p in _produtoRepo.listarTodos()) {
          _add(m, entity, p.id, SyncEntityCodec.produtoParaMap(p));
        }
      case 'cliente':
        for (final c in _clienteRepo.listarTodos()) {
          _add(m, entity, c.id, SyncEntityCodec.clienteParaMap(c));
        }
      case 'vendedor':
        for (final v in _vendedorRepo.listarTodos()) {
          _add(m, entity, v.id, SyncEntityCodec.vendedorParaMap(v));
        }
      case 'funcionario':
        for (final f in _db.funcionarioBox.getAll()) {
          _add(m, entity, f.id, SyncEntityCodecExtras.funcionarioParaMap(f));
        }
      case 'lancamento_funcionario':
        for (final l in _db.lancamentoFuncionarioBox.getAll()) {
          l.funcionario.target;
          _add(
            m,
            entity,
            l.id,
            SyncEntityCodecExtras.lancamentoFuncionarioParaMap(l),
          );
        }
      case 'fechamento_rh_funcionario':
        for (final fe in _db.fechamentoRhFuncionarioBox.getAll()) {
          _add(
            m,
            entity,
            fe.id,
            SyncEntityCodecExtras.fechamentoRhParaMap(fe),
          );
        }
      case 'motorista':
        for (final mo in _db.motoristaBox.getAll()) {
          _add(m, entity, mo.id, SyncEntityCodecExtras.motoristaParaMap(mo));
        }
      case 'vinculo_fornecedor':
        for (final v in _db.vinculoFornecedorProdutoBox.getAll()) {
          v.fornecedor.target;
          v.produto.target;
          _add(m, entity, v.id, SyncEntityCodecExtras.vinculoParaMap(v));
        }
      case 'historico_entrada':
        for (final h in _db.historicoEntradaBox.getAll()) {
          h.produto.target;
          _add(
            m,
            entity,
            h.id,
            SyncEntityCodecExtras.historicoEntradaParaMap(h),
          );
        }
      case 'nfe_importada':
        for (final n in _db.nfeImportadaRegistroBox.getAll()) {
          _add(m, entity, n.id, SyncEntityCodecExtras.nfeImportadaParaMap(n));
        }
      case 'kit_orcamento':
        for (final k in _db.kitOrcamentoBox.getAll()) {
          k.itens.length;
          _add(m, entity, k.id, SyncEntityCodecExtras.kitParaMap(k));
        }
      case 'promocao':
        for (final pr in _db.promocaoBox.getAll()) {
          pr.itens.length;
          _add(m, entity, pr.id, SyncEntityCodecExtras.promocaoParaMap(pr));
        }
      case 'venda':
        for (final vend in _vendaRepo.listarTodas()) {
          _add(m, entity, vend.id, SyncEntityCodec.vendaParaMap(vend));
        }
      case 'titulo_receber':
        for (final t in _db.tituloReceberBox.getAll()) {
          t.cliente.target;
          t.venda.target;
          _add(
            m,
            entity,
            t.id,
            SyncEntityCodecExtras.tituloReceberParaMap(t),
          );
        }
      case 'recebimento_fiado':
        for (final r in _db.recebimentoFiadoBox.getAll()) {
          r.cliente.target;
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecExtras.recebimentoFiadoParaMap(r),
          );
        }
      case 'historico_entrega':
        for (final h in _db.historicoEntregaBox.getAll()) {
          h.venda.target;
          _add(
            m,
            entity,
            h.id,
            SyncEntityCodecExtras.historicoEntregaParaMap(h),
          );
        }
      case 'conferencia_carga_romaneio':
        for (final c in _db.conferenciaCargaRomaneioBox.getAll()) {
          _add(
            m,
            entity,
            c.id,
            SyncEntityCodecExtras.conferenciaCargaRomaneioParaMap(c),
          );
        }
      case 'registro_devolucao':
        for (final r in _db.registroDevolucaoBox.getAll()) {
          r.vendaOrigem.target;
          r.linhasEntrada.length;
          r.linhasSaidaTroca.length;
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecExtras.registroDevolucaoParaMap(r),
          );
        }
      case 'empresa_config':
        final cfg = await _configRepository.carregarEmpresaConfig();
        _add(
          m,
          entity,
          1,
          SyncEntityCodecExtras.empresaConfigParaMap(cfg),
        );
      case 'mensageria_templates':
        final templates = await MensageriaRepository().listarTemplates();
        _add(
          m,
          entity,
          1,
          SyncEntityCodecExtras.mensageriaTemplatesParaMap(templates),
        );
      case 'usuarios_sistema':
        final usuarios = await UsuarioRepository().listarTodos();
        _add(
          m,
          entity,
          1,
          SyncEntityCodecExtras.usuariosParaMap(usuarios),
        );
      case 'caixa_sessoes':
        final sessoes = await CaixaSessaoRepository().listarTodasSessoes();
        _add(
          m,
          entity,
          1,
          CaixaSessaoRepository.pacoteParaSync(sessoes),
        );
      case 'movimento_estoque':
        for (final mv in _db.movimentoEstoqueBox.getAll()) {
          mv.produto.target;
          _add(
            m,
            entity,
            mv.id,
            SyncEntityCodecOperacional.movimentoEstoqueParaMap(mv),
          );
        }
      case 'conta_pagar':
        for (final c in _db.contaPagarBox.getAll()) {
          c.fornecedor.target;
          _add(
            m,
            entity,
            c.id,
            SyncEntityCodecOperacional.contaPagarParaMap(c),
          );
        }
      case 'reajuste_preco':
        for (final r in _db.reajustePrecoBox.getAll()) {
          r.itens.length;
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecOperacional.reajustePrecoParaMap(r),
          );
        }
      case 'auditoria_evento':
        for (final e in _db.auditoriaEventoBox.getAll()) {
          _add(
            m,
            entity,
            e.id,
            SyncEntityCodecOperacional.auditoriaEventoParaMap(e),
          );
        }
      case 'item_lista_compra':
        for (final i in _db.itemListaCompraBox.getAll()) {
          _add(
            m,
            entity,
            i.id,
            SyncEntityCodecOperacional.itemListaCompraParaMap(i),
          );
        }
        break;
      case 'produto_sugestao_venda':
        for (final s in _db.produtoSugestaoVendaBox.getAll()) {
          _add(
            m,
            entity,
            s.id,
            SyncEntityCodecOperacional.produtoSugestaoVendaParaMap(s),
          );
        }
        break;
      case 'sugestao_venda_metrica':
        for (final e in _db.sugestaoVendaMetricaEventoBox.getAll()) {
          _add(
            m,
            entity,
            e.id,
            SyncEntityCodecOperacional.sugestaoVendaMetricaParaMap(e),
          );
        }
        break;
      case 'recado_loja':
        for (final r in _db.recadoLojaBox.getAll()) {
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecOperacional.recadoLojaParaMap(r),
          );
        }
    }
  }

  Future<void> _montarEntidadeId(
    List<Map<String, dynamic>> m,
    String entity,
    int localId,
  ) async {
    if (localId <= 0 && entity != 'empresa_config') return;
    switch (entity) {
      case 'fornecedor_nfe':
        final f = _db.fornecedorNfeBox.get(localId);
        if (f != null) {
          _add(m, entity, f.id, SyncEntityCodecExtras.fornecedorNfeParaMap(f));
        }
      case 'produto':
        final p = _db.produtoBox.get(localId);
        if (p != null) {
          _add(m, entity, p.id, SyncEntityCodec.produtoParaMap(p));
        }
      case 'cliente':
        final c = _clienteRepo.obterPorId(localId);
        if (c != null) {
          _add(m, entity, c.id, SyncEntityCodec.clienteParaMap(c));
        }
      case 'vendedor':
        final v = _vendedorRepo.obterPorId(localId);
        if (v != null) {
          _add(m, entity, v.id, SyncEntityCodec.vendedorParaMap(v));
        }
      case 'funcionario':
        final f = _db.funcionarioBox.get(localId);
        if (f != null) {
          _add(m, entity, f.id, SyncEntityCodecExtras.funcionarioParaMap(f));
        }
      case 'lancamento_funcionario':
        final l = _db.lancamentoFuncionarioBox.get(localId);
        if (l != null) {
          l.funcionario.target;
          _add(
            m,
            entity,
            l.id,
            SyncEntityCodecExtras.lancamentoFuncionarioParaMap(l),
          );
        }
      case 'fechamento_rh_funcionario':
        final fe = _db.fechamentoRhFuncionarioBox.get(localId);
        if (fe != null) {
          _add(
            m,
            entity,
            fe.id,
            SyncEntityCodecExtras.fechamentoRhParaMap(fe),
          );
        }
      case 'motorista':
        final mo = _db.motoristaBox.get(localId);
        if (mo != null) {
          _add(m, entity, mo.id, SyncEntityCodecExtras.motoristaParaMap(mo));
        }
      case 'vinculo_fornecedor':
        final v = _db.vinculoFornecedorProdutoBox.get(localId);
        if (v != null) {
          v.fornecedor.target;
          v.produto.target;
          _add(m, entity, v.id, SyncEntityCodecExtras.vinculoParaMap(v));
        }
      case 'historico_entrada':
        final h = _db.historicoEntradaBox.get(localId);
        if (h != null) {
          h.produto.target;
          _add(
            m,
            entity,
            h.id,
            SyncEntityCodecExtras.historicoEntradaParaMap(h),
          );
        }
      case 'nfe_importada':
        final n = _db.nfeImportadaRegistroBox.get(localId);
        if (n != null) {
          _add(m, entity, n.id, SyncEntityCodecExtras.nfeImportadaParaMap(n));
        }
      case 'kit_orcamento':
        final k = _db.kitOrcamentoBox.get(localId);
        if (k != null) {
          k.itens.length;
          _add(m, entity, k.id, SyncEntityCodecExtras.kitParaMap(k));
        }
      case 'promocao':
        final pr = _db.promocaoBox.get(localId);
        if (pr != null) {
          pr.itens.length;
          _add(m, entity, pr.id, SyncEntityCodecExtras.promocaoParaMap(pr));
        }
      case 'venda':
        final vend = _db.vendaBox.get(localId);
        if (vend != null) {
          _add(m, entity, vend.id, SyncEntityCodec.vendaParaMap(vend));
        }
      case 'titulo_receber':
        final t = _db.tituloReceberBox.get(localId);
        if (t != null) {
          t.cliente.target;
          t.venda.target;
          _add(
            m,
            entity,
            t.id,
            SyncEntityCodecExtras.tituloReceberParaMap(t),
          );
        }
      case 'recebimento_fiado':
        final r = _db.recebimentoFiadoBox.get(localId);
        if (r != null) {
          r.cliente.target;
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecExtras.recebimentoFiadoParaMap(r),
          );
        }
      case 'historico_entrega':
        final h = _db.historicoEntregaBox.get(localId);
        if (h != null) {
          h.venda.target;
          _add(
            m,
            entity,
            h.id,
            SyncEntityCodecExtras.historicoEntregaParaMap(h),
          );
        }
      case 'conferencia_carga_romaneio':
        final c = _db.conferenciaCargaRomaneioBox.get(localId);
        if (c != null) {
          _add(
            m,
            entity,
            c.id,
            SyncEntityCodecExtras.conferenciaCargaRomaneioParaMap(c),
          );
        }
      case 'registro_devolucao':
        final r = _db.registroDevolucaoBox.get(localId);
        if (r != null) {
          r.vendaOrigem.target;
          r.linhasEntrada.length;
          r.linhasSaidaTroca.length;
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecExtras.registroDevolucaoParaMap(r),
          );
        }
      case 'empresa_config':
        final cfg = await _configRepository.carregarEmpresaConfig();
        _add(
          m,
          entity,
          1,
          SyncEntityCodecExtras.empresaConfigParaMap(cfg),
        );
      case 'mensageria_templates':
        final templates = await MensageriaRepository().listarTemplates();
        _add(
          m,
          entity,
          1,
          SyncEntityCodecExtras.mensageriaTemplatesParaMap(templates),
        );
      case 'usuarios_sistema':
        final usuarios = await UsuarioRepository().listarTodos();
        _add(
          m,
          entity,
          1,
          SyncEntityCodecExtras.usuariosParaMap(usuarios),
        );
      case 'caixa_sessoes':
        final sessoes = await CaixaSessaoRepository().listarTodasSessoes();
        _add(
          m,
          entity,
          1,
          CaixaSessaoRepository.pacoteParaSync(sessoes),
        );
      case 'movimento_estoque':
        final mv = _db.movimentoEstoqueBox.get(localId);
        if (mv != null) {
          mv.produto.target;
          _add(
            m,
            entity,
            mv.id,
            SyncEntityCodecOperacional.movimentoEstoqueParaMap(mv),
          );
        }
      case 'conta_pagar':
        final cp = _db.contaPagarBox.get(localId);
        if (cp != null) {
          cp.fornecedor.target;
          _add(
            m,
            entity,
            cp.id,
            SyncEntityCodecOperacional.contaPagarParaMap(cp),
          );
        }
      case 'reajuste_preco':
        final r = _db.reajustePrecoBox.get(localId);
        if (r != null) {
          r.itens.length;
          _add(
            m,
            entity,
            r.id,
            SyncEntityCodecOperacional.reajustePrecoParaMap(r),
          );
        }
      case 'auditoria_evento':
        final ev = _db.auditoriaEventoBox.get(localId);
        if (ev != null) {
          _add(
            m,
            entity,
            ev.id,
            SyncEntityCodecOperacional.auditoriaEventoParaMap(ev),
          );
        }
      case 'item_lista_compra':
        final ic = _db.itemListaCompraBox.get(localId);
        if (ic != null) {
          _add(
            m,
            entity,
            ic.id,
            SyncEntityCodecOperacional.itemListaCompraParaMap(ic),
          );
        }
        break;
      case 'produto_sugestao_venda':
        final sv = _db.produtoSugestaoVendaBox.get(localId);
        if (sv != null) {
          _add(
            m,
            entity,
            sv.id,
            SyncEntityCodecOperacional.produtoSugestaoVendaParaMap(sv),
          );
        }
        break;
      case 'sugestao_venda_metrica':
        final me = _db.sugestaoVendaMetricaEventoBox.get(localId);
        if (me != null) {
          _add(
            m,
            entity,
            me.id,
            SyncEntityCodecOperacional.sugestaoVendaMetricaParaMap(me),
          );
        }
        break;
      case 'recado_loja':
        final recado = _db.recadoLojaBox.get(localId);
        if (recado != null) {
          _add(
            m,
            entity,
            recado.id,
            SyncEntityCodecOperacional.recadoLojaParaMap(recado),
          );
        }
    }
  }

  /// True se ha alteracao local pontual ainda nao enviada para este id.
  /// Nesse caso o pull nao deve sobrescrever (senao preco/orcamento do
  /// celular some antes do push).
  Future<bool> _temDirtyPontualPendente({
    required String entity,
    required int localId,
  }) async {
    if (localId <= 0 && entity != 'empresa_config') return false;
    final dirty = await SyncDirtyOutbox.listar();
    final idAlvo = entity == 'empresa_config' ? 1 : localId;
    return dirty.any(
      (d) =>
          d.entity == entity &&
          d.entityId == idAlvo &&
          !d.sincronizarTodas,
    );
  }

  Future<void> aplicarAlteracao(Map<String, dynamic> ch) async {
    final entity = ch['entity'] as String?;
    final op = ch['op'] as String?;
    if (entity == null || op == null) return;

    if (op == 'delete') {
      final id = (ch['entityId'] as num?)?.toInt() ?? 0;
      if (id <= 0) return;
      // Delete remoto: se o id esta dirty local, ainda assim aplica
      // (servidor e autoridade para remocao).
      _aplicarDelete(entity, id);
      return;
    }

    final payloadRaw = ch['payload'];
    if (payloadRaw is! Map) return;
    final payload = Map<String, dynamic>.from(payloadRaw);
    final localId = (payload['id'] as num?)?.toInt() ?? 0;

    // Preserva dirty local: push sobe a versao do celular depois.
    if (await _temDirtyPontualPendente(entity: entity, localId: localId)) {
      return;
    }

    switch (entity) {
      case 'produto':
        _aplicarProdutoSync(payload);
        break;
      case 'cliente':
        _aplicarClienteSync(payload);
        break;
      case 'vendedor':
        _aplicarVendedorSync(payload);
        break;
      case 'funcionario':
        _aplicarFuncionarioSync(payload);
        break;
      case 'lancamento_funcionario':
        _db.lancamentoFuncionarioBox.put(
          SyncEntityCodecExtras.lancamentoFuncionarioDeMap(payload),
        );
        break;
      case 'fechamento_rh_funcionario':
        _db.fechamentoRhFuncionarioBox.put(
          SyncEntityCodecExtras.fechamentoRhDeMap(payload),
        );
        break;
      case 'motorista':
        _aplicarMotoristaSync(payload);
        break;
      case 'fornecedor_nfe':
        _aplicarFornecedorNfe(payload);
        break;
      case 'vinculo_fornecedor':
        await _aplicarVinculo(payload);
        break;
      case 'historico_entrada':
        await _aplicarHistoricoEntrada(payload);
        break;
      case 'nfe_importada':
        _aplicarNfeImportada(payload);
        break;
      case 'kit_orcamento':
        await _aplicarKit(payload);
        break;
      case 'promocao':
        await _aplicarPromocao(payload);
        break;
      case 'venda':
        await _aplicarVendaPayload(payload);
        break;
      case 'titulo_receber':
        _db.tituloReceberBox.put(
          SyncEntityCodecExtras.tituloReceberDeMap(payload),
        );
        break;
      case 'recebimento_fiado':
        _db.recebimentoFiadoBox.put(
          SyncEntityCodecExtras.recebimentoFiadoDeMap(payload),
        );
        break;
      case 'historico_entrega':
        await _aplicarHistoricoEntrega(payload);
        break;
      case 'conferencia_carga_romaneio':
        await _aplicarConferenciaCargaRomaneio(payload);
        break;
      case 'registro_devolucao':
        await _aplicarRegistroDevolucao(payload);
        break;
      case 'empresa_config':
        await _aplicarEmpresaConfig(payload);
        break;
      case 'mensageria_templates':
        await _aplicarMensageriaTemplates(payload);
        break;
      case 'usuarios_sistema':
        await _aplicarUsuarios(payload);
        break;
      case 'caixa_sessoes':
        await CaixaSessaoRepository().aplicarPacoteRede(payload);
        break;
      case 'movimento_estoque':
        _db.movimentoEstoqueBox.put(
          SyncEntityCodecOperacional.movimentoEstoqueDeMap(payload),
        );
        break;
      case 'conta_pagar':
        await _aplicarContaPagar(payload);
        break;
      case 'reajuste_preco':
        await _aplicarReajustePreco(payload);
        break;
      case 'auditoria_evento':
        _db.auditoriaEventoBox.put(
          SyncEntityCodecOperacional.auditoriaEventoDeMap(payload),
        );
        break;
      case 'item_lista_compra':
        await _aplicarItemListaCompra(payload);
        break;
      case 'produto_sugestao_venda':
        _db.produtoSugestaoVendaBox.put(
          SyncEntityCodecOperacional.produtoSugestaoVendaDeMap(payload),
        );
        break;
      case 'sugestao_venda_metrica':
        _db.sugestaoVendaMetricaEventoBox.put(
          SyncEntityCodecOperacional.sugestaoVendaMetricaDeMap(payload),
        );
        break;
      case 'recado_loja':
        await _aplicarRecadoLoja(payload);
        break;
    }
  }

  void _aplicarProdutoSync(Map<String, dynamic> payload) {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    Produto? local = remoteId > 0 ? _db.produtoBox.get(remoteId) : null;

    // Evita duplicar o mesmo SKU quando o ID remoto ainda nao existe nesta maquina
    // (ex.: storm de sync criou IDs globais novos para o mesmo cimento).
    if (local == null) {
      final sku = (payload['codigoInterno'] ?? '').toString().trim();
      if (sku.isNotEmpty) {
        local = _produtoRepo.obterPorCodigoInterno(sku);
      }
    }
    if (local == null) {
      final ean = (payload['codigoBarras'] ?? '').toString().trim();
      if (ean.isNotEmpty) {
        local = _produtoRepo.buscarPorCodigoBarras(ean);
      }
    }

    final merge = ProdutoEstoqueSync.mergeProdutoRemoto(
      local: local,
      payload: payload,
    );

    // Mantem o ID local se o SKU ja existia — nao cria segundo cadastro.
    if (local != null && local.id > 0) {
      merge.produto.id = local.id;
    } else if (remoteId > 0) {
      merge.produto.id = remoteId;
    } else {
      merge.produto.id = 0;
    }

    _db.produtoBox.put(merge.produto);
    _produtoRepo.invalidarCacheBusca();
    if (merge.estoqueLocalPreservado && merge.produto.id > 0) {
      unawaited(
        SyncConflictLog.registrar(
          tipo: SyncConflictTipo.estoqueMerge,
          entity: 'produto',
          entityId: merge.produto.id,
          detalhe:
              'Estoque local (v${local?.estoqueVersao ?? 0}) preservado sobre versao remota.',
        ),
      );
    }
  }

  /// Une cliente por documento (CPF/CNPJ) ou codigo interno.
  void _aplicarClienteSync(Map<String, dynamic> payload) {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    Cliente? local = remoteId > 0 ? _db.clienteBox.get(remoteId) : null;

    if (local == null) {
      final doc = _somenteDigitos((payload['documento'] ?? '').toString());
      if (doc.length >= 11) {
        for (final c in _db.clienteBox.getAll()) {
          if (_somenteDigitos(c.documento) == doc) {
            local = c;
            break;
          }
        }
      }
    }
    if (local == null) {
      final codigo =
          (payload['codigoInterno'] ?? '').toString().trim().toLowerCase();
      if (codigo.isNotEmpty) {
        for (final c in _db.clienteBox.getAll()) {
          if (c.codigoInterno.trim().toLowerCase() == codigo) {
            local = c;
            break;
          }
        }
      }
    }

    final remoto = SyncEntityCodec.clienteDeMap(payload);
    if (local != null && local.id > 0) {
      remoto.id = local.id;
    } else if (remoteId > 0) {
      remoto.id = remoteId;
    } else {
      remoto.id = 0;
    }
    _db.clienteBox.put(remoto);
  }

  /// Une funcionario por codigo interno ou CPF.
  void _aplicarFuncionarioSync(Map<String, dynamic> payload) {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    Funcionario? local =
        remoteId > 0 ? _db.funcionarioBox.get(remoteId) : null;

    if (local == null) {
      final codigo =
          (payload['codigoInterno'] ?? '').toString().trim().toLowerCase();
      if (codigo.isNotEmpty) {
        for (final f in _db.funcionarioBox.getAll()) {
          if (f.codigoInterno.trim().toLowerCase() == codigo) {
            local = f;
            break;
          }
        }
      }
    }
    if (local == null) {
      final cpf = _somenteDigitos((payload['cpf'] ?? '').toString());
      if (cpf.length == 11) {
        for (final f in _db.funcionarioBox.getAll()) {
          if (_somenteDigitos(f.cpf) == cpf) {
            local = f;
            break;
          }
        }
      }
    }

    final remoto = SyncEntityCodecExtras.funcionarioDeMap(payload);
    if (local != null && local.id > 0) {
      remoto.id = local.id;
      // Preserva foto local se remoto veio sem path.
      if (remoto.fotoPath.trim().isEmpty && local.fotoPath.trim().isNotEmpty) {
        remoto.fotoPath = local.fotoPath;
      }
    } else if (remoteId > 0) {
      remoto.id = remoteId;
    } else {
      remoto.id = 0;
    }
    _db.funcionarioBox.put(remoto);
  }

  static String _somenteDigitos(String s) =>
      s.replaceAll(RegExp(r'\D'), '');

  /// Evita clonar o mesmo vendedor quando o ID global ainda nao existe localmente.
  void _aplicarVendedorSync(Map<String, dynamic> payload) {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    Vendedor? local = remoteId > 0 ? _db.vendedorBox.get(remoteId) : null;

    if (local == null) {
      final codigo =
          (payload['codigoInterno'] ?? '').toString().trim().toLowerCase();
      if (codigo.isNotEmpty) {
        for (final v in _db.vendedorBox.getAll()) {
          if (v.codigoInterno.trim().toLowerCase() == codigo) {
            local = v;
            break;
          }
        }
      }
    }
    if (local == null) {
      final nome =
          (payload['nomeCompleto'] ?? '').toString().trim().toLowerCase();
      if (nome.isNotEmpty) {
        for (final v in _db.vendedorBox.getAll()) {
          if (v.nomeCompleto.trim().toLowerCase() == nome) {
            local = v;
            break;
          }
        }
      }
    }

    final remoto = SyncEntityCodec.vendedorDeMap(payload);
    if (local != null && local.id > 0) {
      remoto.id = local.id;
      if (remoto.senhaPdv.trim().isEmpty && local.senhaPdv.trim().isNotEmpty) {
        remoto.senhaPdv = local.senhaPdv;
      }
    } else if (remoteId > 0) {
      remoto.id = remoteId;
    } else {
      remoto.id = 0;
    }
    _db.vendedorBox.put(remoto);
  }

  /// Evita clonar motorista pelo mesmo nome (sync sem remap gerava varias copias).
  void _aplicarMotoristaSync(Map<String, dynamic> payload) {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    Motorista? local = remoteId > 0 ? _db.motoristaBox.get(remoteId) : null;

    if (local == null) {
      final nome = (payload['nome'] ?? '').toString().trim().toLowerCase();
      if (nome.isNotEmpty) {
        for (final m in _db.motoristaBox.getAll()) {
          if (m.nome.trim().toLowerCase() == nome) {
            local = m;
            break;
          }
        }
      }
    }

    final remoto = SyncEntityCodecExtras.motoristaDeMap(payload);
    if (local != null && local.id > 0) {
      remoto.id = local.id;
      if (remoto.telefone.trim().isEmpty && local.telefone.trim().isNotEmpty) {
        remoto.telefone = local.telefone;
      }
    } else if (remoteId > 0) {
      remoto.id = remoteId;
    } else {
      remoto.id = 0;
    }
    _db.motoristaBox.put(remoto);
  }

  void _aplicarDelete(String entity, int id) {
    if (entity == 'venda' || entity == 'registro_devolucao') {
      _aplicarDeleteInterno(entity, id);
      if (entity == 'produto') {
        _produtoRepo.invalidarCacheBusca();
      }
      return;
    }
    _db.store.runInTransaction(TxMode.write, () {
      _aplicarDeleteInterno(entity, id);
    });
    if (entity == 'produto') {
      _produtoRepo.invalidarCacheBusca();
    }
  }

  void _aplicarDeleteInterno(String entity, int id) {
    switch (entity) {
      case 'produto':
        _db.produtoBox.remove(id);
        break;
      case 'cliente':
        _db.clienteBox.remove(id);
        break;
      case 'vendedor':
        _db.vendedorBox.remove(id);
        break;
      case 'funcionario':
        _db.funcionarioBox.remove(id);
        break;
      case 'lancamento_funcionario':
        _db.lancamentoFuncionarioBox.remove(id);
        break;
      case 'fechamento_rh_funcionario':
        _db.fechamentoRhFuncionarioBox.remove(id);
        break;
      case 'motorista':
        _db.motoristaBox.remove(id);
        break;
      case 'fornecedor_nfe':
        _db.fornecedorNfeBox.remove(id);
        break;
      case 'vinculo_fornecedor':
        _db.vinculoFornecedorProdutoBox.remove(id);
        break;
      case 'historico_entrada':
        _db.historicoEntradaBox.remove(id);
        break;
      case 'nfe_importada':
        _db.nfeImportadaRegistroBox.remove(id);
        break;
      case 'kit_orcamento':
        _removerItensKit(id);
        _db.kitOrcamentoBox.remove(id);
        break;
      case 'promocao':
        _removerItensPromocao(id);
        _db.promocaoBox.remove(id);
        break;
      case 'venda':
        _removerVendaEmCascata(id);
        break;
      case 'titulo_receber':
        _db.tituloReceberBox.remove(id);
        break;
      case 'recebimento_fiado':
        _db.recebimentoFiadoBox.remove(id);
        break;
      case 'historico_entrega':
        _db.historicoEntregaBox.remove(id);
        break;
      case 'conferencia_carga_romaneio':
        _db.conferenciaCargaRomaneioBox.remove(id);
        break;
      case 'registro_devolucao':
        _removerRegistroDevolucao(id);
        break;
      case 'movimento_estoque':
        _db.movimentoEstoqueBox.remove(id);
        break;
      case 'conta_pagar':
        _db.contaPagarBox.remove(id);
        break;
      case 'reajuste_preco':
        _removerReajustePreco(id);
        break;
      case 'auditoria_evento':
        _db.auditoriaEventoBox.remove(id);
        break;
      case 'item_lista_compra':
        _db.itemListaCompraBox.remove(id);
        break;
      case 'produto_sugestao_venda':
        _db.produtoSugestaoVendaBox.remove(id);
        break;
      case 'sugestao_venda_metrica':
        _db.sugestaoVendaMetricaEventoBox.remove(id);
        break;
      case 'recado_loja':
        _db.recadoLojaBox.remove(id);
        break;
    }
  }

  Future<void> _aplicarItemListaCompra(Map<String, dynamic> payload) async {
    final item = SyncEntityCodecOperacional.itemListaCompraDeMap(payload);
    final pid = (payload['produtoId'] as num?)?.toInt() ?? 0;
    if (pid > 0) {
      final p = _db.produtoBox.get(pid);
      if (p != null) item.produto.target = p;
    }
    _db.itemListaCompraBox.put(item);
  }

  Future<void> _aplicarRecadoLoja(Map<String, dynamic> payload) async {
    final incoming = SyncEntityCodecOperacional.recadoLojaDeMap(payload);
    final id = incoming.id;
    if (id > 0) {
      final local = _db.recadoLojaBox.get(id);
      if (local != null) {
        incoming.leiturasJson = RecadoLojaHelper.mesclarLeiturasJson(
          local.leiturasJson,
          incoming.leiturasJson,
        );
      }
    }
    _db.recadoLojaBox.put(incoming);
  }

  Future<void> _aplicarContaPagar(Map<String, dynamic> payload) async {
    final c = SyncEntityCodecOperacional.contaPagarDeMap(payload);
    final fid = (payload['fornecedorId'] as num?)?.toInt() ?? 0;
    if (fid > 0) {
      final f = _db.fornecedorNfeBox.get(fid);
      if (f != null) c.fornecedor.target = f;
    }
    _db.contaPagarBox.put(c);
  }

  Future<void> _aplicarReajustePreco(Map<String, dynamic> payload) async {
    _db.store.runInTransaction(TxMode.write, () {
      final r = SyncEntityCodecOperacional.reajustePrecoDeMap(payload);
      final rid = r.id;
      if (rid > 0) {
        final existente = _db.reajustePrecoBox.get(rid);
        if (existente != null) {
          for (final i in existente.itens.toList()) {
            _db.reajustePrecoItemBox.remove(i.id);
          }
        }
      }
      final novoId = _db.reajustePrecoBox.put(r);
      final rawItens = payload['itens'];
      if (rawItens is List) {
        for (final raw in rawItens) {
          if (raw is! Map) continue;
          final item = SyncEntityCodecOperacional.reajustePrecoItemDeMap(
            raw.cast<String, dynamic>(),
          );
          item.reajuste.targetId = novoId;
          _db.reajustePrecoItemBox.put(item);
        }
      }
    });
  }

  void _removerReajustePreco(int id) {
    _db.store.runInTransaction(TxMode.write, () {
      final r = _db.reajustePrecoBox.get(id);
      if (r != null) {
        for (final i in r.itens.toList()) {
          _db.reajustePrecoItemBox.remove(i.id);
        }
      }
      _db.reajustePrecoBox.remove(id);
    });
  }

  Future<void> _aplicarVinculo(Map<String, dynamic> payload) async {
    final v = SyncEntityCodecExtras.vinculoDeMap(payload);
    var fid = (payload['fornecedorId'] as num?)?.toInt() ?? 0;
    fid = _fornecedorNfeIdAlias[fid] ?? fid;
    final pid = (payload['produtoId'] as num?)?.toInt() ?? 0;
    if (fid > 0) {
      final f = _db.fornecedorNfeBox.get(fid);
      if (f != null) v.fornecedor.target = f;
    }
    if (pid > 0) {
      final p = _db.produtoBox.get(pid);
      if (p != null) v.produto.target = p;
    }
    _db.vinculoFornecedorProdutoBox.put(v);
  }

  void _aplicarFornecedorNfe(Map<String, dynamic> payload) {
    final incoming = SyncEntityCodecExtras.fornecedorNfeDeMap(payload);
    final cnpj = incoming.cnpj.replaceAll(RegExp(r'\D'), '');
    if (cnpj.isEmpty) return;
    incoming.cnpj = cnpj;

    final existente = _buscarFornecedorNfePorCnpj(cnpj);
    final decisao = FornecedorNfeSyncMerge.decidir(
      incomingId: incoming.id,
      idLocalPorCnpj: existente?.id,
    );

    if (decisao.aliasIncomingParaLocal && incoming.id > 0) {
      _fornecedorNfeIdAlias[incoming.id] = decisao.idManter;
    }

    if (existente != null) {
      if (incoming.razaoSocial.trim().isNotEmpty) {
        existente.razaoSocial = incoming.razaoSocial.trim();
      }
      if (incoming.nomeFantasia.trim().isNotEmpty) {
        existente.nomeFantasia = incoming.nomeFantasia.trim();
      }
      existente.cnpj = cnpj;
      _db.fornecedorNfeBox.put(existente);
      return;
    }

    incoming.id = decisao.idManter > 0 ? decisao.idManter : incoming.id;
    _db.fornecedorNfeBox.put(incoming);
  }

  FornecedorNfe? _buscarFornecedorNfePorCnpj(String cnpj) {
    final q = _db.fornecedorNfeBox
        .query(FornecedorNfe_.cnpj.equals(cnpj))
        .build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  void _aplicarNfeImportada(Map<String, dynamic> payload) {
    final incoming = SyncEntityCodecExtras.nfeImportadaDeMap(payload);
    final chave = incoming.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      // Sem chave valida, tenta put direto (raro).
      _db.nfeImportadaRegistroBox.put(incoming);
      return;
    }
    incoming.chaveAcesso = chave;

    final existente = _buscarNfeImportadaPorChave(chave);
    final decisao = NfeImportadaSyncMerge.decidir(
      incomingId: incoming.id,
      idLocalPorChave: existente?.id,
    );

    if (existente != null) {
      existente.numeroNota = incoming.numeroNota;
      existente.dataEmissao = incoming.dataEmissao;
      existente.nomeFornecedor = incoming.nomeFornecedor;
      existente.cnpjFornecedor = incoming.cnpjFornecedor;
      existente.dataHoraImportacao = incoming.dataHoraImportacao;
      existente.quantidadeItens = incoming.quantidadeItens;
      existente.chaveAcesso = chave;
      _db.nfeImportadaRegistroBox.put(existente);
      return;
    }

    incoming.id = decisao.idManter > 0 ? decisao.idManter : incoming.id;
    _db.nfeImportadaRegistroBox.put(incoming);
  }

  NfeImportadaRegistro? _buscarNfeImportadaPorChave(String chave) {
    final q = _db.nfeImportadaRegistroBox
        .query(NfeImportadaRegistro_.chaveAcesso.equals(chave))
        .build();
    try {
      final list = q.find();
      return list.isEmpty ? null : list.first;
    } finally {
      q.close();
    }
  }

  Future<void> _aplicarHistoricoEntrada(Map<String, dynamic> payload) async {
    final h = SyncEntityCodecExtras.historicoEntradaDeMap(payload);
    final pid = (payload['produtoId'] as num?)?.toInt() ?? 0;
    if (pid > 0) {
      final p = _db.produtoBox.get(pid);
      if (p != null) h.produto.target = p;
    }
    _db.historicoEntradaBox.put(h);
  }

  void _removerItensKit(int kitId) {
    final q = _db.kitOrcamentoItemBox
        .query(KitOrcamentoItem_.kit.equals(kitId))
        .build();
    try {
      for (final id in q.findIds()) {
        _db.kitOrcamentoItemBox.remove(id);
      }
    } finally {
      q.close();
    }
  }

  Future<void> _aplicarKit(Map<String, dynamic> payload) async {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    final nome = (payload['nome'] ?? '').toString().trim();
    KitOrcamento? local = remoteId > 0 ? _db.kitOrcamentoBox.get(remoteId) : null;
    if (local == null && nome.isNotEmpty) {
      final nomeKey = nome.toLowerCase();
      for (final k in _db.kitOrcamentoBox.getAll()) {
        if (k.nome.trim().toLowerCase() == nomeKey) {
          local = k;
          break;
        }
      }
    }

    final kit = KitOrcamento(
      id: local?.id ?? (remoteId > 0 ? remoteId : 0),
      nome: nome,
      descricao: (payload['descricao'] ?? '').toString(),
      ativo: payload['ativo'] != false,
      criadoEm: DateTime.tryParse((payload['criadoEm'] ?? '').toString())?.toUtc(),
    );
    _db.store.runInTransaction(TxMode.write, () {
      if (kit.id != 0) _removerItensKit(kit.id);
      final kitId = _db.kitOrcamentoBox.put(kit);
      kit.id = kitId;
      final itensRaw = payload['itens'];
      if (itensRaw is List) {
        var ordem = 0;
        for (final raw in itensRaw) {
          if (raw is! Map) continue;
          final im = Map<String, dynamic>.from(raw);
          final it = KitOrcamentoItem(
            id: 0,
            quantidade: (im['quantidade'] as num?)?.toInt() ?? 1,
            ordem: ordem++,
          );
          it.kit.targetId = kitId;
          final pid = (im['produtoId'] as num?)?.toInt() ?? 0;
          if (pid > 0) {
            final pr = _db.produtoBox.get(pid);
            if (pr != null) it.produto.target = pr;
          }
          _db.kitOrcamentoItemBox.put(it);
        }
      }
    });
  }

  void _removerItensPromocao(int promocaoId) {
    final q = _db.promocaoItemBox
        .query(PromocaoItem_.promocao.equals(promocaoId))
        .build();
    try {
      for (final id in q.findIds()) {
        _db.promocaoItemBox.remove(id);
      }
    } finally {
      q.close();
    }
  }

  void _removerComboItensPromocao(int promocaoId) {
    final q = _db.promocaoComboItemBox
        .query(PromocaoComboItem_.promocao.equals(promocaoId))
        .build();
    try {
      for (final id in q.findIds()) {
        _db.promocaoComboItemBox.remove(id);
      }
    } finally {
      q.close();
    }
  }

  Future<void> _aplicarPromocao(Map<String, dynamic> payload) async {
    final remoteId = (payload['id'] as num?)?.toInt() ?? 0;
    final nome = (payload['nome'] ?? '').toString().trim();
    Promocao? local = remoteId > 0 ? _db.promocaoBox.get(remoteId) : null;
    if (local == null && nome.isNotEmpty) {
      final nomeKey = nome.toLowerCase();
      for (final p in _db.promocaoBox.getAll()) {
        if (p.nome.trim().toLowerCase() == nomeKey) {
          local = p;
          break;
        }
      }
    }

    final promo = Promocao(
      id: local?.id ?? (remoteId > 0 ? remoteId : 0),
      nome: nome,
      descricao: (payload['descricao'] ?? '').toString(),
      dataInicio: DateTime.tryParse((payload['dataInicio'] ?? '').toString())
              ?.toUtc() ??
          DateTime.now().toUtc(),
      dataFim: DateTime.tryParse((payload['dataFim'] ?? '').toString())?.toUtc() ??
          DateTime.now().toUtc(),
      ativa: payload['ativa'] != false,
      prioridade: (payload['prioridade'] as num?)?.toInt() ?? 0,
      tipoRegra: (payload['tipoRegra'] ?? 'preco_fixo').toString(),
      valorRegra: (payload['valorRegra'] as num?)?.toDouble() ?? 0,
      segmentoCliente: (payload['segmentoCliente'] ?? '').toString(),
      tipoCampanha: (payload['tipoCampanha'] ?? 'produto').toString(),
      margemMinimaPercentual:
          (payload['margemMinimaPercentual'] as num?)?.toDouble() ?? 0,
      limiteQuantidadeTotal:
          (payload['limiteQuantidadeTotal'] as num?)?.toInt() ?? 0,
      quantidadeVendidaPromo:
          (payload['quantidadeVendidaPromo'] as num?)?.toInt() ?? 0,
      leveQuantidade: (payload['leveQuantidade'] as num?)?.toInt() ?? 0,
      pagueQuantidade: (payload['pagueQuantidade'] as num?)?.toInt() ?? 0,
      precoCombo: (payload['precoCombo'] as num?)?.toDouble() ?? 0,
      criadoEm: DateTime.tryParse((payload['criadoEm'] ?? '').toString())?.toUtc(),
    );
    _db.store.runInTransaction(TxMode.write, () {
      if (promo.id != 0) {
        _removerItensPromocao(promo.id);
        _removerComboItensPromocao(promo.id);
      }
      final promoId = _db.promocaoBox.put(promo);
      promo.id = promoId;
      final itensRaw = payload['itens'];
      if (itensRaw is List) {
        var ordem = 0;
        for (final raw in itensRaw) {
          if (raw is! Map) continue;
          final im = Map<String, dynamic>.from(raw);
          final it = PromocaoItem(
            id: 0,
            produtoAlvoId: (im['produtoAlvoId'] as num?)?.toInt() ?? 0,
            categoria: (im['categoria'] ?? '').toString(),
            subcategoria: (im['subcategoria'] ?? '').toString(),
            quantidadeMinima: (im['quantidadeMinima'] as num?)?.toInt() ?? 1,
            quantidadeMaximaPromo:
                (im['quantidadeMaximaPromo'] as num?)?.toInt() ?? 0,
            ordem: ordem++,
          );
          it.promocao.targetId = promoId;
          _db.promocaoItemBox.put(it);
        }
      }
      final comboRaw = payload['comboItens'];
      if (comboRaw is List) {
        var ordem = 0;
        for (final raw in comboRaw) {
          if (raw is! Map) continue;
          final im = Map<String, dynamic>.from(raw);
          final c = PromocaoComboItem(
            id: 0,
            produtoAlvoId: (im['produtoAlvoId'] as num?)?.toInt() ?? 0,
            quantidade: (im['quantidade'] as num?)?.toInt() ?? 1,
            ordem: ordem++,
          );
          c.promocao.targetId = promoId;
          _db.promocaoComboItemBox.put(c);
        }
      }
    });
  }

  Future<void> _aplicarHistoricoEntrega(Map<String, dynamic> payload) async {
    final h = SyncEntityCodecExtras.historicoEntregaDeMap(payload);
    final vid = (payload['vendaId'] as num?)?.toInt() ?? 0;
    if (vid > 0) {
      final v = _db.vendaBox.get(vid);
      if (v != null) h.venda.target = v;
    }
    _db.historicoEntregaBox.put(h);
  }

  Future<void> _aplicarConferenciaCargaRomaneio(
    Map<String, dynamic> payload,
  ) async {
    ConferenciaCargaRepository(_db).aplicarConferenciaSync(payload);
  }

  void _removerRegistroDevolucao(int id) {
    _db.store.runInTransaction(TxMode.write, () {
      final r = _db.registroDevolucaoBox.get(id);
      if (r == null) return;
      for (final l in r.linhasEntrada.toList()) {
        if (l.id > 0) _db.linhaDevolucaoEntradaBox.remove(l.id);
      }
      for (final l in r.linhasSaidaTroca.toList()) {
        if (l.id > 0) _db.linhaTrocaSaidaBox.remove(l.id);
      }
      _db.registroDevolucaoBox.remove(id);
    });
  }

  Future<void> _aplicarRegistroDevolucao(Map<String, dynamic> payload) async {
    final reg = SyncEntityCodecExtras.registroDevolucaoDeMap(payload);
    _db.store.runInTransaction(TxMode.write, () {
      if (reg.id != 0) _removerRegistroDevolucao(reg.id);
      final vid = (payload['vendaOrigemId'] as num?)?.toInt() ?? 0;
      if (vid > 0) {
        final v = _db.vendaBox.get(vid);
        if (v != null) reg.vendaOrigem.target = v;
      }
      final regId = _db.registroDevolucaoBox.put(reg);
      reg.id = regId;

      final ent = payload['linhasEntrada'];
      if (ent is List) {
        for (final raw in ent) {
          if (raw is! Map) continue;
          final im = Map<String, dynamic>.from(raw);
          final l = SyncEntityCodecExtras.linhaDevolucaoDeMap(im);
          l.id = 0;
          l.registro.targetId = regId;
          final pid = (im['produtoId'] as num?)?.toInt() ?? 0;
          if (pid > 0) {
            final p = _db.produtoBox.get(pid);
            if (p != null) l.produto.target = p;
          }
          _db.linhaDevolucaoEntradaBox.put(l);
        }
      }
      final sai = payload['linhasSaidaTroca'];
      if (sai is List) {
        for (final raw in sai) {
          if (raw is! Map) continue;
          final im = Map<String, dynamic>.from(raw);
          final l = SyncEntityCodecExtras.linhaTrocaDeMap(im);
          l.id = 0;
          l.registro.targetId = regId;
          final pid = (im['produtoId'] as num?)?.toInt() ?? 0;
          if (pid > 0) {
            final p = _db.produtoBox.get(pid);
            if (p != null) l.produto.target = p;
          }
          _db.linhaTrocaSaidaBox.put(l);
        }
      }
    });
  }

  Future<void> _aplicarEmpresaConfig(Map<String, dynamic> payload) async {
    final atual = await _configRepository.carregarEmpresaConfig();
    final remoto = SyncEntityCodecExtras.empresaConfigDeMap(atual, payload);
    await _configRepository.salvarEmpresaConfig(remoto, propagarRede: false);
    // Token/impressora/rede local ja sao preservados no merge do codec.
    // Nao pede "Aceitar remoto" — so limpa dirty se houver.
    await SyncDirtyOutbox.remover(entity: 'empresa_config', entityId: 1);
  }

  Future<void> _aplicarMensageriaTemplates(Map<String, dynamic> payload) async {
    final lista = SyncEntityCodecExtras.mensageriaTemplatesDeMap(payload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTemplates,
      jsonEncode(lista.map((t) => t.toMap()).toList()),
    );
  }

  Future<void> _aplicarUsuarios(Map<String, dynamic> payload) async {
    final remotos = SyncEntityCodecExtras.usuariosDeMap(payload);
    final repo = UsuarioRepository();
    final locais = await repo.listarTodos();
    final mesclados = SyncEntityCodecExtras.mesclarUsuariosAposSync(
      locais: locais,
      remotos: remotos,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kUsuarios,
      jsonEncode(mesclados.map((u) => u.toMap()).toList()),
    );
  }

  Future<void> _aplicarVendaPayload(Map<String, dynamic> payload) async {
    _db.store.runInTransaction(TxMode.write, () {
      final venda = SyncEntityCodec.vendaCabecaDeMap(payload);
      final clienteId = (payload['clienteId'] as num?)?.toInt() ?? 0;
      final vendedorId = (payload['vendedorId'] as num?)?.toInt() ?? 0;
      final itensRaw = payload['itens'];
      final idsAntigos = <int>[];
      final existente = _db.vendaBox.get(venda.id);
      if (existente != null) {
        idsAntigos.addAll(existente.itens.map((i) => i.id));
      }
      if (idsAntigos.isNotEmpty) {
        _db.itemVendaBox.removeMany(idsAntigos);
      }
      if (clienteId > 0) {
        final c = _db.clienteBox.get(clienteId);
        if (c != null) venda.cliente.target = c;
      }
      if (vendedorId > 0) {
        final w = _db.vendedorBox.get(vendedorId);
        if (w != null) venda.vendedor.target = w;
      }
      _db.vendaBox.put(venda);
      final salva = _db.vendaBox.get(venda.id);
      if (salva == null) return;
      if (itensRaw is List) {
        for (final raw in itensRaw) {
          if (raw is! Map) continue;
          final im = Map<String, dynamic>.from(raw);
          final item = SyncEntityCodec.itemDeMap(im);
          item.venda.target = salva;
          final pid = (im['produtoId'] as num?)?.toInt() ?? 0;
          if (pid > 0) {
            final pr = _db.produtoBox.get(pid);
            if (pr != null) item.produto.target = pr;
          }
          _db.itemVendaBox.put(item);
        }
      }
    });
  }

  void _removerVendaEmCascata(int vendaId) {
    _db.store.runInTransaction(TxMode.write, () {
      final v = _db.vendaBox.get(vendaId);
      if (v == null) return;
      final idsItens = v.itens.map((i) => i.id).toList();
      if (idsItens.isNotEmpty) {
        _db.itemVendaBox.removeMany(idsItens);
      }
      v.itens.clear();
      _db.vendaBox.remove(vendaId);
    });
  }
}
