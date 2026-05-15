import 'dart:async';

import 'package:flutter/material.dart';

import 'sync_refresh_hub.dart';

/// Escuta [SyncRefreshHub] com debounce e evita recarregar a UI durante edicao ou dialogos.
mixin SafeSyncRefreshMixin<T extends StatefulWidget> on State<T> {
  static const Duration debouncePadrao = Duration(milliseconds: 2500);

  Timer? _syncDebounceTimer;
  Duration _syncDebounce = debouncePadrao;
  VoidCallback? _syncOnReload;
  bool Function()? _syncBloquearAtualizacao;
  void Function({required bool daRede})? _syncAoConcluir;
  bool _syncReloadPendente = false;
  bool _syncHubRegistrado = false;
  bool _syncUltimaOrigemRede = false;

  void initSafeSyncRefresh({
    required VoidCallback onReload,
    Duration debounce = debouncePadrao,
    bool Function()? bloquearAtualizacao,
    void Function({required bool daRede})? aoConcluir,
    bool escutarHub = true,
  }) {
    _syncDebounce = debounce;
    _syncOnReload = onReload;
    _syncBloquearAtualizacao = bloquearAtualizacao;
    _syncAoConcluir = aoConcluir;
    if (escutarHub && !_syncHubRegistrado) {
      SyncRefreshHub.instance.addListener(_onSyncHubNotificado);
      _syncHubRegistrado = true;
    }
  }

  void disposeSafeSyncRefresh() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = null;
    if (_syncHubRegistrado) {
      SyncRefreshHub.instance.removeListener(_onSyncHubNotificado);
      _syncHubRegistrado = false;
    }
  }

  /// Dispara o mesmo fluxo debounced (ex.: listener local do repositorio).
  void agendarRecargaSegura({bool daRede = false}) {
    if (!mounted) return;
    if (daRede) _syncUltimaOrigemRede = true;
    if (!podeAtualizarUi()) {
      _syncReloadPendente = true;
      return;
    }
    _agendarReloadDebounced();
  }

  void _onSyncHubNotificado() {
    agendarRecargaSegura(daRede: true);
  }

  bool podeAtualizarUi() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (_syncBloquearAtualizacao?.call() == true) return false;
    return true;
  }

  void _agendarReloadDebounced() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_syncDebounce, _executarReloadLeve);
  }

  void _executarReloadLeve() {
    if (!mounted) return;
    if (!podeAtualizarUi()) {
      _syncReloadPendente = true;
      return;
    }
    _syncReloadPendente = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !podeAtualizarUi()) {
        _syncReloadPendente = true;
        return;
      }
      scheduleMicrotask(() {
        if (!mounted || !podeAtualizarUi()) {
          _syncReloadPendente = true;
          return;
        }
        final daRede = _syncUltimaOrigemRede;
        _syncUltimaOrigemRede = false;
        _syncOnReload?.call();
        _syncAoConcluir?.call(daRede: daRede);
        if (_syncReloadPendente && podeAtualizarUi()) {
          _syncReloadPendente = false;
          agendarRecargaSegura(daRede: daRede);
        }
      });
    });
  }

  /// Foco em campo de texto editavel (exceto nos informados).
  static bool focoEmCampoDeTexto({Set<FocusNode>? ignorar}) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return false;
    if (ignorar != null && ignorar.contains(focus)) return false;
    final ctx = focus.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
