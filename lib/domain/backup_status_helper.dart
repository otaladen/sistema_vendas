import '../data/app_config_repository.dart';

enum BackupSaude { protegido, atencao, critico, desconhecido }

/// Resumo da saude dos backups locais (painel e alertas).
class BackupStatusResumo {
  const BackupStatusResumo({
    required this.saude,
    this.ultimoBackupMs = 0,
    this.ultimoBackupTipo,
    this.ultimoBackupCaminho,
    this.ultimoBackupTamanhoKb = 0,
    this.proximoBackupAutomaticoMs,
    this.horasDesdeUltimo,
    this.automaticoAtivo = false,
  });

  final BackupSaude saude;
  final int ultimoBackupMs;
  final String? ultimoBackupTipo;
  final String? ultimoBackupCaminho;
  final double ultimoBackupTamanhoKb;
  final int? proximoBackupAutomaticoMs;
  final int? horasDesdeUltimo;
  final bool automaticoAtivo;

  bool get exibirAlerta =>
      saude == BackupSaude.atencao || saude == BackupSaude.critico;
}

abstract final class BackupStatusHelper {
  BackupStatusHelper._();

  static const int horasAlertaAtencao = 48;
  static const int horasAlertaCritico = 168;

  static BackupStatusResumo avaliar({
    required EmpresaConfig config,
    required BackupRegistroManual manual,
  }) {
    final autoMs = config.ultimoBackupAutomaticoMs;
    final manualMs = manual.ultimoMs;
    final ultimoMs = autoMs > manualMs ? autoMs : manualMs;
    String? tipo;
    String? caminho;
    var tamanhoKb = 0.0;

    if (ultimoMs <= 0) {
      return BackupStatusResumo(
        saude: BackupSaude.critico,
        automaticoAtivo: config.backupAutomaticoAtivo,
        proximoBackupAutomaticoMs: _proximoMs(config, 0),
      );
    }

    if (autoMs >= manualMs && autoMs > 0) {
      tipo = 'automatico';
    } else {
      tipo = 'manual';
      caminho = manual.ultimoPath;
      tamanhoKb = manual.ultimoTamanhoKb;
    }

    final ultimo = DateTime.fromMillisecondsSinceEpoch(ultimoMs);
    final horas = DateTime.now().difference(ultimo).inHours;

    BackupSaude saude;
    if (horas >= horasAlertaCritico) {
      saude = BackupSaude.critico;
    } else if (horas >= horasAlertaAtencao) {
      saude = BackupSaude.atencao;
    } else {
      saude = BackupSaude.protegido;
    }

    return BackupStatusResumo(
      saude: saude,
      ultimoBackupMs: ultimoMs,
      ultimoBackupTipo: tipo,
      ultimoBackupCaminho: caminho,
      ultimoBackupTamanhoKb: tamanhoKb,
      proximoBackupAutomaticoMs: _proximoMs(config, ultimoMs),
      horasDesdeUltimo: horas,
      automaticoAtivo: config.backupAutomaticoAtivo,
    );
  }

  static int? _proximoMs(EmpresaConfig config, int ultimoMs) {
    if (!config.backupAutomaticoAtivo) return null;
    if (ultimoMs <= 0) {
      return DateTime.now().millisecondsSinceEpoch;
    }
    final intervalo = Duration(
      minutes: config.backupAutomaticoIntervaloMinutos.clamp(15, 10080),
    );
    return DateTime.fromMillisecondsSinceEpoch(ultimoMs)
        .add(intervalo)
        .millisecondsSinceEpoch;
  }

  static String rotuloSaude(BackupSaude s) => switch (s) {
        BackupSaude.protegido => 'Protegido',
        BackupSaude.atencao => 'Atencao',
        BackupSaude.critico => 'Sem backup recente',
        BackupSaude.desconhecido => 'Desconhecido',
      };

  static String rotuloIntervalo(int minutos) {
    final m = minutos.clamp(15, 10080);
    if (m == 60) return 'A cada 1 hora';
    if (m == 360) return 'A cada 6 horas';
    if (m == 720) return 'A cada 12 horas';
    if (m == 1440) return 'Diariamente (24 horas)';
    return 'A cada $m minutos';
  }
}
