import 'package:objectbox/objectbox.dart';

import '../app_config_repository.dart';
import '../cliente_repository.dart';
import '../objectbox.dart';
import '../produto_repository.dart';
import '../venda_repository.dart';
import '../vendedor_repository.dart';
import '../../model/item_venda.dart';
import 'sync_api_client.dart';
import 'sync_cursor_storage.dart';
import 'sync_apply_order.dart';
import 'sync_full_sync.dart';
import 'sync_log.dart';
import 'sync_refresh_hub.dart';
import 'sync_write_trigger.dart';

class SyncService {
  SyncService({
    required ObjectBox objectBox,
    required AppConfigRepository configRepository,
    SyncCursorStorage? cursorStorage,
  })  : _db = objectBox,
        _configRepository = configRepository,
        _cursorStorage = cursorStorage ?? SyncCursorStorage() {
    _produtoRepo = ProdutoRepository(objectBox);
    _clienteRepo = ClienteRepository(objectBox);
    _vendedorRepo = VendedorRepository(objectBox);
    _vendaRepo = VendaRepository(
      objectBox,
      onAposEscrita: _produtoRepo.invalidarCacheBusca,
    );
  }

  final ObjectBox _db;
  final AppConfigRepository _configRepository;
  final SyncCursorStorage _cursorStorage;
  late final ProdutoRepository _produtoRepo;
  late final ClienteRepository _clienteRepo;
  late final VendedorRepository _vendedorRepo;
  late final VendaRepository _vendaRepo;

  late final SyncFullSync _fullSync = SyncFullSync(
    db: _db,
    configRepository: _configRepository,
    produtoRepo: _produtoRepo,
    clienteRepo: _clienteRepo,
    vendedorRepo: _vendedorRepo,
    vendaRepo: _vendaRepo,
  );

  /// Retorna mensagem de erro ou null se OK.
  Future<String?> executarSync() async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva || config.redeServidorUrl.trim().isEmpty) {
      return null;
    }

    final client = SyncApiClient(
      baseUrl: config.redeServidorUrl,
      syncToken: config.redeSyncToken,
    );
    if (!client.configurado) {
      return 'URL do servidor vazia.';
    }

    final deviceId = await _cursorStorage.obterOuCriarDeviceId();

    try {
      var since = await _cursorStorage.carregarUltimaRevision();

      final pullData = await client.pull(since: since, deviceId: deviceId);
      final changes = pullData['changes'];
      var houveAlteracaoRemota = false;
      if (changes is List && changes.isNotEmpty) {
        enterSyncApplySilencioso();
        try {
          final fila = List<dynamic>.from(changes);
          SyncApplyOrder.ordenarAlteracoes(fila);
          for (final raw in fila) {
            if (raw is Map<String, dynamic>) {
              await _fullSync.aplicarAlteracao(raw);
            } else if (raw is Map) {
              await _fullSync.aplicarAlteracao(Map<String, dynamic>.from(raw));
            }
          }
          houveAlteracaoRemota = true;
        } finally {
          leaveSyncApplySilencioso();
        }
      }

      final lastRev = (pullData['lastRevision'] as num?)?.toInt() ?? since;
      if (lastRev > since) {
        await _cursorStorage.salvarUltimaRevision(lastRev);
      }

      if (houveAlteracaoRemota) {
        _produtoRepo.invalidarCacheBusca();
        SyncRefreshHub.instance.notificarDadosAtualizados();
      }

      final mutations = await _fullSync.montarMutacoes();
      if (mutations.isEmpty) {
        SyncLog.registrarSucesso();
        return null;
      }

      final pushResp = await client.push(deviceId: deviceId, mutations: mutations);
      final mappings = pushResp['mappings'];
      if (mappings is List) {
        for (final m in mappings) {
          if (m is Map<String, dynamic>) {
            await _aplicarMapeamento(m);
          } else if (m is Map) {
            await _aplicarMapeamento(Map<String, dynamic>.from(m));
          }
        }
      }

      final numeroCorrections = pushResp['numeroCorrections'];
      if (numeroCorrections is List) {
        for (final raw in numeroCorrections) {
          if (raw is Map<String, dynamic>) {
            await _aplicarCorrecaoNumeroOrcamento(raw);
          } else if (raw is Map) {
            await _aplicarCorrecaoNumeroOrcamento(
              Map<String, dynamic>.from(raw),
            );
          }
        }
      }

      SyncLog.registrarSucesso();
      return null;
    } catch (e, st) {
      final msg =
          '${e.toString()}\n${st.toString().split('\n').take(3).join('\n')}';
      SyncLog.registrarFalha(msg);
      return msg;
    }
  }

  Future<void> _aplicarCorrecaoNumeroOrcamento(Map<String, dynamic> m) async {
    final globalId = (m['globalId'] as num?)?.toInt();
    final numero = (m['numeroOrcamento'] as num?)?.toInt();
    if (globalId == null || globalId <= 0 || numero == null || numero <= 0) {
      return;
    }
    _db.store.runInTransaction(TxMode.write, () {
      final v = _db.vendaBox.get(globalId);
      if (v == null) return;
      if (v.numeroOrcamento == numero) return;
      v.numeroOrcamento = numero;
      _db.vendaBox.put(v);
    });
  }

  Future<void> _aplicarMapeamento(Map<String, dynamic> m) async {
    final entity = m['entity'] as String?;
    final localId = (m['localId'] as num?)?.toInt();
    final globalId = (m['globalId'] as num?)?.toInt();
    if (entity == null || localId == null || globalId == null) return;
    if (localId == globalId) return;

    switch (entity) {
      case 'produto':
        _remapProduto(localId, globalId);
        break;
      case 'cliente':
        _remapCliente(localId, globalId);
        break;
      case 'vendedor':
        _remapVendedor(localId, globalId);
        break;
      case 'venda':
        _remapVenda(localId, globalId);
        break;
    }
  }

  void _remapProduto(int oldId, int newId) {
    final old = _db.produtoBox.get(oldId);
    if (old == null) return;

    for (final item in _db.itemVendaBox.getAll()) {
      if (item.produto.targetId == oldId) {
        final np = _db.produtoBox.get(newId);
        if (np != null) {
          item.produto.target = np;
          _db.itemVendaBox.put(item);
        }
      }
    }

    _db.produtoBox.remove(oldId);
    old.id = newId;
    _produtoRepo.salvar(old);
  }

  void _remapCliente(int oldId, int newId) {
    final old = _db.clienteBox.get(oldId);
    if (old == null) return;

    final afetadas = _db.vendaBox
        .getAll()
        .where((v) => v.cliente.targetId == oldId)
        .toList();

    _db.clienteBox.remove(oldId);
    old.id = newId;
    _clienteRepo.salvar(old);

    final novo = _db.clienteBox.get(newId);
    if (novo == null) return;
    for (final v in afetadas) {
      v.cliente.target = novo;
      _db.vendaBox.put(v);
    }
  }

  void _remapVendedor(int oldId, int newId) {
    final old = _db.vendedorBox.get(oldId);
    if (old == null) return;

    final afetadas = _db.vendaBox
        .getAll()
        .where((v) => v.vendedor.targetId == oldId)
        .toList();

    _db.vendedorBox.remove(oldId);
    old.id = newId;
    _vendedorRepo.salvar(old);

    final novo = _db.vendedorBox.get(newId);
    if (novo == null) return;
    for (final v in afetadas) {
      v.vendedor.target = novo;
      _db.vendaBox.put(v);
    }
  }

  void _remapVenda(int oldId, int newId) {
    final v = _db.vendaBox.get(oldId);
    if (v == null) return;

    final itens = <ItemVenda>[];
    for (final i in v.itens) {
      itens.add(i);
    }
    final ids = itens.map((i) => i.id).where((id) => id > 0).toList();
    if (ids.isNotEmpty) {
      _db.itemVendaBox.removeMany(ids);
    }
    v.itens.clear();
    _db.vendaBox.remove(oldId);

    v.id = newId;
    _db.vendaBox.put(v);
    final salva = _db.vendaBox.get(newId);
    if (salva == null) return;

    for (final item in itens) {
      item.id = 0;
      item.venda.target = salva;
      final pid = item.produto.targetId;
      if (pid > 0) {
        final pr = _db.produtoBox.get(pid);
        if (pr != null) item.produto.target = pr;
      }
      _db.itemVendaBox.put(item);
    }
  }
}
