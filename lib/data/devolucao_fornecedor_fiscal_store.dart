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
  final DateTime emitidaEm;

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
        'emitidaEm': emitidaEm.toUtc().toIso8601String(),
      };

  factory DevolucaoFornecedorFiscalRegistro.fromJson(Map<String, dynamic> json) {
    return DevolucaoFornecedorFiscalRegistro(
      chaveNotaCompra: (json['chaveNotaCompra'] ?? '').toString(),
      referenciaFocus: (json['referenciaFocus'] ?? '').toString(),
      chaveNfe: (json['chaveNfe'] ?? '').toString(),
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      urlDanfe: (json['urlDanfe'] ?? '').toString(),
      urlXml: (json['urlXml'] ?? '').toString(),
      statusFocus: (json['statusFocus'] ?? '').toString(),
      motivo: (json['motivo'] ?? '').toString(),
      nomeFornecedor: (json['nomeFornecedor'] ?? '').toString(),
      cnpjFornecedor: (json['cnpjFornecedor'] ?? '').toString(),
      itensBaixaJson: (json['itensBaixaJson'] ?? '[]').toString(),
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

  int proximaSequencia(String chaveNotaCompra) =>
      listarPorChaveCompra(chaveNotaCompra).length + 1;

  /// Soma das quantidades ja baixadas por historico de entrada nesta NF.
  Map<int, int> quantidadesJaDevolvidasPorHistorico(String chaveNotaCompra) {
    final out = <int, int>{};
    for (final reg in listarPorChaveCompra(chaveNotaCompra)) {
      if (reg.statusFocus.toLowerCase().contains('erro') ||
          reg.statusFocus.toLowerCase().contains('rejeit')) {
        continue;
      }
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
