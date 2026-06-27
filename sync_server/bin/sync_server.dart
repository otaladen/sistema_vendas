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

Middleware _syncAuthMiddleware(Handler inner) {
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
  _initSchema(_db);

  final router = Router()
    ..get('/health', _health)
    ..get('/sync/presence', _presence)
    ..post('/sync/heartbeat', _heartbeat)
    ..get('/sync/meta', _meta)
    ..get('/sync/pull', _pull)
    ..get(
      '/sync/stream',
      webSocketHandler((WebSocketChannel channel, _) {
        final sink = channel.sink;
        _wsClientes.add(sink);
        channel.stream.listen(
          (_) {},
          onDone: () => _wsClientes.remove(sink),
          onError: (_) => _wsClientes.remove(sink),
        );
      }),
    )
    ..post('/sync/push', _push)
    ..get('/sync/pod/<fileName>', _podDownload)
    ..post('/sync/pod', _podUpload);

  final podDir = _diretorioPodEntrega();
  if (!Directory(podDir).existsSync()) {
    Directory(podDir).createSync(recursive: true);
  }

  final handler = Pipeline()
      .addMiddleware(_syncAuthMiddleware)
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print(
    'sistema_vendas sync server | db=$dbPath | pod=$podDir | '
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

final RegExp _regexNomeArquivoPod = RegExp(r'^venda_\d+_\d{8}_\d{6}\.jpg$');

bool _nomeArquivoPodValido(String raw) {
  final name = raw.trim();
  if (name.isEmpty || name.contains('..') || name.contains('/')) {
    return false;
  }
  return _regexNomeArquivoPod.hasMatch(name);
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
      body: jsonEncode({'ok': false, 'error': 'nao_encontrado'}),
      headers: {'content-type': 'application/json'},
    );
  }
  final path =
      '${_diretorioPodEntrega()}${Platform.pathSeparator}$fileName';
  final arquivo = File(path);
  if (!arquivo.existsSync()) {
    return Response.notFound(
      body: jsonEncode({'ok': false, 'error': 'nao_encontrado'}),
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

void _broadcastNovaRevision(int revision) {
  final msg = jsonEncode({'type': 'revision', 'revision': revision});
  for (final sink in List<StreamSink<Object?>>.from(_wsClientes)) {
    try {
      sink.add(msg);
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
int _alocarNumeroOrcamentoServidor(Database db) {
  final sel = db.prepare('SELECT next_num FROM orcamento_seq WHERE id = 1');
  final rs = sel.select([]);
  sel.dispose();
  if (rs.isEmpty) {
    db.execute(
      'INSERT OR REPLACE INTO orcamento_seq (id, next_num) VALUES (1, 2);',
    );
    return 1;
  }
  final atual = (rs.first['next_num'] as int?) ?? 1;
  db.execute(
    'UPDATE orcamento_seq SET next_num = next_num + 1 WHERE id = 1',
  );
  return atual;
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
  return Response.ok(
    jsonEncode({
      'ok': true,
      'ttlSeconds': _presenceTtlMs ~/ 1000,
      'activeCount': stations.length,
      'stations': stations,
    }),
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
  _pruneHeartbeats();
  return Response.ok(
    jsonEncode({'ok': true}),
    headers: {'content-type': 'application/json'},
  );
}

Response _meta(Request request) {
  final now = DateTime.now().toUtc().toIso8601String();
  return Response.ok(
    jsonEncode({'serverTime': now, 'schemaVersion': 2}),
    headers: {'content-type': 'application/json'},
  );
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

Response _pull(Request request) {
  final since =
      int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
  final limit =
      int.tryParse(request.url.queryParameters['limit'] ?? '2000') ?? 2000;

  final rs = _db.select(
    'SELECT revision, entity, entity_id, op, payload, ts FROM changelog '
    'WHERE revision > ? ORDER BY revision ASC LIMIT ?',
    [since, limit],
  );

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

  final body = jsonEncode({
    'lastRevision': lastRev,
    'changes': changes,
    'hasMore': rs.length >= limit,
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
  if (pushBatchId.isNotEmpty) {
    final cached = _db.select(
      'SELECT response_json FROM push_batches WHERE device_id = ? AND batch_id = ?',
      [deviceId, pushBatchId],
    );
    if (cached.isNotEmpty) {
      final raw = cached.first['response_json']?.toString() ?? '{}';
      return Response.ok(
        raw,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  final mutations = body['mutations'];
  if (mutations is! List) {
    return Response(400, body: 'mutations deve ser lista');
  }

  final mappings = <Map<String, dynamic>>[];
  final numeroCorrections = <Map<String, dynamic>>[];
  final now = DateTime.now().millisecondsSinceEpoch;

  try {
    _db.execute('BEGIN IMMEDIATE');
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
      final payload = payloadRaw is Map<String, dynamic>
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
        final servidorNum = _alocarNumeroOrcamentoServidor(_db);
        payload['numeroOrcamento'] = servidorNum;
        numeroCorrections.add({
          'globalId': globalId,
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

    _db.execute('COMMIT');
  } catch (e, st) {
    try {
      _db.execute('ROLLBACK');
    } catch (_) {}
    return Response.internalServerError(
      body: 'Erro ao aplicar push: $e\n$st',
    );
  }

  final maxRevRs = _db.select(
    'SELECT COALESCE(MAX(revision), 0) AS r FROM changelog',
  );
  final appliedRevision =
      maxRevRs.isEmpty ? 0 : (maxRevRs.first['r'] as int?) ?? 0;

  _broadcastNovaRevision(appliedRevision);

  final responseBody = jsonEncode({
    'ok': true,
    'appliedRevision': appliedRevision,
    'mappings': mappings,
    'numeroCorrections': numeroCorrections,
    'idempotentReplay': false,
  });

  if (pushBatchId.isNotEmpty) {
    final insBatch = _db.prepare(
      'INSERT OR REPLACE INTO push_batches (device_id, batch_id, response_json, created_ts) VALUES (?, ?, ?, ?)',
    );
    insBatch.execute([deviceId, pushBatchId, responseBody, now]);
    insBatch.dispose();
    _prunePushBatches(deviceId);
  }

  return Response.ok(
    responseBody,
    headers: {'content-type': 'application/json'},
  );
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
