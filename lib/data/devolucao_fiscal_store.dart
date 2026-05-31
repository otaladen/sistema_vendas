import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Metadados da NF-e de devolucao emitida para um [RegistroDevolucao].
class DevolucaoFiscalRegistro {
  DevolucaoFiscalRegistro({
    required this.registroDevolucaoId,
    required this.vendaId,
    required this.referenciaFocus,
    required this.chaveNfe,
    this.numero = '',
    this.serie = '',
    this.urlDanfe = '',
    this.urlXml = '',
    this.statusFocus = '',
    this.motivo = '',
    DateTime? emitidaEm,
  }) : emitidaEm = emitidaEm ?? DateTime.now();

  final int registroDevolucaoId;
  final int vendaId;
  final String referenciaFocus;
  final String chaveNfe;
  final String numero;
  final String serie;
  final String urlDanfe;
  final String urlXml;
  final String statusFocus;
  final String motivo;
  final DateTime emitidaEm;

  Map<String, dynamic> toJson() => {
        'registroDevolucaoId': registroDevolucaoId,
        'vendaId': vendaId,
        'referenciaFocus': referenciaFocus,
        'chaveNfe': chaveNfe,
        'numero': numero,
        'serie': serie,
        'urlDanfe': urlDanfe,
        'urlXml': urlXml,
        'statusFocus': statusFocus,
        'motivo': motivo,
        'emitidaEm': emitidaEm.toUtc().toIso8601String(),
      };

  factory DevolucaoFiscalRegistro.fromJson(Map<String, dynamic> json) {
    return DevolucaoFiscalRegistro(
      registroDevolucaoId: ((json['registroDevolucaoId'] as num?) ?? 0).toInt(),
      vendaId: ((json['vendaId'] as num?) ?? 0).toInt(),
      referenciaFocus: (json['referenciaFocus'] ?? '').toString(),
      chaveNfe: (json['chaveNfe'] ?? '').toString(),
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      urlDanfe: (json['urlDanfe'] ?? '').toString(),
      urlXml: (json['urlXml'] ?? '').toString(),
      statusFocus: (json['statusFocus'] ?? '').toString(),
      motivo: (json['motivo'] ?? '').toString(),
      emitidaEm: DateTime.tryParse((json['emitidaEm'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Persistencia local das NF-e de devolucao (sem ObjectBox).
class DevolucaoFiscalStore {
  DevolucaoFiscalStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;

  File get _arquivo => File(
        p.join(_storeDirectoryPath, 'devolucao_fiscal_registros.json'),
      );

  List<DevolucaoFiscalRegistro> listar() {
    final f = _arquivo;
    if (!f.existsSync()) return [];
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => DevolucaoFiscalRegistro.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  DevolucaoFiscalRegistro? porRegistroDevolucao(int registroDevolucaoId) {
    for (final r in listar()) {
      if (r.registroDevolucaoId == registroDevolucaoId) return r;
    }
    return null;
  }

  List<DevolucaoFiscalRegistro> listarPorVenda(int vendaId) {
    return listar()
        .where((r) => r.vendaId == vendaId)
        .toList()
      ..sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));
  }

  void salvar(DevolucaoFiscalRegistro registro) {
    final todos = listar();
    final idx = todos.indexWhere(
      (r) => r.registroDevolucaoId == registro.registroDevolucaoId,
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
