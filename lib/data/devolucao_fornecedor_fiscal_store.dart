import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Metadados da NF-e de devolucao de compra (loja → fornecedor/fabrica).
class DevolucaoFornecedorFiscalRegistro {
  DevolucaoFornecedorFiscalRegistro({
    required this.chaveNotaCompra,
    required this.referenciaFocus,
    required this.chaveNfe,
    this.numero = '',
    this.serie = '',
    this.urlDanfe = '',
    this.urlXml = '',
    this.statusFocus = '',
    this.motivo = '',
    this.nomeFornecedor = '',
    this.cnpjFornecedor = '',
    this.itensBaixaJson = '[]',
    this.estoqueBaixado = false,
    DateTime? emitidaEm,
  }) : emitidaEm = emitidaEm ?? DateTime.now();

  final String chaveNotaCompra;
  final String referenciaFocus;
  final String chaveNfe;
  final String numero;
  final String serie;
  final String urlDanfe;
  final String urlXml;
  final String statusFocus;
  final String motivo;
  final String nomeFornecedor;
  final String cnpjFornecedor;

  /// JSON com [{historicoEntradaId, produtoId, quantidade}].
  final String itensBaixaJson;

  /// true depois que o fisico foi debitado (emissao imediata ou reconsulta).
  final bool estoqueBaixado;
  final DateTime emitidaEm;

  String get _status => statusFocus.toLowerCase();

  bool get rejeitada =>
      _status.contains('erro') ||
      _status.contains('rejeit') ||
      _status.contains('denegad');

  bool get cancelada => _status.contains('cancel');

  bool get processando => _status.contains('processando');

  bool get autorizada =>
      !rejeitada &&
      !cancelada &&
      !processando &&
      _status.contains('autoriz');

  /// Processando, ou autorizada ainda sem baixa (crash entre SEFAZ e estoque).
  bool get pendenteReconsulta =>
      processando || (autorizada && !estoqueBaixado);

  String get rotuloStatus {
    if (cancelada) return 'Cancelada';
    if (autorizada) return 'Autorizada';
    if (processando) return 'Processando';
    if (rejeitada) return 'Rejeitada';
    if (statusFocus.isNotEmpty) return statusFocus;
    return 'Desconhecido';
  }

  DevolucaoFornecedorFiscalRegistro copyWith({
    String? chaveNfe,
    String? numero,
    String? serie,
    String? urlDanfe,
    String? urlXml,
    String? statusFocus,
    bool? estoqueBaixado,
  }) {
    return DevolucaoFornecedorFiscalRegistro(
      chaveNotaCompra: chaveNotaCompra,
      referenciaFocus: referenciaFocus,
      chaveNfe: chaveNfe ?? this.chaveNfe,
      numero: numero ?? this.numero,
      serie: serie ?? this.serie,
      urlDanfe: urlDanfe ?? this.urlDanfe,
      urlXml: urlXml ?? this.urlXml,
      statusFocus: statusFocus ?? this.statusFocus,
      motivo: motivo,
      nomeFornecedor: nomeFornecedor,
      cnpjFornecedor: cnpjFornecedor,
      itensBaixaJson: itensBaixaJson,
      estoqueBaixado: estoqueBaixado ?? this.estoqueBaixado,
      emitidaEm: emitidaEm,
    );
  }

  Map<String, dynamic> toJson() => {
        'chaveNotaCompra': chaveNotaCompra,
        'referenciaFocus': referenciaFocus,
        'chaveNfe': chaveNfe,
        'numero': numero,
        'serie': serie,
        'urlDanfe': urlDanfe,
        'urlXml': urlXml,
        'statusFocus': statusFocus,
        'motivo': motivo,
        'nomeFornecedor': nomeFornecedor,
        'cnpjFornecedor': cnpjFornecedor,
        'itensBaixaJson': itensBaixaJson,
        'estoqueBaixado': estoqueBaixado,
        'emitidaEm': emitidaEm.toUtc().toIso8601String(),
      };

  factory DevolucaoFornecedorFiscalRegistro.fromJson(Map<String, dynamic> json) {
    final status = (json['statusFocus'] ?? '').toString();
    final rawBaixa = json['estoqueBaixado'];
    // Legado: nota ja autorizada no JSON teve baixa na emissao imediata.
    // Processando sem o campo = ainda nao baixou (bug antigo da reconsulta).
    final estoqueBaixado = rawBaixa is bool
        ? rawBaixa
        : status.toLowerCase().contains('autoriz') &&
            !status.toLowerCase().contains('processando') &&
            !status.toLowerCase().contains('erro') &&
            !status.toLowerCase().contains('rejeit');
    return DevolucaoFornecedorFiscalRegistro(
      chaveNotaCompra: (json['chaveNotaCompra'] ?? '').toString(),
      referenciaFocus: (json['referenciaFocus'] ?? '').toString(),
      chaveNfe: (json['chaveNfe'] ?? '').toString(),
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      urlDanfe: (json['urlDanfe'] ?? '').toString(),
      urlXml: (json['urlXml'] ?? '').toString(),
      statusFocus: status,
      motivo: (json['motivo'] ?? '').toString(),
      nomeFornecedor: (json['nomeFornecedor'] ?? '').toString(),
      cnpjFornecedor: (json['cnpjFornecedor'] ?? '').toString(),
      itensBaixaJson: (json['itensBaixaJson'] ?? '[]').toString(),
      estoqueBaixado: estoqueBaixado,
      emitidaEm: DateTime.tryParse((json['emitidaEm'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Persistencia local das NF-e de devolucao ao fornecedor.
class DevolucaoFornecedorFiscalStore {
  DevolucaoFornecedorFiscalStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;

  File get _arquivo => File(
        p.join(_storeDirectoryPath, 'devolucao_fornecedor_fiscal_registros.json'),
      );

  List<DevolucaoFornecedorFiscalRegistro> listar() {
    final f = _arquivo;
    if (!f.existsSync()) return [];
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map(
            (e) => DevolucaoFornecedorFiscalRegistro.fromJson(
              e.cast<String, dynamic>(),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<DevolucaoFornecedorFiscalRegistro> listarPorChaveCompra(String chave) {
    final c = chave.replaceAll(RegExp(r'\D'), '');
    return listar()
        .where((r) => r.chaveNotaCompra.replaceAll(RegExp(r'\D'), '') == c)
        .toList()
      ..sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));
  }

  DevolucaoFornecedorFiscalRegistro? obterPorReferencia(String referencia) {
    final ref = referencia.trim();
    if (ref.isEmpty) return null;
    for (final r in listar()) {
      if (r.referenciaFocus == ref) return r;
    }
    return null;
  }

  int proximaSequencia(String chaveNotaCompra) =>
      listarPorChaveCompra(chaveNotaCompra).length + 1;

  List<DevolucaoFornecedorFiscalRegistro> listarPendentesReconsulta() {
    final out = listar().where((r) => r.pendenteReconsulta).toList();
    out.sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));
    return out;
  }

  /// Soma das quantidades ja baixadas por historico de entrada nesta NF.
  Map<int, int> quantidadesJaDevolvidasPorHistorico(String chaveNotaCompra) {
    final out = <int, int>{};
    for (final reg in listarPorChaveCompra(chaveNotaCompra)) {
      // Rejeitada/erro libera a qtd. Cancelada sem baixa tambem.
      // Processando continua reservada para nao emitir em duplicata.
      if (reg.rejeitada) continue;
      if (reg.cancelada && !reg.estoqueBaixado) continue;
      try {
        final raw = jsonDecode(reg.itensBaixaJson);
        if (raw is! List) continue;
        for (final e in raw.whereType<Map>()) {
          final id = ((e['historicoEntradaId'] as num?) ?? 0).toInt();
          final q = ((e['quantidade'] as num?) ?? 0).toInt();
          if (id <= 0 || q <= 0) continue;
          out[id] = (out[id] ?? 0) + q;
        }
      } catch (_) {}
    }
    return out;
  }

  void salvar(DevolucaoFornecedorFiscalRegistro registro) {
    final todos = listar();
    final idx = todos.indexWhere(
      (r) => r.referenciaFocus == registro.referenciaFocus,
    );
    if (idx >= 0) {
      todos[idx] = registro;
    } else {
      todos.insert(0, registro);
    }
    _arquivo.parent.createSync(recursive: true);
    _arquivo.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
        todos.map((e) => e.toJson()).toList(),
      ),
    );
  }
}
