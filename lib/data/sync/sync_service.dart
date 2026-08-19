import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:objectbox/objectbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config_repository.dart';
import '../cliente_repository.dart';
import '../objectbox.dart';
import '../produto_repository.dart';
import '../usuario_repository.dart';
import '../venda_repository.dart';
import '../vendedor_repository.dart';
import '../../model/cliente.dart';
import '../../model/funcionario.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../../model/kit_orcamento.dart';
import '../../model/produto.dart';
import '../../model/promocao_combo_item.dart';
import '../../model/promocao_item.dart';
import '../../model/vendedor.dart';
import '../../services/produto_imagem_lan_service.dart';
import '../../services/lan_sync_server_manager.dart';
import 'sync_api_client.dart';
import 'sync_cursor_storage.dart';
import 'sync_apply_order.dart';
import 'sync_delete_outbox.dart';
import 'sync_dirty_outbox.dart';
import 'sync_full_sync.dart';
import 'sync_log.dart';
import 'sync_push_idempotency.dart';
import 'sync_priority.dart';
import 'sync_pull_catchup.dart';
import 'sync_primeira_carga.dart';
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
      onAposEscrita: _produtoRepo.atualizarCacheAposMovimentoEstoque,
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

  /// Ultimo push: localId da venda no aparelho -> globalId no servidor.
  /// O PDV usa apos [LanSyncScheduler.solicitarSyncPrioritario] porque o
  /// ObjectBox pode ter remapeado o id antes de reler o orcamento.
  static final Map<int, int> _vendaRemapLocalParaGlobal = {};

  /// Resolve a venda apos push (id local ou ja remapeado para global).
  static int? globalIdVendaAposPush(int localId) {
    if (localId <= 0) return null;
    return _vendaRemapLocalParaGlobal[localId];
  }

  static void _registrarRemapVenda(int localId, int globalId) {
    if (localId <= 0 || globalId <= 0) return;
    _vendaRemapLocalParaGlobal[localId] = globalId;
  }

  /// Carga inicial dedicada (legado; tela PrimeiraCargaPage removida): pull
  /// completo com progresso. Mantido para celular / testes; Windows nao usa.
  ///
  /// Retorna null se OK; mensagem de erro caso contrario.
  Future<String?> executarBootstrapInicial({
    void Function(SyncPrimeiraCargaProgresso progresso)? onProgresso,
  }) async {
    // Throttle UI: no maximo ~5 updates/s (setState em excesso tambem congela).
    DateTime? ultimoReport;
    SyncPrimeiraCargaProgresso? pendenteReport;
    void reportar(
      SyncPrimeiraCargaProgresso p, {
      bool forcar = false,
    }) {
      if (onProgresso == null) return;
      final agora = DateTime.now();
      if (!forcar &&
          ultimoReport != null &&
          agora.difference(ultimoReport!) < const Duration(milliseconds: 200)) {
        pendenteReport = p;
        return;
      }
      ultimoReport = agora;
      pendenteReport = null;
      onProgresso(p);
    }

    void flushReport() {
      final p = pendenteReport;
      if (p != null && onProgresso != null) {
        pendenteReport = null;
        ultimoReport = DateTime.now();
        onProgresso(p);
      }
    }

    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva) {
      return 'Ative a sincronizacao de rede nas configuracoes.';
    }
    if (config.redeServidorUrl.trim().isEmpty) {
      return 'Informe o endereco do PC servidor (ex.: http://192.168.0.10:8787).';
    }

    final client = SyncApiClient(
      baseUrl: config.redeServidorUrl,
      syncToken: config.redeSyncToken,
    );
    if (!client.configurado) {
      return 'URL do servidor vazia.';
    }

    reportar(
      const SyncPrimeiraCargaProgresso(
        percentual: 1,
        mensagem: 'Conectando ao servidor da loja...',
      ),
      forcar: true,
    );

    int? revisionRemota;
    try {
      final versao = await client.obterVersao();
      if (versao != null && versao.lastRevision > 0) {
        revisionRemota = versao.lastRevision;
      }
    } catch (_) {}

    final deviceId = await _cursorStorage.obterOuCriarDeviceId();
    final sinceInicial = await _cursorStorage.carregarUltimaRevision();
    var registrosAcumulados = 0;
    var paginaAtual = 0;
    var revisionAtual = sinceInicial;
    var produtosCache = _db.produtoBox.count();

    SyncPrimeiraCargaProgresso montar({
      required String mensagem,
      required bool hasMore,
      int? revision,
      double? percentualOverride,
      bool concluido = false,
      String? erro,
    }) {
      final rev = revision ?? revisionAtual;
      final pct = percentualOverride ??
          SyncPrimeiraCargaProgresso.calcularPercentual(
            revisionLocal: rev,
            revisionRemota: revisionRemota,
            hasMore: hasMore,
            pagina: paginaAtual,
            registrosAcumulados: registrosAcumulados,
          );
      return SyncPrimeiraCargaProgresso(
        pagina: paginaAtual,
        registrosPagina: 0,
        registrosAcumulados: registrosAcumulados,
        revisionLocal: rev,
        revisionRemota: revisionRemota,
        produtosLocais: produtosCache,
        percentual: concluido ? 100 : pct,
        mensagem: mensagem,
        concluido: concluido,
        erro: erro,
      );
    }

    reportar(
      montar(
        mensagem: 'Baixando banco de dados da loja...',
        hasMore: true,
        revision: sinceInicial,
      ),
      forcar: true,
    );

    try {
      // Lotes grandes + pruning no servidor (bootstrap=1): menos HTTP e menos puts.
      const limitBootstrap = 1000;
      await executarPullCatchup(
        sinceInicial: sinceInicial,
        maxPaginas: null,
        delayEntrePaginas: const Duration(milliseconds: 12),
        buscarPagina: (since) async {
          final pullData = await client.pull(
            since: since,
            deviceId: deviceId,
            limit: limitBootstrap,
            bootstrap: true,
          );
          final lr = (pullData['lastRevision'] as num?)?.toInt();
          final changes = pullData['changes'];
          return SyncPullPage(
            changes:
                changes is List ? List<dynamic>.from(changes) : const [],
            lastRevision: lr ?? since,
            hasMore: pullData['hasMore'] == true,
          );
        },
        aplicarAlteracoes: (changes) async {
          enterSyncApplySilencioso();
          try {
            _fullSync.prepararLotePull();
            final fila = List<dynamic>.from(changes);
            SyncApplyOrder.ordenarAlteracoes(fila);
            var i = 0;
            for (final raw in fila) {
              if (raw is Map<String, dynamic>) {
                await _fullSync.aplicarAlteracao(raw);
              } else if (raw is Map) {
                await _fullSync.aplicarAlteracao(
                  Map<String, dynamic>.from(raw),
                );
              }
              i++;
              // Yield periodico: lotes de 1000 precisam liberar a UI com menos frequencia.
              if (i % 12 == 0) {
                await Future<void>.delayed(const Duration(milliseconds: 2));
                reportar(
                  montar(
                    mensagem:
                        'Sincronizando... ${registrosAcumulados + i} registros',
                    hasMore: true,
                  ),
                );
              }
            }
            registrosAcumulados += fila.length;
          } finally {
            leaveSyncApplySilencioso();
          }
        },
        salvarRevision: (revision) async {
          await _cursorStorage.salvarUltimaRevision(revision);
          revisionAtual = revision;
        },
        onProgresso: (p) {
          paginaAtual = p.pagina;
          registrosAcumulados = p.registrosAcumulados;
          revisionAtual = p.revision;
          // Contagem de produtos so a cada 2 paginas (ObjectBox count e custo).
          if (p.pagina == 1 || p.pagina % 2 == 0 || !p.hasMore) {
            produtosCache = _db.produtoBox.count();
          }
          if (!p.hasMore && p.revision > 0) {
            revisionRemota = p.revision;
          }
          reportar(
            montar(
              mensagem: p.hasMore
                  ? 'Sincronizando banco de dados inicial da loja... '
                      'Mantenha o app aberto.'
                  : 'Finalizando carga inicial...',
              hasMore: p.hasMore,
              revision: p.revision,
            ),
            forcar: !p.hasMore,
          );
        },
      );

      flushReport();
      _produtoRepo.invalidarCacheBusca();
      SyncRefreshHub.instance.notificarDadosAtualizados();
      SyncLog.registrarSucesso();

      final produtos = _db.produtoBox.count();
      final rev = await _cursorStorage.carregarUltimaRevision();
      produtosCache = produtos;
      reportar(
        montar(
          mensagem: produtos > 0
              ? 'Carga concluida: $produtos produtos prontos.'
              : 'Servidor sem produtos no catalogo. Voce ja pode usar o app.',
          hasMore: false,
          revision: rev,
          percentualOverride: 100,
          concluido: true,
        ),
        forcar: true,
      );
      return null;
    } catch (e) {
      flushReport();
      final msg = 'Falha na carga inicial: $e';
      SyncLog.registrarFalha(msg);
      reportar(
        montar(
          mensagem: msg,
          hasMore: true,
          erro: msg,
        ),
        forcar: true,
      );
      return msg;
    }
  }

  /// Retorna mensagem de erro ou null se OK.
  ///
  /// [modo]:
  /// - [SyncModo.periodico]: checa `/sync/version`; pula pull se revision igual.
  /// - [SyncModo.prioritario]: empurra dirty primeiro; pull so se atrasado.
  /// - [SyncModo.completo]: pull + push sempre (manual / bootstrap / pull-to-refresh).
  Future<String?> executarSync({SyncModo modo = SyncModo.periodico}) async {
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva || config.redeServidorUrl.trim().isEmpty) {
      return null;
    }
    // PC servidor e a fonte dos dados: hub (8787) + API (8788). Nao deve
    // puxar/empurrar contra si mesmo (travava UI com bootstrap em banco vazio
    // ou changelog antigo do sync_server).
    if (config.redeModoServidor) {
      return null;
    }

    // Repara loop causado por remarcar todos os produtos com foto a cada sync.
    if (!_plataformaCelular) {
      await _repararStormSyncFotosSeNecessario();
    } else {
      // Celular: so limpa pending enorme, sem dedupe/varredura.
      await _repararStormSyncFotosCelularLeve();
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
      Future<bool> precisaPullPesado() async {
        if (modo == SyncModo.completo) return true;
        final local = await _cursorStorage.carregarUltimaRevision();
        final versao = await client.obterVersao();
        if (versao == null) {
          // Sem endpoint: periodico puxa (seguro); prioritario so empurra.
          return modo != SyncModo.prioritario;
        }
        return versao.lastRevision > local;
      }

      Future<void> executarPull() async {
        final sinceInicial = await _cursorStorage.carregarUltimaRevision();
        var houveAlteracaoRemota = false;
        // Celular novo / banco vazio: precisa puxar bastante de uma vez,
        // senao fica "online" com catalogo vazio por muitos minutos.
        final bancoVazio = _db.produtoBox.count() == 0;
        final bootstrapCatchup = sinceInicial == 0 || bancoVazio;
        final maxPaginasCelular = bootstrapCatchup
            ? 40
            : (modo == SyncModo.completo ? 8 : 3);
        // Desktop: NUNCA paginas ilimitadas — travava a UI no "Sync agora".
        final maxPaginasDesktop = bootstrapCatchup
            ? 24
            : (modo == SyncModo.completo ? 8 : 4);
        // Bootstrap com pruning no servidor: lotes grandes (menos round-trips).
        final limitCelular = bootstrapCatchup ? 1000 : 60;
        final limitDesktop = bootstrapCatchup ? 200 : 80;

        await executarPullCatchup(
          sinceInicial: sinceInicial,
          maxPaginas:
              _plataformaCelular ? maxPaginasCelular : maxPaginasDesktop,
          buscarPagina: (since) async {
            final pullData = await client.pull(
              since: since,
              deviceId: deviceId,
              limit: _plataformaCelular ? limitCelular : limitDesktop,
              bootstrap: bootstrapCatchup,
            );
            final changes = pullData['changes'];
            return SyncPullPage(
              changes: changes is List ? List<dynamic>.from(changes) : const [],
              lastRevision:
                  (pullData['lastRevision'] as num?)?.toInt() ?? since,
              hasMore: pullData['hasMore'] == true,
            );
          },
          aplicarAlteracoes: (changes) async {
            enterSyncApplySilencioso();
            try {
              _fullSync.prepararLotePull();
              final fila = List<dynamic>.from(changes);
              SyncApplyOrder.ordenarAlteracoes(fila);
              var i = 0;
              for (final raw in fila) {
                if (raw is Map<String, dynamic>) {
                  await _fullSync.aplicarAlteracao(raw);
                } else if (raw is Map) {
                  await _fullSync.aplicarAlteracao(
                    Map<String, dynamic>.from(raw),
                  );
                }
                i++;
                // Cede a UI com frequencia (PC e celular).
                if (_plataformaCelular) {
                  final ms = bootstrapCatchup ? 4 : 12;
                  await Future<void>.delayed(Duration(milliseconds: ms));
                } else if (i % 8 == 0) {
                  await Future<void>.delayed(const Duration(milliseconds: 1));
                }
              }
              houveAlteracaoRemota = true;
            } finally {
              leaveSyncApplySilencioso();
            }
          },
          salvarRevision: (revision) =>
              _cursorStorage.salvarUltimaRevision(revision),
        );

        if (houveAlteracaoRemota) {
          _produtoRepo.invalidarCacheBusca();
          // Sempre notifica apos bootstrap/banco vazio — senao o celular
          // fica com dados no ObjectBox mas telas em branco.
          if (!_plataformaCelular || bootstrapCatchup) {
            SyncRefreshHub.instance.notificarDadosAtualizados();
            if (!_plataformaCelular) {
              unawaited(_prefetchFotosProdutos());
            }
          }
        }

        // Ainda atrasado do servidor: marca para o scheduler continuar o catch-up.
        _precisaCatchupContinuo = false;
        if (_plataformaCelular && bootstrapCatchup) {
          try {
            final local = await _cursorStorage.carregarUltimaRevision();
            final versao = await client.obterVersao();
            if (versao != null && versao.lastRevision > local) {
              _precisaCatchupContinuo = true;
            }
          } catch (_) {}
        }
      }

      Future<String?> executarPush() async {
        final revisionAntes = await _cursorStorage.carregarUltimaRevision();
        final bootstrap =
            await SyncDirtyOutbox.precisaBootstrap() || revisionAntes == 0;

        // Celular: nao faz snapshot completo nem reenvia batch gigante (congela).
        if (_plataformaCelular) {
          final pendenteCel = await SyncPushIdempotency.carregarPendente();
          if (pendenteCel != null && pendenteCel.mutations.length > 120) {
            await SyncPushIdempotency.limparPendente();
          }
          if (bootstrap) {
            // Marca bootstrap ok, MAS nao limpa dirty — senao apaga orcamento
            // acabado de salvar no PDV antes do push (bug da loja).
            await SyncDirtyOutbox.marcarBootstrapConcluido();
          }
          // Nao faca early-return por dirty "vazio": batch pendente antigo
          // ainda precisa subir; montarMutacoes / merge tratam o resto.
        }

        final pendente = await SyncPushIdempotency.carregarPendente();
        late final List<Map<String, dynamic>> mutations;
        late String pushBatchId;

        if (pendente != null) {
          mutations = List<Map<String, dynamic>>.from(pendente.mutations);
          pushBatchId = pendente.batchId;
          // Mescla dirty novo (ex.: orcamento 342) que chegou enquanto o
          // batch antigo ainda estava pendente — senao ele nunca sobe.
          final frescas = await _fullSync.montarMutacoes(
            // Snapshot completo no PC tambem congela (mesmo padrao do celular).
            evitarSnapshotCompleto: true,
          );
          final chaves = <String>{};
          for (final m in mutations) {
            chaves.add(
              '${m['entity']}:${(m['localId'] as num?)?.toInt() ?? 0}',
            );
          }
          var mesclou = false;
          for (final f in frescas) {
            final k =
                '${f['entity']}:${(f['localId'] as num?)?.toInt() ?? 0}';
            if (chaves.add(k)) {
              mutations.add(f);
              mesclou = true;
            }
          }
          if (mesclou) {
            // Novo batchId: senao o servidor devolve cache do lote antigo e as
            // mutacoes mescladas nunca sobem.
            pushBatchId = SyncPushIdempotency.gerarBatchId(deviceId);
            await SyncPushIdempotency.salvarPendente(
              batchId: pushBatchId,
              mutations: mutations,
            );
          }
        } else {
          var montadas = await _fullSync.montarMutacoes(
            evitarSnapshotCompleto: true,
          );
          if (montadas.isEmpty) {
            // Mesmo sem mutacoes de dados, sobe fotos locais (PC servidor/caixa).
            unawaited(_enviarFotosProdutosLocais());
            SyncLog.registrarSucesso();
            return null;
          }
          // Evita gravar JSON enorme no SharedPreferences no celular.
          if (_plataformaCelular && montadas.length > 120) {
            montadas = montadas.sublist(0, 120);
          }
          mutations = montadas;
          pushBatchId = SyncPushIdempotency.gerarBatchId(deviceId);
          await SyncPushIdempotency.salvarPendente(
            batchId: pushBatchId,
            mutations: mutations,
          );
        }

        if (mutations.isEmpty) {
          await SyncPushIdempotency.limparPendente();
          SyncLog.registrarSucesso();
          return null;
        }

        final pushResp = await client.push(
          deviceId: deviceId,
          mutations: mutations,
          pushBatchId: pushBatchId,
        );
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

        var numeroCorrigido = false;
        final numeroCorrections = pushResp['numeroCorrections'];
        if (numeroCorrections is List) {
          for (final raw in numeroCorrections) {
            final Map<String, dynamic>? m;
            if (raw is Map<String, dynamic>) {
              m = raw;
            } else if (raw is Map) {
              m = Map<String, dynamic>.from(raw);
            } else {
              m = null;
            }
            if (m == null) continue;
            if (await _aplicarCorrecaoNumeroOrcamento(m)) {
              numeroCorrigido = true;
            }
          }
        }
        if (numeroCorrigido) {
          SyncRefreshHub.instance.notificarDadosAtualizados();
        }

        await SyncDeleteOutbox.limparEnviadas(mutations);
        await SyncDirtyOutbox.limparEnviadas(mutations);
        await SyncPushIdempotency.limparPendente();
        if (bootstrap && !_plataformaCelular) {
          await SyncDirtyOutbox.marcarBootstrapConcluido();
          await SyncDirtyOutbox.limparTudo();
        }

        SyncLog.registrarSucesso();
        unawaited(_enviarFotosProdutosLocais());
        return null;
      }

      if (modo == SyncModo.prioritario) {
        final erroPush = await executarPush();
        if (erroPush != null) return erroPush;
        if (await precisaPullPesado()) {
          await executarPull();
        }
        // Segundo push: cobre dirty que chegou apos o 1o ciclo, ou que so
        // passou a montar depois do pull avancar a revision (celular rev=0).
        final dirtyRestante = await SyncDirtyOutbox.listar();
        final deletesRestantes = await SyncDeleteOutbox.mutacoesParaPush();
        final temPontual =
            dirtyRestante.any((d) => !d.sincronizarTodas);
        if (temPontual || deletesRestantes.isNotEmpty) {
          return await executarPush();
        }
        return null;
      }

      // Periodico/completo: se ha dirty pontual e o banco ja tem dados,
      // empurra ANTES do pull — senao o pull remoto apaga preco/produto
      // local e o PC nunca recebe a alteracao do celular.
      final dirtyAntes = await SyncDirtyOutbox.listar();
      final temDirtyPontual = dirtyAntes.any((d) => !d.sincronizarTodas);
      final bancoAindaVazio = _db.produtoBox.count() == 0;
      final revisionLocal = await _cursorStorage.carregarUltimaRevision();
      final precisaHidratacao = revisionLocal == 0 || bancoAindaVazio;

      if (temDirtyPontual && !precisaHidratacao) {
        final erroPush = await executarPush();
        if (erroPush != null) return erroPush;
        if (await precisaPullPesado() || modo == SyncModo.completo) {
          await executarPull();
        }
        final dirtyRestante = await SyncDirtyOutbox.listar();
        if (dirtyRestante.any((d) => !d.sincronizarTodas)) {
          return await executarPush();
        }
        return null;
      }

      if (await precisaPullPesado() || modo == SyncModo.completo) {
        await executarPull();
      }

      final erro = await executarPush();
      if (erro != null) return erro;
      // Apos pull+push, se ainda houver dirty pontual (ex.: orcamento novo
      // durante o ciclo), empurra de novo no mesmo ciclo.
      final dirtyRestante = await SyncDirtyOutbox.listar();
      if (dirtyRestante.any((d) => !d.sincronizarTodas)) {
        return await executarPush();
      }
      return null;
    } catch (e, st) {
      final msg =
          '${e.toString()}\n${st.toString().split('\n').take(3).join('\n')}';
      SyncLog.registrarFalha(msg);
      return msg;
    }
  }

  static bool get _plataformaCelular =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _enviarFotosProdutosLocais({bool forcar = false}) async {
    try {
      // Upload de pasta e trabalho de PC servidor/caixa — no celular so baixa.
      if (_plataformaCelular) return;

      final agora = DateTime.now();
      final ultimo = _ultimoUploadFotosEm;
      if (!forcar &&
          ultimo != null &&
          agora.difference(ultimo) < const Duration(minutes: 2)) {
        return;
      }
      _ultimoUploadFotosEm = agora;

      // Normaliza caminhos locais sem remarcar dirty (nao gera loop de sync).
      _produtoRepo.normalizarFotoPathsParaSyncLan();

      final lan = ProdutoImagemLanService(
        imagesDirectoryPath: _produtoRepo.productImagesDirPath,
        configRepository: _configRepository,
      );
      // Envia bastante por ciclo para o celular achar a foto no servidor.
      await lan.enviarPastaLocalCompleta(limitePorCiclo: 80);
    } catch (_) {}
  }

  /// Usado por Configuracoes > Rede (PC) para garantir fotos no servidor.
  Future<({int enviados, int ignorados, int falhas, String? detalhe})>
      enviarFotosParaServidorAgora() async {
    if (_plataformaCelular) {
      return (
        enviados: 0,
        ignorados: 0,
        falhas: 0,
        detalhe: 'Envio de fotos so no PC.',
      );
    }
    _produtoRepo.normalizarFotoPathsParaSyncLan();
    final lan = ProdutoImagemLanService(
      imagesDirectoryPath: _produtoRepo.productImagesDirPath,
      configRepository: _configRepository,
    );
    ProdutoImagemLanService.limparCacheEnviosSessao();
    final fallback =
        await LanSyncServerManager.caminhoPadraoProductImages();
    final r = await lan.publicarFotosNoServidor(
      limitePorCiclo: 300,
      pastaServidorFallback: fallback,
    );
    _ultimoUploadFotosEm = DateTime.now();
    return r;
  }

  static DateTime? _ultimoUploadFotosEm;
  static bool _reparoStormFeito = false;

  /// Celular novo ainda atrasado do changelog: o scheduler deve repetir o pull.
  static bool _precisaCatchupContinuo = false;
  static bool consumirPedidoCatchupContinuo() {
    if (!_precisaCatchupContinuo) return false;
    _precisaCatchupContinuo = false;
    return true;
  }

  Future<void> _repararStormSyncFotosSeNecessario() async {
    if (_reparoStormFeito) return;
    _reparoStormFeito = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      const chave = 'fix_sync_storm_fotos_v5';
      if (prefs.getBool(chave) == true) return;
      // Limpa fila suja de produtos gerada pelo loop + batch pendente enorme.
      await SyncDirtyOutbox.removerVarios(entity: 'produto');
      await SyncPushIdempotency.limparPendente();
      await _produtoRepo.deduplicarProdutosMesmoSku(notificarRede: true);
      await prefs.setBool(chave, true);
    } catch (_) {}
  }

  Future<void> _repararStormSyncFotosCelularLeve() async {
    if (_reparoStormFeito) return;
    _reparoStormFeito = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      const chave = 'fix_sync_storm_fotos_v5';
      if (prefs.getBool(chave) == true) return;
      await SyncDirtyOutbox.removerVarios(entity: 'produto');
      await SyncPushIdempotency.limparPendente();
      await prefs.setBool(chave, true);
    } catch (_) {}
  }

  Future<void> _prefetchFotosProdutos() async {
    try {
      if (_plataformaCelular) return;
      _normalizarFotoPathsParaLan();
      final lan = ProdutoImagemLanService(
        imagesDirectoryPath: _produtoRepo.productImagesDirPath,
        configRepository: _configRepository,
      );
      final paths = _produtoRepo
          .listarTodos()
          .map((p) => p.fotoPath)
          .where((s) => s.trim().isNotEmpty);
      await lan.prefetchFotosFaltantes(paths, limitePorCiclo: 15);
    } catch (_) {}
  }

  /// Troca caminhos absolutos de outro PC pelo nome `shared_*.jpg`.
  void _normalizarFotoPathsParaLan() {
    try {
      _produtoRepo.normalizarFotoPathsParaSyncLan();
    } catch (_) {}
  }

  /// Aplica ACK do servidor com o `numeroOrcamento` oficial.
  /// Retorna true se gravou alteracao local (para notificar a UI).
  Future<bool> _aplicarCorrecaoNumeroOrcamento(Map<String, dynamic> m) async {
    final globalId = (m['globalId'] as num?)?.toInt();
    final localId = (m['localId'] as num?)?.toInt();
    final numero = (m['numeroOrcamento'] as num?)?.toInt();
    if (numero == null || numero <= 0) return false;
    if (localId != null &&
        localId > 0 &&
        globalId != null &&
        globalId > 0) {
      _registrarRemapVenda(localId, globalId);
    }
    var alterou = false;
    _db.store.runInTransaction(TxMode.write, () {
      Venda? v;
      // Apos mappings, a venda ja esta no globalId; localId pode ter sumido.
      if (globalId != null && globalId > 0) {
        v = _db.vendaBox.get(globalId);
      }
      if (v == null && localId != null && localId > 0) {
        v = _db.vendaBox.get(localId);
      }
      if (v == null && localId != null && localId > 0) {
        final gid = _vendaRemapLocalParaGlobal[localId];
        if (gid != null && gid > 0) {
          v = _db.vendaBox.get(gid);
        }
      }
      if (v == null) return;
      if (v.numeroOrcamento == numero) return;
      v.numeroOrcamento = numero;
      _db.vendaBox.put(v);
      alterou = true;
    });
    return alterou;
  }

  Future<void> _aplicarMapeamento(Map<String, dynamic> m) async {
    final entity = m['entity'] as String?;
    final localId = (m['localId'] as num?)?.toInt();
    final globalId = (m['globalId'] as num?)?.toInt();
    if (entity == null || localId == null || globalId == null) return;
    if (localId == globalId) return;

    var produtoAfetado = false;
    var vendedorRemap = false;
    _db.store.runInTransaction(TxMode.write, () {
      switch (entity) {
        case 'produto':
          produtoAfetado = _remapProduto(localId, globalId);
          break;
        case 'cliente':
          _remapCliente(localId, globalId);
          break;
        case 'vendedor':
          _remapVendedor(localId, globalId);
          vendedorRemap = true;
          break;
        case 'motorista':
          _remapMotorista(localId, globalId);
          break;
        case 'funcionario':
          _remapFuncionario(localId, globalId);
          break;
        case 'kit_orcamento':
          _remapKitOrcamento(localId, globalId);
          break;
        case 'promocao':
          _remapPromocao(localId, globalId);
          break;
        case 'fornecedor_nfe':
          _remapFornecedorNfe(localId, globalId);
          break;
        case 'venda':
          _registrarRemapVenda(localId, globalId);
          _remapVenda(localId, globalId);
          break;
      }
    });
    if (produtoAfetado) {
      _produtoRepo.invalidarCacheBusca();
    }
    if (vendedorRemap) {
      await _remapUsuarioVendedorId(localId, globalId);
    }
  }

  bool _remapProduto(int oldId, int newId) {
    final old = _db.produtoBox.get(oldId);
    if (old == null || oldId == newId) return false;

    final destino = _db.produtoBox.get(newId);
    if (destino != null) {
      // Destino ja existe (pull criou o global): so move vinculos e remove o local.
      _reatribuirProdutoEmItens(oldId, destino);
      _db.produtoBox.remove(oldId);
      return true;
    }

    _db.produtoBox.remove(oldId);
    old.id = newId;
    _db.produtoBox.put(old);
    final novo = _db.produtoBox.get(newId);
    if (novo != null) {
      _reatribuirProdutoEmItens(oldId, novo);
    }
    return true;
  }

  void _reatribuirProdutoEmItens(int oldId, Produto destino) {
    for (final item in _db.itemVendaBox.getAll()) {
      if (item.produto.targetId == oldId) {
        item.produto.target = destino;
        _db.itemVendaBox.put(item);
      }
    }
    for (final h in _db.historicoEntradaBox.getAll()) {
      if (h.produto.targetId == oldId) {
        h.produto.target = destino;
        _db.historicoEntradaBox.put(h);
      }
    }
    for (final mv in _db.movimentoEstoqueBox.getAll()) {
      if (mv.produto.targetId == oldId) {
        mv.produto.target = destino;
        _db.movimentoEstoqueBox.put(mv);
      }
    }
  }

  void _remapCliente(int oldId, int newId) {
    final old = _db.clienteBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.clienteBox.get(newId);
    if (destino != null) {
      _reatribuirClienteRefs(oldId, destino);
      _db.clienteBox.remove(oldId);
      return;
    }

    _db.clienteBox.remove(oldId);
    old.id = newId;
    _db.clienteBox.put(old);

    final novo = _db.clienteBox.get(newId);
    if (novo == null) return;
    _reatribuirClienteRefs(oldId, novo);
  }

  void _reatribuirClienteRefs(int oldId, Cliente destino) {
    for (final v in _db.vendaBox.getAll()) {
      if (v.cliente.targetId == oldId) {
        v.cliente.target = destino;
        _db.vendaBox.put(v);
      }
    }
    for (final t in _db.tituloReceberBox.getAll()) {
      if (t.cliente.targetId == oldId) {
        t.cliente.target = destino;
        _db.tituloReceberBox.put(t);
      }
    }
  }

  void _remapVendedor(int oldId, int newId) {
    final old = _db.vendedorBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.vendedorBox.get(newId);
    if (destino != null) {
      _reatribuirVendedorRefs(oldId, destino);
      _db.vendedorBox.remove(oldId);
      return;
    }

    _db.vendedorBox.remove(oldId);
    old.id = newId;
    _db.vendedorBox.put(old);

    final novo = _db.vendedorBox.get(newId);
    if (novo == null) return;
    _reatribuirVendedorRefs(oldId, novo);
  }

  void _reatribuirVendedorRefs(int oldId, Vendedor destino) {
    for (final v in _db.vendaBox.getAll()) {
      if (v.vendedor.targetId == oldId) {
        v.vendedor.target = destino;
        _db.vendaBox.put(v);
      }
    }
    for (final f in _db.funcionarioBox.getAll()) {
      if (f.vendedorId == oldId) {
        f.vendedorId = destino.id;
        _db.funcionarioBox.put(f);
      }
    }
    for (final c in _db.clienteBox.getAll()) {
      if (c.vendedorResponsavelId == oldId) {
        c.vendedorResponsavelId = destino.id;
        _db.clienteBox.put(c);
      }
    }
  }

  void _remapMotorista(int oldId, int newId) {
    final old = _db.motoristaBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.motoristaBox.get(newId);
    if (destino != null) {
      _reatribuirMotoristaRefs(oldId, destino.id);
      _db.motoristaBox.remove(oldId);
      return;
    }

    _db.motoristaBox.remove(oldId);
    old.id = newId;
    _db.motoristaBox.put(old);
    _reatribuirMotoristaRefs(oldId, newId);
  }

  void _reatribuirMotoristaRefs(int oldId, int newId) {
    for (final f in _db.funcionarioBox.getAll()) {
      if (f.motoristaId == oldId) {
        f.motoristaId = newId;
        _db.funcionarioBox.put(f);
      }
    }
  }

  void _remapFuncionario(int oldId, int newId) {
    final old = _db.funcionarioBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.funcionarioBox.get(newId);
    if (destino != null) {
      _reatribuirFuncionarioRefs(oldId, destino);
      _db.funcionarioBox.remove(oldId);
      return;
    }

    _db.funcionarioBox.remove(oldId);
    old.id = newId;
    _db.funcionarioBox.put(old);
    final novo = _db.funcionarioBox.get(newId);
    if (novo != null) {
      _reatribuirFuncionarioRefs(oldId, novo);
    }
  }

  void _reatribuirFuncionarioRefs(int oldId, Funcionario destino) {
    for (final l in _db.lancamentoFuncionarioBox.getAll()) {
      if (l.funcionario.targetId == oldId) {
        l.funcionario.target = destino;
        _db.lancamentoFuncionarioBox.put(l);
      }
    }
    for (final f in _db.fechamentoRhFuncionarioBox.getAll()) {
      if (f.funcionarioId == oldId) {
        f.funcionarioId = destino.id;
        _db.fechamentoRhFuncionarioBox.put(f);
      }
    }
  }

  void _remapKitOrcamento(int oldId, int newId) {
    final old = _db.kitOrcamentoBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.kitOrcamentoBox.get(newId);
    if (destino != null) {
      _moverItensKit(oldId, newId);
      _db.kitOrcamentoBox.remove(oldId);
      return;
    }

    final itens = <KitOrcamentoItem>[];
    for (final it in _db.kitOrcamentoItemBox.getAll()) {
      if (it.kit.targetId == oldId) itens.add(it);
    }
    _db.kitOrcamentoBox.remove(oldId);
    old.id = newId;
    _db.kitOrcamentoBox.put(old);
    for (final it in itens) {
      it.kit.targetId = newId;
      _db.kitOrcamentoItemBox.put(it);
    }
  }

  void _moverItensKit(int deKitId, int paraKitId) {
    for (final it in _db.kitOrcamentoItemBox.getAll()) {
      if (it.kit.targetId == deKitId) {
        it.kit.targetId = paraKitId;
        _db.kitOrcamentoItemBox.put(it);
      }
    }
  }

  void _remapPromocao(int oldId, int newId) {
    final old = _db.promocaoBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.promocaoBox.get(newId);
    if (destino != null) {
      _moverItensPromocao(oldId, newId);
      _db.promocaoBox.remove(oldId);
      return;
    }

    final itens = <PromocaoItem>[];
    final combos = <PromocaoComboItem>[];
    for (final it in _db.promocaoItemBox.getAll()) {
      if (it.promocao.targetId == oldId) itens.add(it);
    }
    for (final c in _db.promocaoComboItemBox.getAll()) {
      if (c.promocao.targetId == oldId) combos.add(c);
    }
    _db.promocaoBox.remove(oldId);
    old.id = newId;
    _db.promocaoBox.put(old);
    for (final it in itens) {
      it.promocao.targetId = newId;
      _db.promocaoItemBox.put(it);
    }
    for (final c in combos) {
      c.promocao.targetId = newId;
      _db.promocaoComboItemBox.put(c);
    }
  }

  void _moverItensPromocao(int deId, int paraId) {
    for (final it in _db.promocaoItemBox.getAll()) {
      if (it.promocao.targetId == deId) {
        it.promocao.targetId = paraId;
        _db.promocaoItemBox.put(it);
      }
    }
    for (final c in _db.promocaoComboItemBox.getAll()) {
      if (c.promocao.targetId == deId) {
        c.promocao.targetId = paraId;
        _db.promocaoComboItemBox.put(c);
      }
    }
  }

  void _remapFornecedorNfe(int oldId, int newId) {
    final old = _db.fornecedorNfeBox.get(oldId);
    if (old == null || oldId == newId) return;

    final destino = _db.fornecedorNfeBox.get(newId);
    if (destino != null) {
      _reatribuirFornecedorRefs(oldId, destino.id);
      _db.fornecedorNfeBox.remove(oldId);
      return;
    }

    _db.fornecedorNfeBox.remove(oldId);
    old.id = newId;
    _db.fornecedorNfeBox.put(old);
    _reatribuirFornecedorRefs(oldId, newId);
  }

  void _reatribuirFornecedorRefs(int oldId, int newId) {
    for (final v in _db.vinculoFornecedorProdutoBox.getAll()) {
      if (v.fornecedor.targetId == oldId) {
        final f = _db.fornecedorNfeBox.get(newId);
        if (f != null) {
          v.fornecedor.target = f;
          _db.vinculoFornecedorProdutoBox.put(v);
        }
      }
    }
    for (final c in _db.contaPagarBox.getAll()) {
      if (c.fornecedor.targetId == oldId) {
        final f = _db.fornecedorNfeBox.get(newId);
        if (f != null) {
          c.fornecedor.target = f;
          _db.contaPagarBox.put(c);
        }
      }
    }
  }

  Future<void> _remapUsuarioVendedorId(int oldId, int newId) async {
    try {
      final repo = UsuarioRepository();
      final todos = await repo.listarTodos();
      for (final u in todos) {
        if (u.vendedorId != oldId) continue;
        await repo.salvar(
          u.copyWith(vendedorId: newId),
          anterior: u,
          resumoExtra: 'Remap sync vendedorId $oldId -> $newId',
        );
      }
    } catch (_) {
      // Preferencias podem falhar sem derrubar o sync.
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
