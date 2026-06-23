import 'dart:io';

import '../data/local_backup_service.dart';

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
  });

  final Directory pasta;
  final DateTime criadoEm;
  final LocalBackupTipo? tipo;
  final double tamanhoBancoKb;
  final String empresa;
  final bool valido;
  final String pastaRaiz;

  String get rotuloTipo => switch (tipo) {
        LocalBackupTipo.manual => 'Manual',
        LocalBackupTipo.automatico => 'Automatico',
        null => 'Desconhecido',
      };

  String get tamanhoFormatado {
    if (tamanhoBancoKb <= 0) return '—';
    if (tamanhoBancoKb >= 1024) {
      return '${(tamanhoBancoKb / 1024).toStringAsFixed(1)} MB';
    }
    return '${tamanhoBancoKb.toStringAsFixed(0)} KB';
  }
}
