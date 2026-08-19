import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_config_repository.dart';
import '../data/api/lan_api_url.dart';
import '../data/objectbox.dart';
import 'lan_api_server.dart';
import 'lan_servidor_bootstrap.dart';

/// Processo sem janela: ObjectBox + API de terminais (como o servidor do ERP antigo).
///
/// Sobe com o Windows via `--servidor-terminais-headless`.
/// Ao abrir o app com interface neste PC, [pararInstanciaSeExistir] encerra
/// o processo de fundo e libera o banco.
abstract final class LanServidorHeadlessService {
  LanServidorHeadlessService._();

  static const argHeadless = '--servidor-terminais-headless';
  static const _pidFileName = 'lan_servidor_headless.pid';

  static bool deveExecutar(List<String> args) => args.contains(argHeadless);

  /// Encerra instancia headless, se existir (libera ObjectBox para a UI).
  static Future<void> pararInstanciaSeExistir() async {
    if (kIsWeb || !Platform.isWindows) return;
    final arquivo = await _arquivoPid();
    if (!arquivo.existsSync()) return;

    final salvo = int.tryParse(arquivo.readAsStringSync().trim());
    try {
      arquivo.deleteSync();
    } catch (_) {}

    if (salvo == null || salvo <= 0) return;
    // `pid` = processo atual (dart:io).
    if (salvo == pid) return;

    try {
      await Process.run('taskkill', ['/PID', '$salvo', '/F'], runInShell: true);
    } catch (e) {
      debugPrint('LanServidorHeadless: taskkill $salvo: $e');
    }
    // Espera o lock do ObjectBox liberar.
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  /// Sobe a API e permanece vivo ate o processo ser encerrado.
  static Future<int> executarEManterVivo() async {
    if (!Platform.isWindows) return 2;

    // Evita duas instancias: mata headless anterior (Startup + schtasks).
    await pararInstanciaSeExistir();

    // Se a UI (ou outro processo) ja estiver atendendo a porta, nao disputa.
    if (await _portaApiJaEmUso()) {
      debugPrint('Headless: API ja ativa na porta — nada a fazer.');
      return 0;
    }

    late final ObjectBox objectBox;
    try {
      objectBox = await ObjectBox.create();
    } catch (e, st) {
      debugPrint('Headless: falha ObjectBox: $e\n$st');
      return 4;
    }

    final configRepo = AppConfigRepository();
    final config = await configRepo.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva || !config.redeModoServidor) {
      debugPrint(
        'Headless: rede nao esta em modo servidor. '
        'Configure no app (Configuracoes > Rede) e reinicie o PC.',
      );
      return 5;
    }

    // Aguarda a pilha de rede apos o login do Windows.
    await Future<void>.delayed(const Duration(seconds: 2));

    try {
      await _gravarPid();
    } catch (e) {
      debugPrint('Headless: nao gravou pid: $e');
    }

    await LanServidorBootstrap.garantirAtivo(
      objectBox: objectBox,
      configRepository: configRepo,
    );

    if (!LanApiServerHub.instance.ativo) {
      debugPrint(
        'Headless: API nao subiu. ${LanServidorBootstrap.ultimoErro ?? ""}',
      );
      await _limparPid();
      return 6;
    }

    debugPrint(
      'Headless: servidor de terminais ativo (sem janela). PID $pid',
    );

    // Mantem o isolate vivo (HttpServer + ObjectBox).
    await Completer<void>().future;
    return 0;
  }

  static Future<File> _arquivoPid() async {
    final base = await getApplicationSupportDirectory();
    return File(p.join(base.path, _pidFileName));
  }

  static Future<void> _gravarPid() async {
    final f = await _arquivoPid();
    f.writeAsStringSync('$pid', flush: true);
  }

  static Future<void> _limparPid() async {
    try {
      final f = await _arquivoPid();
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  static Future<bool> _portaApiJaEmUso() async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        LanApiUrl.portaPadrao,
        shared: false,
      );
      await socket.close();
      return false;
    } catch (_) {
      return true;
    }
  }
}
