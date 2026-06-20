import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'seletor_tema_app.dart';

/// Barra inferior com Temas, usuario e data/hora (referencia ao ERP legado).
class AppRodapeStatusBar extends StatefulWidget {
  const AppRodapeStatusBar({
    super.key,
    this.usuarioLogin,
    this.usuarioNome,
  });

  final String? usuarioLogin;
  final String? usuarioNome;

  @override
  State<AppRodapeStatusBar> createState() => _AppRodapeStatusBarState();
}

class _AppRodapeStatusBarState extends State<AppRodapeStatusBar> {
  static final _dataHora = DateFormat('dd/MM/yyyy · HH:mm', 'pt_BR');
  String _agora = '';
  Timer? _relogioTimer;

  @override
  void initState() {
    super.initState();
    _atualizarRelogio();
    _relogioTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _atualizarRelogio();
    });
  }

  @override
  void dispose() {
    _relogioTimer?.cancel();
    super.dispose();
  }

  void _atualizarRelogio() {
    final novo = _dataHora.format(DateTime.now());
    if (!mounted || novo == _agora) return;
    setState(() => _agora = novo);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final login = widget.usuarioLogin?.trim();
    final nome = widget.usuarioNome?.trim();

    return Material(
      color: tema.colorScheme.surfaceContainerHighest.withValues(
        alpha: tema.brightness == Brightness.dark ? 0.55 : 0.75,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const SeletorTemaApp(),
                const Spacer(),
                if (login != null && login.isNotEmpty)
                  Flexible(
                    child: Text(
                      nome != null && nome.isNotEmpty ? '$nome ($login)' : login,
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                if (login != null && login.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '|',
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.outline,
                      ),
                    ),
                  ),
                Text(
                  _agora,
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
