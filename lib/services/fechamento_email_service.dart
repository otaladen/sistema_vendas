import 'dart:typed_data';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'fiscal_config_store.dart';

class FechamentoEmailException implements Exception {
  FechamentoEmailException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Envio do pacote de fechamento fiscal (ZIP + Excel) ao contador via SMTP.
abstract final class FechamentoEmailService {
  FechamentoEmailService._();

  static Future<void> enviarParaContador({
    required int mes,
    required int ano,
    required Uint8List zipBytes,
    required Uint8List excelBytes,
    required String nomeBaseArquivo,
    String? destinatarioOverride,
  }) async {
    await FiscalConfigStore.carregar();
    final cfg = FiscalConfigStore.efetivo;
    final para = (destinatarioOverride ?? cfg.emailContador).trim();
    if (!para.contains('@') || para.length < 5) {
      throw FechamentoEmailException(
        'E-mail do contador nao configurado. '
        'Cadastre em Configuracoes > Fiscal.',
      );
    }
    if (!cfg.smtpConfigurado) {
      throw FechamentoEmailException(
        'SMTP nao configurado. Informe servidor, usuario e senha em '
        'Configuracoes > Fiscal (envio ao contador).',
      );
    }

    final from = cfg.smtpFromEmail.trim().isNotEmpty
        ? cfg.smtpFromEmail.trim()
        : cfg.smtpUser.trim();
    final mesPad = mes.toString().padLeft(2, '0');
    final periodo = '$mesPad/$ano';
    final emitente = cfg.razaoSocialEmitente.trim().isNotEmpty
        ? cfg.razaoSocialEmitente.trim()
        : 'Empresa';

    final message = Message()
      ..from = Address(from, emitente)
      ..recipients.add(para)
      ..subject = 'Fechamento fiscal $periodo — $emitente'
      ..text = 'Segue em anexo o fechamento fiscal mensal ($periodo) de $emitente.\n\n'
          'Arquivos:\n'
          '- $nomeBaseArquivo.zip (XMLs + planilha na raiz)\n'
          '- $nomeBaseArquivo.xlsx (planilha contabilidade)\n\n'
          'Pastas no ZIP: Autorizadas/NFCe, Autorizadas/NFe, Canceladas, '
          'Inutilizadas, Entradas, Cartas_Correcao.\n'
      ..attachments = [
        StreamAttachment(
          Stream<List<int>>.fromIterable([zipBytes]),
          'application/zip',
          fileName: '$nomeBaseArquivo.zip',
        ),
        StreamAttachment(
          Stream<List<int>>.fromIterable([excelBytes]),
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          fileName: '$nomeBaseArquivo.xlsx',
        ),
      ];

    final smtpServer = SmtpServer(
      cfg.smtpHost.trim(),
      port: cfg.smtpPort,
      username: cfg.smtpUser.trim(),
      password: cfg.smtpPassword,
      ssl: cfg.smtpSsl,
      allowInsecure: !cfg.smtpSsl && cfg.smtpPort == 587,
    );

    try {
      await send(message, smtpServer);
    } on MailerException catch (e) {
      final detalhes = e.problems.map((p) => p.msg).join('; ');
      throw FechamentoEmailException(
        detalhes.isNotEmpty
            ? 'Falha ao enviar e-mail: $detalhes'
            : 'Falha ao enviar e-mail ao contador: $e',
      );
    } catch (e) {
      throw FechamentoEmailException('Falha ao enviar e-mail ao contador: $e');
    }
  }
}
