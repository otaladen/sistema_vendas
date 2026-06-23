import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../domain/backup_historico_item.dart';
import 'local_backup_service.dart';
import 'local_backup_validation.dart';

/// Varre pastas de destino e monta historico a partir de manifest.json.
class BackupHistoricoService {
  BackupHistoricoService._();

  static const _prefixoPasta = 'backup_sistema_vendas_';
  static final _fmtPasta = DateFormat('yyyyMMdd_HHmmss');

  static Future<List<BackupHistoricoItem>> listar({
    required Iterable<String> pastasRaiz,
    int limite = 50,
  }) async {
    final vistos = <String>{};
    final itens = <BackupHistoricoItem>[];

    for (final raizRaw in pastasRaiz) {
      final raiz = raizRaw.trim();
      if (raiz.isEmpty) continue;
      final dir = Directory(raiz);
      if (!dir.existsSync()) continue;

      await for (final entidade in dir.list(followLinks: false)) {
        if (entidade is! Directory) continue;
        final nome = p.basename(entidade.path);
        if (!nome.startsWith(_prefixoPasta)) continue;

        final normalizado = p.normalize(entidade.path).toLowerCase();
        if (vistos.contains(normalizado)) continue;
        vistos.add(normalizado);

        itens.add(await _lerEntrada(entidade, raiz));
      }
    }

    itens.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    if (itens.length <= limite) return itens;
    return itens.sublist(0, limite);
  }

  static Future<BackupHistoricoItem> _lerEntrada(
    Directory pasta,
    String pastaRaiz,
  ) async {
    var criadoEm = _dataDoNomePasta(p.basename(pasta.path));
    LocalBackupTipo? tipo;
    var tamanhoKb = 0.0;
    var empresa = '';
    var valido = false;

    final manifestFile = File(
      p.join(pasta.path, LocalBackupService.manifestFileName),
    );
    if (manifestFile.existsSync()) {
      try {
        final map = jsonDecode(manifestFile.readAsStringSync()) as Map;
        final criadoRaw = map['criadoEm']?.toString();
        if (criadoRaw != null && criadoRaw.isNotEmpty) {
          criadoEm = DateTime.tryParse(criadoRaw) ?? criadoEm;
        }
        final tipoRaw = map['tipo']?.toString();
        if (tipoRaw == LocalBackupTipo.manual.name) {
          tipo = LocalBackupTipo.manual;
        } else if (tipoRaw == LocalBackupTipo.automatico.name) {
          tipo = LocalBackupTipo.automatico;
        }
        tamanhoKb = (map['tamanhoBancoKb'] as num?)?.toDouble() ?? 0;
        empresa = map['empresa']?.toString() ?? '';
      } catch (_) {}
    }

    try {
      final dados = LocalBackupValidation.resolverPastaDadosBackup(pasta);
      LocalBackupValidation.validarDadosAplicacao(dados);
      valido = true;
      if (tamanhoKb <= 0) {
        final mdb = LocalBackupValidation.localizarDataMdb(dados);
        if (mdb != null) {
          tamanhoKb = mdb.lengthSync() / 1024.0;
        }
      }
    } catch (_) {
      valido = false;
    }

    return BackupHistoricoItem(
      pasta: pasta,
      criadoEm: criadoEm,
      tipo: tipo,
      tamanhoBancoKb: tamanhoKb,
      empresa: empresa,
      valido: valido,
      pastaRaiz: pastaRaiz,
    );
  }

  static DateTime _dataDoNomePasta(String nomePasta) {
    final sufixo = nomePasta.replaceFirst(_prefixoPasta, '');
    final parsed = _fmtPasta.tryParse(sufixo);
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
