import 'dart:io';

import 'package:path/path.dart' as p;

/// Armazena XML original das NF-e de entrada importadas (fechamento contabil).
class NfeEntradaXmlStore {
  NfeEntradaXmlStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;
  static const String _pasta = 'nfe_entrada_xml';

  Directory get _dir {
    final d = Directory(p.join(_storeDirectoryPath, _pasta));
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d;
  }

  File arquivoDaChave(String chaveAcesso) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    return File(p.join(_dir.path, '$chave.xml'));
  }

  void salvarXml(String chaveAcesso, String conteudoXml) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44 || conteudoXml.trim().isEmpty) return;
    arquivoDaChave(chave).writeAsStringSync(conteudoXml, flush: true);
  }

  String? lerXml(String chaveAcesso) {
    final f = arquivoDaChave(chaveAcesso);
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  bool existe(String chaveAcesso) => arquivoDaChave(chaveAcesso).existsSync();
}
