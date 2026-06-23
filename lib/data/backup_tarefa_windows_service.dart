import 'dart:io';

/// Tarefa agendada no Windows (schtasks) para backup com app fechado.
class BackupTarefaWindowsService {
  BackupTarefaWindowsService._();

  static const nomeTarefa = r'SistemaVendas_Backup';

  static bool get suportado => Platform.isWindows;

  static Future<bool> tarefaInstalada() async {
    if (!suportado) return false;
    final r = await Process.run(
      'schtasks',
      ['/Query', '/TN', nomeTarefa, '/FO', 'LIST'],
      runInShell: true,
    );
    return r.exitCode == 0;
  }

  static Future<void> instalar({
    required String horarioHhMm,
    required String argumentosExe,
  }) async {
    if (!suportado) {
      throw UnsupportedError('Tarefa agendada so esta disponivel no Windows.');
    }
    final exe = Platform.resolvedExecutable;
    if (!exe.toLowerCase().endsWith('.exe')) {
      throw Exception(
        'Instale o sistema compilado (.exe) para usar tarefa agendada. '
        'No modo desenvolvimento (flutter run) nao e possivel.',
      );
    }

    final partes = horarioHhMm.split(':');
    if (partes.length != 2) {
      throw Exception('Horario invalido. Use HH:mm.');
    }
    final hh = partes[0].padLeft(2, '0');
    final mm = partes[1].padLeft(2, '0');

    await remover();

    final tr = '"$exe" $argumentosExe';
    final r = await Process.run(
      'schtasks',
      [
        '/Create',
        '/TN',
        nomeTarefa,
        '/TR',
        tr,
        '/SC',
        'DAILY',
        '/ST',
        '$hh:$mm',
        '/RL',
        'HIGHEST',
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

  static Future<void> remover() async {
    if (!suportado) return;
    if (!await tarefaInstalada()) return;
    await Process.run(
      'schtasks',
      ['/Delete', '/TN', nomeTarefa, '/F'],
      runInShell: true,
    );
  }

  static String normalizarHorario(String? raw) {
    final t = (raw ?? '22:00').trim();
    final partes = t.split(':');
    if (partes.length != 2) return '22:00';
    final h = int.tryParse(partes[0]) ?? 22;
    final m = int.tryParse(partes[1]) ?? 0;
    return '${h.clamp(0, 23).toString().padLeft(2, '0')}:'
        '${m.clamp(0, 59).toString().padLeft(2, '0')}';
  }
}
