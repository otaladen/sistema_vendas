import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'lan_servidor_headless_service.dart';

/// Sobe o **servidor sem janela** ao ligar o PC (Startup + tarefa agendada).
///
/// Equivalente ao ERP antigo: ligou o PC servidor, os terminais ja funcionam.
/// Ao abrir o app com interface neste PC, o headless e parado e a UI assume
/// o banco; ao fechar a UI, o headless volta.
abstract final class WindowsAppStartupHelper {
  WindowsAppStartupHelper._();

  static const _prefsKey = 'windows_iniciar_app_com_windows';
  static const _arquivoCmd = 'SistemaVendas_ServidorTerminais.cmd';
  static const nomeTarefa = r'SistemaVendas_ServidorTerminais';

  static Future<bool> estaAtivo() async {
    if (!Platform.isWindows) return false;
    final prefs = await SharedPreferences.getInstance();
    final marcado = prefs.getBool(_prefsKey) ?? false;
    if (!marcado) return false;
    if (_arquivoStartup().existsSync()) return true;
    return _tarefaInstalada();
  }

  /// Ativa/desativa inicio automatico (atalho Startup + schtasks ONLOGON).
  static Future<String?> definir(bool ativo) async {
    if (!Platform.isWindows) {
      return 'Disponivel apenas no Windows.';
    }
    final prefs = await SharedPreferences.getInstance();
    if (!ativo) {
      await _removerStartupCmd();
      await _removerTarefa();
      await prefs.setBool(_prefsKey, false);
      return null;
    }

    final exe = Platform.resolvedExecutable;
    if (exe.trim().isEmpty || !File(exe).existsSync()) {
      return 'Executavel do app nao encontrado.';
    }
    if (!exe.toLowerCase().endsWith('.exe')) {
      return 'Instale o sistema compilado (.exe) para iniciar com o Windows. '
          'No modo desenvolvimento (flutter run) o atalho nao e confiavel.';
    }

    try {
      await _escreverStartupCmd(exe);
    } catch (e) {
      return 'Nao foi possivel criar o atalho de inicializacao: $e';
    }

    // Tarefa ONLOGON reforça o Startup (mais confiavel apos login).
    try {
      await _instalarTarefa(exe);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowsAppStartupHelper schtasks: $e');
      }
    }

    await prefs.setBool(_prefsKey, true);
    return null;
  }

  /// Se este PC e servidor e o usuario nao desativou, garante o registro no boot.
  ///
  /// Chamado ao salvar modo servidor / ao subir a API — assim nao depende de
  /// o operador lembrar do switch "Servidor ao ligar o PC".
  static Future<void> garantirRegistroSeServidor() async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    // Opt-out explicito: nao forçar de volta.
    if (prefs.containsKey(_prefsKey) && prefs.getBool(_prefsKey) == false) {
      return;
    }
    if (await estaAtivo()) return;
    await definir(true);
  }

  /// Apos fechar o app com UI, reacende o headless (terminais continuam).
  static Future<void> agendarHeadlessAposSaida() async {
    if (!Platform.isWindows) return;
    if (!await estaAtivo()) return;
    final exe = Platform.resolvedExecutable;
    if (exe.trim().isEmpty || !File(exe).existsSync()) return;
    final arg = LanServidorHeadlessService.argHeadless;
    try {
      // Espera o processo atual liberar o ObjectBox, depois sobe o headless.
      // ping ~3s + margem para fechar o store.
      await Process.start(
        'cmd',
        [
          '/c',
          'ping 127.0.0.1 -n 5 >nul & start "" /B "$exe" $arg',
        ],
        mode: ProcessStartMode.detached,
        workingDirectory: File(exe).parent.path,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WindowsAppStartupHelper.agendarHeadlessAposSaida: $e');
      }
    }
  }

  static Future<void> _escreverStartupCmd(String exe) async {
    final arquivo = _arquivoStartup();
    arquivo.parent.createSync(recursive: true);
    final workDir = File(exe).parent.path;
    final arg = LanServidorHeadlessService.argHeadless;
    // Delay: rede/Wi-Fi costuma subir depois do login.
    arquivo.writeAsStringSync(
      '@echo off\r\n'
      'rem Sistema de Vendas — servidor de terminais ao ligar o PC\r\n'
      'cd /d "$workDir"\r\n'
      'timeout /t 20 /nobreak >nul\r\n'
      'start "" /B "$exe" $arg\r\n',
      flush: true,
    );
  }

  static Future<void> _removerStartupCmd() async {
    try {
      final arquivo = _arquivoStartup();
      if (arquivo.existsSync()) arquivo.deleteSync();
    } catch (_) {}
  }

  static Future<bool> _tarefaInstalada() async {
    final r = await Process.run(
      'schtasks',
      ['/Query', '/TN', nomeTarefa, '/FO', 'LIST'],
      runInShell: true,
    );
    return r.exitCode == 0;
  }

  static Future<void> _instalarTarefa(String exe) async {
    await _removerTarefa();
    final arg = LanServidorHeadlessService.argHeadless;
    final tr = '"$exe" $arg';
    final r = await Process.run(
      'schtasks',
      [
        '/Create',
        '/TN',
        nomeTarefa,
        '/TR',
        tr,
        '/SC',
        'ONLOGON',
        '/DELAY',
        '0000:30',
        '/RL',
        'LIMITED',
        '/F',
      ],
      runInShell: true,
    );
    if (r.exitCode != 0) {
      throw Exception(
        'Falha ao criar tarefa: ${r.stderr.toString().trim()}',
      );
    }
  }

  static Future<void> _removerTarefa() async {
    if (!await _tarefaInstalada()) return;
    await Process.run(
      'schtasks',
      ['/Delete', '/TN', nomeTarefa, '/F'],
      runInShell: true,
    );
  }

  static File _arquivoStartup() {
    final appData = Platform.environment['APPDATA'] ?? '';
    final dir = p.join(
      appData,
      'Microsoft',
      'Windows',
      'Start Menu',
      'Programs',
      'Startup',
    );
    return File(p.join(dir, _arquivoCmd));
  }
}
