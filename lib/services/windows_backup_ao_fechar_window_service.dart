import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'configuracoes_service.dart';
import '../ui/app_global_error_handler.dart';

/// Intercepta o fechamento da janela no Windows enquanto o backup ao sair roda.
abstract final class WindowsBackupAoFecharWindowService {
  WindowsBackupAoFecharWindowService._();

  static _WindowsBackupCloseListener? _listener;
  static bool _fechamentoEmAndamento = false;

  static Future<void> ensureInitialized() async {
    if (!Platform.isWindows) return;
    await windowManager.ensureInitialized();
  }

  static Future<void> instalar({
    required ConfiguracoesService configuracoesService,
    required Future<void> Function({bool agendarHeadless}) executarBackupAoFechar,
    required bool Function() servidorComObjectBox,
  }) async {
    if (!Platform.isWindows) return;
    await ensureInitialized();
    _listener?.dispose();
    _listener = _WindowsBackupCloseListener(
      configuracoesService: configuracoesService,
      executarBackupAoFechar: executarBackupAoFechar,
      servidorComObjectBox: servidorComObjectBox,
    );
    windowManager.addListener(_listener!);
    await _listener!.atualizarPreventClose();
  }

  static Future<void> atualizarPreventClose() async {
    await _listener?.atualizarPreventClose();
  }

  static void remover() {
    _listener?.dispose();
    _listener = null;
  }
}

class _WindowsBackupCloseListener with WindowListener {
  _WindowsBackupCloseListener({
    required this.configuracoesService,
    required this.executarBackupAoFechar,
    required this.servidorComObjectBox,
  });

  final ConfiguracoesService configuracoesService;
  final Future<void> Function({bool agendarHeadless}) executarBackupAoFechar;
  final bool Function() servidorComObjectBox;

  Future<void> atualizarPreventClose() async {
    if (!Platform.isWindows) return;
    // Sempre intercepta no PC servidor para concluir rotinas de saida.
    await windowManager.setPreventClose(servidorComObjectBox());
  }

  void dispose() {
    windowManager.removeListener(this);
  }

  @override
  void onWindowClose() {
    unawaited(_tratarFechamento());
  }

  Future<void> _tratarFechamento() async {
    if (WindowsBackupAoFecharWindowService._fechamentoEmAndamento) return;
    WindowsBackupAoFecharWindowService._fechamentoEmAndamento = true;

    try {
      if (!servidorComObjectBox()) {
        await executarBackupAoFechar(agendarHeadless: true);
        await windowManager.destroy();
        return;
      }

      final backupAoFechar =
          await configuracoesService.repository.carregarBackupAoFecharAtivo();
      if (!backupAoFechar) {
        await executarBackupAoFechar(agendarHeadless: true);
        await windowManager.destroy();
        return;
      }

      await windowManager.setPreventClose(true);
      await _executarBackupComModalBloqueante();
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      await _fecharModalSeAberto();
      try {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      } catch (_) {}
    }
  }

  BuildContext? _dialogContext;

  Future<void> _executarBackupComModalBloqueante() async {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      unawaited(
        showDialog<void>(
          context: ctx,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (dialogCtx) {
            _dialogContext = dialogCtx;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('Backup de seguranca'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      'Realizando backup de seguranca... Por favor, aguarde.',
                      style: Theme.of(dialogCtx).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    try {
      await executarBackupAoFechar(agendarHeadless: true);
    } finally {
      await _fecharModalSeAberto();
    }
  }

  Future<void> _fecharModalSeAberto() async {
    final ctx = _dialogContext;
    _dialogContext = null;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  }
}
