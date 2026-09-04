import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/cliente_repository.dart';
import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../data/sync/caixa_local_refresh_hub.dart';
import '../data/sync/entrega_local_refresh_hub.dart';
import '../data/sync/estoque_local_refresh_hub.dart';
import '../data/sync/sync_auth.dart';
import '../data/sync/sync_presence_hub.dart';
import '../data/sync/sync_refresh_hub.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/catalogo_produto_revision.dart';
import 'lan_api/lan_api_deps.dart';
import 'lan_api/lan_api_json.dart';
import 'lan_api/routes/register_all_routes.dart';

/// API HTTP embutida no Flutter do PC Servidor (ObjectBox local).
///
/// Porta padrao 8788.
class LanApiServer {
  LanApiServer({
    required this.objectBox,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    this.syncToken = '',
    LanApiDeps? deps,
  }) : _depsOverride = deps;

  /// Construtor legado (bootstrap antigo / testes).
  factory LanApiServer.legado({
    required ProdutoRepository produtoRepository,
    required ClienteRepository clienteRepository,
    required VendaRepository vendaRepository,
    required VendedorRepository vendedorRepository,
    String syncToken = '',
  }) {
    return LanApiServer(
      objectBox: produtoRepository.objectBox,
      produtoRepository: produtoRepository,
      clienteRepository: clienteRepository,
      vendaRepository: vendaRepository,
      vendedorRepository: vendedorRepository,
      syncToken: syncToken,
    );
  }

  final ObjectBox objectBox;
  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final String syncToken;
  final LanApiDeps? _depsOverride;

  HttpServer? _server;
  final List<_WsClienteApi> _ws = [];

  bool get emExecucao => _server != null;
  int? get portaAtiva => _server?.port;

  /// Terminais leves com WebSocket `/api/stream` aberto.
  int get wsAtivos => _ws.length;

  /// Snapshot no mesmo formato do hub `/sync/presence` (rodape / config).
  Map<String, dynamic> presencaSnapshot() {
    final stations = <Map<String, dynamic>>[];
    for (var i = 0; i < _ws.length; i++) {
      final c = _ws[i];
      final lab = c.label.trim();
      stations.add({
        'stationId': c.stationId.isEmpty ? 'ws-$i' : c.stationId,
        'label': lab.isEmpty ? 'Terminal' : lab,
        'via': 'api',
      });
    }
    return {
      'ok': true,
      'activeCount': stations.length,
      'stations': stations,
      'fonte': 'lan_api',
    };
  }

  void _publicarPresenca() {
    final snap = presencaSnapshot();
    try {
      SyncPresenceHub.instance.aplicarMap(snap);
    } catch (_) {}
    _broadcastJson({'type': 'presence', ...snap});
    LanApiServerHub.instance.avisarMudanca();
  }

  Future<void> iniciar({int porta = 8788}) async {
    await parar();
    final router = Router();

    final deps = _depsOverride ??
        LanApiDeps.fromObjectBox(
          objectBox,
          syncToken: syncToken,
          notificar: notificarEntityChanged,
          notificarEvento: notificarEvento,
        );

    router.get('/api/health', (Request req) {
      return lanApiJson({
        'ok': true,
        'service': 'sistema_vendas_api',
        'authLogin': true,
      });
    });

    router.get('/api/presence', (Request req) {
      return lanApiJson(presencaSnapshot());
    });

    router.get('/api/meta', (Request req) {
      return lanApiJson({
        'ok': true,
        'produtos': objectBox.produtoBox.count(),
        'clientes': objectBox.clienteBox.count(),
        'vendas': objectBox.vendaBox.count(),
        'titulosAbertos': objectBox.tituloReceberBox.count(),
        'contasPagar': objectBox.contaPagarBox.count(),
        'porta': porta,
        'terminaisWs': wsAtivos,
        'authLogin': true,
        'faseApi': 'p0_p1_p2_p3',
        'emitNfce': true,
        'emitNfe': true,
        'fechamentoFiscal': true,
        'capacidades': {
          'vendas': true,
          'entregas': true,
          'financeiro': true,
          'estoque': true,
          'rh': true,
          'kits': true,
          'promocoes': true,
          'fiscal': true,
          'fiscalFechamento': true,
          'fiscalNfeSaida': true,
          'relatorios': true,
          'authLogin': true,
          'backupRemoto': true,
        },
      });
    });

    registerAllLanApiRoutes(router, deps);

    router.get(
      '/api/stream',
      webSocketHandler((WebSocketChannel channel, String? _) {
        final cliente = _WsClienteApi(channel);
        _ws.add(cliente);
        _publicarPresenca();
        channel.sink.add(jsonEncode({'type': 'hello', 'ok': true}));
        channel.stream.listen(
          (raw) => _tratarMensagemWs(cliente, raw),
          onDone: () {
            _ws.remove(cliente);
            _publicarPresenca();
          },
          onError: (_) {
            _ws.remove(cliente);
            _publicarPresenca();
          },
          cancelOnError: true,
        );
      }),
    );

    final handler = Pipeline()
        .addMiddleware(_catchErrors())
        .addMiddleware(_cors())
        .addMiddleware(_auth())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, porta);
    } on SocketException catch (e) {
      // Porta ocupada por processo antigo: tenta liberar e sobe de novo.
      debugPrint('LanApiServer: porta $porta ocupada ($e). Tentando liberar...');
      await _tentarLiberarPortaWindows(porta);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, porta);
    }
  }

  static Future<void> _tentarLiberarPortaWindows(int porta) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-NetTCPConnection -LocalPort $porta -State Listen '
              '-ErrorAction SilentlyContinue | '
              'Select-Object -ExpandProperty OwningProcess -Unique | '
              'ForEach-Object { if (\$_ -and \$_ -ne $pid) { '
              'Stop-Process -Id \$_ -Force -ErrorAction SilentlyContinue } }',
        ],
        runInShell: true,
      );
    } catch (e) {
      debugPrint('LanApiServer: liberar porta $porta: $e');
    }
  }

  Future<void> parar() async {
    for (final c in List<_WsClienteApi>.from(_ws)) {
      try {
        await c.channel.sink.close();
      } catch (_) {}
    }
    _ws.clear();
    _publicarPresenca();
    await _server?.close(force: true);
    _server = null;
  }

  void _tratarMensagemWs(_WsClienteApi cliente, Object? raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final map = jsonDecode(text);
      if (map is! Map) return;
      final type = map['type']?.toString();
      if (type != 'register' && type != 'heartbeat') return;
      final sid = (map['stationId'] ?? '').toString().trim();
      final lab = (map['label'] ?? '').toString().trim();
      var mudou = false;
      if (sid.isNotEmpty && sid != cliente.stationId) {
        cliente.stationId = sid;
        mudou = true;
      }
      if (lab.isNotEmpty && lab != cliente.label) {
        cliente.label = lab;
        mudou = true;
      }
      if (mudou) _publicarPresenca();
    } catch (_) {}
  }

  void notificarEntityChanged(String entity, {List<int>? ids}) {
    if (entity.trim() == 'produto') {
      CatalogoProdutoRevision.bump();
    }
    final payload = <String, dynamic>{
      'type': 'entityChanged',
      'entity': entity,
      'ts': DateTime.now().toUtc().toIso8601String(),
      if (entity.trim() == 'produto')
        'revision': CatalogoProdutoRevision.revisao,
    };
    if (ids != null && ids.isNotEmpty) {
      payload['ids'] = ids.where((id) => id > 0).toList();
    }
    _broadcastJson(payload);
  }

  /// Evento WS tipado (ex.: `novo_recado_chat`).
  void notificarEvento(String type, Map<String, dynamic> payload) {
    final msg = <String, dynamic>{
      ...payload,
      'type': type,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    _broadcastJson(msg);
  }

  void _broadcastJson(Map<String, dynamic> payload) {
    final msg = jsonEncode(payload);
    for (final c in List<_WsClienteApi>.from(_ws)) {
      try {
        c.channel.sink.add(msg);
      } catch (_) {
        _ws.remove(c);
      }
    }
  }

  /// Captura excecoes nao tratadas nas rotas e devolve JSON 500 limpo
  /// (sem pilha interna no corpo da resposta).
  Middleware _catchErrors() {
    return (inner) {
      return (request) async {
        try {
          return await inner(request);
        } catch (e, st) {
          debugPrint('LanApiServer erro nao tratado [${request.method} '
              '${request.requestedUri.path}]: $e\n$st');
          return lanApiJson(
            {
              'ok': false,
              'error': 'Erro interno do servidor',
              'code': 'internal_error',
            },
            status: 500,
          );
        }
      };
    };
  }

  Middleware _cors() {
    return (inner) {
      return (request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final res = await inner(request);
        return res.change(headers: {...res.headers, ..._corsHeaders});
      };
    };
  }

  static const _corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type, ${SyncAuth.headerName}',
    'access-control-allow-methods': 'GET, POST, PUT, PATCH, OPTIONS',
  };

  Middleware _auth() {
    final esperado = syncToken.trim();
    return (inner) {
      return (request) async {
        final path = request.url.path;
        // Health/presence ficam abertos para diagnostico de rede (sem dados).
        if (path == 'api/health' ||
            path.endsWith('/api/health') ||
            path == 'api/presence' ||
            path.endsWith('/api/presence')) {
          return inner(request);
        }
        // Token de maquina obrigatorio em todas as demais rotas /api/* (HTTP + WS).
        if (esperado.isEmpty) {
          return Response(
            401,
            body: 'token de maquina nao configurado no servidor',
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          );
        }
        final header = (request.headers[SyncAuth.headerName] ?? '').trim();
        final query =
            (request.url.queryParameters[SyncAuth.queryParam] ?? '').trim();
        if (header.isEmpty && query.isEmpty) {
          return Response(
            401,
            body: 'token ausente',
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          );
        }
        if (header != esperado && query != esperado) {
          return Response(
            401,
            body: 'token invalido',
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          );
        }
        return inner(request);
      };
    };
  }
}

/// Singleton de processo para o shell do servidor iniciar/parar a API.
class LanApiServerHub extends ChangeNotifier {
  LanApiServerHub._();
  static final instance = LanApiServerHub._();

  LanApiServer? _server;
  final List<void Function(String type, Map<String, dynamic> payload)>
      _eventoListeners = [];

  LanApiServer? get server => _server;
  bool get ativo => _server?.emExecucao == true;
  int get terminaisWsAtivos => _server?.wsAtivos ?? 0;

  Map<String, dynamic>? get presencaSnapshot =>
      _server?.emExecucao == true ? _server!.presencaSnapshot() : null;

  /// UI local do PC1 (ex.: chat) escuta eventos sem precisar de WS loopback.
  void addEventoListener(
    void Function(String type, Map<String, dynamic> payload) listener,
  ) {
    if (!_eventoListeners.contains(listener)) {
      _eventoListeners.add(listener);
    }
  }

  void removeEventoListener(
    void Function(String type, Map<String, dynamic> payload) listener,
  ) {
    _eventoListeners.remove(listener);
  }

  /// Atualiza [SyncPresenceHub] com os terminais da API (rodape do PC1).
  void publicarPresencaNoHub() {
    final snap = presencaSnapshot;
    if (snap == null) return;
    SyncPresenceHub.instance.aplicarMap(snap);
  }

  /// Rodape / config: API subiu, parou ou mudou a lista de terminais WS.
  void avisarMudanca() {
    notifyListeners();
  }

  Future<void> iniciar(LanApiServer server, {required int porta}) async {
    if (_server?.emExecucao == true && _server?.portaAtiva == porta) {
      return;
    }
    await _server?.parar();
    _server = server;
    await server.iniciar(porta: porta);
    publicarPresencaNoHub();
    notifyListeners();
  }

  Future<void> parar() async {
    await _server?.parar();
    _server = null;
    notifyListeners();
  }

  void notificar(String entity, {List<int>? ids}) {
    _server?.notificarEntityChanged(entity, ids: ids);
    // PC1 UI: rotas da API chamam d.notificar (nao notificarAlteracaoParaRede).
    // Sem SyncRefreshHub o painel "A receber" / KPIs do Inicio ficam defasados
    // enquanto terminais/celular ja refrescam via WebSocket.
    final e = entity.trim();
    if (e.isEmpty) return;
    if (e == 'venda' ||
        e == 'titulo_receber' ||
        e == 'recebimento_fiado' ||
        e == 'conta_pagar' ||
        e == 'financeiro' ||
        e == 'recado_loja' ||
        e == 'lista_preco_externa' ||
        e == 'nfe_importada') {
      SyncRefreshHub.instance.notificarDadosAtualizados();
    }
    if (e == 'produto') {
      EstoqueLocalRefreshHub.instance.notificar(ids: ids);
    }
    if (e == 'caixa_sessoes' || e == 'caixa') {
      CaixaLocalRefreshHub.instance.notificar();
    }
    if (e == 'venda' ||
        e == 'entrega' ||
        e == 'conferencia_carga' ||
        e == 'conferencia_carga_romaneio') {
      EntregaLocalRefreshHub.instance.notificar();
    }
  }

  void notificarEvento(String type, Map<String, dynamic> payload) {
    _server?.notificarEvento(type, payload);
    for (final l in List.of(_eventoListeners)) {
      try {
        l(type, payload);
      } catch (_) {}
    }
  }
}

class _WsClienteApi {
  _WsClienteApi(this.channel);

  final WebSocketChannel channel;
  String stationId = '';
  String label = '';
}
