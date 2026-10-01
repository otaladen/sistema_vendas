import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'local_backup_copy.dart';

/// Resultado da copia pesada executada fora da thread principal.
class LocalBackupCopiaIsolateResult {
  const LocalBackupCopiaIsolateResult({this.checksumDataMdbSha256});

  final String? checksumDataMdbSha256;
}

class _LocalBackupCopiaArgs {
  _LocalBackupCopiaArgs({
    required this.replyPort,
    required this.modo,
    required this.origemPath,
    required this.destinoPath,
    required this.ignorarNomes,
  });

  final SendPort replyPort;
  final String modo;
  final String origemPath;
  final String destinoPath;
  final List<String> ignorarNomes;
}

void _localBackupCopiaEntry(_LocalBackupCopiaArgs args) async {
  void report(double v, String etapa) {
    args.replyPort.send(['progress', v, etapa]);
  }

  try {
    final ignorar = args.ignorarNomes.toSet();
    String? checksum;
    if (args.modo == 'somente_banco') {
      report(0.24, 'Copiando banco de dados…');
      await copiarObjectBoxSomenteBanco(
        origem: Directory(args.origemPath),
        destino: Directory(args.destinoPath),
        onProgressoBytes: (copiados, total) {
          if (total <= 0) {
            report(0.55, 'Copiando banco de dados…');
            return;
          }
          final frac = copiados / total;
          final pct = (frac * 100).round().clamp(0, 100);
          report(
            0.24 + frac * 0.48,
            'Copiando banco de dados ($pct%)…',
          );
        },
      );
      report(0.76, 'Calculando integridade do banco…');
      final mdb = File(p.join(args.destinoPath, 'data.mdb'));
      checksum = sha256.convert(await mdb.readAsBytes()).toString();
    } else {
      report(0.2, 'Contando arquivos…');
      final origem = Directory(args.origemPath);
      final totalBytes = await contarBytesArquivosRecursivo(
        origem,
        ignorarNomes: ignorar,
      );
      report(0.22, 'Copiando dados…');
      await copiarDiretorioRecursivo(
        origem: origem,
        destino: Directory(args.destinoPath),
        ignorarNomes: ignorar,
        bytesTotalPrevisto: totalBytes > 0 ? totalBytes : null,
        onProgressoBytes: totalBytes > 0
            ? (copiados, total) {
                final frac = copiados / total;
                final pct = (frac * 100).round().clamp(0, 100);
                report(
                  0.22 + frac * 0.52,
                  'Copiando dados ($pct%)…',
                );
              }
            : null,
        onArquivoCopiado: totalBytes <= 0
            ? () => report(0.4, 'Copiando dados…')
            : null,
      );
      report(0.76, 'Calculando integridade do banco…');
      final mdb = _localizarDataMdb(Directory(args.destinoPath));
      if (mdb != null) {
        checksum = sha256.convert(await mdb.readAsBytes()).toString();
      }
    }
    args.replyPort.send(['done', checksum]);
  } catch (e) {
    args.replyPort.send(['error', e.toString()]);
  }
}

File? _localizarDataMdb(Directory dadosAplicacao) {
  final direto = File(p.join(dadosAplicacao.path, 'data.mdb'));
  if (direto.existsSync()) return direto;
  final aninhado =
      File(p.join(dadosAplicacao.path, 'objectbox', 'data.mdb'));
  if (aninhado.existsSync()) return aninhado;
  return null;
}

/// Executa a copia de arquivos em [Isolate] e repassa progresso para a UI.
Future<LocalBackupCopiaIsolateResult> executarCopiaLocalBackupIsolate({
  required bool somenteBanco,
  required Directory origem,
  required Directory destino,
  Set<String> ignorarNomes = const {},
  void Function(double progresso, String etapa)? onProgress,
}) async {
  final receivePort = ReceivePort();
  final args = _LocalBackupCopiaArgs(
    replyPort: receivePort.sendPort,
    modo: somenteBanco ? 'somente_banco' : 'diretorio',
    origemPath: origem.path,
    destinoPath: destino.path,
    ignorarNomes: ignorarNomes.toList(),
  );

  await Isolate.spawn(_localBackupCopiaEntry, args);

  String? checksum;
  await for (final message in receivePort) {
    if (message is! List || message.isEmpty) continue;
    final tag = message[0];
    if (tag == 'progress' && message.length >= 3) {
      onProgress?.call(
        (message[1] as num).toDouble(),
        message[2] as String,
      );
    } else if (tag == 'done') {
      checksum = message.length >= 2 ? message[1] as String? : null;
      receivePort.close();
      break;
    } else if (tag == 'error') {
      receivePort.close();
      throw Exception(message.length >= 2 ? message[1] : 'Falha na copia.');
    }
  }

  return LocalBackupCopiaIsolateResult(checksumDataMdbSha256: checksum);
}
