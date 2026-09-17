import '../services/app_boot_log.dart';

/// Participantes (shell, caixa, etc.) pausam timers antes do ObjectBox fechar para backup.
abstract interface class ObjectBoxStoreLifecycleListener {
  Future<void> onObjectBoxClosingForCopy();

  void onObjectBoxReopenedAfterCopy();
}

/// Orquestra pausa da UI antes de [ObjectBox.fecharParaCopiaDeArquivos] e retomada apos reabrir.
abstract final class ObjectBoxLifecycleHub {
  ObjectBoxLifecycleHub._();

  static final List<ObjectBoxStoreLifecycleListener> _listeners = [];

  /// Verdadeiro entre o aviso de fechamento e [notificarStoreReaberta].
  static bool storeFechadaParaCopia = false;

  /// Incrementado a cada reabertura; use como [Key] para remontar telas.
  static int geracaoStore = 0;

  /// Checagem sincrona (main isolate) antes de queries ou timers locais.
  static bool get acessoLocalSuspenso => storeFechadaParaCopia;

  static void registrar(ObjectBoxStoreLifecycleListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void remover(ObjectBoxStoreLifecycleListener listener) {
    _listeners.remove(listener);
  }

  /// Aguarda todos os listeners cancelarem timers / polling antes do `store.close()`.
  static Future<void> notificarAntesDeFecharStore() async {
    storeFechadaParaCopia = true;
    AppBootLog.info(
      'objectbox_lifecycle',
      'Pausando ${_listeners.length} listener(s) antes de fechar store',
    );
    if (_listeners.isEmpty) {
      await Future<void>.delayed(Duration.zero);
      return;
    }
    await Future.wait(
      _listeners.map((l) async {
        try {
          await l.onObjectBoxClosingForCopy();
        } catch (_) {}
      }),
    );
    await Future<void>.delayed(Duration.zero);
  }

  static void notificarStoreReaberta() {
    storeFechadaParaCopia = false;
    geracaoStore++;
    AppBootLog.info(
      'objectbox_lifecycle',
      'Store reaberta; retomando ${_listeners.length} listener(s)',
    );
    for (final l in List<ObjectBoxStoreLifecycleListener>.from(_listeners)) {
      try {
        l.onObjectBoxReopenedAfterCopy();
      } catch (_) {}
    }
  }

  /// Evita UI zumbi se [ObjectBox.reabrirAposCopiaDeArquivos] falhar.
  static void resetAposFalhaReabertura(Object erro, {StackTrace? stack}) {
    storeFechadaParaCopia = false;
    AppBootLog.registrar(
      'objectbox_reabrir',
      erro,
      stack: stack,
      contexto:
          'Falha ao reabrir ObjectBox apos backup (lock de arquivo / permissao)',
    );
  }
}
