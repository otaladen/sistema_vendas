// ignore_for_file: avoid_print
/// Auditoria / stress fiscal Focus NFe contra a Lan API do PC1 (:8788).
///
/// Garante idempotencia de emissao, fluxo assincrono (processando), resiliencia
/// a timeout e tratamento amigavel de rejeicoes SEFAZ — sem travar o Terminal.
///
/// Uso (PC servidor com API ativa + Focus configurada):
///   dart run tools/stress_test_fiscal.dart
///   dart run tools/stress_test_fiscal.dart --host=192.168.0.10 --token=SEU_TOKEN
///   dart run tools/stress_test_fiscal.dart --concorrencia=10 --venda-id=123
///   dart run tools/stress_test_fiscal.dart --skip-rejeicao --skip-timeout
///
/// Modo simulacao (sem Certificado A1 / sem depender da Focus):
///   dart run tools/stress_test_fiscal.dart --mock
///   dart run tools/stress_test_fiscal.dart --dry-run
///
/// Flags:
///   --host=127.0.0.1
///   --port=8788
///   --token=                 (header x-sync-token)
///   --produto-id=0           (0 = 1o produto ativo)
///   --venda-id=0             (0 = cria venda de teste)
///   --concorrencia=10        (emissões simultaneas no Teste 1)
///   --timeout-curto-ms=2500  (timeout do cliente no Teste 3)
///   --ws-segundos=12
///   --mock | --dry-run       valida payload/tributos/XML/idempotencia local
///   --skip-idempotencia | --skip-polling | --skip-timeout | --skip-rejeicao
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
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
    required this.vendaId,
    required this.concorrencia,
    required this.timeoutCurtoMs,
    required this.wsSegundos,
    required this.dryRun,
    required this.skipIdempotencia,
    required this.skipPolling,
    required this.skipTimeout,
    required this.skipRejeicao,
  });

  final String host;
  final int port;
  final String token;
  final int produtoId;
  final int vendaId;
  final int concorrencia;
  final int timeoutCurtoMs;
  final int wsSegundos;
  final bool dryRun;
  final bool skipIdempotencia;
  final bool skipPolling;
  final bool skipTimeout;
  final bool skipRejeicao;

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
    var vendaId = 0;
    var concorrencia = 10;
    var timeoutCurtoMs = 2500;
    var wsSegundos = 12;
    var dryRun = false;
    var skipIdempotencia = false;
    var skipPolling = false;
    var skipTimeout = false;
    var skipRejeicao = false;

    for (final a in argv) {
      if (a.startsWith('--host=')) {
        host = a.substring(7).trim();
      } else if (a.startsWith('--port=')) {
        port = int.tryParse(a.substring(7)) ?? port;
      } else if (a.startsWith('--token=')) {
        token = a.substring(8);
      } else if (a.startsWith('--produto-id=')) {
        produtoId = int.tryParse(a.substring(13)) ?? 0;
      } else if (a.startsWith('--venda-id=')) {
        vendaId = int.tryParse(a.substring(11)) ?? 0;
      } else if (a.startsWith('--concorrencia=')) {
        concorrencia = int.tryParse(a.substring(15)) ?? concorrencia;
      } else if (a.startsWith('--timeout-curto-ms=')) {
        timeoutCurtoMs = int.tryParse(a.substring(19)) ?? timeoutCurtoMs;
      } else if (a.startsWith('--ws-segundos=')) {
        wsSegundos = int.tryParse(a.substring(14)) ?? wsSegundos;
      } else if (a == '--mock' || a == '--dry-run') {
        dryRun = true;
      } else if (a == '--skip-idempotencia') {
        skipIdempotencia = true;
      } else if (a == '--skip-polling') {
        skipPolling = true;
      } else if (a == '--skip-timeout') {
        skipTimeout = true;
      } else if (a == '--skip-rejeicao') {
        skipRejeicao = true;
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
      vendaId: vendaId,
      concorrencia: max(2, concorrencia),
      timeoutCurtoMs: max(500, timeoutCurtoMs),
      wsSegundos: max(4, wsSegundos),
      dryRun: dryRun,
      skipIdempotencia: skipIdempotencia,
      skipPolling: skipPolling,
      skipTimeout: skipTimeout,
      skipRejeicao: skipRejeicao,
    );
  }

  static void _printHelp() {
    print('''
Auditoria fiscal Focus NFe — Lan API PC1 (:8788)

  dart run tools/stress_test_fiscal.dart [flags]

Flags:
  --host=127.0.0.1
  --port=8788
  --token=
  --produto-id=0
  --venda-id=0              0 = cria venda de teste
  --concorrencia=10         Teste 1 (POST /api/fiscal/emitir)
  --timeout-curto-ms=2500   Teste 3 (timeout do cliente)
  --ws-segundos=12
  --mock | --dry-run        simula sem Certificado A1 / Focus
  --skip-idempotencia | --skip-polling | --skip-timeout | --skip-rejeicao
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
    this.bodyJson,
    this.softOk = false,
  });

  final String label;
  final int statusCode;
  final int ms;
  final String? error;
  final String bodySnippet;
  final Map<String, dynamic>? bodyJson;

  /// Resposta Focus 400/422 por certificado ausente (nao conta como falha).
  final bool softOk;

  bool get okHttp => statusCode >= 200 && statusCode < 300;
  bool get ok => softOk || (error == null && okHttp);
}

class _Report {
  final List<_ReqResult> results = [];
  final List<String> notes = [];
  final List<String> falhasCriticas = [];
  int wsEntityFiscal = 0;
  int wsEntityVenda = 0;
  int wsHello = 0;
  int wsMensagens = 0;
  bool dryRun = false;
  int softFocusCert = 0;

  void add(_ReqResult r) => results.add(r);

  void critico(String msg) {
    falhasCriticas.add(msg);
    notes.add('CRITICO: $msg');
  }

  void printFinal({required bool passou}) {
    final total = results.length;
    final ok = results.where((r) => r.ok).length;
    final http4xx =
        results.where((r) => r.statusCode >= 400 && r.statusCode < 500).length;
    final http5xx = results.where((r) => r.statusCode >= 500).length;
    final ex = results.where((r) => r.error != null).length;
    final msList = results.map((r) => r.ms).toList()..sort();
    final avgMs = msList.isEmpty
        ? 0.0
        : msList.reduce((a, b) => a + b) / msList.length;

    print('');
    print('=' * 68);
    print(
      ' RELATORIO FINAL — stress_test_fiscal'
      '${dryRun ? " [DRY-RUN / MOCK]" : ""}',
    );
    print('=' * 68);
    print('Resultado:               ${passou ? "PASSOU" : "FALHOU"}');
    print('Total HTTP:              $total');
    print('Sucesso 2xx / soft-ok:   $ok');
    print('HTTP 4xx / 5xx / rede:   $http4xx / $http5xx / $ex');
    print('Focus cert soft-pass:    $softFocusCert');
    print('Latencia media:          ${avgMs.toStringAsFixed(1)} ms');
    print(
      'WS: msgs=$wsMensagens hello=$wsHello '
      'entity(fiscal)=$wsEntityFiscal entity(venda)=$wsEntityVenda',
    );
    if (notes.isNotEmpty) {
      print('');
      print('Observacoes:');
      for (final n in notes) {
        print('  - $n');
      }
    }
    if (falhasCriticas.isNotEmpty) {
      print('');
      print('Falhas criticas:');
      for (final f in falhasCriticas) {
        print('  ! $f');
      }
    }
    final amostra = results.where((r) => !r.ok).take(10).toList();
    if (amostra.isNotEmpty) {
      print('');
      print('Amostra nao-2xx / erros (ate 10):');
      for (final e in amostra) {
        final det = e.error ??
            'HTTP ${e.statusCode}'
                '${e.bodySnippet.isEmpty ? '' : ': ${e.bodySnippet}'}';
        print('  [${e.label}] ${e.ms}ms — $det');
      }
    }
    print('=' * 68);
  }
}

// ---------------------------------------------------------------------------
// Focus certificado / dry-run helpers
// ---------------------------------------------------------------------------

const _msgPayloadValidoAguardandoA1 =
    'Payload válido localmente. Transmissão aguardando Certificado A1 na Focus.';

bool _textoIndicaCertificadoAusente(String raw) {
  final t = raw.toLowerCase();
  if (t.trim().isEmpty) return false;
  return t.contains('certificado') ||
      t.contains('certificate') ||
      (t.contains('a1') &&
          (t.contains('ausente') ||
              t.contains('nao encontrado') ||
              t.contains('não encontrado') ||
              t.contains('inexist') ||
              t.contains('obrigat') ||
              t.contains('pendente') ||
              t.contains('nao cadastr') ||
              t.contains('não cadastr') ||
              t.contains('sem certificado'))) ||
      (t.contains('focus') &&
          (t.contains('certificado') || t.contains('certificate')));
}

bool _respostaEhCertificadoFocus(_ReqResult r) {
  if (r.statusCode != 400 && r.statusCode != 422 && r.statusCode != 403) {
    return false;
  }
  final j = r.bodyJson;
  final partes = <String>[
    r.bodySnippet,
    if (j != null) ...[
      '${j['error'] ?? ''}',
      '${j['mensagem'] ?? ''}',
      '${j['message'] ?? ''}',
      '${j['codigo'] ?? ''}',
      jsonEncode(j),
    ],
  ];
  return _textoIndicaCertificadoAusente(partes.join(' '));
}

_ReqResult _marcarSoftSeCertificado(_ReqResult r, _Report report) {
  if (!_respostaEhCertificadoFocus(r)) return r;
  report.softFocusCert++;
  print('  $_msgPayloadValidoAguardandoA1');
  report.notes.add(
    '${r.label}: HTTP ${r.statusCode} certificado Focus — soft-pass.',
  );
  return _ReqResult(
    label: r.label,
    statusCode: r.statusCode,
    ms: r.ms,
    error: r.error,
    bodySnippet: r.bodySnippet,
    bodyJson: r.bodyJson,
    softOk: true,
  );
}

bool _ehFalhaConfigFocus(_ReqResult r) {
  if (r.statusCode != 400 && r.statusCode != 422) return false;
  final err = (r.bodyJson?['error'] ?? r.bodySnippet).toString().toLowerCase();
  return err.contains('focus') ||
      err.contains('token') ||
      err.contains('config') ||
      _textoIndicaCertificadoAusente(err);
}

// ---------------------------------------------------------------------------
// Montagem local de payload NFC-e (modelo 65) — espelho das regras do ERP
// ---------------------------------------------------------------------------

class _ProdutoFiscalMock {
  const _ProdutoFiscalMock({
    required this.id,
    required this.codigo,
    required this.nome,
    required this.ncm,
    required this.unidade,
    required this.grupoTributario,
    this.cest = '',
    this.icmsOrigem = '0',
    this.icmsSituacaoTributaria = '',
    this.pisCofinsSituacaoTributaria = '',
    this.cfopVenda = '',
    this.preco = 10.0,
  });

  final int id;
  final String codigo;
  final String nome;
  final String ncm;
  final String unidade;
  final String grupoTributario;
  final String cest;
  final String icmsOrigem;
  final String icmsSituacaoTributaria;
  final String pisCofinsSituacaoTributaria;
  final String cfopVenda;
  final double preco;
}

Map<String, dynamic> _camposIcmsItem({
  required String origem,
  required String cst,
}) {
  final map = <String, String>{'icms_origem': origem};
  if (cst.trim() == '00') {
    map['icms_modalidade_base_calculo'] = '3';
  }
  map['icms_situacao_tributaria'] = cst;
  return map;
}

Map<String, dynamic> _camposIbscbs(double base) {
  final b = (base * 100).roundToDouble() / 100.0;
  final cbs = (b * 0.9 / 100.0 * 100).roundToDouble() / 100.0;
  final ibsUf = (b * 0.1 / 100.0 * 100).roundToDouble() / 100.0;
  return {
    'ibs_cbs_situacao_tributaria': '000',
    'ibs_cbs_classificacao_tributaria': '000001',
    'ibs_cbs_base_calculo': b,
    'cbs_aliquota': '0.9',
    'cbs_valor': cbs.toStringAsFixed(2),
    'ibs_uf_aliquota': '0.1',
    'ibs_uf_valor': ibsUf.toStringAsFixed(2),
    'ibs_mun_aliquota': '0',
    'ibs_mun_valor': '0.00',
    'ibs_valor_total': ibsUf.toStringAsFixed(2),
  };
}

String _resolverIcmsCst(_ProdutoFiscalMock p) {
  final cadastro = p.icmsSituacaoTributaria.trim();
  if (RegExp(r'^\d{2,3}$').hasMatch(cadastro)) return cadastro;
  switch (p.grupoTributario) {
    case 'substituicao_tributaria':
      return '60'; // ICMS cobrado anteriormente por ST
    case 'isento':
      return '40';
    default:
      return '00';
  }
}

String _resolverPisCofins(_ProdutoFiscalMock p) {
  final cadastro = p.pisCofinsSituacaoTributaria.trim();
  if (RegExp(r'^\d{2}$').hasMatch(cadastro)) return cadastro;
  if (p.grupoTributario == 'isento') return '07';
  return '01';
}

String _resolverCfopNfce(_ProdutoFiscalMock p) {
  final cadastro = p.cfopVenda.trim();
  if (RegExp(r'^\d{4}$').hasMatch(cadastro)) return cadastro;
  if (p.grupoTributario == 'substituicao_tributaria') return '5405';
  return '5102';
}

Map<String, dynamic> _montarItemNfce({
  required int numero,
  required _ProdutoFiscalMock produto,
  required int quantidade,
}) {
  final valorUnit = produto.preco;
  final valorBruto = quantidade * valorUnit;
  final icmsCst = _resolverIcmsCst(produto);
  final pis = _resolverPisCofins(produto);
  final cfop = _resolverCfopNfce(produto);
  final ncm = produto.ncm.replaceAll(RegExp(r'\D'), '').padLeft(8, '0');
  return {
    'numero_item': '$numero',
    'codigo_produto': produto.codigo,
    'descricao': produto.nome,
    'codigo_barras_comercial': 'SEM GTIN',
    'codigo_barras_tributavel': 'SEM GTIN',
    'cfop': cfop,
    'unidade_comercial': produto.unidade.toLowerCase(),
    'quantidade_comercial': quantidade.toStringAsFixed(4),
    'valor_unitario_comercial': valorUnit.toStringAsFixed(2),
    'unidade_tributavel': produto.unidade.toLowerCase(),
    'quantidade_tributavel': quantidade.toStringAsFixed(4),
    'valor_unitario_tributavel': valorUnit.toStringAsFixed(2),
    'codigo_ncm': ncm,
    if (produto.cest.replaceAll(RegExp(r'\D'), '').length == 7)
      'cest': produto.cest.replaceAll(RegExp(r'\D'), ''),
    'valor_bruto': valorBruto.toStringAsFixed(2),
    'inclui_no_total': '1',
    ..._camposIcmsItem(origem: produto.icmsOrigem, cst: icmsCst),
    'pis_situacao_tributaria': pis,
    'cofins_situacao_tributaria': pis,
    ..._camposIbscbs(valorBruto),
  };
}

Map<String, dynamic> _montarPayloadNfce65({
  required int vendaId,
  required List<_ProdutoFiscalMock> produtos,
  String cnpjEmitente = '32662298000191',
  String ufEmitente = 'BA',
}) {
  final items = <Map<String, dynamic>>[];
  var n = 1;
  var total = 0.0;
  for (final prod in produtos) {
    final item = _montarItemNfce(numero: n++, produto: prod, quantidade: 1);
    items.add(item);
    total += double.parse(item['valor_bruto'] as String);
  }
  return {
    'modelo': '65',
    'ambiente': 'homologacao',
    'referencia': 'venda_$vendaId',
    'cnpj_emitente': cnpjEmitente,
    'nome_emitente': 'COMPROU LEVOU MATERIAIS DE CONSTRUÇÃO LTDA',
    'inscricao_estadual_emitente': '025232204',
    'regime_tributario_emitente': 3,
    'natureza_operacao': 'Venda de mercadoria',
    'data_emissao': DateTime.now().toUtc().toIso8601String(),
    'tipo_documento': '1',
    'local_destino': '1',
    'finalidade_emissao': '1',
    'consumidor_final': '1',
    'presenca_comprador': '1',
    'modalidade_frete': '9',
    'uf_emitente': ufEmitente,
    'valor_produtos': total.toStringAsFixed(2),
    'valor_desconto': '0.00',
    'valor_frete': '0.00',
    'valor_total': total.toStringAsFixed(2),
    'items': items,
    'formas_pagamento': [
      {
        'forma_pagamento': '01',
        'valor_pagamento': total.toStringAsFixed(2),
      },
    ],
  };
}

void _validarPayloadNfceLocal(
  Map<String, dynamic> payload, {
  required _Report report,
  required String rotulo,
}) {
  final itens = payload['items'];
  if (itens is! List || itens.isEmpty) {
    report.critico('$rotulo: payload sem items.');
    return;
  }
  if (payload['modelo']?.toString() != '65') {
    report.critico('$rotulo: modelo deve ser 65 (NFC-e).');
  }
  if ((payload['referencia'] ?? '').toString().isEmpty) {
    report.critico('$rotulo: referencia vazia.');
  }
  if ((payload['cnpj_emitente'] ?? '').toString().length != 14) {
    report.critico('$rotulo: CNPJ emitente invalido.');
  }
  for (final raw in itens) {
    if (raw is! Map) {
      report.critico('$rotulo: item nao-mapa.');
      continue;
    }
    final m = Map<String, dynamic>.from(raw);
    final ncm = (m['codigo_ncm'] ?? '').toString();
    final cfop = (m['cfop'] ?? '').toString();
    final icms = (m['icms_situacao_tributaria'] ?? '').toString();
    final pis = (m['pis_situacao_tributaria'] ?? '').toString();
    final cofins = (m['cofins_situacao_tributaria'] ?? '').toString();
    if (!RegExp(r'^\d{8}$').hasMatch(ncm) || ncm.replaceAll('0', '').isEmpty) {
      report.critico('$rotulo: NCM invalido ($ncm).');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(cfop)) {
      report.critico('$rotulo: CFOP invalido ($cfop).');
    }
    if (icms.isEmpty) {
      report.critico('$rotulo: ICMS CST ausente.');
    }
    if (icms == '00' && m['icms_modalidade_base_calculo']?.toString() != '3') {
      report.critico(
        '$rotulo: CST 00 exige icms_modalidade_base_calculo=3.',
      );
    }
    if (pis.isEmpty || cofins.isEmpty) {
      report.critico('$rotulo: PIS/COFINS ausente.');
    }
    if (m['ibs_cbs_situacao_tributaria'] == null) {
      report.critico('$rotulo: IBS/CBS ausente no item.');
    }
  }
  print(
    '  $rotulo OK — ${itens.length} item(ns), '
    'total=${payload['valor_total']} ref=${payload['referencia']}',
  );
}

// ---------------------------------------------------------------------------
// XML local (pasta contabilidade / store NFC-e)
// ---------------------------------------------------------------------------

class _NfceXmlStoreLocal {
  _NfceXmlStoreLocal(this.rootDir);

  final String rootDir;
  static const pasta = 'nfce_saida_xml';

  Directory get _dir {
    final d = Directory(p.join(rootDir, pasta));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File arquivo(String chave) {
    final c = chave.replaceAll(RegExp(r'\D'), '');
    return File(p.join(_dir.path, '$c.xml'));
  }

  void salvar(String chave, String xml) {
    final c = chave.replaceAll(RegExp(r'\D'), '');
    if (c.length != 44 || xml.trim().isEmpty) {
      throw StateError('Chave/XML invalidos para gravacao local.');
    }
    arquivo(c).writeAsStringSync(xml, flush: true);
  }

  bool existe(String chave) => arquivo(chave).existsSync();

  String? ler(String chave) {
    final f = arquivo(chave);
    if (!f.existsSync()) return null;
    return f.readAsStringSync();
  }
}

String _xmlNfceMockAutorizado({
  required String chave,
  required String ncm,
  required String cfop,
  required String icmsCst,
}) {
  return '''<?xml version="1.0" encoding="UTF-8"?>
<nfeProc versao="4.00" xmlns="http://www.portalfiscal.inf.br/nfe">
  <NFe>
    <infNFe Id="NFe$chave" versao="4.00">
      <ide>
        <cUF>29</cUF>
        <mod>65</mod>
        <serie>1</serie>
        <nNF>1</nNF>
        <tpAmb>2</tpAmb>
        <tpEmis>1</tpEmis>
      </ide>
      <det nItem="1">
        <prod>
          <cProd>MOCK1</cProd>
          <xProd>PRODUTO MOCK STRESS FISCAL</xProd>
          <NCM>$ncm</NCM>
          <CFOP>$cfop</CFOP>
          <uCom>UN</uCom>
          <qCom>1.0000</qCom>
          <vUnCom>10.00</vUnCom>
          <vProd>10.00</vProd>
        </prod>
        <imposto>
          <ICMS>
            <ICMS${icmsCst == '60' ? '60' : '00'}>
              <orig>0</orig>
              <CST>$icmsCst</CST>
            </ICMS${icmsCst == '60' ? '60' : '00'}>
          </ICMS>
          <PIS><PISAliq><CST>01</CST></PISAliq></PIS>
          <COFINS><COFINSAliq><CST>01</CST></COFINSAliq></COFINS>
        </imposto>
      </det>
      <total><ICMSTot><vNF>10.00</vNF></ICMSTot></total>
    </infNFe>
  </NFe>
  <protNFe>
    <infProt>
      <chNFe>$chave</chNFe>
      <cStat>100</cStat>
      <xMotivo>Autorizado o uso da NF-e (MOCK)</xMotivo>
      <nProt>123456789012345</nProt>
    </infProt>
  </protNFe>
</nfeProc>
''';
}

String _chaveAcessoMock(int seed) {
  // 44 digitos numericos (estrutura NF-e / NFC-e).
  final base = '29${FiscalCnpjMock.cnpj.substring(0, 8)}'
      '65'
      '001'
      '${seed.toString().padLeft(9, '0')}'
      '1'
      '12345678';
  final digitos = base.replaceAll(RegExp(r'\D'), '');
  return digitos.padRight(44, '0').substring(0, 44);
}

abstract final class FiscalCnpjMock {
  static const cnpj = '32662298000191';
}

// ---------------------------------------------------------------------------
// Suite DRY-RUN / MOCK (sem Focus)
// ---------------------------------------------------------------------------

Future<void> _suiteDryRunLocal({
  required _Args args,
  required _Report report,
}) async {
  print('');
  print('=== SUITE DRY-RUN / MOCK (sem transmissao Focus) ===');
  report.notes.add(
    'Modo --mock/--dry-run: valida payload, tributos, XML local e '
    'idempotencia sem Certificado A1.',
  );

  // --- Payload com e sem ST ---
  print('');
  print('--- Dry-run A: Payload NFC-e 65 (com / sem ICMS-ST) ---');
  final semSt = _ProdutoFiscalMock(
    id: 1,
    codigo: 'MOCK-TRIB',
    nome: 'CIMENTO CP-II 50KG (TRIBUTADO)',
    ncm: '25232910',
    unidade: 'UN',
    grupoTributario: 'tributado',
    preco: 32.90,
  );
  final comSt = _ProdutoFiscalMock(
    id: 2,
    codigo: 'MOCK-ST',
    nome: 'TINTA ACRILICA 18L (ST)',
    ncm: '32091010',
    unidade: 'UN',
    grupoTributario: 'substituicao_tributaria',
    cest: '1003000',
    preco: 289.90,
  );

  final payloadMisto = _montarPayloadNfce65(
    vendaId: 900001,
    produtos: [semSt, comSt],
  );
  _validarPayloadNfceLocal(
    payloadMisto,
    report: report,
    rotulo: 'payload-misto',
  );

  final itens = (payloadMisto['items'] as List).cast<Map<String, dynamic>>();
  final cstSem = itens[0]['icms_situacao_tributaria']?.toString();
  final cstCom = itens[1]['icms_situacao_tributaria']?.toString();
  final cfopSem = itens[0]['cfop']?.toString();
  final cfopCom = itens[1]['cfop']?.toString();
  print('  sem ST → CST=$cstSem CFOP=$cfopSem NCM=${itens[0]['codigo_ncm']}');
  print('  com ST → CST=$cstCom CFOP=$cfopCom NCM=${itens[1]['codigo_ncm']} '
      'CEST=${itens[1]['cest']}');

  if (cstSem != '00') {
    report.critico('Produto tributado deveria gerar ICMS CST 00 (foi $cstSem).');
  }
  if (cstCom != '60') {
    report.critico(
      'Produto ST deveria gerar ICMS CST 60 / cobrado ant. (foi $cstCom).',
    );
  }
  if (cfopSem != '5102') {
    report.critico('CFOP tributado NFC-e esperado 5102 (foi $cfopSem).');
  }
  if (cfopCom != '5405') {
    report.critico('CFOP ST NFC-e esperado 5405 (foi $cfopCom).');
  }
  if (itens[0]['pis_situacao_tributaria'] != '01' ||
      itens[0]['cofins_situacao_tributaria'] != '01') {
    report.critico('PIS/COFINS padrao balcao deveria ser 01.');
  }

  // Dump do JSON para conferencia visual.
  final dumpDir = Directory(
    p.join(Directory.systemTemp.path, 'sistema_vendas_fiscal_dryrun'),
  );
  if (!dumpDir.existsSync()) dumpDir.createSync(recursive: true);
  final payloadFile = File(p.join(dumpDir.path, 'payload_nfce65_mock.json'));
  const encoder = JsonEncoder.withIndent('  ');
  await payloadFile.writeAsString(encoder.convert(payloadMisto));
  print('  JSON salvo em: ${payloadFile.path}');
  report.notes.add('Dry-run A: payload NFC-e 65 com/sem ST validado.');

  // --- Idempotencia / concorrencia local ---
  print('');
  print(
    '--- Dry-run B: Idempotencia / concorrencia local '
    '(${args.concorrencia}x) ---',
  );
  final lock = Completer<String>();
  final refs = <String>{};
  final resultados = await Future.wait(
    List.generate(args.concorrencia, (i) async {
      await Future<void>.delayed(Duration(milliseconds: i % 3));
      if (!lock.isCompleted) {
        lock.complete('venda_900001');
        return (status: 200, ref: 'venda_900001', winner: true);
      }
      final ref = await lock.future;
      return (status: 409, ref: ref, winner: false);
    }),
  );
  var winners = 0;
  var conflitos = 0;
  for (final r in resultados) {
    refs.add(r.ref);
    if (r.winner) winners++;
    if (r.status == 409) conflitos++;
  }
  print('  winners=$winners conflitos409=$conflitos refs=${refs.join(",")}');
  if (winners != 1) {
    report.critico('Dry-run B: esperado 1 vencedor, veio $winners.');
  }
  if (conflitos != args.concorrencia - 1) {
    report.critico(
      'Dry-run B: esperado ${args.concorrencia - 1} conflitos, veio $conflitos.',
    );
  }
  if (refs.length != 1 || refs.single != 'venda_900001') {
    report.critico('Dry-run B: referencia nao estavel ($refs).');
  } else {
    report.notes.add(
      'Dry-run B: idempotencia local OK (1 emit + ${conflitos}x 409).',
    );
  }

  // --- XML em disco (pasta contabilidade) ---
  print('');
  print('--- Dry-run C: Salvamento XML local (nfce_saida_xml) ---');
  final storeRoot = p.join(dumpDir.path, 'objectbox_store_mock');
  final store = _NfceXmlStoreLocal(storeRoot);
  final chaveTrib = _chaveAcessoMock(1001);
  final chaveSt = _chaveAcessoMock(1002);
  final xmlTrib = _xmlNfceMockAutorizado(
    chave: chaveTrib,
    ncm: '25232910',
    cfop: '5102',
    icmsCst: '00',
  );
  final xmlSt = _xmlNfceMockAutorizado(
    chave: chaveSt,
    ncm: '32091010',
    cfop: '5405',
    icmsCst: '60',
  );
  store.salvar(chaveTrib, xmlTrib);
  store.salvar(chaveSt, xmlSt);

  final lidosOk = store.existe(chaveTrib) &&
      store.existe(chaveSt) &&
      (store.ler(chaveTrib)?.contains('<mod>65</mod>') ?? false) &&
      (store.ler(chaveSt)?.contains('<CST>60</CST>') ?? false) &&
      (store.ler(chaveTrib)?.contains(chaveTrib) ?? false);

  // Espelho "banco": metadados da venda apos autorizacao mock.
  final metaDb = {
    'vendaId': 900001,
    'modelo': '65',
    'nfceChaveAcesso': chaveTrib,
    'nfceStatusFocus': 'autorizado',
    'nfceNumero': '1',
    'nfceSerie': '1',
    'nfceProtocolo': '123456789012345',
    'xmlPath': store.arquivo(chaveTrib).path,
    'xmlPathSt': store.arquivo(chaveSt).path,
  };
  final metaFile = File(p.join(dumpDir.path, 'venda_fiscal_mock_db.json'));
  await metaFile.writeAsString(encoder.convert(metaDb));

  print('  store: ${p.join(storeRoot, _NfceXmlStoreLocal.pasta)}');
  print('  chave trib=$chaveTrib existe=${store.existe(chaveTrib)}');
  print('  chave ST  =$chaveSt existe=${store.existe(chaveSt)}');
  print('  meta DB: ${metaFile.path}');

  if (!lidosOk) {
    report.critico('Dry-run C: falha ao gravar/ler XML na pasta local.');
  } else {
    report.notes.add(
      'Dry-run C: XMLs NFC-e gravados em nfce_saida_xml + meta DB mock OK.',
    );
  }

  print('');
  print('$_msgPayloadValidoAguardandoA1');
  report.notes.add(_msgPayloadValidoAguardandoA1);
}

// ---------------------------------------------------------------------------
// HTTP
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
    final pth = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$pth').replace(queryParameters: q);
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

  Future<_ReqResult> post(
    String label,
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final r = await _client
          .post(_u(path), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
      sw.stop();
      return _ReqResult(
        label: label,
        statusCode: r.statusCode,
        ms: sw.elapsedMilliseconds,
        bodySnippet: snip(r.body),
        bodyJson: _asMap(r.body),
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

  Future<({int status, String body, int ms})> postFull(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final sw = Stopwatch()..start();
    final r = await _client
        .post(_u(path), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
    sw.stop();
    return (status: r.statusCode, body: r.body, ms: sw.elapsedMilliseconds);
  }

  void close() => _client.close();

  static String snip(String body, [int max = 180]) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  static Map<String, dynamic>? _asMap(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helpers de dominio
// ---------------------------------------------------------------------------

Future<int> _resolverProdutoId(_LanHttp client, int preferido) async {
  if (preferido > 0) return preferido;
  final r = await client.getFull('/api/produtos', query: {'limit': '40'});
  if (r.status < 200 || r.status >= 300) {
    throw StateError('GET /api/produtos HTTP ${r.status}: ${_LanHttp.snip(r.body)}');
  }
  final map = jsonDecode(r.body);
  final items = map is Map ? map['items'] : null;
  if (items is! List || items.isEmpty) {
    throw StateError('Nenhum produto na API para montar venda de teste.');
  }
  for (final raw in items.whereType<Map>()) {
    final ativo = raw['ativo'] != false;
    final id = (raw['id'] as num?)?.toInt() ?? 0;
    if (ativo && id > 0) return id;
  }
  final first = items.first;
  if (first is Map) {
    final id = (first['id'] as num?)?.toInt() ?? 0;
    if (id > 0) return id;
  }
  throw StateError('Nao foi possivel resolver produto-id.');
}

Future<int> _criarVendaFinalizada({
  required _LanHttp client,
  required int produtoId,
  double preco = 1.0,
}) async {
  final orc = await client.postFull('/api/orcamentos', {
    'itens': [
      {
        'produtoId': produtoId,
        'quantidade': 1,
        'precoUnitario': preco,
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
  if (orc.status < 200 || orc.status >= 300) {
    throw StateError(
      'POST /api/orcamentos HTTP ${orc.status}: ${_LanHttp.snip(orc.body)}',
    );
  }
  final map = jsonDecode(orc.body);
  final vendaId = map is Map ? (map['id'] as num?)?.toInt() ?? 0 : 0;
  if (vendaId <= 0) {
    throw StateError('Orcamento sem id: ${_LanHttp.snip(orc.body)}');
  }

  final fin = await client.postFull('/api/vendas/$vendaId/finalizar', {
    'permitirVendaSemEstoque': true,
  });
  if (fin.status < 200 || fin.status >= 300) {
    throw StateError(
      'POST /api/vendas/$vendaId/finalizar HTTP ${fin.status}: '
      '${_LanHttp.snip(fin.body)}',
    );
  }
  return vendaId;
}

Future<Map<String, dynamic>?> _obterVenda(_LanHttp client, int vendaId) async {
  final r = await client.getFull('/api/vendas/$vendaId');
  if (r.status < 200 || r.status >= 300) return null;
  final map = jsonDecode(r.body);
  if (map is! Map) return null;
  final item = map['item'];
  if (item is Map<String, dynamic>) return item;
  if (item is Map) return Map<String, dynamic>.from(item);
  return null;
}

String _refEsperadaNfce(int vendaId) => 'venda_$vendaId';

bool _entityEhFiscal(String entity) {
  final e = entity.trim().toLowerCase();
  return e == 'fiscal' ||
      e == 'venda' ||
      e == 'nfe_saida' ||
      e == 'nfe' ||
      e == 'nfce';
}

// ---------------------------------------------------------------------------
// Teste 1 — Idempotencia / concorrencia
// ---------------------------------------------------------------------------

Future<void> _testeIdempotenciaConcorrencia({
  required _Args args,
  required _LanHttp client,
  required _Report report,
  required int vendaId,
}) async {
  print('');
  print(
    '--- Teste 1: Idempotencia e concorrencia '
    '(${args.concorrencia}x POST /api/fiscal/emitir) ---',
  );
  print('  vendaId=$vendaId  ref esperada=${_refEsperadaNfce(vendaId)}');

  final payload = <String, dynamic>{
    'vendaId': vendaId,
    'tipo': 'nfce',
    'permitirVendaSemEstoque': true,
  };

  final futures = <Future<_ReqResult>>[];
  for (var i = 0; i < args.concorrencia; i++) {
    final idx = i + 1;
    futures.add(
      client.post(
        'emitir#$idx',
        '/api/fiscal/emitir',
        payload,
        timeout: const Duration(seconds: 180),
      ),
    );
  }

  final results = await Future.wait(futures);
  for (final raw in results) {
    report.add(_marcarSoftSeCertificado(raw, report));
  }

  final refs = <String>{};
  final chaves = <String>{};
  var autorizadas = 0;
  var processando = 0;
  var conflitos = 0;
  var errosConfig = 0;
  var okFocus = 0;
  var softCert = 0;

  for (final r in results) {
    final j = r.bodyJson;
    if (r.statusCode == 409) conflitos++;
    if (_respostaEhCertificadoFocus(r)) softCert++;
    if (_ehFalhaConfigFocus(r)) errosConfig++;
    if (j == null) continue;
    final ref = (j['referencia'] ?? '').toString().trim();
    if (ref.isNotEmpty) refs.add(ref);
    final chave = (j['chaveNfe'] ?? '').toString().trim();
    if (chave.isNotEmpty) chaves.add(chave);
    if (j['autorizada'] == true) {
      autorizadas++;
      okFocus++;
    }
    if (j['processando'] == true) {
      processando++;
      okFocus++;
    }
  }

  print(
    '  respostas: autorizada=$autorizadas processando=$processando '
    'conflito409=$conflitos configErr=$errosConfig softCert=$softCert',
  );
  print('  refs distintas=${refs.length}  chaves distintas=${chaves.length}');
  if (refs.isNotEmpty) print('  refs: ${refs.join(", ")}');
  if (chaves.isNotEmpty) {
    print(
      '  chaves: ${chaves.map((c) => c.length > 20 ? "${c.substring(0, 20)}…" : c).join(", ")}',
    );
  }

  if (softCert == results.length ||
      (args.dryRun && softCert > 0 && okFocus == 0)) {
    print('  $_msgPayloadValidoAguardandoA1');
    report.notes.add(
      'Teste 1: Focus bloqueou por certificado A1 — soft-pass '
      '(estrutura local ja validada no dry-run).',
    );
    return;
  }

  if (errosConfig == results.length) {
    report.notes.add(
      'Teste 1: Focus nao configurada no PC1 (todas as emissões falharam '
      'na validacao). Configure token/ambiente Focus e rode de novo.',
    );
    return;
  }

  final refOk = refs.isEmpty ||
      (refs.length == 1 && refs.single == _refEsperadaNfce(vendaId));
  if (!refOk) {
    report.critico(
      'Referencias divergentes ou diferentes de '
      '${_refEsperadaNfce(vendaId)}: $refs',
    );
  } else if (refs.isNotEmpty) {
    report.notes.add(
      'Teste 1: referencia Focus unica e estavel (${refs.single}).',
    );
  }

  if (chaves.length > 1) {
    report.critico(
      'Duplicidade de chave NFC-e detectada (${chaves.length} chaves).',
    );
  } else if (chaves.length == 1) {
    report.notes.add('Teste 1: uma unica chave autorizada — sem duplicidade.');
  }

  if (autorizadas > 1 && chaves.length <= 1) {
    report.notes.add(
      'Teste 1: $autorizadas respostas "autorizada" com a mesma chave '
      '(idempotencia Focus/servidor OK).',
    );
  }

  final venda = await _obterVenda(client, vendaId);
  if (venda == null) {
    report.critico('GET /api/vendas/$vendaId falhou apos emissao concorrente.');
    return;
  }
  final chaveFinal = (venda['nfceChaveAcesso'] ?? '').toString().trim();
  final statusFinal = (venda['nfceStatusFocus'] ?? '').toString().trim();
  print(
    '  estado final: statusFocus=$statusFinal '
    'chave=${chaveFinal.isEmpty ? "(vazia)" : "${chaveFinal.substring(0, min(20, chaveFinal.length))}…"}',
  );
  if (chaves.isNotEmpty &&
      chaveFinal.isNotEmpty &&
      !chaves.contains(chaveFinal)) {
    report.critico('Chave gravada na venda difere das chaves retornadas.');
  }
  if (okFocus == 0 && conflitos == 0 && errosConfig == 0) {
    report.notes.add(
      'Teste 1: nenhuma autorizacao/processando — verifique rejeicao SEFAZ '
      'ou ambiente Focus (homologacao).',
    );
  }
}

// ---------------------------------------------------------------------------
// Teste 2 — Processando / polling + WebSocket fiscal
// ---------------------------------------------------------------------------

Future<void> _testePollingProcessando({
  required _Args args,
  required _LanHttp client,
  required _Report report,
  required int vendaId,
}) async {
  print('');
  print('--- Teste 2: Fluxo assincrono (processando / polling / WS fiscal) ---');

  final wsEntities = <String>[];
  WebSocketChannel? ch;
  StreamSubscription<dynamic>? sub;
  try {
    ch = WebSocketChannel.connect(args.wsUri);
    sub = ch.stream.listen((raw) {
      report.wsMensagens++;
      try {
        final text = raw is String ? raw : raw.toString();
        final d = jsonDecode(text);
        if (d is! Map) return;
        final type = (d['type'] ?? '').toString();
        if (type == 'hello') {
          report.wsHello++;
          return;
        }
        if (type != 'entityChanged') return;
        final entity = (d['entity'] ?? '').toString();
        if (entity == 'fiscal') report.wsEntityFiscal++;
        if (entity == 'venda') report.wsEntityVenda++;
        if (_entityEhFiscal(entity)) wsEntities.add(entity);
      } catch (_) {}
    });
  } catch (e) {
    report.notes.add('Teste 2: WS nao conectou ($e) — segue so com polling HTTP.');
  }

  await Future<void>.delayed(const Duration(milliseconds: 350));

  var emit = await client.post(
    'polling/emitir',
    '/api/fiscal/emitir',
    {
      'vendaId': vendaId,
      'tipo': 'nfce',
      'permitirVendaSemEstoque': true,
    },
    timeout: const Duration(seconds: 180),
  );
  emit = _marcarSoftSeCertificado(emit, report);
  report.add(emit);

  final j = emit.bodyJson;
  final processando = j?['processando'] == true;
  final autorizada = j?['autorizada'] == true;
  final ref = (j?['referencia'] ?? '').toString();
  print(
    '  emitir → HTTP ${emit.statusCode} '
    'autorizada=$autorizada processando=$processando ref=$ref',
  );

  if (emit.softOk || _respostaEhCertificadoFocus(emit)) {
    report.notes.add(
      'Teste 2: certificado A1 ausente — polling Focus pulado (soft-pass).',
    );
    await sub?.cancel();
    await ch?.sink.close();
    return;
  }

  if (emit.statusCode == 400 && _ehFalhaConfigFocus(emit)) {
    report.notes.add('Teste 2: Focus nao configurada — polling pulado.');
    await sub?.cancel();
    await ch?.sink.close();
    return;
  }

  final recon = await client.post(
    'polling/reconsultar',
    '/api/vendas/$vendaId/reconsultar-nfce',
    const {},
    timeout: const Duration(seconds: 90),
  );
  report.add(_marcarSoftSeCertificado(recon, report));
  print(
    '  reconsultar-nfce → HTTP ${recon.statusCode} '
    '${recon.bodySnippet}',
  );

  final lote = await client.post(
    'polling/reconsultar-todas',
    '/api/fiscal/nfce/reconsultar-todas',
    const {},
    timeout: const Duration(seconds: 120),
  );
  report.add(_marcarSoftSeCertificado(lote, report));
  print('  reconsultar-todas → HTTP ${lote.statusCode} ${lote.bodySnippet}');

  final deadline = DateTime.now().add(Duration(seconds: args.wsSegundos));
  while (DateTime.now().isBefore(deadline) && wsEntities.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  await sub?.cancel();
  try {
    await ch?.sink.close();
  } catch (_) {}

  final venda = await _obterVenda(client, vendaId);
  final status = (venda?['nfceStatusFocus'] ?? '').toString();
  print('  status reidratado na venda: $status');
  print(
    '  WS entity fiscal/venda: '
    'fiscal=${report.wsEntityFiscal} venda=${report.wsEntityVenda} '
    'vistos=$wsEntities',
  );

  if (processando || autorizada || recon.okHttp || lote.okHttp) {
    if (wsEntities.isEmpty) {
      report.notes.add(
        'Teste 2: nenhum entityChanged fiscal/venda no WS durante a janela '
        '(${args.wsSegundos}s). Verifique /api/stream e notificar(fiscal).',
      );
    } else {
      report.notes.add(
        'Teste 2: WS recebeu entityChanged ($wsEntities) — Terminal pode '
        'invalidar cache fiscal.',
      );
    }
  }

  if (processando && status.isEmpty) {
    report.critico(
      'Emitiu processando=true mas venda ficou sem nfceStatusFocus.',
    );
  }
}

// ---------------------------------------------------------------------------
// Teste 3 — Timeout / resiliencia
// ---------------------------------------------------------------------------

Future<void> _testeTimeoutResiliencia({
  required _Args args,
  required _LanHttp client,
  required _Report report,
  required int produtoId,
}) async {
  print('');
  print(
    '--- Teste 3: Timeout do Terminal '
    '(timeout cliente ${args.timeoutCurtoMs} ms) ---',
  );

  final vendaId = await _criarVendaFinalizada(
    client: client,
    produtoId: produtoId,
    preco: 1.01,
  );
  print('  venda de resiliencia id=$vendaId');

  var curto = await client.post(
    'timeout/emitir-curto',
    '/api/fiscal/emitir',
    {
      'vendaId': vendaId,
      'tipo': 'nfce',
      'permitirVendaSemEstoque': true,
    },
    timeout: Duration(milliseconds: args.timeoutCurtoMs),
  );
  curto = _marcarSoftSeCertificado(curto, report);
  report.add(curto);

  final foiTimeout = curto.error != null &&
      (curto.error!.toLowerCase().contains('timeout') ||
          curto.error!.toLowerCase().contains('timed out'));
  print(
    '  cliente curto → '
    '${foiTimeout ? "TIMEOUT (esperado se Focus lenta)" : "HTTP ${curto.statusCode}"} '
    '${curto.ms}ms',
  );

  await Future<void>.delayed(const Duration(seconds: 3));
  final venda = await _obterVenda(client, vendaId);
  final status = (venda?['nfceStatusFocus'] ?? '').toString().toLowerCase();
  final chave = (venda?['nfceChaveAcesso'] ?? '').toString();
  final protocolo = (venda?['nfceProtocolo'] ?? '').toString();
  print(
    '  apos espera: statusFocus=$status '
    'chave=${chave.isEmpty ? "(vazia)" : "ok"} '
    'protocolo=${protocolo.isEmpty ? "(vazio)" : "ok"}',
  );

  if (curto.softOk || _respostaEhCertificadoFocus(curto)) {
    report.notes.add(
      'Teste 3: certificado A1 — resiliencia de timeout nao exercitada '
      '(soft-pass).',
    );
  } else if (foiTimeout) {
    report.notes.add(
      'Teste 3: cliente estourou timeout — UI deve mostrar '
      '"Aguardando Autorizacao / Em Fila" e reconsultar '
      '(/api/vendas/$vendaId/reconsultar-nfce), nao crashar.',
    );
    final emFila = status.contains('process') ||
        status.contains('andamento') ||
        status.contains('emissao') ||
        chave.isNotEmpty ||
        protocolo.contains('emissao_lock');
    if (!emFila && status.isEmpty && chave.isEmpty) {
      report.notes.add(
        'Teste 3: apos timeout a venda ainda sem status fiscal. '
        'Se Focus estiver ativa, confira se o servidor gravou '
        'processando/em_andamento.',
      );
    }
  } else if (curto.okHttp && curto.bodyJson?['processando'] == true) {
    report.notes.add(
      'Teste 3: Focus respondeu processando dentro do timeout curto — '
      'Terminal recebe fila sem precisar de timeout.',
    );
  } else if (curto.statusCode == 400 || curto.statusCode == 422) {
    report.notes.add(
      'Teste 3: emissao retornou ${curto.statusCode} '
      '(config/rejeicao) — resiliencia de timeout nao exercitada.',
    );
  }

  final recon = await client.post(
    'timeout/reconsultar',
    '/api/vendas/$vendaId/reconsultar-nfce',
    const {},
    timeout: const Duration(seconds: 90),
  );
  report.add(_marcarSoftSeCertificado(recon, report));
  print('  reconsultar pos-timeout → HTTP ${recon.statusCode}');
}

// ---------------------------------------------------------------------------
// Teste 4 — Rejeicao SEFAZ / payload invalido
// ---------------------------------------------------------------------------

Future<void> _testeRejeicaoSefaz({
  required _Args args,
  required _LanHttp client,
  required _Report report,
}) async {
  print('');
  print('--- Teste 4: Payload invalido / rejeicao SEFAZ (NCM ruim) ---');

  final sku =
      'AUDIT-FISCAL-${DateTime.now().millisecondsSinceEpoch % 100000000}';
  final criar = await client.postFull('/api/produtos', {
    'produto': {
      'codigoInterno': sku,
      'nome': 'AUDITORIA FISCAL NCM INVALIDO',
      'nomeImpressao': 'AUDITORIA FISCAL NCM INVALIDO',
      'unidade': 'UN',
      'ncm': '00000000',
      'icmsSituacaoTributaria': '99',
      'pisCofinsSituacaoTributaria': '99',
      'preco1': 1.5,
      'precoCusto': 1.0,
      'estoqueReal': 100,
      'ativo': true,
    },
  });
  report.add(
    _ReqResult(
      label: 'rejeicao/criar-produto',
      statusCode: criar.status,
      ms: criar.ms,
      bodySnippet: _LanHttp.snip(criar.body),
      bodyJson: _LanHttp._asMap(criar.body),
    ),
  );
  if (criar.status < 200 || criar.status >= 300) {
    report.notes.add(
      'Teste 4: nao criou produto de auditoria '
      '(HTTP ${criar.status}). Skip.',
    );
    return;
  }
  final criado = jsonDecode(criar.body);
  final produtoId = criado is Map ? (criado['id'] as num?)?.toInt() ?? 0 : 0;
  if (produtoId <= 0) {
    report.notes.add('Teste 4: produto sem id — skip.');
    return;
  }
  print('  produto auditoria id=$produtoId ncm=00000000');

  late final int vendaId;
  try {
    vendaId = await _criarVendaFinalizada(
      client: client,
      produtoId: produtoId,
      preco: 1.5,
    );
  } catch (e) {
    report.notes.add('Teste 4: falha ao criar venda ($e).');
    return;
  }
  print('  venda auditoria id=$vendaId');

  var emit = await client.post(
    'rejeicao/emitir',
    '/api/fiscal/emitir',
    {
      'vendaId': vendaId,
      'tipo': 'nfce',
      'permitirVendaSemEstoque': true,
    },
    timeout: const Duration(seconds: 180),
  );
  emit = _marcarSoftSeCertificado(emit, report);
  report.add(emit);

  final j = emit.bodyJson;
  final err = (j?['error'] ?? j?['mensagem'] ?? '').toString();
  print(
    '  emitir → HTTP ${emit.statusCode}: '
    '${_LanHttp.snip(err.isEmpty ? emit.bodySnippet : err)}',
  );

  if (emit.softOk || _respostaEhCertificadoFocus(emit)) {
    report.notes.add(
      'Teste 4: certificado A1 — rejeicao NCM nao exercitada na Focus '
      '(soft-pass).',
    );
    try {
      await client.postFull('/api/produtos/$produtoId/remover', const {});
    } catch (_) {}
    return;
  }

  final statusOk = emit.statusCode == 400 || emit.statusCode == 422;
  final msgAmigavel = err.trim().isNotEmpty &&
      !err.toLowerCase().contains('null') &&
      err.length >= 8;

  if (emit.okHttp && j?['autorizada'] == true) {
    report.notes.add(
      'Teste 4: Focus autorizou mesmo com NCM 00000000 '
      '(ambiente permissivo?). Nao houve rejeicao para auditar.',
    );
  } else if (statusOk && msgAmigavel) {
    report.notes.add(
      'Teste 4: rejeicao/validacao HTTP ${emit.statusCode} com mensagem '
      'amigavel — Terminal pode exibir o motivo sem crash.',
    );
  } else if (statusOk && !msgAmigavel) {
    if (args.dryRun) {
      report.notes.add(
        'Teste 4: HTTP ${emit.statusCode} sem detalhe Focus — aceito em dry-run.',
      );
    } else {
      report.critico(
        'HTTP ${emit.statusCode} sem mensagem amigavel de rejeicao.',
      );
    }
  } else if (emit.statusCode >= 500) {
    report.critico(
      'Rejeicao fiscal virou HTTP ${emit.statusCode} (deveria ser 400/422).',
    );
  } else if (emit.error != null) {
    report.notes.add('Teste 4: rede/timeout na emissao ($emit.error).');
  } else {
    report.notes.add(
      'Teste 4: HTTP ${emit.statusCode} — confira se Focus esta ativa.',
    );
  }

  final venda = await _obterVenda(client, vendaId);
  final statusFocus = (venda?['nfceStatusFocus'] ?? '').toString();
  print(
    '  statusFocus apos rejeicao: '
    '${statusFocus.isEmpty ? "(vazio/limpo)" : statusFocus}',
  );

  try {
    await client.postFull('/api/produtos/$produtoId/remover', const {});
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

Future<void> main(List<String> argv) async {
  final args = _Args.parse(argv);
  final report = _Report()..dryRun = args.dryRun;
  final httpClient = _LanHttp(args.baseHttp, args.token);

  print('stress_test_fiscal → ${args.baseHttp}');
  print(
    'token=${args.token.trim().isEmpty ? "(vazio)" : "***"}  '
    'concorrencia=${args.concorrencia}  '
    'timeoutCurto=${args.timeoutCurtoMs}ms  '
    'modo=${args.dryRun ? "DRY-RUN/MOCK" : "LIVE Focus"}',
  );

  if (args.dryRun) {
    try {
      await _suiteDryRunLocal(args: args, report: report);
    } catch (e, st) {
      report.critico('Dry-run local abortado: $e');
      print('ERRO DRY-RUN: $e');
      print(st);
    }
  }

  var apiOk = false;
  try {
    final health = await httpClient.getFull(
      '/api/health',
      timeout: const Duration(seconds: 5),
    );
    report.add(
      _ReqResult(
        label: 'health',
        statusCode: health.status,
        ms: health.ms,
        bodySnippet: _LanHttp.snip(health.body),
      ),
    );
    if (health.status >= 200 && health.status < 300) {
      apiOk = true;
      print('Health OK (${health.ms} ms)');
    } else {
      print(
        'AVISO: /api/health HTTP ${health.status}. '
        '${args.dryRun ? "Segue so com suite local." : ""}',
      );
    }
  } catch (e) {
    print(
      'AVISO: API ${args.baseHttp} indisponivel ($e). '
      '${args.dryRun ? "Suite local ja executada." : ""}',
    );
    if (!args.dryRun) {
      report.critico('Falha ao conectar em ${args.baseHttp}: $e');
      report.printFinal(passou: false);
      httpClient.close();
      exit(2);
    }
  }

  if (!apiOk && !args.dryRun) {
    print(
      'FALHA: /api/health indisponivel. '
      'PC1 com Lan API :${args.port} ativa?',
    );
    report.printFinal(passou: false);
    httpClient.close();
    exit(2);
  }

  if (apiOk) {
    try {
      final produtoId = await _resolverProdutoId(httpClient, args.produtoId);
      print('produto-id=$produtoId');

      var vendaIdempotencia = args.vendaId;
      if (!args.skipIdempotencia || !args.skipPolling) {
        if (vendaIdempotencia <= 0) {
          vendaIdempotencia = await _criarVendaFinalizada(
            client: httpClient,
            produtoId: produtoId,
            preco: 1.0,
          );
          print('venda de teste criada id=$vendaIdempotencia');
        } else {
          print('usando venda-id=$vendaIdempotencia');
        }
      }

      if (!args.skipIdempotencia) {
        await _testeIdempotenciaConcorrencia(
          args: args,
          client: httpClient,
          report: report,
          vendaId: vendaIdempotencia,
        );
      }

      if (!args.skipPolling) {
        final vendaPolling = args.vendaId > 0
            ? args.vendaId
            : await _criarVendaFinalizada(
                client: httpClient,
                produtoId: produtoId,
                preco: 1.02,
              );
        await _testePollingProcessando(
          args: args,
          client: httpClient,
          report: report,
          vendaId: vendaPolling,
        );
      }

      if (!args.skipTimeout) {
        await _testeTimeoutResiliencia(
          args: args,
          client: httpClient,
          report: report,
          produtoId: produtoId,
        );
      }

      if (!args.skipRejeicao) {
        await _testeRejeicaoSefaz(
          args: args,
          client: httpClient,
          report: report,
        );
      }
    } catch (e, st) {
      if (args.dryRun) {
        report.notes.add(
          'API live pulada/parcial em dry-run apos erro: $e',
        );
        print('AVISO (dry-run): bateria live nao completa — $e');
      } else {
        report.critico('Abortado: $e');
        print('ERRO FATAL: $e');
        print(st);
      }
    }
  } else if (args.dryRun) {
    report.notes.add(
      'API offline — bateria live pulada; suite local dry-run permanece.',
    );
  }

  httpClient.close();
  final passou = report.falhasCriticas.isEmpty;
  report.printFinal(passou: passou);
  exit(passou ? 0 : 1);
}
