import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Chaves globais para SnackBar/navegacao fora de um [BuildContext] local
/// (ex.: erros em [runZonedGuarded] / [FlutterError.onError]).
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

DateTime? _ultimoSnackErroEm;
String? _ultimoSnackErroMsg;

/// Captura erros de framework, zona e isolate; mostra SnackBar amigavel.
void configurarTratamentoErrosGlobais() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
      );
    }
    reportarErroGlobal(details.exception);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('PlatformDispatcher.onError: $error\n$stack');
    }
    reportarErroGlobal(error);
    return true;
  };

  ErrorWidget.builder = (details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return const Material(
      color: Color(0xFFFAFAFA),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Algo deu errado nesta tela.\nVolte e tente novamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.35),
            ),
          ),
        ),
      ),
    );
  };
}

/// Entrada unica para erros de zona / background (SnackBar, sem crash).
void reportarErroGlobal(Object erro, [StackTrace? stack]) {
  if (kDebugMode && stack != null) {
    debugPrint('Erro global: $erro\n$stack');
  }
  _agendarSnackErroAmigavel(erro);
}

void _agendarSnackErroAmigavel(Object erro) {
  // Evita SnackBar durante o frame de erro / sem tree montada.
  scheduleMicrotask(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mostrarSnackErroAmigavel(erro);
    });
  });
}

void _mostrarSnackErroAmigavel(Object erro) {
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;

  final msg = _mensagemAmigavel(erro);
  final agora = DateTime.now();
  final ultimo = _ultimoSnackErroEm;
  if (ultimo != null &&
      agora.difference(ultimo) < const Duration(seconds: 4) &&
      _ultimoSnackErroMsg == msg) {
    return;
  }
  _ultimoSnackErroEm = agora;
  _ultimoSnackErroMsg = msg;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
}

String _mensagemAmigavel(Object erro) {
  final raw = erro.toString().toLowerCase();
  if (raw.contains('socket') ||
      raw.contains('network') ||
      raw.contains('connection') ||
      raw.contains('failed host lookup') ||
      raw.contains('timed out') ||
      raw.contains('timeout') ||
      raw.contains('servidor offline') ||
      raw.contains('connection refused')) {
    return 'Falha de rede. Verifique a conexao com o servidor e tente de novo.';
  }
  if (raw.contains('objectbox') || raw.contains('database')) {
    return 'Falha ao acessar dados locais. Tente de novo ou reinicie o app.';
  }
  return 'Ocorreu um erro inesperado. A operacao pode nao ter sido concluida.';
}

/// Em release, silencia [debugPrint] para nao pesar o console o dia inteiro.
void silenciarDebugPrintEmProducao() {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
}
