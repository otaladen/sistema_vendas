import 'dart:io';

import 'package:path/path.dart' as p;

/// Armazena XML das CC-e (eventos de correcao) das NF-e de saida.
class NfeCceXmlStore {
  NfeCceXmlStore(this._storeDirectoryPath);

  final String _storeDirectoryPath;
  static const String _pasta = 'nfe_cce_xml';

  Directory get _dir {
    final d = Directory(p.join(_storeDirectoryPath, _pasta));
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d;
  }

  String _nomeArquivo(String chaveAcesso, int numeroSequencia) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    return '${chave}_cce_$numeroSequencia.xml';
  }

  File arquivoDaChave(String chaveAcesso, int numeroSequencia) {
    return File(p.join(_dir.path, _nomeArquivo(chaveAcesso, numeroSequencia)));
  }

  void salvarXml(
    String chaveAcesso,
    int numeroSequencia,
    String conteudoXml,
  ) {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44 || numeroSequencia <= 0 || conteudoXml.trim().isEmpty) {
      return;
    }
    arquivoDaChave(chave, numeroSequencia)
        .writeAsStringSync(conteudoXml, flush: true);
  }

  String? lerXml(String chaveAcesso, int numeroSequencia) {
    final f = arquivoDaChave(chaveAcesso, numeroSequencia);
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  bool existe(String chaveAcesso, int numeroSequencia) =>
      arquivoDaChave(chaveAcesso, numeroSequencia).existsSync();

  List<File> listarArquivosNoDiretorio() {
    if (!_dir.existsSync()) return [];
    return _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.xml'))
        .toList();
  }
}
