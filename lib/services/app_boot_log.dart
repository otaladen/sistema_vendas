import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/local_app_data_paths.dart';

/// Log local de boot / pos-login (console + arquivo rotativo).
abstract final class AppBootLog {
  AppBootLog._();

  static const _nomeArquivo = 'boot_diagnostico.log';
  static const _maxBytes = 512 * 1024;

  static Future<void>? _fila;

  static void registrar(
    String etapa,
    Object erro, {
    StackTrace? stack,
    String? contexto,
  }) {
    final linha = _formatarLinha(etapa, erro, stack: stack, contexto: contexto);
    if (kDebugMode) {
      debugPrint('[BootLog] $linha');
    } else {
      // Release: so boot — nao silencia erros pos-login.
      // ignore: avoid_print
      print('[BootLog] $linha');
    }
    _enfileirarGravacao(linha);
  }

  static void info(String etapa, String mensagem) {
    final ts = DateTime.now().toIso8601String();
    final linha = '$ts INFO [$etapa] $mensagem';
    if (kDebugMode) {
      debugPrint('[BootLog] $linha');
    }
    _enfileirarGravacao(linha);
  }

  static String _formatarLinha(
    String etapa,
    Object erro, {
    StackTrace? stack,
    String? contexto,
  }) {
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer('$ts ERROR [$etapa]');
    if (contexto != null && contexto.trim().isNotEmpty) {
      buf.write(' ($contexto)');
    }
    buf.write(': $erro');
    if (stack != null) {
      buf.write('\n$stack');
    }
    return buf.toString();
  }

  static void _enfileirarGravacao(String linha) {
    final anterior = _fila;
    _fila = (anterior ?? Future<void>.value()).then((_) async {
      try {
        await _appendArquivo(linha);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BootLog] falha ao gravar arquivo: $e');
        }
      }
    });
  }

  static Future<File> _arquivoLog() async {
    final base = await obterDiretorioBaseDadosApp();
    final dir = Directory('${base.path}${Platform.pathSeparator}logs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_nomeArquivo');
  }

  static Future<void> _appendArquivo(String linha) async {
    final file = await _arquivoLog();
    await file.writeAsString('$linha\n\n', mode: FileMode.append, flush: true);
    try {
      final len = await file.length();
      if (len > _maxBytes) {
        final texto = await file.readAsString();
        final cortado = texto.substring(texto.length - (_maxBytes ~/ 2));
        await file.writeAsString(cortado, flush: true);
      }
    } catch (_) {}
  }

  static Future<String?> caminhoArquivoLog() async {
    try {
      final f = await _arquivoLog();
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
