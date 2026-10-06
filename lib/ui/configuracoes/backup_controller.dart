import 'package:intl/intl.dart';

import '../../data/local_backup_service.dart';
import '../../data/local_backup_validation.dart';

export '../../data/local_backup_validation.dart' show LocalBackupInvalidoException;

/// Textos padronizados do indicador de progresso do backup manual.
abstract final class BackupManualProgressoTextos {
  BackupManualProgressoTextos._();

  static const tituloDialogo = 'Gerando cópia de segurança';
  static const aguarde = 'Gerando cópia de segurança, aguarde...';
}

/// Dados exibidos no modal de sucesso após backup manual.
class BackupManualConclusaoInfo {
  const BackupManualConclusaoInfo({
    required this.caminho,
    required this.tamanhoTotalFormatado,
    required this.horarioConclusaoFormatado,
    this.descricaoExtra,
  });

  final String caminho;
  final String tamanhoTotalFormatado;
  final String horarioConclusaoFormatado;
  final String? descricaoExtra;

  factory BackupManualConclusaoInfo.fromResult(
    LocalBackupResult resultado, {
    DateFormat? formatadorDataHora,
  }) {
    final fmt = formatadorDataHora ?? DateFormat('dd/MM/yyyy HH:mm:ss');
    final kb = resultado.tamanhoPastaKb > 0
        ? resultado.tamanhoPastaKb
        : resultado.tamanhoBancoKb;
    final tamanho = LocalBackupValidation.formatarTamanhoBytes(
      (kb * 1024).round(),
    );
    String? extra;
    if (resultado.escopo == LocalBackupEscopo.cadastroProdutos) {
      extra =
          'Cadastro exportado: ${resultado.quantidadeProdutos ?? 0} produto(s).';
    }
    return BackupManualConclusaoInfo(
      caminho: resultado.pastaBackup.path,
      tamanhoTotalFormatado: tamanho,
      horarioConclusaoFormatado: fmt.format(resultado.criadoEm),
      descricaoExtra: extra,
    );
  }
}

/// Utilitários de feedback do backup manual (mensagens amigáveis).
abstract final class BackupController {
  BackupController._();

  static String mensagemErroAmigavel(Object erro) {
    if (erro is LocalBackupInvalidoException) {
      return erro.message;
    }
    final bruto = erro.toString();
    const prefixo = 'Exception: ';
    if (bruto.startsWith(prefixo)) {
      return bruto.substring(prefixo.length);
    }
    return bruto;
  }
}
