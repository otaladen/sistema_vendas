import 'dart:io';

import '../data/local_backup_service.dart';
import '../data/local_backup_validation.dart';
import '../domain/local_backup_escopo.dart';

/// Entrada da lista de backups encontrados em disco.
class BackupHistoricoItem {
  const BackupHistoricoItem({
    required this.pasta,
    required this.criadoEm,
    required this.tipo,
    required this.tamanhoBancoKb,
    required this.empresa,
    required this.valido,
    required this.pastaRaiz,
    this.escopo = LocalBackupEscopo.completo,
    this.tamanhoPastaKb = 0,
  });

  final Directory pasta;
  final DateTime criadoEm;
  final LocalBackupTipo? tipo;
  final double tamanhoBancoKb;

  /// Pasta inteira do backup. 0 em copias antigas ate a medicao preencher.
  final double tamanhoPastaKb;
  final String empresa;
  final bool valido;
  final String pastaRaiz;
  final LocalBackupEscopo escopo;

  String get rotuloTipo => switch (tipo) {
        LocalBackupTipo.manual => 'Manual',
        LocalBackupTipo.automatico => 'Automatico',
        null => 'Desconhecido',
      };

  String get rotuloEscopo => escopo.rotulo;

  String get tamanhoFormatado {
    final pasta = tamanhoPastaKb;
    final banco = tamanhoBancoKb;
    if (pasta > 0 && banco > 0 && pasta > banco * 1.15) {
      return '${LocalBackupValidation.formatarTamanhoKb(pasta)} '
          '(banco ${LocalBackupValidation.formatarTamanhoKb(banco)})';
    }
    if (pasta > 0) return LocalBackupValidation.formatarTamanhoKb(pasta);
    return LocalBackupValidation.formatarTamanhoKb(banco);
  }
}
