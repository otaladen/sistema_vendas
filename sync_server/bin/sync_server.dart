import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Servidor de sincronizacao na LAN.
///
/// Uso (no PC servidor):
///   cd sync_server
///   dart pub get
///   dart run bin/sync_server.dart [porta]
///
/// Variaveis de ambiente:
///   PORT — porta (padrao 8787)
///   SYNC_DB_PATH — caminho do arquivo SQLite
late Database _db;

/// Clientes WebSocket para aviso instantaneo de novas revisoes apos push.
final List<StreamSink<Object?>> _wsClientes = [];

/// Serializa pushes HTTP (dois celulares ao mesmo tempo nao estouram SQLITE_BUSY).
Future<void> _mutexPush = Future<void>.value();

/// Ultimo heartbeat por estacao ([stationId] = epoch ms UTC). TTL define "online".
const int _presenceTtlMs = 90000;

/// Se definido, exige header `x-sync-token` em `/sync/*`.
/// Query `token` ainda aceita por compatibilidade, mas clientes novos usam so header.
final String _syncToken = (Platform.environment['SYNC_TOKEN'] ?? '').trim();

/// Quando `1`, recusa sync se SYNC_TOKEN estiver vazio (producao na LAN).
final bool _syncRequireToken =
    (Platform.environment['SYNC_REQUIRE_TOKEN'] ?? '').trim() == '1';

bool _syncAutorizado(Request request) {
  final path = request.url.path;
  if (path == '/health') return true;
  if (!path.startsWith('/sync')) return true;
  if (_syncRequireToken && _syncToken.isEmpty) return false;
  if (_syncToken.isEmpty) return true;
  final header = (request.headers['x-sync-token'] ?? '').trim();
  final query = (request.url.queryParameters['token'] ?? '').trim();
  return header == _syncToken || query == _syncToken;
}

Handler _syncAuthMiddleware(Handler inner) {
  return (Request request) {
    if (_syncAutorizado(request)) return inner(request);
    return Response.forbidden(
      jsonEncode({'ok': false, 'error': 'sync_token_invalid'}),
      headers: {'content-type': 'application/json'},
    );
  };
}

final Map<String, int> _heartbeatLastMs = {};
final Map<String, String> _heartbeatLabels = {};

void _pruneHeartbeats() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final stale = _heartbeatLastMs.keys
      .where((k) => now - (_heartbeatLastMs[k] ?? 0) > _presenceTtlMs)
      .toList();
  for (final k in stale) {
    _heartbeatLastMs.remove(k);
    _heartbeatLabels.remove(k);
  }
}

/// Pasta do .exe (AOT) ou pasta atual ao rodar com `dart run`.
String _diretorioBaseInstalacao() {
  try {
    final resolved = Platform.resolvedExecutable;
    if (resolved.isNotEmpty) {
      return File(resolved).parent.path;
    }
  } catch (_) {}
  return Directory.current.path;
}

void main(List<String> args) async {
  final envPort = Platform.environment['PORT'];
  final argPort = args.isNotEmpty ? int.tryParse(args.first) : null;
  final port =
      int.tryParse(envPort ?? '') ?? argPort ?? 8787;

  final dbPath = Platform.environment['SYNC_DB_PATH'] ??
      '${_diretorioBaseInstalacao()}${Platform.pathSeparator}sistema_vendas_sync.db';

  _db = sqlite3.open(dbPath);
  // WAL + busy_timeout: 2+ celulares podem push/pull em paralelo sem 500 "database is locked".
  _db.execute('PRAGMA journal_mode=WAL;');
  _db.execute('PRAGMA busy_timeout=5000;');
  _db.execute('PRAGMA synchronous=NORMAL;');
  _initSchema(_db);

  final router = Router()
    ..get('/health', _health)
    ..get('/sync/presence', _presence)
    ..post('/sync/heartbeat', _heartbeat)
    ..get('/sync/meta', _meta)
    ..get('/sync/version', _version)
    ..get('/sync/pull', _pull)
    ..get(
      '/sync/stream',
      webSocketHandler(
        (WebSocketChannel channel, _) {
          final sink = channel.sink;
          _wsClientes.add(sink);
          // Snapshot imediato: cliente que acabou de conectar nao espera o proximo push.
          try {
            final rev = _maxRevisionAtual();
            sink.add(jsonEncode({'type': 'revision', 'revision': rev}));
            final snap = _presenceSnapshot();
            sink.add(jsonEncode({
              'type': 'presence',
              'activeCount': snap['activeCount'],
              'ttlSeconds': snap['ttlSeconds'],
              'stations': snap['stations'],
            }));
          } catch (_) {}
          channel.stream.listen(
            (_) {},
            onDone: () => _wsClientes.remove(sink),
            onError: (_) => _wsClientes.remove(sink),
          );
        },
        // Mantem 2+ celulares vivos apos blip de Wi-Fi (detecta half-open).
        pingInterval: const Duration(seconds: 25),
      ),
    )
    ..post('/sync/push', _push)
    ..get('/sync/pod/<fileName>', _podDownload)
    ..post('/sync/pod', _podUpload)
    ..get('/sync/product-image/<fileName>', _productImageDownload)
    ..post('/sync/product-image', _productImageUpload);

  final podDir = _diretorioPodEntrega();
  if (!Directory(podDir).existsSync()) {
    Directory(podDir).createSync(recursive: true);
  }
  final productImagesDir = _diretorioProductImages();
  if (!Directory(productImagesDir).existsSync()) {
    Directory(productImagesDir).createSync(recursive: true);
  }

  final handler = Pipeline()
      .addMiddleware(_syncAuthMiddleware)
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print(
    'sistema_vendas sync server | db=$dbPath | pod=$podDir | '
    'product_images=$productImagesDir | '
    'http://${server.address.address}:$port | ws=/sync/stream | '
    'auth=${_syncToken.isEmpty ? (_syncRequireToken ? "BLOQUEADA-defina_SYNC_TOKEN" : "desligada") : "token ativo"}',
  );
  if (_syncRequireToken && _syncToken.isEmpty) {
    print(
      'AVISO: SYNC_REQUIRE_TOKEN=1 mas SYNC_TOKEN vazio — rotas /sync/* recusadas.',
    );
  } else if (_syncToken.isEmpty) {
    print(
      'AVISO: servidor sem SYNC_TOKEN — qualquer PC na rede pode sincronizar. '
      'Defina SYNC_TOKEN e o mesmo valor em Configuracoes > Rede.',
    );
  }
}

String _diretorioPodEntrega() {
  final env = (Platform.environment['SYNC_POD_PATH'] ?? '').trim();
  if (env.isNotEmpty) return env;
  return '${_diretorioBaseInstalacao()}${Platform.pathSeparator}pod_entrega';
}

String _diretorioProductImages() {
  final env = (Platform.environment['SYNC_PRODUCT_IMAGES_PATH'] ?? '').trim();
  if (env.isNotEmpty) return env;
  return '${_diretorioBaseInstalacao()}${Platform.pathSeparator}product_images';
}

final RegExp _regexNomeArquivoPod = RegExp(r'^venda_\d+_\d{8}_\d{6}\.jpg$');
final RegExp _regexNomeArquivoProduto =
    RegExp(r'^(shared_[a-fA-F0-9]{40}\.jpg|[a-zA-Z0-9._\-]+\.(jpe?g|png|webp))$',
        caseSensitive: false);

bool _nomeArquivoPodValido(String raw) {
  final name = raw.trim();
  if (name.isEmpty || name.contains('..') || name.contains('/')) {
    return false;
  }
  return _regexNomeArquivoPod.hasMatch(name);
}

bool _nomeArquivoProdutoValido(String raw) {
  final name = Uri.decodeComponent(raw.trim());
  if (name.isEmpty ||
      name.contains('..') ||
      name.contains('/') ||
      name.contains(r'\')) {
    return false;
  }
  if (name.length > 180) return false;
  return _regexNomeArquivoProduto.hasMatch(name);
}

Future<Response> _podUpload(Request request) async {
  try {
    final body = await request.readAsString();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'json_invalido'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final fileName = (decoded['fileName'] ?? '').toString();
    if (!_nomeArquivoPodValido(fileName)) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'nome_arquivo_invalido'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final b64 = (decoded['contentBase64'] ?? '').toString();
    if (b64.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'contentBase64_vazio'}),
        headers: {'content-type': 'application/json'},
      );
    }
    List<int> bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'base64_invalido'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (bytes.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'arquivo_vazio'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (bytes.length > 6 * 1024 * 1024) {
      return Response(
        413,
        body: jsonEncode({'ok': false, 'error': 'arquivo_muito_grande'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final dir = Directory(_diretorioPodEntrega());
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}$fileName')
        .writeAsBytesSync(bytes);
    return Response.ok(
      jsonEncode({
        'ok': true,
        'path': 'pod_entrega/$fileName',
        'bytes': bytes.length,
      }),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'ok': false, 'error': '$e'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

Response _podDownload(Request request, String fileName) {
  if (!_nomeArquivoPodValido(fileName)) {
    return Response.notFound(
      jsonEncode({'ok': false, 'error': 'nao_encontrado'}),
      headers: {'content-type': 'application/json'},
    );
  }
  final path =
      '${_diretorioPodEntrega()}${Platform.pathSeparator}$fileName';
  final arquivo = File(path);
  if (!arquivo.existsSync()) {
    return Response.notFound(
      jsonEncode({'ok': false, 'error': 'nao_encontrado'}),
      headers: {'content-type': 'application/json'},
    );
  }
  final bytes = arquivo.readAsBytesSync();
  return Response.ok(
    bytes,
    headers: {
      'content-type': 'image/jpeg',
      'cache-control': 'private, max-age=3600',
    },
  );
}

Future<Response> _productImageUpload(Request request) async {
  try {
    final body = await request.readAsString();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'json_invalido'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final fileName = (decoded['fileName'] ?? '').toString();
    if (!_nomeArquivoProdutoValido(fileName)) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'nome_arquivo_invalido'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final b64 = (decoded['contentBase64'] ?? '').toString();
    if (b64.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'contentBase64_vazio'}),
        headers: {'content-type': 'application/json'},
      );
    }
    List<int> bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'base64_invalido'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (bytes.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'ok': false, 'error': 'arquivo_vazio'}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (bytes.length > 6 * 1024 * 1024) {
      return Response(
        413,
        body: jsonEncode({'ok': false, 'error': 'arquivo_muito_grande'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final dir = Directory(_diretorioProductImages());
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}$fileName')
        .writeAsBytesSync(bytes);
    return Response.ok(
      jsonEncode({
        'ok': true,
        'path': 'product_images/$fileName',
        'bytes': bytes.length,
      }),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'ok': false, 'error': '$e'}),
      headers: {'content-type': 'application/json'},
    );
  }
}

Response _productImageDownload(Request request, String fileName) {
  final nome = Uri.decodeComponent(fileName.trim());
  if (!_nomeArquivoProdutoValido(nome)) {
    return Response.notFound(
      jsonEncode({'ok': false, 'error': 'nao_encontrado'}),
      headers: {'content-type': 'application/json'},
    );
  }
  final path =
      '${_diretorioProductImages()}${Platform.pathSeparator}$nome';
  final arquivo = File(path);
  if (!arquivo.existsSync()) {
    return Response.notFound(
      jsonEncode({'ok': false, 'error': 'nao_encontrado'}),
      headers: {'content-type': 'application/json'},
    );
  }
  final bytes = arquivo.readAsBytesSync();
  return Response.ok(
    bytes,
    headers: {
      'content-type': 'image/jpeg',
      'cache-control': 'private, max-age=86400',
    },
  );
}

int _maxRevisionAtual() {
  final maxRevRs = _db.select(
    'SELECT COALESCE(MAX(revision), 0) AS r FROM changelog',
  );
  return maxRevRs.isEmpty ? 0 : (maxRevRs.first['r'] as int?) ?? 0;
}

void _broadcastNovaRevision(int revision) {
  final msg = jsonEncode({'type': 'revision', 'revision': revision});
  final mortos = <StreamSink<Object?>>[];
  for (final sink in List<StreamSink<Object?>>.from(_wsClientes)) {
    try {
      sink.add(msg);
    } catch (_) {
      mortos.add(sink);
    }
  }
  for (final s in mortos) {
    _wsClientes.remove(s);
    try {
      s.close();
    } catch (_) {}
  }
}

Map<String, dynamic> _presenceSnapshot() {
  _pruneHeartbeats();
  final stations = <Map<String, dynamic>>[];
  for (final e in _heartbeatLastMs.entries) {
    final id = e.key;
    final ts = e.value;
    stations.add({
      'stationId': id,
      'label': _heartbeatLabels[id] ?? '',
      'lastSeen': DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true)
          .toIso8601String(),
    });
  }
  return {
    'ok': true,
    'ttlSeconds': _presenceTtlMs ~/ 1000,
    'activeCount': stations.length,
    'stations': stations,
  };
}

void _broadcastPresence() {
  final snap = _presenceSnapshot();
  final msg = jsonEncode({
    'type': 'presence',
    'activeCount': snap['activeCount'],
    'ttlSeconds': snap['ttlSeconds'],
    'stations': snap['stations'],
  });
  final mortos = <StreamSink<Object?>>[];
  for (final sink in List<StreamSink<Object?>>.from(_wsClientes)) {
    try {
      sink.add(msg);
    } catch (_) {
      mortos.add(sink);
    }
  }
  for (final s in mortos) {
    _wsClientes.remove(s);
    try {
      s.close();
    } catch (_) {}
  }
}

void _initSchema(Database db) {
  db.execute('''
CREATE TABLE IF NOT EXISTS changelog (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  op TEXT NOT NULL,
  payload TEXT NOT NULL DEFAULT '{}',
  ts INTEGER NOT NULL
);
''');
  db.execute('''
CREATE TABLE IF NOT EXISTS id_map (
  device_id TEXT NOT NULL,
  entity TEXT NOT NULL,
  local_id INTEGER NOT NULL,
  global_id INTEGER NOT NULL,
  PRIMARY KEY (device_id, entity, local_id)
);
''');
  db.execute('''
CREATE TABLE IF NOT EXISTS orcamento_seq (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  next_num INTEGER NOT NULL
);
''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_changelog_entity ON changelog (entity, entity_id);',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_changelog_entity_rev '
    'ON changelog (entity, entity_id, revision);',
  );
  db.execute(
    'INSERT OR IGNORE INTO orcamento_seq (id, next_num) VALUES (1, 1);',
  );
  db.execute('''
CREATE TABLE IF NOT EXISTS push_batches (
  device_id TEXT NOT NULL,
  batch_id TEXT NOT NULL,
  response_json TEXT NOT NULL,
  created_ts INTEGER NOT NULL,
  PRIMARY KEY (device_id, batch_id)
);
''');
  db.execute('''
CREATE TABLE IF NOT EXISTS tombstones (
  entity TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  deleted_ts INTEGER NOT NULL,
  device_id TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (entity, entity_id)
);
''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tombstones_entity ON tombstones (entity, entity_id);',
  );
  _alinharOrcamentoSeqAoHistorico(db);
}

/// Garante que o proximo numero emitido pelo servidor seja > qualquer orcamento ja gravado.
void _alinharOrcamentoSeqAoHistorico(Database db) {
  final rs = db.select(
    'SELECT payload FROM changelog WHERE entity = ?',
    ['venda'],
  );
  var maxN = 0;
  for (final row in rs) {
    try {
      final raw = row['payload'];
      if (raw == null) continue;
      final j = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final n = (j['numeroOrcamento'] as num?)?.toInt() ?? 0;
      if (n > maxN) maxN = n;
    } catch (_) {}
  }
  if (maxN <= 0) return;
  final sel = db.select('SELECT next_num FROM orcamento_seq WHERE id = 1');
  final atual = sel.isEmpty ? 1 : (sel.first['next_num'] as int?) ?? 1;
  if (maxN >= atual) {
    db.execute(
      'UPDATE orcamento_seq SET next_num = ? WHERE id = 1',
      [maxN + 1],
    );
  }
}

/// Proximo numero de orcamento unico na rede (transacao BEGIN IMMEDIATE ja deve estar ativa).
/// Nunca devolve numero que ja exista no changelog (evita 123 "fantasma" enquanto
/// o celular tinha 349 e o seq local do servidor estava desatualizado).
int _alocarNumeroOrcamentoServidor(Database db) {
  final sel = db.prepare('SELECT next_num FROM orcamento_seq WHERE id = 1');
  final rs = sel.select([]);
  sel.dispose();
  var candidato = 1;
  if (rs.isEmpty) {
    db.execute(
      'INSERT OR REPLACE INTO orcamento_seq (id, next_num) VALUES (1, 2);',
    );
  } else {
    candidato = (rs.first['next_num'] as int?) ?? 1;
  }

  for (var i = 0; i < 5000; i++) {
    final ocupado = db.select(
      "SELECT 1 AS x FROM changelog WHERE entity = 'venda' AND op = 'upsert' "
      "AND json_extract(payload, '\$.numeroOrcamento') = ? LIMIT 1",
      [candidato],
    );
    if (ocupado.isEmpty) {
      db.execute(
        'UPDATE orcamento_seq SET next_num = ? WHERE id = 1',
        [candidato + 1],
      );
      return candidato;
    }
    candidato++;
  }
  db.execute(
    'UPDATE orcamento_seq SET next_num = ? WHERE id = 1',
    [candidato + 1],
  );
  return candidato;
}

/// Mantem o numero do cliente se ainda nao existir na rede; senao aloca novo.
/// Evita celular mostrar 342 e caixa so ter 350 (ou vice-versa).
int _reservarNumeroOrcamentoCliente(Database db, int desejado) {
  if (desejado <= 0) return _alocarNumeroOrcamentoServidor(db);

  final rs = db.select(
    "SELECT 1 AS x FROM changelog WHERE entity = 'venda' AND op = 'upsert' "
    "AND json_extract(payload, '\$.numeroOrcamento') = ? LIMIT 1",
    [desejado],
  );
  if (rs.isNotEmpty) {
    return _alocarNumeroOrcamentoServidor(db);
  }

  final sel = db.select('SELECT next_num FROM orcamento_seq WHERE id = 1');
  final atual = sel.isEmpty ? 1 : (sel.first['next_num'] as int?) ?? 1;
  if (desejado >= atual) {
    db.execute(
      'UPDATE orcamento_seq SET next_num = ? WHERE id = 1',
      [desejado + 1],
    );
  }
  return desejado;
}

Response _health(Request request) {
  _pruneHeartbeats();
  return Response.ok(
    jsonEncode({
      'ok': true,
      'service': 'sistema_vendas_sync',
      'presenceStations': _heartbeatLastMs.length,
      'presenceTtlSeconds': _presenceTtlMs ~/ 1000,
    }),
    headers: {'content-type': 'application/json'},
  );
}

Response _presence(Request request) {
  return Response.ok(
    jsonEncode(_presenceSnapshot()),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _heartbeat(Request request) async {
  final raw = await request.readAsString();
  Map<String, dynamic> body;
  try {
    body = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: 'JSON invalido');
  }
  final stationId = (body['stationId'] ?? '').toString().trim();
  if (stationId.isEmpty) {
    return Response(400, body: 'stationId obrigatorio');
  }
  var label = (body['label'] ?? '').toString().trim();
  if (label.length > 80) {
    label = label.substring(0, 80);
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  _heartbeatLastMs[stationId] = now;
  _heartbeatLabels[stationId] = label;
  final snap = _presenceSnapshot();
  _broadcastPresence();
  return Response.ok(
    jsonEncode(snap),
    headers: {'content-type': 'application/json'},
  );
}

Response _meta(Request request) {
  final now = DateTime.now().toUtc().toIso8601String();
  final lastRev = _ultimaRevisionChangelog();
  return Response.ok(
    jsonEncode({
      'serverTime': now,
      'schemaVersion': 2,
      'lastRevision': lastRev,
      'productImagesPath': _diretorioProductImages(),
    }),
    headers: {'content-type': 'application/json'},
  );
}

/// Endpoint leve: cliente compara [lastRevision] local e so faz pull pesado se mudar.
Response _version(Request request) {
  final lastRev = _ultimaRevisionChangelog();
  return Response.ok(
    jsonEncode({
      'lastRevision': lastRev,
      'schemaVersion': 2,
      'serverTime': DateTime.now().toUtc().toIso8601String(),
    }),
    headers: {'content-type': 'application/json'},
  );
}

int _ultimaRevisionChangelog() {
  final rs = _db.select(
    'SELECT COALESCE(MAX(revision), 0) AS r FROM changelog',
  );
  if (rs.isEmpty) return 0;
  return (rs.first['r'] as int?) ?? 0;
}

int _maxEntityId(Database db, String entity) {
  final rs = db.select(
    'SELECT COALESCE(MAX(entity_id), 0) AS m FROM changelog WHERE entity = ?',
    [entity],
  );
  if (rs.isEmpty) return 0;
  final row = rs.first;
  return (row['m'] as int?) ?? 0;
}

int _allocateGlobalId(Database db, String entity) {
  return _maxEntityId(db, entity) + 1;
}

bool _queryFlagTrue(Request request, String name) {
  final v = (request.url.queryParameters[name] ?? '').trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes';
}

/// Janela de orcamentos/vendas recentes na carga inicial do celular.
const int _bootstrapVendaDias = 7;

Response _pull(Request request) {
  final since =
      int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
  final bootstrap = _queryFlagTrue(request, 'bootstrap');
  final defaultLimit = bootstrap ? 1000 : 2000;
  var limit =
      int.tryParse(request.url.queryParameters['limit'] ?? '$defaultLimit') ??
          defaultLimit;
  // Bootstrap: lotes grandes (menos HTTP). Incremental: teto seguro na LAN.
  final maxLimit = bootstrap ? 2000 : 5000;
  if (limit < 1) limit = 1;
  if (limit > maxLimit) limit = maxLimit;

  if (bootstrap) {
    return _pullBootstrap(since: since, limit: limit);
  }

  final rs = _db.select(
    'SELECT revision, entity, entity_id, op, payload, ts FROM changelog '
    'WHERE revision > ? ORDER BY revision ASC LIMIT ?',
    [since, limit],
  );

  return _pullRespostaDeRows(
    rs: rs,
    since: since,
    limit: limit,
    bootstrap: false,
  );
}

/// Carga seletiva (pruning) para celular novo: so estado atual util na loja.
///
/// Filtros:
/// - produto: apenas ativos (`ativo != false`); deletes sempre passam
/// - venda: so orcamentos abertos (`status = orcamento`) OU criados nos
///   ultimos [_bootstrapVendaDias] dias; historico finalizado antigo fica de fora
/// - demais entidades: inalteradas
/// - alem disso: so a **ultima** revision por (entity, entity_id), para nao
///   reenviar o historico inteiro de updates do changelog
Response _pullBootstrap({required int since, required int limit}) {
  final cutoffIso = DateTime.now()
      .toUtc()
      .subtract(const Duration(days: _bootstrapVendaDias))
      .toIso8601String();

  // JOIN no MAX(revision) por entidade: 1 linha atual por registro (nao o log todo).
  final rs = _db.select(
    '''
SELECT c.revision, c.entity, c.entity_id, c.op, c.payload, c.ts
FROM changelog c
INNER JOIN (
  SELECT entity, entity_id, MAX(revision) AS max_rev
  FROM changelog
  GROUP BY entity, entity_id
) latest
  ON latest.entity = c.entity
 AND latest.entity_id = c.entity_id
 AND latest.max_rev = c.revision
WHERE c.revision > ?
  AND (
    c.entity NOT IN ('produto', 'venda')
    OR (
      c.entity = 'produto'
      AND (
        c.op = 'delete'
        OR COALESCE(json_extract(c.payload, '\$.ativo'), 1) IN (1, 'true', '1')
      )
    )
    OR (
      c.entity = 'venda'
      AND c.op != 'delete'
      AND (
        json_extract(c.payload, '\$.status') = 'orcamento'
        OR IFNULL(json_extract(c.payload, '\$.data'), '') >= ?
      )
    )
  )
ORDER BY c.revision ASC
LIMIT ?
''',
    [since, cutoffIso, limit],
  );

  return _pullRespostaDeRows(
    rs: rs,
    since: since,
    limit: limit,
    bootstrap: true,
  );
}

Response _pullRespostaDeRows({
  required ResultSet rs,
  required int since,
  required int limit,
  required bool bootstrap,
}) {
  final changes = <Map<String, dynamic>>[];
  var lastRev = since;
  for (final row in rs) {
    final rev = row['revision'] as int;
    lastRev = rev;
    changes.add({
      'revision': rev,
      'entity': row['entity'] as String,
      'entityId': row['entity_id'] as int,
      'op': row['op'] as String,
      'payload': jsonDecode((row['payload'] as String?) ?? '{}'),
      'ts': row['ts'] as int,
    });
  }

  final hasMore = rs.length >= limit;
  // Bootstrap: ao terminar a pagina filtrada, avanca o cursor ate o MAX do
  // changelog (linhas podadas nao devem deixar o celular "atrasado" eterno).
  if (bootstrap && !hasMore) {
    final maxRev = _ultimaRevisionChangelog();
    if (maxRev > lastRev) lastRev = maxRev;
  }
  // Pagina vazia no bootstrap (so restavam registros podados): fecha no MAX.
  if (bootstrap && rs.isEmpty) {
    final maxRev = _ultimaRevisionChangelog();
    if (maxRev > lastRev) lastRev = maxRev;
  }

  final body = jsonEncode({
    'lastRevision': lastRev,
    'changes': changes,
    'hasMore': hasMore,
    if (bootstrap) 'bootstrap': true,
    if (bootstrap) 'pruned': true,
    if (bootstrap) 'vendaDias': _bootstrapVendaDias,
  });

  return Response.ok(body, headers: {'content-type': 'application/json'});
}

Future<Response> _push(Request request) async {
  final raw = await request.readAsString();
  Map<String, dynamic> body;
  try {
    body = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return Response.badRequest(body: 'JSON invalido');
  }

  final deviceId = (body['deviceId'] ?? '').toString().trim();
  if (deviceId.isEmpty) {
    return Response(400, body: 'deviceId obrigatorio');
  }

  final pushBatchId = (body['pushBatchId'] ?? '').toString().trim();
  final mutations = body['mutations'];
  if (mutations is! List) {
    return Response(400, body: 'mutations deve ser lista');
  }

  // Serializa pushes concorrentes (Celular A + B).
  final anterior = _mutexPush;
  final liberado = Completer<void>();
  _mutexPush = liberado.future;
  await anterior;
  try {
    return _pushAplicar(
      deviceId: deviceId,
      pushBatchId: pushBatchId,
      mutations: mutations,
    );
  } finally {
    liberado.complete();
  }
}

Response _pushAplicar({
  required String deviceId,
  required String pushBatchId,
  required List<dynamic> mutations,
}) {
  final mappings = <Map<String, dynamic>>[];
  final numeroCorrections = <Map<String, dynamic>>[];
  final now = DateTime.now().millisecondsSinceEpoch;

  try {
    _db.execute('BEGIN IMMEDIATE');

    // Idempotencia DENTRO do lock: evita TOCTOU entre 2 retries.
    if (pushBatchId.isNotEmpty) {
      final cached = _db.select(
        'SELECT response_json FROM push_batches WHERE device_id = ? AND batch_id = ?',
        [deviceId, pushBatchId],
      );
      if (cached.isNotEmpty) {
        final rawCached = cached.first['response_json']?.toString() ?? '{}';
        _db.execute('COMMIT');
        // Re-avisa clientes: quem perdeu o 1o WS ainda recebe o evento.
        try {
          final decoded = jsonDecode(rawCached);
          final rev = decoded is Map
              ? (decoded['appliedRevision'] as num?)?.toInt()
              : null;
          _broadcastNovaRevision(rev ?? _maxRevisionAtual());
        } catch (_) {
          _broadcastNovaRevision(_maxRevisionAtual());
        }
        return Response.ok(
          rawCached,
          headers: {'content-type': 'application/json'},
        );
      }
    }

    for (final m in mutations) {
      if (m is! Map) continue;
      final map = Map<String, dynamic>.from(m);
      final entity = (map['entity'] ?? '').toString();
      final op = (map['op'] ?? 'upsert').toString();
      final localId = map['localId'];
      final localIdInt = localId is int ? localId : int.tryParse('$localId') ?? 0;

      if (entity.isEmpty) continue;

      if (op == 'delete') {
        final entityId =
            map['entityId'] is int ? map['entityId'] as int : int.tryParse('${map['entityId']}') ?? 0;
        if (entityId <= 0) continue;
        final stmt = _db.prepare(
          'INSERT INTO changelog (entity, entity_id, op, payload, ts) VALUES (?, ?, ?, ?, ?)',
        );
        stmt.execute([
          entity,
          entityId,
          'delete',
          '{}',
          now,
        ]);
        stmt.dispose();

        final delGlobal = _db.prepare(
          'DELETE FROM id_map WHERE entity = ? AND global_id = ?',
        );
        delGlobal.execute([entity, entityId]);
        delGlobal.dispose();

        if (localIdInt > 0) {
          final delLocal = _db.prepare(
            'DELETE FROM id_map WHERE device_id = ? AND entity = ? AND local_id = ?',
          );
          delLocal.execute([deviceId, entity, localIdInt]);
          delLocal.dispose();
        }

        final insTomb = _db.prepare(
          'INSERT OR REPLACE INTO tombstones (entity, entity_id, deleted_ts, device_id) VALUES (?, ?, ?, ?)',
        );
        insTomb.execute([entity, entityId, now, deviceId]);
        insTomb.dispose();
        continue;
      }

      final payloadRaw = map['payload'];
      final payload = payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : <String, dynamic>{};

      var globalId = 0;
      var vendaNovaNaRede = false;

      final existing = _db.select(
        'SELECT global_id FROM id_map WHERE device_id = ? AND entity = ? AND local_id = ?',
        [deviceId, entity, localIdInt],
      );
      if (existing.isNotEmpty) {
        globalId = existing.first['global_id'] as int;
      } else {
        globalId = _allocateGlobalId(_db, entity);
        vendaNovaNaRede = entity == 'venda';
        final ins = _db.prepare(
          'INSERT OR REPLACE INTO id_map (device_id, entity, local_id, global_id) VALUES (?, ?, ?, ?)',
        );
        ins.execute([deviceId, entity, localIdInt, globalId]);
        ins.dispose();

        if (localIdInt != globalId) {
          mappings.add({
            'entity': entity,
            'localId': localIdInt,
            'globalId': globalId,
          });
        }
      }

      final delTomb = _db.prepare(
        'DELETE FROM tombstones WHERE entity = ? AND entity_id = ?',
      );
      delTomb.execute([entity, globalId]);
      delTomb.dispose();

      payload['id'] = globalId;

      if (entity == 'venda' && vendaNovaNaRede) {
        final clienteNum = (payload['numeroOrcamento'] as num?)?.toInt() ?? 0;
        final servidorNum = _reservarNumeroOrcamentoCliente(_db, clienteNum);
        payload['numeroOrcamento'] = servidorNum;
        // Sempre ACK o numero oficial (mesmo se manteve o do cliente): o PDV
        // precisa confirmar na UI o comprovante alinhado com o caixa.
        numeroCorrections.add({
          'globalId': globalId,
          'localId': localIdInt,
          'numeroOrcamento': servidorNum,
        });
      }

      final stmt = _db.prepare(
        'INSERT INTO changelog (entity, entity_id, op, payload, ts) VALUES (?, ?, ?, ?, ?)',
      );
      stmt.execute([
        entity,
        globalId,
        'upsert',
        jsonEncode(payload),
        now,
      ]);
      stmt.dispose();
    }

    final appliedRevision = _maxRevisionAtual();
    final responseBody = jsonEncode({
      'ok': true,
      'appliedRevision': appliedRevision,
      'mappings': mappings,
      'numeroCorrections': numeroCorrections,
      'idempotentReplay': false,
    });

    // Cache do lote NA MESMA transacao (crash entre commit e insert nao perde idempotencia).
    if (pushBatchId.isNotEmpty) {
      final insBatch = _db.prepare(
        'INSERT OR REPLACE INTO push_batches (device_id, batch_id, response_json, created_ts) VALUES (?, ?, ?, ?)',
      );
      insBatch.execute([deviceId, pushBatchId, responseBody, now]);
      insBatch.dispose();
    }

    _db.execute('COMMIT');

    if (pushBatchId.isNotEmpty) {
      _prunePushBatches(deviceId);
    }

    // Avisa TODOS os clientes WS (Celular B, C, PC) — incluindo o remetente.
    _broadcastNovaRevision(appliedRevision);

    return Response.ok(
      responseBody,
      headers: {'content-type': 'application/json'},
    );
  } catch (e, st) {
    try {
      _db.execute('ROLLBACK');
    } catch (_) {}
    return Response.internalServerError(
      body: 'Erro ao aplicar push: $e\n$st',
    );
  }
}

void _prunePushBatches(String deviceId) {
  final rows = _db.select(
    'SELECT batch_id FROM push_batches WHERE device_id = ? ORDER BY created_ts DESC',
    [deviceId],
  );
  if (rows.length <= 120) return;
  for (var i = 120; i < rows.length; i++) {
    final bid = rows[i]['batch_id']?.toString() ?? '';
    if (bid.isEmpty) continue;
    final del = _db.prepare(
      'DELETE FROM push_batches WHERE device_id = ? AND batch_id = ?',
    );
    del.execute([deviceId, bid]);
    del.dispose();
  }
}
