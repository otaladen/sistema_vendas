import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/lista_preco_externa.dart';
import '../domain/lista_preco_externa_pdf_parser.dart';
import '../services/lista_preco_externa_pdf_service.dart';
import '../services/lan_api_server.dart';

/// Contrato compartilhado pelo PC servidor (JSON local) e pelos terminais (API).
abstract class ListaPrecoExternaStore {
  Future<List<ListaPrecoExternaResumo>> listarResumos();
  Future<ListaPrecoExterna?> obterPorId(String id);
  Future<ListaPrecoExterna?> obterMaisRecente();
  Future<ListaPrecoExterna> importarPdf(
    List<int> bytes, {
    required String arquivoOrigem,
  });
  Future<void> excluir(String id);
}

/// Persistencia local (JSON) das tabelas de preco externas.
class ListaPrecoExternaRepository implements ListaPrecoExternaStore {
  ListaPrecoExternaRepository({Directory? overrideDir})
      : _overrideDir = overrideDir;

  final Directory? _overrideDir;

  Future<Directory> _dir() async {
    final override = _overrideDir;
    if (override != null) return override;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'listas_preco_externas'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _dir();
    return File(p.join(dir.path, 'index.json'));
  }

  Future<File> _listaFile(String id) async {
    final dir = await _dir();
    return File(p.join(dir.path, '$id.json'));
  }

  @override
  Future<List<ListaPrecoExternaResumo>> listarResumos() async {
    final f = await _indexFile();
    if (!f.existsSync()) return <ListaPrecoExternaResumo>[];
    try {
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! List) return <ListaPrecoExternaResumo>[];
      final out = <ListaPrecoExternaResumo>[];
      for (final e in decoded) {
        if (e is Map) {
          out.add(
            ListaPrecoExternaResumo.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
      out.sort((a, b) => b.importadoEm.compareTo(a.importadoEm));
      return out;
    } catch (_) {
      return <ListaPrecoExternaResumo>[];
    }
  }

  @override
  Future<ListaPrecoExterna?> obterPorId(String id) async {
    final f = await _listaFile(id);
    if (!f.existsSync()) return null;
    try {
      final map = jsonDecode(await f.readAsString());
      if (map is! Map) return null;
      return ListaPrecoExterna.fromJson(Map<String, dynamic>.from(map));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ListaPrecoExterna?> obterMaisRecente() async {
    final resumos = await listarResumos();
    if (resumos.isEmpty) return null;
    return obterPorId(resumos.first.id);
  }

  void _avisarRede() {
    try {
      LanApiServerHub.instance.notificar('lista_preco_externa');
    } catch (_) {}
  }

  @override
  Future<ListaPrecoExterna> importarPdf(
    List<int> bytes, {
    required String arquivoOrigem,
  }) async {
    final parse = ListaPrecoExternaPdfService.importarBytes(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      arquivoOrigem: arquivoOrigem,
    );
    if (parse.itens.isEmpty) {
      throw StateError(
        'Nenhum item encontrado. Confirme se o PDF e a tabela '
        'Codigo / Produto / Preco (Comprou Levou / Itinga).',
      );
    }
    final lista = await salvarParse(parse);
    _avisarRede();
    return lista;
  }

  Future<ListaPrecoExterna> salvarParse(
    ListaPrecoExternaParseResult parse,
  ) async {
    final id =
        'lista_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    final lista = ListaPrecoExterna(
      id: id,
      nomeLoja: parse.nomeLoja,
      dataLista: parse.dataLista,
      importadoEm: DateTime.now(),
      arquivoOrigem: parse.arquivoOrigem,
      itens: parse.itens,
      linhasIgnoradas: parse.linhasIgnoradas,
    );
    final f = await _listaFile(id);
    await f.writeAsString(jsonEncode(lista.toJson()));

    // Copia mutavel: listarResumos pode devolver lista const/imutavel.
    final resumos = List<ListaPrecoExternaResumo>.from(await listarResumos());
    resumos.removeWhere((r) => r.id == id);
    resumos.insert(
      0,
      ListaPrecoExternaResumo(
        id: id,
        nomeLoja: lista.nomeLoja,
        dataLista: lista.dataLista,
        importadoEm: lista.importadoEm,
        arquivoOrigem: lista.arquivoOrigem,
        quantidade: lista.quantidade,
        linhasIgnoradas: lista.linhasIgnoradas,
      ),
    );
    // Mantem no maximo 8 listas.
    while (resumos.length > 8) {
      final antigo = resumos.removeLast();
      final af = await _listaFile(antigo.id);
      if (af.existsSync()) {
        try {
          af.deleteSync();
        } catch (_) {}
      }
    }
    final idx = await _indexFile();
    await idx.writeAsString(
      jsonEncode(resumos.map((e) => e.toJson()).toList()),
    );
    return lista;
  }

  @override
  Future<void> excluir(String id) async {
    final f = await _listaFile(id);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    final resumos = List<ListaPrecoExternaResumo>.from(await listarResumos());
    resumos.removeWhere((r) => r.id == id);
    final idx = await _indexFile();
    await idx.writeAsString(
      jsonEncode(resumos.map((e) => e.toJson()).toList()),
    );
    _avisarRede();
  }
}

class ListaPrecoExternaResumo {
  const ListaPrecoExternaResumo({
    required this.id,
    required this.nomeLoja,
    required this.dataLista,
    required this.importadoEm,
    required this.arquivoOrigem,
    required this.quantidade,
    this.linhasIgnoradas = 0,
  });

  final String id;
  final String nomeLoja;
  final DateTime dataLista;
  final DateTime importadoEm;
  final String arquivoOrigem;
  final int quantidade;
  final int linhasIgnoradas;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nomeLoja': nomeLoja,
        'dataLista': dataLista.toIso8601String(),
        'importadoEm': importadoEm.toIso8601String(),
        'arquivoOrigem': arquivoOrigem,
        'quantidade': quantidade,
        'linhasIgnoradas': linhasIgnoradas,
      };

  factory ListaPrecoExternaResumo.fromJson(Map<String, dynamic> m) {
    return ListaPrecoExternaResumo(
      id: (m['id'] ?? '').toString(),
      nomeLoja: (m['nomeLoja'] ?? '').toString(),
      dataLista: DateTime.tryParse((m['dataLista'] ?? '').toString()) ??
          DateTime.now(),
      importadoEm: DateTime.tryParse((m['importadoEm'] ?? '').toString()) ??
          DateTime.now(),
      arquivoOrigem: (m['arquivoOrigem'] ?? '').toString(),
      quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
      linhasIgnoradas: (m['linhasIgnoradas'] as num?)?.toInt() ?? 0,
    );
  }
}
