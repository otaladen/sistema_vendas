import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../domain/local_backup_escopo.dart';
import '../services/app_boot_log.dart';
import 'local_app_data_paths.dart';
import 'local_backup_atomic.dart';
import 'local_backup_cadastro_produtos_service.dart';
import 'local_backup_copy.dart';
import 'local_backup_isolate.dart';
import 'local_backup_preferencias_service.dart';
import 'local_backup_validation.dart';
import 'objectbox.dart';
import 'sync/lan_sync_scheduler.dart';

export '../domain/local_backup_escopo.dart';

enum LocalBackupTipo { manual, automatico }

typedef BackupProgressCallback = void Function(double progresso, String etapa);

/// Estado de progresso consumivel pela UI (notifier ou stream).
class LocalBackupProgressoEstado {
  const LocalBackupProgressoEstado({
    required this.progresso,
    required this.etapa,
    this.decorrido = Duration.zero,
  });

  final double progresso;
  final String etapa;
  final Duration decorrido;

  int get percentual => (progresso * 100).round().clamp(0, 100);
}

class LocalBackupResult {
  const LocalBackupResult({
    required this.pastaBackup,
    required this.pastaDados,
    required this.tamanhoBancoKb,
    required this.criadoEm,
    required this.escopo,
    this.tamanhoPastaKb = 0,
    this.quantidadeProdutos,
  });

  final Directory pastaBackup;
  final Directory pastaDados;
  final double tamanhoBancoKb;

  /// Tamanho da pasta do backup inteira (banco + fotos + manifesto).
  final double tamanhoPastaKb;
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
    await Future<void>.delayed(Duration.zero);
    final baseDadosDir = await obterDiretorioBaseDadosApp();
    if (!baseDadosDir.existsSync()) {
      throw Exception('Pasta de dados local nao encontrada.');
    }
    if (escopo != LocalBackupEscopo.cadastroProdutos) {
      LocalBackupValidation.validarDadosAplicacao(baseDadosDir);
    }

    final agora = DateTime.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(agora);
    final pastaTemp = LocalBackupAtomic.pastaTemp(destinoRaiz, timestamp);
    final pastaFinal = LocalBackupAtomic.pastaFinal(destinoRaiz, timestamp);
    LocalBackupAtomic.removerPastaTempSeExistir(pastaTemp);
    pastaTemp.createSync(recursive: true);
    final pastaBackup = pastaTemp;

    if (escopo == LocalBackupEscopo.cadastroProdutos) {
      report(0.08, 'Preparando exportacao de produtos…');
      await Future<void>.delayed(Duration.zero);
      report(0.12, 'Exportando cadastro de produtos…');
      final resumo = await LocalBackupCadastroProdutosService.exportar(
        objectBox: objectBox,
        pastaBackup: pastaBackup,
        onProgress: onProgress,
      );
      LocalBackupValidation.validarCadastroProdutos(pastaBackup);

      final tamanhoPastaKb = await _kbDaPasta(pastaBackup);
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
        'tamanhoPastaKb': double.parse(tamanhoPastaKb.toStringAsFixed(2)),
        'quantidadeProdutos': resumo.quantidadeProdutos,
        'quantidadeFotos': resumo.quantidadeFotos,
        'pastaDados': LocalBackupCadastroProdutosService.subpasta,
        'incluiPreferencias': false,
      };
      try {
        await File(p.join(pastaBackup.path, manifestFileName)).writeAsString(
          const JsonEncoder.withIndent('  ').convert(manifest),
        );
        report(0.98, 'Finalizando copia…');
        final promovida = await LocalBackupAtomic.promoverPastaTemp(
          pastaTemp: pastaTemp,
          pastaFinal: pastaFinal,
          dadosValidacao: resumo.pasta,
          escopo: escopo,
        );
        report(1.0, 'Concluido');
        return LocalBackupResult(
          pastaBackup: promovida,
          pastaDados: resumo.pasta,
          tamanhoBancoKb: resumo.tamanhoTotalKb,
          tamanhoPastaKb: tamanhoPastaKb,
          criadoEm: agora,
          escopo: escopo,
          quantidadeProdutos: resumo.quantidadeProdutos,
        );
      } catch (e) {
        LocalBackupAtomic.removerPastaTempSeExistir(pastaTemp);
        rethrow;
      }
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
    AppBootLog.info(
      'local_backup',
      'Fechando ObjectBox para copia (${tipo.name}, ${escopo.manifestValue})',
    );
    await objectBox.fecharParaCopiaDeArquivos();
    try {
      final origemObjectBox = Directory(p.join(baseDadosDir.path, 'objectbox'));
      if (!origemObjectBox.existsSync()) {
        throw Exception('Pasta objectbox nao encontrada.');
      }

      final pularImagens = escopo == LocalBackupEscopo.semImagens
          ? nomesPastasImagemNoBackup
          : const <String>{};
      String? checksumDataMdb;
      if (escopo == LocalBackupEscopo.somenteBanco) {
        report(0.18, 'Preparando arquivos…');
        destinoDados.createSync(recursive: true);
        final destinoOb = Directory(p.join(destinoDados.path, 'objectbox'));
        destinoOb.createSync(recursive: true);
        final copia = await executarCopiaLocalBackupIsolate(
          somenteBanco: true,
          origem: origemObjectBox,
          destino: destinoOb,
          onProgress: report,
        );
        checksumDataMdb = copia.checksumDataMdbSha256;
      } else {
        report(
          0.16,
          escopo == LocalBackupEscopo.semImagens
              ? 'Preparando arquivos (sem fotos)…'
              : 'Preparando arquivos…',
        );
        destinoDados.createSync(recursive: true);
        final copia = await executarCopiaLocalBackupIsolate(
          somenteBanco: false,
          origem: baseDadosDir,
          destino: destinoDados,
          ignorarNomes: pularImagens,
          onProgress: report,
        );
        checksumDataMdb = copia.checksumDataMdbSha256;
        report(0.78, 'Exportando configuracoes locais…');
        await LocalBackupPreferenciasService.exportarParaPasta(pastaBackup);
      }

      report(0.88, 'Verificando integridade…');
      LocalBackupValidation.validarDadosAplicacao(destinoDados);

      final mdb = LocalBackupValidation.localizarDataMdb(destinoDados);
      final tamanhoKb = mdb == null ? 0.0 : mdb.lengthSync() / 1024.0;

      report(0.94, 'Gravando manifesto…');
      checksumDataMdb ??= LocalBackupAtomic.checksumDataMdb(destinoDados);
      final tamanhoPastaKb = escopo == LocalBackupEscopo.somenteBanco
          ? tamanhoKb + 2
          : await _kbDaPasta(pastaBackup);
      final manifest = {
        'app': 'sistema_vendas',
        'versaoApp': versaoApp,
        'empresa': nomeLoja,
        'tipo': tipo.name,
        'escopo': escopo.manifestValue,
        'criadoEm': agora.toIso8601String(),
        'tamanhoBancoKb': double.parse(tamanhoKb.toStringAsFixed(2)),
        'tamanhoPastaKb': double.parse(tamanhoPastaKb.toStringAsFixed(2)),
        'checksumDataMdbSha256': checksumDataMdb,
        'pastaDados': 'dados_aplicacao',
        'incluiPreferencias': escopo.incluiPreferencias,
      };
      try {
        await File(p.join(pastaBackup.path, manifestFileName)).writeAsString(
          const JsonEncoder.withIndent('  ').convert(manifest),
        );
        report(0.98, 'Finalizando copia…');
        final promovida = await LocalBackupAtomic.promoverPastaTemp(
          pastaTemp: pastaTemp,
          pastaFinal: pastaFinal,
          dadosValidacao: destinoDados,
          escopo: escopo,
        );
        report(1.0, 'Concluido');
        return LocalBackupResult(
          pastaBackup: promovida,
          pastaDados: destinoDados,
          tamanhoBancoKb: tamanhoKb,
          tamanhoPastaKb: tamanhoPastaKb,
          criadoEm: agora,
          escopo: escopo,
        );
      } catch (e) {
        LocalBackupAtomic.removerPastaTempSeExistir(pastaTemp);
        rethrow;
      }
    } catch (e) {
      LocalBackupAtomic.removerPastaTempSeExistir(pastaTemp);
      rethrow;
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

  static Future<double> _kbDaPasta(Directory pasta) async {
    final bytes = await tamanhoDiretorioBytes(pasta);
    return bytes / 1024.0;
  }
}
