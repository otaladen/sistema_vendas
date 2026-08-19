// ignore_for_file: avoid_print
/// Stress / concorrencia contra a Lan API do PC1 (:8788).
///
/// Uso (PC servidor com app em modo servidor / API ativa):
///   dart run tools/stress_test_lan.dart
///   dart run tools/stress_test_lan.dart --host=192.168.0.10 --port=8788 --token=SEU_TOKEN
///   dart run tools/stress_test_lan.dart --produto-id=42 --vendas=20 --ws=5
///
/// Flags:
///   --host=127.0.0.1
///   --port=8788
///   --token=                (header x-sync-token; vazio se o PC1 nao exige)
///   --produto-id=0          (0 = escolhe o 1o produto ativo da API)
///   --vendas=20             (checkout concorrente no Teste 1)
///   --fiscal-paralelo=12    (GETs fiscais no Teste 2)
///   --ws=5                  (conexoes WebSocket no Teste 3)
///   --ws-segundos=8         (tempo de escuta WS)
///   --strict-estoque        (nao permite venda sem estoque no checkout)
///   --skip-vendas | --skip-fiscal | --skip-ws
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

class _Args {
  _Args({
    required this.host,
    required this.port,
    required this.token,
    required this.produtoId,
    required this.vendas,
    required this.fiscalParalelo,
    required this.wsCount,
    required this.wsSegundos,
    required this.strictEstoque,
    required this.skipVendas,
    required this.skipFiscal,
    required this.skipWs,
  });

  final String host;
  final int port;
  final String token;
  final int produtoId;
  final int vendas;
  final int fiscalParalelo;
  final int wsCount;
  final int wsSegundos;
  final bool strictEstoque;
  final bool skipVendas;
  final bool skipFiscal;
  final bool skipWs;

  String get baseHttp => 'http://$host:$port';

  Uri get wsUri {
    final q = <String, String>{};
    if (token.trim().isNotEmpty) q['token'] = token.trim();
    return Uri(
      scheme: 'ws',
      host: host,
      port: port,
      path: '/api/stream',
      queryParameters: q.isEmpty ? null : q,
    );
  }

  factory _Args.parse(List<String> argv) {
    var host = '127.0.0.1';
    var port = 8788;
    var token = '';
    var produtoId = 0;
    var vendas = 20;
    var fiscalParalelo = 12;
    var wsCount = 5;
    var wsSegundos = 8;
    var strictEstoque = false;
    var skipVendas = false;
    var skipFiscal = false;
    var skipWs = false;

    for (final a in argv) {
      if (a.startsWith('--host=')) {
        host = a.substring(7).trim();
      } else if (a.startsWith('--port=')) {
        port = int.tryParse(a.substring(7)) ?? port;
      } else if (a.startsWith('--token=')) {
        token = a.substring(8);
      } else if (a.startsWith('--produto-id=')) {
        produtoId = int.tryParse(a.substring(13)) ?? 0;
      } else if (a.startsWith('--vendas=')) {
        vendas = int.tryParse(a.substring(9)) ?? vendas;
      } else if (a.startsWith('--fiscal-paralelo=')) {
        fiscalParalelo = int.tryParse(a.substring(18)) ?? fiscalParalelo;
      } else if (a.startsWith('--ws=')) {
        wsCount = int.tryParse(a.substring(5)) ?? wsCount;
      } else if (a.startsWith('--ws-segundos=')) {
        wsSegundos = int.tryParse(a.substring(14)) ?? wsSegundos;
      } else if (a == '--strict-estoque') {
        strictEstoque = true;
      } else if (a == '--skip-vendas') {
        skipVendas = true;
      } else if (a == '--skip-fiscal') {
        skipFiscal = true;
      } else if (a == '--skip-ws') {
        skipWs = true;
      } else if (a == '--help' || a == '-h') {
        _printHelp();
        exit(0);
      }
    }
    return _Args(
      host: host.isEmpty ? '127.0.0.1' : host,
      port: port,
      token: token,
      produtoId: produtoId,
      vendas: max(1, vendas),
      fiscalParalelo: max(1, fiscalParalelo),
      wsCount: max(1, wsCount),
      wsSegundos: max(2, wsSegundos),
      strictEstoque: strictEstoque,
      skipVendas: skipVendas,
      skipFiscal: skipFiscal,
      skipWs: skipWs,
    );
  }

  static void _printHelp() {
    print('''
Stress / concorrencia — Lan API PC1 (:8788)

  dart run tools/stress_test_lan.dart [flags]

Flags:
  --host=127.0.0.1
  --port=8788
  --token=                x-sync-token (se o PC1 exigir)
  --produto-id=0          0 = 1o produto ativo
  --vendas=20
  --fiscal-paralelo=12
  --ws=5
  --ws-segundos=8
  --strict-estoque        falha se estoque insuficiente
  --skip-vendas | --skip-fiscal | --skip-ws
''');
  }
}

// ---------------------------------------------------------------------------
// Metricas
// ---------------------------------------------------------------------------

class _ReqResult {
  _ReqResult({
    required this.label,
    required this.statusCode,
    required this.ms,
    this.error,
    this.bodySnippet = '',
  });

  final String label;
  final int statusCode;
  final int ms;
  final String? error;
  final String bodySnippet;

  bool get okHttp => statusCode >= 200 && statusCode < 300;
  bool get ok => error == null && okHttp;
}

class _Report {
  final List<_ReqResult> results = [];
  final List<String> notes = [];
  int wsConexoesOk = 0;
  int wsConexoesFalhas = 0;
  int wsMensagens = 0;
  int wsHello = 0;
  int wsEntityChanged = 0;
  int wsErrosStream = 0;

  void add(_ReqResult r) => results.add(r);

  void printFinal() {
    final total = results.length;
    final ok = results.where((r) => r.ok).length;
    final http2xx = results.where((r) => r.okHttp).length;
    final http4xx =
        results.where((r) => r.statusCode >= 400 && r.statusCode < 500).length;
    final http5xx = results.where((r) => r.statusCode >= 500).length;
    final ex = results.where((r) => r.error != null).length;
    final msList = results.map((r) => r.ms).toList()..sort();
    final avgMs = msList.isEmpty
        ? 0.0
        : msList.reduce((a, b) => a + b) / msList.length;
    final p95 = msList.isEmpty
        ? 0
        : msList[(msList.length * 0.95).floor().clamp(0, msList.length - 1)];

    print('');
    print('=' * 64);
    print(' RELATORIO FINAL — stress_test_lan');
    print('=' * 64);
    print('Total HTTP/API:          $total');
    print(
      'Sucesso (2xx + sem ex):  $ok'
      ' (${total == 0 ? 0 : (100 * ok / total).toStringAsFixed(1)}%)',
    );
    print('HTTP 2xx:                $http2xx');
    print('HTTP 4xx:                $http4xx');
    print('HTTP 5xx:                $http5xx');
    print('Excecoes de rede/parse:  $ex');
    print('Latencia media:          ${avgMs.toStringAsFixed(1)} ms');
    print('Latencia p95:            $p95 ms');
    if (msList.isNotEmpty) {
      print('Latencia min/max:        ${msList.first} / ${msList.last} ms');
    }
    print('');
    print('WebSocket:');
    print('  conexoes OK / falha:   $wsConexoesOk / $wsConexoesFalhas');
    print(
      '  mensagens recebidas:   $wsMensagens'
      ' (hello=$wsHello, entityChanged=$wsEntityChanged)',
    );
    print('  erros de stream:       $wsErrosStream');
    if (notes.isNotEmpty) {
      print('');
      print('Observacoes:');
      for (final n in notes) {
        print('  - $n');
      }
    }

    final erros = results.where((r) => !r.ok).take(12).toList();
    if (erros.isNotEmpty) {
      print('');
      print('Amostra de falhas (ate 12):');
      for (final e in erros) {
        final det = e.error ??
            'HTTP ${e.statusCode}'
                '${e.bodySnippet.isEmpty ? '' : ': ${e.bodySnippet}'}';
        print('  [${e.label}] ${e.ms}ms — $det');
      }
    }
    print('=' * 64);
  }
}

// ---------------------------------------------------------------------------
// Cliente HTTP minimo
// ---------------------------------------------------------------------------

class _LanHttp {
  _LanHttp(this.base, this.token);

  final String base;
  final String token;
  final http.Client _client = http.Client();

  Map<String, String> get _headers {
    final h = <String, String>{'content-type': 'application/json'};
    final t = token.trim();
    if (t.isNotEmpty) h['x-sync-token'] = t;
    return h;
  }

  Uri _u(String path, [Map<String, String>? q]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: q);
  }

  Future<_ReqResult> get(
    String label,
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _client
          .get(_u(path, query), headers: _headers)
          .timeout(timeout);
      sw.stop();
      return _ReqResult(
        label: label,
        statusCode: r.statusCode,
        ms: sw.elapsedMilliseconds,
        bodySnippet: snip(r.body),
      );
    } catch (e) {
      sw.stop();
      return _ReqResult(
        label: label,
        statusCode: 0,
        ms: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  Future<({int status, String body, int ms})> getFull(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final sw = Stopwatch()..start();
    final r = await _client
        .get(_u(path, query), headers: _headers)
        .timeout(timeout);
    sw.stop();
    return (status: r.statusCode, body: r.body, ms: sw.elapsedMilliseconds);
  }

  Future<({int status, String body, int ms})> postFull(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final sw = Stopwatch()..start();
    final r = await _client
        .post(_u(path), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
    sw.stop();
    return (status: r.statusCode, body: r.body, ms: sw.elapsedMilliseconds);
  }

  void close() => _client.close();

  static String snip(String body, [int max = 160]) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }
}

// ---------------------------------------------------------------------------
// Suites
// ---------------------------------------------------------------------------

Future<int> _resolverProdutoId(_LanHttp client, int preferido) async {
  if (preferido > 0) return preferido;
  final full = await client.getFull(
    '/api/produtos',
    query: {'limit': '5', 'somenteAtivos': 'true'},
  );
  if (full.status < 200 || full.status >= 300) {
    throw StateError(
      'Nao foi possivel listar produtos (HTTP ${full.status}): '
      '${_LanHttp.snip(full.body)}',
    );
  }
  final d = jsonDecode(full.body);
  if (d is! Map) throw StateError('Resposta /api/produtos invalida');
  final items = d['items'];
  if (items is! List || items.isEmpty) {
    throw StateError('Nenhum produto ativo no PC1 para o teste de vendas.');
  }
  final first = items.first;
  if (first is! Map) throw StateError('Item de produto invalido');
  final id = (first['id'] as num?)?.toInt() ?? 0;
  if (id <= 0) throw StateError('produtoId invalido na listagem');
  final nome = (first['nome'] ?? first['codigoInterno'] ?? id).toString();
  print('Produto escolhido: #$id ($nome)');
  return id;
}

Future<void> _testeVendasEstoque({
  required _LanHttp client,
  required _Report report,
  required int produtoId,
  required int n,
  required bool strictEstoque,
}) async {
  print('');
  print('--- Teste 1: Concorrencia Vendas/Estoque ($n checkouts) ---');
  print('produtoId=$produtoId  permitirVendaSemEstoque=${!strictEstoque}');

  final futures = <Future<_ReqResult>>[];
  for (var i = 0; i < n; i++) {
    final idx = i + 1;
    futures.add(() async {
      final bodyOrc = {
        'itens': [
          {
            'produtoId': produtoId,
            'quantidade': 1,
            'precoUnitario': 1.0,
            'precoTipo': 'preco1',
            'tipoEntregaItem': 'retirada',
          },
        ],
        'pagamento': {
          'formaPagamento': 'dinheiro',
          'quantidadeParcelas': 1,
        },
        'entrega': {
          'tipoEntrega': 'retirada',
        },
        'permitirVendaSemEstoque': !strictEstoque,
      };

      final sw = Stopwatch()..start();
      try {
        final orc = await client.postFull('/api/orcamentos', bodyOrc);
        if (orc.status < 200 || orc.status >= 300) {
          sw.stop();
          return _ReqResult(
            label: 'venda#$idx/orcamento',
            statusCode: orc.status,
            ms: sw.elapsedMilliseconds,
            bodySnippet: _LanHttp.snip(orc.body),
          );
        }
        final map = jsonDecode(orc.body);
        final vendaId = map is Map ? (map['id'] as num?)?.toInt() ?? 0 : 0;
        if (vendaId <= 0) {
          sw.stop();
          return _ReqResult(
            label: 'venda#$idx/orcamento',
            statusCode: orc.status,
            ms: sw.elapsedMilliseconds,
            error: 'orcamento sem id',
            bodySnippet: _LanHttp.snip(orc.body),
          );
        }

        final fin = await client.postFull('/api/vendas/$vendaId/finalizar', {
          'permitirVendaSemEstoque': !strictEstoque,
        });
        sw.stop();
        return _ReqResult(
          label: 'venda#$idx/finalizar',
          statusCode: fin.status,
          ms: sw.elapsedMilliseconds,
          bodySnippet: _LanHttp.snip(fin.body),
        );
      } catch (e) {
        sw.stop();
        return _ReqResult(
          label: 'venda#$idx',
          statusCode: 0,
          ms: sw.elapsedMilliseconds,
          error: e.toString(),
        );
      }
    }());
  }

  final results = await Future.wait(futures);
  for (final r in results) {
    report.add(r);
  }
  final ok = results.where((r) => r.ok).length;
  final avg = results.isEmpty
      ? 0.0
      : results.map((r) => r.ms).reduce((a, b) => a + b) / results.length;
  print('Checkout OK: $ok/$n  media=${avg.toStringAsFixed(1)} ms');
  if (ok < n) {
    report.notes.add(
      'Teste 1: ${n - ok} checkout(s) falharam '
      '(estoque, validacao ou lock). Veja amostra de falhas.',
    );
  }
}

Future<void> _testeFiscalCarga({
  required _LanHttp client,
  required _Report report,
  required int paralelo,
}) async {
  print('');
  print('--- Teste 2: Carga fiscal / historico ($paralelo x 3 endpoints) ---');

  final now = DateTime.now();
  final endpoints = <({String label, String path, Map<String, String>? q})>[
    (label: 'nfe-importadas', path: '/api/nfe-importadas', q: {'limit': '50'}),
    (label: 'fiscal/pendencias', path: '/api/fiscal/pendencias', q: null),
    (
      label: 'fiscal/relatorio-mensal',
      path: '/api/fiscal/relatorio-mensal',
      q: {'mes': '${now.month}', 'ano': '${now.year}'},
    ),
  ];

  final futures = <Future<_ReqResult>>[];
  for (var i = 0; i < paralelo; i++) {
    for (final ep in endpoints) {
      final round = i + 1;
      futures.add(
        client.get(
          '${ep.label}#$round',
          ep.path,
          query: ep.q,
          timeout: const Duration(seconds: 60),
        ),
      );
    }
  }

  final results = await Future.wait(futures);
  for (final r in results) {
    report.add(r);
  }

  for (final ep in endpoints) {
    final subset = results.where((r) => r.label.startsWith(ep.label)).toList();
    final ok = subset.where((r) => r.ok).length;
    final avg = subset.isEmpty
        ? 0.0
        : subset.map((r) => r.ms).reduce((a, b) => a + b) / subset.length;
    print(
      '  ${ep.path}: OK $ok/${subset.length}  '
      'media=${avg.toStringAsFixed(1)} ms',
    );
  }
}

Future<void> _testeWebSocketFlood({
  required _Args args,
  required _LanHttp client,
  required _Report report,
}) async {
  print('');
  print(
    '--- Teste 3: WebSocket Event Flood '
    '(${args.wsCount} conexoes, ${args.wsSegundos}s) ---',
  );

  final channels = <WebSocketChannel>[];
  final subs = <StreamSubscription<dynamic>>[];

  for (var i = 0; i < args.wsCount; i++) {
    final idx = i + 1;
    try {
      final ch = WebSocketChannel.connect(args.wsUri);
      channels.add(ch);
      report.wsConexoesOk++;
      final sub = ch.stream.listen(
        (raw) {
          report.wsMensagens++;
          try {
            final text = raw is String ? raw : raw.toString();
            final d = jsonDecode(text);
            if (d is Map) {
              final type = (d['type'] ?? '').toString();
              if (type == 'hello') report.wsHello++;
              if (type == 'entityChanged') report.wsEntityChanged++;
            }
          } catch (_) {}
        },
        onError: (Object e) {
          report.wsErrosStream++;
          report.notes.add('WS#$idx erro de stream: $e');
        },
        cancelOnError: false,
      );
      subs.add(sub);
      print('  WS#$idx conectado → ${args.wsUri}');
    } catch (e) {
      report.wsConexoesFalhas++;
      report.notes.add('WS#$idx falha ao conectar: $e');
      print('  WS#$idx FALHA: $e');
    }
  }

  // Aguarda hello chegar.
  await Future<void>.delayed(const Duration(milliseconds: 400));

  print('  Gerando mutacoes leves para flood de entityChanged...');
  try {
    final produtoId = await _resolverProdutoId(client, args.produtoId);
    final mutacoes = <Future<_ReqResult>>[];
    for (var i = 0; i < 6; i++) {
      mutacoes.add(() async {
        final orc = await client.postFull('/api/orcamentos', {
          'itens': [
            {
              'produtoId': produtoId,
              'quantidade': 1,
              'precoUnitario': 1.0,
              'precoTipo': 'preco1',
            },
          ],
          'pagamento': {
            'formaPagamento': 'dinheiro',
            'quantidadeParcelas': 1,
          },
          'entrega': {'tipoEntrega': 'retirada'},
          'permitirVendaSemEstoque': true,
        });
        return _ReqResult(
          label: 'ws-trigger/orcamento#${i + 1}',
          statusCode: orc.status,
          ms: orc.ms,
          bodySnippet: _LanHttp.snip(orc.body),
        );
      }());
    }
    for (var i = 0; i < 4; i++) {
      mutacoes.add(
        client.get('ws-trigger/pendencias#${i + 1}', '/api/fiscal/pendencias'),
      );
    }
    final trig = await Future.wait(mutacoes);
    for (final r in trig) {
      report.add(r);
    }
  } catch (e) {
    report.notes.add('Triggers WS: $e');
    print('  Aviso: nao foi possivel gerar mutacoes ($e)');
  }

  await Future<void>.delayed(Duration(seconds: args.wsSegundos));

  for (final s in subs) {
    try {
      await s.cancel();
    } catch (_) {}
  }
  for (final ch in channels) {
    try {
      await ch.sink.close();
    } catch (_) {}
  }

  report.notes.add(
    'Teste 3: hello=${report.wsHello}/${args.wsCount} esperados; '
    'entityChanged=${report.wsEntityChanged} '
    '(depende de mutacoes no PC1 durante a janela).',
  );
  print(
    '  Mensagens=${report.wsMensagens}  hello=${report.wsHello}  '
    'entityChanged=${report.wsEntityChanged}  '
    'errosStream=${report.wsErrosStream}',
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main(List<String> argv) async {
  final args = _Args.parse(argv);
  final report = _Report();
  final httpClient = _LanHttp(args.baseHttp, args.token);

  print('stress_test_lan → ${args.baseHttp}');
  print(
    'token=${args.token.trim().isEmpty ? "(vazio)" : "***"}  '
    'vendas=${args.vendas}  fiscal=${args.fiscalParalelo}  ws=${args.wsCount}',
  );

  try {
    final health = await httpClient.getFull('/api/health');
    report.add(
      _ReqResult(
        label: 'health',
        statusCode: health.status,
        ms: health.ms,
        bodySnippet: _LanHttp.snip(health.body),
      ),
    );
    if (health.status < 200 || health.status >= 300) {
      print(
        'FALHA: /api/health HTTP ${health.status}. '
        'O PC1 esta com a Lan API :${args.port} ativa?',
      );
      report.printFinal();
      httpClient.close();
      exit(2);
    }
    print('Health OK (${health.ms} ms)');
  } catch (e) {
    print('FALHA ao conectar em ${args.baseHttp}: $e');
    report.add(
      _ReqResult(
        label: 'health',
        statusCode: 0,
        ms: 0,
        error: e.toString(),
      ),
    );
    report.printFinal();
    httpClient.close();
    exit(2);
  }

  try {
    if (!args.skipVendas) {
      final produtoId = await _resolverProdutoId(httpClient, args.produtoId);
      await _testeVendasEstoque(
        client: httpClient,
        report: report,
        produtoId: produtoId,
        n: args.vendas,
        strictEstoque: args.strictEstoque,
      );
    }

    if (!args.skipFiscal) {
      await _testeFiscalCarga(
        client: httpClient,
        report: report,
        paralelo: args.fiscalParalelo,
      );
    }

    if (!args.skipWs) {
      await _testeWebSocketFlood(
        args: args,
        client: httpClient,
        report: report,
      );
    }
  } catch (e, st) {
    report.notes.add('Abortado: $e');
    print('ERRO FATAL: $e');
    print(st);
  } finally {
    httpClient.close();
  }

  report.printFinal();

  final falhasHttp = report.results.where((r) => !r.ok).length;
  final wsRuim = !args.skipWs && report.wsConexoesOk == 0;
  exit(falhasHttp > 0 || wsRuim || report.wsErrosStream > 0 ? 1 : 0);
}
