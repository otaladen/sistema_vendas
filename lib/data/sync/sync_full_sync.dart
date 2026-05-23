import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../model/kit_orcamento.dart';
import '../../model/promocao.dart';
import '../../model/promocao_combo_item.dart';
import '../../model/promocao_item.dart';
import '../app_config_repository.dart';
import '../mensageria_repository.dart';
import '../objectbox.dart';
import '../usuario_repository.dart';
import '../cliente_repository.dart';
import '../../objectbox.g.dart';
import '../produto_repository.dart';
import '../venda_repository.dart';
import '../vendedor_repository.dart';
import 'sync_entity_codec.dart';
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

  void _add(
    List<Map<String, dynamic>> out,
    String entity,
    int localId,
    Map<String, dynamic> payload,
  ) {
    out.add({
      'entity': entity,
      'op': 'upsert',
      'localId': localId,
      'payload': payload,
    });
  }

  Future<List<Map<String, dynamic>>> montarMutacoes() async {
    final m = <Map<String, dynamic>>[];

    for (final f in _db.fornecedorNfeBox.getAll()) {
      _add(m, 'fornecedor_nfe', f.id, SyncEntityCodecExtras.fornecedorNfeParaMap(f));
    }
    for (final p in _produtoRepo.listarTodos()) {
      _add(m, 'produto', p.id, SyncEntityCodec.produtoParaMap(p));
    }
    for (final c in _clienteRepo.listarTodos()) {
      _add(m, 'cliente', c.id, SyncEntityCodec.clienteParaMap(c));
    }
    for (final v in _vendedorRepo.listarTodos()) {
      _add(m, 'vendedor', v.id, SyncEntityCodec.vendedorParaMap(v));
    }
    for (final f in _db.funcionarioBox.getAll()) {
      _add(m, 'funcionario', f.id, SyncEntityCodecExtras.funcionarioParaMap(f));
    }
    for (final l in _db.lancamentoFuncionarioBox.getAll()) {
      l.funcionario.target;
      _add(
        m,
        'lancamento_funcionario',
        l.id,
        SyncEntityCodecExtras.lancamentoFuncionarioParaMap(l),
      );
    }
    for (final mo in _db.motoristaBox.getAll()) {
      _add(m, 'motorista', mo.id, SyncEntityCodecExtras.motoristaParaMap(mo));
    }
    for (final v in _db.vinculoFornecedorProdutoBox.getAll()) {
      v.fornecedor.target;
      v.produto.target;
      _add(m, 'vinculo_fornecedor', v.id, SyncEntityCodecExtras.vinculoParaMap(v));
    }
    for (final h in _db.historicoEntradaBox.getAll()) {
      h.produto.target;
      _add(m, 'historico_entrada', h.id, SyncEntityCodecExtras.historicoEntradaParaMap(h));
    }
    for (final n in _db.nfeImportadaRegistroBox.getAll()) {
      _add(m, 'nfe_importada', n.id, SyncEntityCodecExtras.nfeImportadaParaMap(n));
    }
    for (final k in _db.kitOrcamentoBox.getAll()) {
      k.itens.length;
      _add(m, 'kit_orcamento', k.id, SyncEntityCodecExtras.kitParaMap(k));
    }
    for (final pr in _db.promocaoBox.getAll()) {
      pr.itens.length;
      _add(m, 'promocao', pr.id, SyncEntityCodecExtras.promocaoParaMap(pr));
    }
    for (final vend in _vendaRepo.listarTodas()) {
      _add(m, 'venda', vend.id, SyncEntityCodec.vendaParaMap(vend));
    }
    for (final t in _db.tituloReceberBox.getAll()) {
      t.cliente.target;
      t.venda.target;
      _add(m, 'titulo_receber', t.id, SyncEntityCodecExtras.tituloReceberParaMap(t));
    }
    for (final r in _db.recebimentoFiadoBox.getAll()) {
      r.cliente.target;
      _add(
        m,
        'recebimento_fiado',
        r.id,
        SyncEntityCodecExtras.recebimentoFiadoParaMap(r),
      );
    }
    for (final h in _db.historicoEntregaBox.getAll()) {
      h.venda.target;
      _add(m, 'historico_entrega', h.id, SyncEntityCodecExtras.historicoEntregaParaMap(h));
    }
    for (final c in _db.conferenciaCargaRomaneioBox.getAll()) {
      _add(
        m,
        'conferencia_carga_romaneio',
        c.id,
        SyncEntityCodecExtras.conferenciaCargaRomaneioParaMap(c),
      );
    }
    for (final r in _db.registroDevolucaoBox.getAll()) {
      r.vendaOrigem.target;
      r.linhasEntrada.length;
      r.linhasSaidaTroca.length;
      _add(m, 'registro_devolucao', r.id, SyncEntityCodecExtras.registroDevolucaoParaMap(r));
    }

    final cfg = await _configRepository.carregarEmpresaConfig();
    _add(m, 'empresa_config', 1, SyncEntityCodecExtras.empresaConfigParaMap(cfg));

    final templates = await MensageriaRepository().listarTemplates();
    _add(
      m,
      'mensageria_templates',
      1,
      SyncEntityCodecExtras.mensageriaTemplatesParaMap(templates),
    );

    final usuarios = await UsuarioRepository().listarTodos();
    _add(m, 'usuarios_sistema', 1, SyncEntityCodecExtras.usuariosParaMap(usuarios));

    return m;
  }

  Future<void> aplicarAlteracao(Map<String, dynamic> ch) async {
    final entity = ch['entity'] as String?;
    final op = ch['op'] as String?;
    if (entity == null || op == null) return;

    if (op == 'delete') {
      final id = (ch['entityId'] as num?)?.toInt() ?? 0;
      if (id <= 0) return;
      _aplicarDelete(entity, id);
      return;
    }

    final payloadRaw = ch['payload'];
    if (payloadRaw is! Map) return;
    final payload = Map<String, dynamic>.from(payloadRaw);

    switch (entity) {
      case 'produto':
        _db.produtoBox.put(SyncEntityCodec.produtoDeMap(payload));
        break;
      case 'cliente':
        _db.clienteBox.put(SyncEntityCodec.clienteDeMap(payload));
        break;
      case 'vendedor':
        _db.vendedorBox.put(SyncEntityCodec.vendedorDeMap(payload));
        break;
      case 'funcionario':
        _db.funcionarioBox.put(SyncEntityCodecExtras.funcionarioDeMap(payload));
        break;
      case 'lancamento_funcionario':
        _db.lancamentoFuncionarioBox.put(
          SyncEntityCodecExtras.lancamentoFuncionarioDeMap(payload),
        );
        break;
      case 'motorista':
        _db.motoristaBox.put(SyncEntityCodecExtras.motoristaDeMap(payload));
        break;
      case 'fornecedor_nfe':
        _db.fornecedorNfeBox.put(SyncEntityCodecExtras.fornecedorNfeDeMap(payload));
        break;
      case 'vinculo_fornecedor':
        await _aplicarVinculo(payload);
        break;
      case 'historico_entrada':
        await _aplicarHistoricoEntrada(payload);
        break;
      case 'nfe_importada':
        _db.nfeImportadaRegistroBox.put(
          SyncEntityCodecExtras.nfeImportadaDeMap(payload),
        );
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
    }
  }

  void _aplicarDelete(String entity, int id) {
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
    }
  }

  Future<void> _aplicarVinculo(Map<String, dynamic> payload) async {
    final v = SyncEntityCodecExtras.vinculoDeMap(payload);
    final fid = (payload['fornecedorId'] as num?)?.toInt() ?? 0;
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
    final kit = KitOrcamento(
      id: (payload['id'] as num?)?.toInt() ?? 0,
      nome: (payload['nome'] ?? '').toString(),
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
    final promo = Promocao(
      id: (payload['id'] as num?)?.toInt() ?? 0,
      nome: (payload['nome'] ?? '').toString(),
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
    final remoto = SyncEntityCodecExtras.conferenciaCargaRomaneioDeMap(payload);
    final escopo = remoto.escopoViagem.trim();
    final chave = remoto.chaveProduto.trim();
    if (escopo.isEmpty || chave.isEmpty) return;

    final q = _db.conferenciaCargaRomaneioBox
        .query(
          ConferenciaCargaRomaneio_.escopoViagem
              .equals(escopo)
              .and(ConferenciaCargaRomaneio_.chaveProduto.equals(chave)),
        )
        .build();
    try {
      final local = q.findFirst();
      if (local != null) {
        if (!remoto.atualizadoEm.isBefore(local.atualizadoEm)) {
          local.conferido = remoto.conferido;
          local.usuarioLogin = remoto.usuarioLogin;
          local.atualizadoEm = remoto.atualizadoEm;
        }
        _db.conferenciaCargaRomaneioBox.put(local);
      } else {
        _db.conferenciaCargaRomaneioBox.put(remoto);
      }
    } finally {
      q.close();
    }
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
    final novo = SyncEntityCodecExtras.empresaConfigDeMap(atual, payload);
    await _configRepository.salvarEmpresaConfig(novo, propagarRede: false);
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
    final lista = SyncEntityCodecExtras.usuariosDeMap(payload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kUsuarios,
      jsonEncode(lista.map((u) => u.toMap()).toList()),
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
