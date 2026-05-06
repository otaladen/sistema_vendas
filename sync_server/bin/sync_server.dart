import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

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
    ..get('/sync/meta', _meta)
    ..get('/sync/pull', _pull)
    ..post('/sync/push', _push);

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print(
    'sistema_vendas sync server | db=$dbPath | http://${server.address.address}:$port',
  );
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
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_changelog_entity ON changelog (entity, entity_id);',
  );
}

Response _health(Request request) {
  return Response.ok(
    jsonEncode({'ok': true, 'service': 'sistema_vendas_sync'}),
    headers: {'content-type': 'application/json'},
  );
}

Response _meta(Request request) {
  final now = DateTime.now().toUtc().toIso8601String();
  return Response.ok(
    jsonEncode({'serverTime': now, 'schemaVersion': 1}),
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

  final mutations = body['mutations'];
  if (mutations is! List) {
    return Response(400, body: 'mutations deve ser lista');
  }

  final mappings = <Map<String, dynamic>>[];
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
        continue;
      }

      final payloadRaw = map['payload'];
      final payload = payloadRaw is Map<String, dynamic>
          ? Map<String, dynamic>.from(payloadRaw)
          : <String, dynamic>{};

      var globalId = 0;

      final existing = _db.select(
        'SELECT global_id FROM id_map WHERE device_id = ? AND entity = ? AND local_id = ?',
        [deviceId, entity, localIdInt],
      );
      if (existing.isNotEmpty) {
        globalId = existing.first['global_id'] as int;
      } else {
        globalId = _allocateGlobalId(_db, entity);
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

      payload['id'] = globalId;

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

  return Response.ok(
    jsonEncode({
      'ok': true,
      'appliedRevision': appliedRevision,
      'mappings': mappings,
    }),
    headers: {'content-type': 'application/json'},
  );
}
