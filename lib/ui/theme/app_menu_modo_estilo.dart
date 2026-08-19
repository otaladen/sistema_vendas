import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import 'app_menu_modo_id.dart';
import 'app_menu_modo_scope.dart';
import 'app_modulo_cores.dart';

/// Cores fixas por modulo (modos com identidade visual forte).
abstract final class AppMenuModoCoresFixas {
  static Color destino(MainMenuDestino d) {
    switch (d) {
      case MainMenuDestino.inicio:
        return const Color(0xFF37474F);
      case MainMenuDestino.vendas:
        return const Color(0xFF1565C0);
      case MainMenuDestino.pdv:
        return const Color(0xFF0D47A1);
      case MainMenuDestino.caixa:
        return const Color(0xFF7B1FA2);
      case MainMenuDestino.estoque:
        return const Color(0xFFE65100);
      case MainMenuDestino.notasFiscais:
        return const Color(0xFF2E7D32);
      case MainMenuDestino.entregas:
        return const Color(0xFF00838F);
      case MainMenuDestino.financeiro:
        return const Color(0xFF00897B);
      case MainMenuDestino.cadastros:
        return const Color(0xFF3949AB);
      case MainMenuDestino.configuracoes:
        return const Color(0xFF546E7A);
      case MainMenuDestino.motorista:
        return const Color(0xFF5D4037);
    }
  }

  static Color pastel(MainMenuDestino d) {
    final base = HSLColor.fromColor(destino(d));
    return base
        .withSaturation((base.saturation * 0.45).clamp(0.2, 0.55))
        .withLightness(0.88)
        .toColor();
  }
}

/// Estilo visual do menu lateral esquerdo (desktop).
abstract final class AppMenuModoEstilo {
  static AppMenuModoId modoAtual(BuildContext context) =>
      AppMenuModoScope.maybeOf(context)?.modoAtual ?? AppMenuModoId.classico;

  static bool usaRailPadrao(BuildContext context) =>
      modoAtual(context) == AppMenuModoId.classico;

  static bool _usaCoresFixas(AppMenuModoId modo) =>
      modo != AppMenuModoId.classico && modo != AppMenuModoId.colorido;

  static Color corDestaque(BuildContext context, MainMenuDestino destino) {
    if (_usaCoresFixas(modoAtual(context))) {
      return AppMenuModoCoresFixas.destino(destino);
    }
    return destino.cor(context);
  }

  static double larguraLateralDe(BuildContext context, bool estendido) {
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return estendido ? 200 : 72;
      case AppMenuModoId.colorido:
        return estendido ? 228 : 84;
      case AppMenuModoId.vibrante:
        return estendido ? 248 : 92;
      case AppMenuModoId.amplo:
        return estendido ? 272 : 104;
      case AppMenuModoId.neon:
        return estendido ? 252 : 90;
      case AppMenuModoId.pastel:
        return estendido ? 232 : 82;
      case AppMenuModoId.retro:
        // Estreito como retaguarda classica (Chacal): ~15% da tela em Full HD.
        return estendido ? 168 : 52;
      case AppMenuModoId.faixa:
        return estendido ? 218 : 78;
    }
  }

  static BoxDecoration decoracaoPainelLateral(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return BoxDecoration(color: scheme.surfaceContainerLow);
      case AppMenuModoId.colorido:
        return BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.07),
          border: Border(
            right: BorderSide(color: scheme.primary.withValues(alpha: 0.22)),
          ),
        );
      case AppMenuModoId.vibrante:
        return const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF263238), Color(0xFF37474F)],
          ),
        );
      case AppMenuModoId.amplo:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              scheme.secondary.withValues(alpha: 0.92),
            ],
          ),
        );
      case AppMenuModoId.neon:
        return const BoxDecoration(
          color: Color(0xFF0A0A0F),
          border: Border(
            right: BorderSide(color: Color(0xFF00E5FF), width: 1.5),
          ),
        );
      case AppMenuModoId.pastel:
        return BoxDecoration(
          color: const Color(0xFFF8F9FC),
          border: Border(
            right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        );
      case AppMenuModoId.retro:
        return const BoxDecoration(
          color: Color(0xFFF2F2F2),
          border: Border(
            right: BorderSide(color: Color(0xFFC0C0C0), width: 1),
          ),
        );
      case AppMenuModoId.faixa:
        return BoxDecoration(
          color: scheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(2, 0),
            ),
          ],
        );
    }
  }

  static Color corIconeMenu(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return scheme.onSurface;
      case AppMenuModoId.colorido:
        return scheme.primary;
      case AppMenuModoId.vibrante:
      case AppMenuModoId.amplo:
        return Colors.white;
      case AppMenuModoId.neon:
        return const Color(0xFF00E5FF);
      case AppMenuModoId.pastel:
        return scheme.primary;
      case AppMenuModoId.retro:
        return const Color(0xFF212121);
      case AppMenuModoId.faixa:
        return scheme.onSurfaceVariant;
    }
  }

  static double tamanhoIconeItem(BuildContext context) {
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return 24;
      case AppMenuModoId.colorido:
        return 26;
      case AppMenuModoId.vibrante:
        return 28;
      case AppMenuModoId.amplo:
        return 32;
      case AppMenuModoId.neon:
        return 28;
      case AppMenuModoId.pastel:
        return 26;
      case AppMenuModoId.retro:
        return 18;
      case AppMenuModoId.faixa:
        return 24;
    }
  }

  static double tamanhoFonteItem(BuildContext context) {
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return 13;
      case AppMenuModoId.colorido:
        return 14;
      case AppMenuModoId.vibrante:
        return 14.5;
      case AppMenuModoId.amplo:
        return 15.5;
      case AppMenuModoId.neon:
        return 14.5;
      case AppMenuModoId.pastel:
        return 14;
      case AppMenuModoId.retro:
        return 11.5;
      case AppMenuModoId.faixa:
        return 13.5;
    }
  }

  /// Subitens do menu (orcamentos, listagem, etc.) — menor que o grupo pai.
  static double tamanhoFonteSubItem(BuildContext context) {
    if (modoAtual(context) == AppMenuModoId.retro) return 10.5;
    return (tamanhoFonteItem(context) - 1.25).clamp(11.0, 14.0);
  }

  static FontWeight pesoTextoGrupoMenu(BuildContext context, bool selecionado) {
    if (selecionado) return pesoTextoItem(context, true);
    return FontWeight.w600;
  }

  static FontWeight pesoTextoSubMenu(BuildContext context, bool selecionado) =>
      selecionado ? FontWeight.w600 : FontWeight.w400;

  static double alturaItemMinima(BuildContext context) {
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return 48;
      case AppMenuModoId.colorido:
        return 52;
      case AppMenuModoId.vibrante:
        return 56;
      case AppMenuModoId.amplo:
        return 60;
      case AppMenuModoId.neon:
        return 54;
      case AppMenuModoId.pastel:
        return 50;
      case AppMenuModoId.retro:
        return 28;
      case AppMenuModoId.faixa:
        return 46;
    }
  }

  static EdgeInsets paddingItem(BuildContext context, bool estendido) {
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 12 : 8,
          vertical: 6,
        );
      case AppMenuModoId.colorido:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 14 : 10,
          vertical: 8,
        );
      case AppMenuModoId.vibrante:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 14 : 10,
          vertical: 9,
        );
      case AppMenuModoId.amplo:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 16 : 12,
          vertical: 10,
        );
      case AppMenuModoId.neon:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 14 : 10,
          vertical: 8,
        );
      case AppMenuModoId.pastel:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 12 : 8,
          vertical: 7,
        );
      case AppMenuModoId.retro:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 8 : 4,
          vertical: 3,
        );
      case AppMenuModoId.faixa:
        return EdgeInsets.symmetric(
          horizontal: estendido ? 10 : 6,
          vertical: 6,
        );
    }
  }

  static BoxDecoration decoracaoItemLateral(
    BuildContext context, {
    required MainMenuDestino destino,
    required bool selecionado,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final cor = corDestaque(context, destino);
    final radius = BorderRadius.circular(_raioItem(context));

    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return BoxDecoration(
          color: selecionado
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: radius,
        );
      case AppMenuModoId.colorido:
        return BoxDecoration(
          color: selecionado
              ? cor.withValues(alpha: 0.24)
              : Colors.transparent,
          borderRadius: radius,
          border: selecionado
              ? Border.all(color: cor.withValues(alpha: 0.5))
              : null,
        );
      case AppMenuModoId.vibrante:
        return BoxDecoration(
          color: selecionado ? cor : Colors.white.withValues(alpha: 0.06),
          borderRadius: radius,
          boxShadow: selecionado
              ? [
                  BoxShadow(
                    color: cor.withValues(alpha: 0.45),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        );
      case AppMenuModoId.amplo:
        return BoxDecoration(
          color: selecionado
              ? Colors.white.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: radius,
          border: Border.all(
            color: selecionado
                ? Colors.white
                : Colors.white.withValues(alpha: 0.18),
          ),
          boxShadow: selecionado
              ? const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        );
      case AppMenuModoId.neon:
        return BoxDecoration(
          color: selecionado
              ? cor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: radius,
          border: Border.all(
            color: selecionado ? cor : cor.withValues(alpha: 0.22),
            width: selecionado ? 2 : 1,
          ),
          boxShadow: selecionado
              ? [
                  BoxShadow(
                    color: cor.withValues(alpha: 0.65),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        );
      case AppMenuModoId.pastel:
        final fundo = AppMenuModoCoresFixas.pastel(destino);
        return BoxDecoration(
          color: selecionado
              ? fundo
              : fundo.withValues(alpha: 0.55),
          borderRadius: radius,
          border: Border.all(
            color: cor.withValues(alpha: selecionado ? 0.45 : 0.2),
          ),
        );
      case AppMenuModoId.retro:
        // Compacto: fundo neutro; destaque sutil; icone colorido faz a identidade.
        return BoxDecoration(
          color: selecionado
              ? cor.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: radius,
          border: selecionado
              ? Border(
                  left: BorderSide(color: cor, width: 3),
                )
              : null,
        );
      case AppMenuModoId.faixa:
        return BoxDecoration(
          color: selecionado
              ? cor.withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: radius,
          border: Border(
            left: BorderSide(
              color: cor,
              width: selecionado ? 6 : 4,
            ),
          ),
        );
    }
  }

  static Color corIconeItem(
    BuildContext context, {
    required MainMenuDestino destino,
    required bool selecionado,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final cor = corDestaque(context, destino);
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return selecionado ? cor : scheme.onSurfaceVariant;
      case AppMenuModoId.colorido:
        return selecionado ? cor : scheme.onSurface.withValues(alpha: 0.72);
      case AppMenuModoId.vibrante:
        return selecionado ? Colors.white : Colors.white.withValues(alpha: 0.72);
      case AppMenuModoId.amplo:
        return selecionado ? cor : Colors.white;
      case AppMenuModoId.neon:
        return selecionado ? cor : cor.withValues(alpha: 0.55);
      case AppMenuModoId.pastel:
        return cor;
      case AppMenuModoId.retro:
        // Sempre colorido (como o ERP antigo), mesmo sem selecao.
        return cor;
      case AppMenuModoId.faixa:
        return selecionado ? cor : scheme.onSurfaceVariant;
    }
  }

  static Color corTextoItem(
    BuildContext context, {
    required MainMenuDestino destino,
    required bool selecionado,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final cor = corDestaque(context, destino);
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return selecionado ? cor : scheme.onSurface;
      case AppMenuModoId.colorido:
        return selecionado
            ? cor
            : scheme.onSurface.withValues(alpha: 0.85);
      case AppMenuModoId.vibrante:
        return selecionado ? Colors.white : Colors.white.withValues(alpha: 0.82);
      case AppMenuModoId.amplo:
        return selecionado ? cor : Colors.white;
      case AppMenuModoId.neon:
        return selecionado
            ? Colors.white
            : Colors.white.withValues(alpha: 0.65);
      case AppMenuModoId.pastel:
        return cor.withValues(alpha: selecionado ? 1 : 0.82);
      case AppMenuModoId.retro:
        return selecionado ? cor : const Color(0xFF333333);
      case AppMenuModoId.faixa:
        return selecionado
            ? cor
            : scheme.onSurface.withValues(alpha: 0.82);
    }
  }

  static FontWeight pesoTextoItem(BuildContext context, bool selecionado) {
    if (!selecionado) return FontWeight.w500;
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
      case AppMenuModoId.colorido:
      case AppMenuModoId.vibrante:
      case AppMenuModoId.neon:
      case AppMenuModoId.pastel:
      case AppMenuModoId.faixa:
        return FontWeight.w700;
      case AppMenuModoId.amplo:
        return FontWeight.w800;
      case AppMenuModoId.retro:
        return FontWeight.w600;
    }
  }

  static Color corRodapeLateral(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return scheme.onSurface.withValues(alpha: 0.55);
      case AppMenuModoId.colorido:
        return scheme.primary.withValues(alpha: 0.7);
      case AppMenuModoId.vibrante:
      case AppMenuModoId.amplo:
        return Colors.white.withValues(alpha: 0.72);
      case AppMenuModoId.neon:
        return const Color(0xFF00E5FF).withValues(alpha: 0.75);
      case AppMenuModoId.pastel:
        return scheme.primary.withValues(alpha: 0.6);
      case AppMenuModoId.retro:
        return const Color(0xFF424242);
      case AppMenuModoId.faixa:
        return scheme.onSurfaceVariant;
    }
  }

  static double _raioItem(BuildContext context) {
    switch (modoAtual(context)) {
      case AppMenuModoId.classico:
        return 10;
      case AppMenuModoId.colorido:
        return 12;
      case AppMenuModoId.vibrante:
        return 14;
      case AppMenuModoId.amplo:
        return 16;
      case AppMenuModoId.neon:
        return 12;
      case AppMenuModoId.pastel:
        return 14;
      case AppMenuModoId.retro:
        return 4;
      case AppMenuModoId.faixa:
        return 8;
    }
  }
}
