import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/auditoria_catalogo.dart';
import '../domain/backup_historico_item.dart';
import '../domain/local_backup_escopo.dart';
import '../domain/sessao_operacional_guard.dart';
import '../services/auditoria_registrar.dart';
import 'app_config_repository.dart';
import 'auto_backup_service.dart';
import 'backup_historico_service.dart';
import 'backup_pos_execucao_service.dart';
import 'backup_zip_service.dart';
import 'local_app_data_paths.dart';
import 'local_backup_service.dart';
import 'objectbox.dart';

/// Backup disparado pela API (terminais) — copia o banco do PC servidor.
class BackupRemotoServidorService {
  BackupRemotoServidorService._();

  static const prefixoArquivo = 'backup_sistema_vendas_';
  static const subpastaFallback = 'backups_terminais';

  static bool _emExecucao = false;
  static String? _ultimoZipPath;

  static bool get emExecucao => _emExecucao;

  static Future<List<String>> pastasRaizPermitidas(
    AppConfigRepository repository,
  ) async {
    final config = await repository.carregarEmpresaConfig();
    final manual = await repository.carregarRegistroBackupManual();
    final base = await obterDiretorioBaseDadosApp();
    final fallback = p.join(base.path, subpastaFallback);
    final pastas = <String>{
      if (config.backupAutomaticoPasta.trim().isNotEmpty)
        config.backupAutomaticoPasta.trim(),
      if (manual.pastaPadrao.trim().isNotEmpty) manual.pastaPadrao.trim(),
      if (config.backupSegundoDestinoPasta.trim().isNotEmpty)
        config.backupSegundoDestinoPasta.trim(),
      fallback,
    };
    return pastas.toList();
  }

  static Future<Directory> resolverDestino(
    AppConfigRepository repository,
  ) async {
    final config = await repository.carregarEmpresaConfig();
    final manual = await repository.carregarRegistroBackupManual();
    var pasta = config.backupAutomaticoPasta.trim();
    if (pasta.isEmpty) pasta = manual.pastaPadrao.trim();
    if (pasta.isEmpty) {
      final base = await obterDiretorioBaseDadosApp();
      pasta = p.join(base.path, subpastaFallback);
    }
    final dir = Directory(pasta);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static bool ehArquivoZipDeBackup(String caminho) {
    final nome = p.basename(caminho).toLowerCase();
    return nome.startsWith(prefixoArquivo) && nome.endsWith('.zip');
  }

  static bool zipDentroDePastasPermitidas(
    String caminho,
    Iterable<String> pastasRaiz,
  ) {
    if (!ehArquivoZipDeBackup(caminho)) return false;
    final arquivo = p.normalize(caminho).replaceAll('/', p.separator);
    final arquivoLower = arquivo.toLowerCase();
    for (final raiz in pastasRaiz) {
      if (raiz.trim().isEmpty) continue;
      final r = p.normalize(raiz).replaceAll('/', p.separator);
      final rLower = r.toLowerCase();
      final prefixo =
          rLower.endsWith(p.separator) ? rLower : '$rLower${p.separator}';
      if (arquivoLower.startsWith(prefixo) ||
          p.dirname(arquivoLower) == rLower) {
        return true;
      }
    }
    return false;
  }

  static Future<Map<String, dynamic>> status() async {
    final repository = AppConfigRepository();
    final config = await repository.carregarEmpresaConfig();
    final manual = await repository.carregarRegistroBackupManual();
    final destino = await resolverDestino(repository);
    final zip = await _localizarZipMaisRecente(repository);
    final pastas = await pastasRaizPermitidas(repository);
    final historico = await BackupHistoricoService.listar(
      pastasRaiz: pastas,
      limite: 8,
    );
    BackupHistoricoItem? item;
    for (final e in historico) {
      if (e.valido && e.escopo != LocalBackupEscopo.cadastroProdutos) {
        item = e;
        break;
      }
    }

    return {
      'ok': true,
      'pdvEmUso': SessaoOperacionalGuard.pdvEmUso,
      'emExecucao': _emExecucao || AutoBackupService.emExecucao,
      'pastaDestino': destino.path,
      'pastaConfigurada': config.backupAutomaticoPasta.trim().isNotEmpty ||
          manual.pastaPadrao.trim().isNotEmpty,
      'ultimoManualMs': manual.ultimoMs,
      'ultimoManualPath': manual.ultimoPath,
      'ultimoAutomaticoMs': config.ultimoBackupAutomaticoMs,
      if (item != null)
        'ultimoBackup': {
          'criadoEm': item.criadoEm.toIso8601String(),
          'tamanhoBancoKb': item.tamanhoBancoKb,
          'escopo': item.escopo.manifestValue,
          'pasta': item.pasta.path,
        },
      'temZip': zip != null,
      if (zip != null)
        'zip': {
          'nome': p.basename(zip.path),
          'tamanhoBytes': zip.lengthSync(),
          'modificadoEm': zip.lastModifiedSync().toIso8601String(),
        },
    };
  }

  static Future<Map<String, dynamic>> criar({
    required ObjectBox objectBox,
  }) async {
    if (_emExecucao || AutoBackupService.emExecucao) {
      throw BackupRemotoOcupadoException(
        'Ja existe um backup em andamento no PC servidor.',
      );
    }
    if (SessaoOperacionalGuard.pdvEmUso) {
      throw BackupRemotoPdvAbertoException(
        'O PDV esta aberto no PC servidor. Feche a venda e tente de novo, '
        'ou baixe o ultimo backup ja existente.',
      );
    }

    _emExecucao = true;
    try {
      final repository = AppConfigRepository();
      final destino = await resolverDestino(repository);
      final config = await repository.carregarEmpresaConfig();
      final nomeLoja =
          config.nomeLoja.trim().isEmpty ? 'LOJA' : config.nomeLoja.trim();

      final resultado = await LocalBackupService.executar(
        destinoRaiz: destino,
        tipo: LocalBackupTipo.manual,
        nomeLoja: nomeLoja,
        objectBox: objectBox,
        escopo: LocalBackupEscopo.completo,
      );

      await BackupPosExecucaoService.aposBackupSucesso(
        repository: repository,
        pastaRaizPrimaria: destino,
        pastaBackup: resultado.pastaBackup,
      );

      await repository.salvarRegistroBackupManual(
        ultimoMs: resultado.criadoEm.millisecondsSinceEpoch,
        ultimoPath: resultado.pastaBackup.path,
        ultimoTamanhoKb: resultado.tamanhoBancoKb,
        pastaPadrao: destino.path,
      );
      await repository.atualizarUltimoBackupAutomaticoMs(
        resultado.criadoEm.millisecondsSinceEpoch,
      );
      await repository.limparFalhaBackupAutomatico();

      final zip = await BackupZipService.exportarPasta(
        pastaBackup: resultado.pastaBackup,
      );
      _ultimoZipPath = zip.arquivo.path;

      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupCriar,
        usuarioLogin: 'terminal',
        resumo: 'Backup criado a pedido de um terminal',
        detalhes: {
          'caminho': resultado.pastaBackup.path,
          'zip': zip.arquivo.path,
        },
      );

      return {
        'ok': true,
        'pastaBackup': resultado.pastaBackup.path,
        'criadoEm': resultado.criadoEm.toIso8601String(),
        'tamanhoBancoKb': resultado.tamanhoBancoKb,
        'zipNome': p.basename(zip.arquivo.path),
        'zipTamanhoBytes': zip.arquivo.lengthSync(),
      };
    } finally {
      _emExecucao = false;
    }
  }

  static Future<File> obterZipParaDownload() async {
    final repository = AppConfigRepository();
    final atual = _ultimoZipPath;
    if (atual != null && File(atual).existsSync()) {
      final pastas = await pastasRaizPermitidas(repository);
      if (zipDentroDePastasPermitidas(atual, pastas)) {
        return File(atual);
      }
    }

    final existente = await _localizarZipMaisRecente(repository);
    if (existente != null) {
      _ultimoZipPath = existente.path;
      return existente;
    }

    final pastas = await pastasRaizPermitidas(repository);
    final historico = await BackupHistoricoService.listar(
      pastasRaiz: pastas,
      limite: 20,
    );
    for (final item in historico) {
      if (!item.valido) continue;
      if (item.escopo == LocalBackupEscopo.cadastroProdutos) continue;
      final zip = await BackupZipService.exportarPasta(pastaBackup: item.pasta);
      _ultimoZipPath = zip.arquivo.path;
      return zip.arquivo;
    }

    throw BackupRemotoSemArquivoException(
      'Nenhum backup completo encontrado no PC servidor. '
      'Crie um backup agora.',
    );
  }

  static Future<File?> _localizarZipMaisRecente(
    AppConfigRepository repository,
  ) async {
    final pastas = await pastasRaizPermitidas(repository);
    File? melhor;
    var melhorMs = 0;
    for (final raiz in pastas) {
      final dir = Directory(raiz);
      if (!dir.existsSync()) continue;
      await for (final entidade in dir.list(followLinks: false)) {
        if (entidade is! File) continue;
        if (!ehArquivoZipDeBackup(entidade.path)) continue;
        final ms = entidade.lastModifiedSync().millisecondsSinceEpoch;
        if (ms >= melhorMs) {
          melhorMs = ms;
          melhor = entidade;
        }
      }
    }
    return melhor;
  }
}

class BackupRemotoOcupadoException implements Exception {
  BackupRemotoOcupadoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupRemotoPdvAbertoException implements Exception {
  BackupRemotoPdvAbertoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupRemotoSemArquivoException implements Exception {
  BackupRemotoSemArquivoException(this.message);
  final String message;
  @override
  String toString() => message;
}
