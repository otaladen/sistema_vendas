import 'dart:io';

import 'package:path/path.dart' as p;

/// Armazena XML das NFC-e de saida (modelo 65) para fechamento offline.
class NfceSaidaXmlStore {
  NfceSaidaXmlStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;
  static const String _pasta = 'nfce_saida_xml';

  Directory get _dir {
    final d = Directory(p.join(_storeDirectoryPath, _pasta));
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d;
  }

  String _nomeArquivo(String chaveAcesso, {bool cancelada = false}) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final sufixo = cancelada ? '_cancelada' : '';
    return '$chave$sufixo.xml';
  }

  File arquivoDaChave(String chaveAcesso, {bool cancelada = false}) {
    return File(p.join(_dir.path, _nomeArquivo(chaveAcesso, cancelada: cancelada)));
  }

  void salvarXml(
    String chaveAcesso,
    String conteudoXml, {
    bool cancelada = false,
  }) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44 || conteudoXml.trim().isEmpty) return;
    arquivoDaChave(chave, cancelada: cancelada)
        .writeAsStringSync(conteudoXml, flush: true);
  }

  String? lerXml(String chaveAcesso, {bool cancelada = false}) {
    final f = arquivoDaChave(chaveAcesso, cancelada: cancelada);
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  bool existe(String chaveAcesso, {bool cancelada = false}) =>
      arquivoDaChave(chaveAcesso, cancelada: cancelada).existsSync();
}
