import 'dart:io';

import 'package:path/path.dart' as p;

/// Armazena XML de inutilizacao de numeracao NF-e.
class NfeInutilizacaoXmlStore {
  NfeInutilizacaoXmlStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;
  static const String _pasta = 'nfe_inutilizacao_xml';

  Directory get _dir {
    final d = Directory(p.join(_storeDirectoryPath, _pasta));
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d;
  }

  String _nomeArquivo(String id) {
    final safe = id.replaceAll(RegExp(r'[^\w\-]'), '_');
    return 'inut_$safe.xml';
  }

  File arquivoPorId(String id) =>
      File(p.join(_dir.path, _nomeArquivo(id)));

  void salvarXml(String id, String conteudoXml) {
    final xml = conteudoXml.trim();
    if (id.trim().isEmpty || xml.isEmpty) return;
    arquivoPorId(id).writeAsStringSync(xml, flush: true);
  }

  String? lerXml(String id) {
    final f = arquivoPorId(id);
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  bool existe(String id) => arquivoPorId(id).existsSync();
}
