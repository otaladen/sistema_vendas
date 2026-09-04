import '../data/app_config_repository.dart';

enum BackupSaude {
  protegido,
  atencao,
  critico,
  /// Automatico ligado sem pasta de destino (agendamento fantasma).
  configIncompleta,
  desconhecido,
}

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
    this.automaticoSemDestino = false,
  });

  final BackupSaude saude;
  final int ultimoBackupMs;
  final String? ultimoBackupTipo;
  final String? ultimoBackupCaminho;
  final double ultimoBackupTamanhoKb;
  final int? proximoBackupAutomaticoMs;
  final int? horasDesdeUltimo;
  final bool automaticoAtivo;

  /// True quando o automatico esta marcado ativo mas sem pasta valida.
  final bool automaticoSemDestino;

  bool get exibirAlerta =>
      saude == BackupSaude.atencao ||
      saude == BackupSaude.critico ||
      saude == BackupSaude.configIncompleta;
}

abstract final class BackupStatusHelper {
  BackupStatusHelper._();

  static const int horasAlertaAtencao = 48;
  static const int horasAlertaCritico = 168;

  static bool pastaAutomaticaConfigurada(EmpresaConfig config) =>
      config.backupAutomaticoPasta.trim().isNotEmpty;

  static BackupStatusResumo avaliar({
    required EmpresaConfig config,
    required BackupRegistroManual manual,
  }) {
    final pastaOk = pastaAutomaticaConfigurada(config);
    final autoSemDestino = config.backupAutomaticoAtivo && !pastaOk;

    if (autoSemDestino) {
      final autoMs = config.ultimoBackupAutomaticoMs;
      final manualMs = manual.ultimoMs;
      final ultimoMs = autoMs > manualMs ? autoMs : manualMs;
      return BackupStatusResumo(
        saude: BackupSaude.configIncompleta,
        ultimoBackupMs: ultimoMs,
        ultimoBackupTipo: ultimoMs > 0
            ? (autoMs >= manualMs && autoMs > 0 ? 'automatico' : 'manual')
            : null,
        ultimoBackupCaminho: manualMs >= autoMs ? manual.ultimoPath : null,
        ultimoBackupTamanhoKb:
            manualMs >= autoMs ? manual.ultimoTamanhoKb : 0,
        proximoBackupAutomaticoMs: null,
        horasDesdeUltimo: ultimoMs > 0
            ? DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(ultimoMs))
                .inHours
            : null,
        automaticoAtivo: true,
        automaticoSemDestino: true,
      );
    }

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

  /// So agenda "proximo" com automatico ativo E pasta de destino preenchida.
  static int? _proximoMs(EmpresaConfig config, int ultimoMs) {
    if (!config.backupAutomaticoAtivo) return null;
    if (!pastaAutomaticaConfigurada(config)) return null;
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
        BackupSaude.configIncompleta => 'Configuracao incompleta',
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
