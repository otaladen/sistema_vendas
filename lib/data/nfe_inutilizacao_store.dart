import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Registro de inutilizacao de numeracao NF-e (55) ou NFC-e (65).
class NfeInutilizacaoRegistro {
  NfeInutilizacaoRegistro({
    required this.id,
    required this.serie,
    required this.numeroInicial,
    required this.numeroFinal,
    required this.justificativa,
    required this.usuarioLogin,
    required this.sucesso,
    this.modelo = '55',
    this.protocolo = '',
    this.mensagemSefaz = '',
    this.urlXml = '',
    DateTime? registradaEm,
  }) : registradaEm = registradaEm ?? DateTime.now();

  final String id;
  /// `55` = NF-e, `65` = NFC-e.
  final String modelo;
  final String serie;
  final int numeroInicial;
  final int numeroFinal;
  final String justificativa;
  final String usuarioLogin;
  final bool sucesso;
  final String protocolo;
  final String mensagemSefaz;
  final String urlXml;
  final DateTime registradaEm;

  bool get isNfce => modelo == '65';

  String get rotuloModelo => isNfce ? 'NFC-e' : 'NF-e';

  String get nomeArquivoXml {
    final prefix = isNfce ? 'inutilizacao_NFCe' : 'inutilizacao_NFe';
    return '${prefix}_serie${serie}_$numeroInicial-$numeroFinal.xml';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'modelo': modelo,
        'serie': serie,
        'numeroInicial': numeroInicial,
        'numeroFinal': numeroFinal,
        'justificativa': justificativa,
        'usuarioLogin': usuarioLogin,
        'sucesso': sucesso,
        if (protocolo.trim().isNotEmpty) 'protocolo': protocolo,
        if (mensagemSefaz.trim().isNotEmpty) 'mensagemSefaz': mensagemSefaz,
        if (urlXml.trim().isNotEmpty) 'urlXml': urlXml,
        'registradaEm': registradaEm.toUtc().toIso8601String(),
      };

  factory NfeInutilizacaoRegistro.fromJson(Map<String, dynamic> json) {
    final modeloRaw = (json['modelo'] ?? '55').toString().trim();
    return NfeInutilizacaoRegistro(
      id: (json['id'] ?? '').toString(),
      modelo: modeloRaw == '65' ? '65' : '55',
      serie: (json['serie'] ?? '1').toString(),
      numeroInicial: ((json['numeroInicial'] as num?) ?? 0).toInt(),
      numeroFinal: ((json['numeroFinal'] as num?) ?? 0).toInt(),
      justificativa: (json['justificativa'] ?? '').toString(),
      usuarioLogin: (json['usuarioLogin'] ?? '').toString(),
      sucesso: json['sucesso'] == true,
      protocolo: (json['protocolo'] ?? '').toString(),
      mensagemSefaz: (json['mensagemSefaz'] ?? '').toString(),
      urlXml: (json['urlXml'] ?? '').toString(),
      registradaEm:
          DateTime.tryParse((json['registradaEm'] ?? '').toString()) ??
              DateTime.now(),
    );
  }
}

/// Persistencia JSON do historico de inutilizacoes NF-e / NFC-e.
class NfeInutilizacaoStore {
  NfeInutilizacaoStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;
  String get storeDirectoryPath => _storeDirectoryPath;
  static const String _arquivo = 'nfe_inutilizacoes_v1.json';

  File get _file => File(p.join(_storeDirectoryPath, _arquivo));

  List<NfeInutilizacaoRegistro> listar() {
    if (!_file.existsSync()) return [];
    try {
      final raw = jsonDecode(_file.readAsStringSync());
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map(
            (e) => NfeInutilizacaoRegistro.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList()
        ..sort((a, b) => b.registradaEm.compareTo(a.registradaEm));
    } catch (_) {
      return [];
    }
  }

  List<NfeInutilizacaoRegistro> listarNoPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) {
    final ini = DateTime(inicio.year, inicio.month, inicio.day);
    final f = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);
    return listar().where((r) {
      final local = r.registradaEm.toLocal();
      return !local.isBefore(ini) && !local.isAfter(f);
    }).toList();
  }

  void gravar(NfeInutilizacaoRegistro registro) {
    final todos = listar();
    final idx = todos.indexWhere((r) => r.id == registro.id);
    if (idx >= 0) {
      todos[idx] = registro;
    } else {
      todos.insert(0, registro);
    }
    _file.writeAsStringSync(
      jsonEncode(todos.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }
}
