import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../domain/local_backup_escopo.dart';
import 'local_app_data_paths.dart';
import 'local_backup_cadastro_produtos_service.dart';
import 'local_backup_copy.dart';
import 'local_backup_preferencias_service.dart';
import 'local_backup_validation.dart';
import 'objectbox.dart';
import 'sync/lan_sync_scheduler.dart';

export '../domain/local_backup_escopo.dart';

enum LocalBackupTipo { manual, automatico }

typedef BackupProgressCallback = void Function(double progresso, String etapa);

class LocalBackupResult {
  const LocalBackupResult({
    required this.pastaBackup,
    required this.pastaDados,
    required this.tamanhoBancoKb,
    required this.criadoEm,
    required this.escopo,
    this.quantidadeProdutos,
  });

  final Directory pastaBackup;
  final Directory pastaDados;
  final double tamanhoBancoKb;
  final DateTime criadoEm;
  final LocalBackupEscopo escopo;
  final int? quantidadeProdutos;
}

/// Copia dos dados locais com manifesto e progresso.
class LocalBackupService {
  LocalBackupService._();

  static const String manifestFileName = 'manifest.json';
  static const String versaoApp = '1.0.0';

  static Future<LocalBackupEscopo> lerEscopoManifest(Directory pastaBackup) async {
    final arquivo = File(p.join(pastaBackup.path, manifestFileName));
    if (!arquivo.existsSync()) return LocalBackupEscopo.completo;
    try {
      final map = jsonDecode(arquivo.readAsStringSync()) as Map;
      return localBackupEscopoFromManifest(map['escopo']);
    } catch (_) {
      return LocalBackupEscopo.completo;
    }
  }

  static Future<LocalBackupResult> executar({
    required Directory destinoRaiz,
    required LocalBackupTipo tipo,
    required String nomeLoja,
    required ObjectBox objectBox,
    LocalBackupEscopo escopo = LocalBackupEscopo.completo,
    LanSyncScheduler? lanSyncScheduler,
    BackupProgressCallback? onProgress,
  }) async {
    void report(double v, String etapa) => onProgress?.call(v, etapa);

    report(0.02, 'Validando dados locais…');
    final baseDadosDir = await obterDiretorioBaseDadosApp();
    if (!baseDadosDir.existsSync()) {
      throw Exception('Pasta de dados local nao encontrada.');
    }
    if (escopo != LocalBackupEscopo.cadastroProdutos) {
      LocalBackupValidation.validarDadosAplicacao(baseDadosDir);
    }

    final agora = DateTime.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(agora);
    final pastaBackup = Directory(
      p.join(destinoRaiz.path, 'backup_sistema_vendas_$timestamp'),
    );
    pastaBackup.createSync(recursive: true);

    if (escopo == LocalBackupEscopo.cadastroProdutos) {
      report(0.12, 'Exportando cadastro de produtos…');
      final resumo = await LocalBackupCadastroProdutosService.exportar(
        objectBox: objectBox,
        pastaBackup: pastaBackup,
        onProgress: onProgress,
      );
      LocalBackupValidation.validarCadastroProdutos(pastaBackup);

      final manifest = {
        'app': 'sistema_vendas',
        'versaoApp': versaoApp,
        'empresa': nomeLoja,
        'tipo': tipo.name,
        'escopo': escopo.manifestValue,
        'criadoEm': agora.toIso8601String(),
        'tamanhoBancoKb': double.parse(
          resumo.tamanhoTotalKb.toStringAsFixed(2),
        ),
        'quantidadeProdutos': resumo.quantidadeProdutos,
        'quantidadeFotos': resumo.quantidadeFotos,
        'pastaDados': LocalBackupCadastroProdutosService.subpasta,
        'incluiPreferencias': false,
      };
      await File(p.join(pastaBackup.path, manifestFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );

      report(1.0, 'Concluido');
      return LocalBackupResult(
        pastaBackup: pastaBackup,
        pastaDados: resumo.pasta,
        tamanhoBancoKb: resumo.tamanhoTotalKb,
        criadoEm: agora,
        escopo: escopo,
        quantidadeProdutos: resumo.quantidadeProdutos,
      );
    }

    final destinoDados = Directory(
      p.join(pastaBackup.path, 'dados_aplicacao'),
    );

    report(0.12, 'Preparando copia…');
    var syncParada = false;
    if (lanSyncScheduler != null && lanSyncScheduler.estaAgendado) {
      await lanSyncScheduler.parar();
      syncParada = true;
    }
    await objectBox.fecharParaCopiaDeArquivos();
    try {
      final origemObjectBox = Directory(p.join(baseDadosDir.path, 'objectbox'));
      if (!origemObjectBox.existsSync()) {
        throw Exception('Pasta objectbox nao encontrada.');
      }

      if (escopo == LocalBackupEscopo.somenteBanco) {
        report(0.22, 'Copiando banco…');
        final destinoOb = Directory(p.join(destinoDados.path, 'objectbox'));
        destinoOb.createSync(recursive: true);
        await copiarDiretorioRecursivo(
          origem: origemObjectBox,
          destino: destinoOb,
          onArquivoCopiado: () => report(0.5, 'Copiando banco…'),
        );
      } else {
        report(0.18, 'Contando arquivos…');
        final totalArquivos = await contarArquivosRecursivo(baseDadosDir);
        report(0.22, 'Copiando dados…');
        var copiados = 0;
        await copiarDiretorioRecursivo(
          origem: baseDadosDir,
          destino: destinoDados,
          onArquivoCopiado: totalArquivos > 0
              ? () {
                  copiados++;
                  final frac = copiados / totalArquivos;
                  report(
                    0.22 + frac * 0.52,
                    'Copiando… ($copiados/$totalArquivos)',
                  );
                }
              : null,
        );
        report(0.78, 'Exportando configuracoes locais…');
        await LocalBackupPreferenciasService.exportarParaPasta(pastaBackup);
      }

      report(0.88, 'Verificando integridade…');
      LocalBackupValidation.validarDadosAplicacao(destinoDados);

      final mdb = LocalBackupValidation.localizarDataMdb(destinoDados);
      final tamanhoKb = mdb == null ? 0.0 : mdb.lengthSync() / 1024.0;

      report(0.94, 'Gravando manifesto…');
      final manifest = {
        'app': 'sistema_vendas',
        'versaoApp': versaoApp,
        'empresa': nomeLoja,
        'tipo': tipo.name,
        'escopo': escopo.manifestValue,
        'criadoEm': agora.toIso8601String(),
        'tamanhoBancoKb': double.parse(tamanhoKb.toStringAsFixed(2)),
        'pastaDados': 'dados_aplicacao',
        'incluiPreferencias': escopo == LocalBackupEscopo.completo,
      };
      await File(p.join(pastaBackup.path, manifestFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );

      report(1.0, 'Concluido');
      return LocalBackupResult(
        pastaBackup: pastaBackup,
        pastaDados: destinoDados,
        tamanhoBancoKb: tamanhoKb,
        criadoEm: agora,
        escopo: escopo,
      );
    } finally {
      try {
        await objectBox.reabrirAposCopiaDeArquivos();
      } catch (_) {}
      if (syncParada && lanSyncScheduler != null) {
        try {
          await lanSyncScheduler.iniciar();
        } catch (_) {}
      }
    }
  }
}
