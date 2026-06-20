import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import '../theme/app_modulo_cores.dart';

/// Cores de destaque do hub derivadas do tema ativo.
abstract final class HubNavColors {
  static Color menuCadastros(BuildContext context) =>
      AppModuloCores.destino(context, MainMenuDestino.cadastros);

  static Color menuEstoque(BuildContext context) =>
      AppModuloCores.destino(context, MainMenuDestino.estoque);

  static Color menuNotasFiscais(BuildContext context) =>
      AppModuloCores.destino(context, MainMenuDestino.notasFiscais);

  static Color menuVendas(BuildContext context) =>
      AppModuloCores.destino(context, MainMenuDestino.vendas);

  static Color menuFinanceiro(BuildContext context) =>
      AppModuloCores.destino(context, MainMenuDestino.financeiro);

  static Color menuConfig(BuildContext context) =>
      AppModuloCores.destino(context, MainMenuDestino.configuracoes);
}

/// Botao de navegacao usado no menu principal e nas telas Cadastros / Vendas.
class HubNavButton extends StatelessWidget {
  const HubNavButton({
    super.key,
    required this.icon,
    required this.corDestaque,
    required this.titulo,
    required this.onTap,
    this.habilitado = true,
    this.subtitulo,
  });

  final IconData icon;
  final Color corDestaque;
  final String titulo;
  final VoidCallback onTap;
  final bool habilitado;
  /// Quando preenchido, o botao fica mais alto (titulo + descricao abaixo, alinhados ao centro).
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final scheme = tema.colorScheme;
    final corLetrasTelas = tema.colorScheme.onSurface;
    final estiloTitulo = (tema.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: habilitado
          ? corLetrasTelas
          : scheme.onSurface.withValues(alpha: 0.38),
    );
    final estiloSub = tema.textTheme.bodySmall?.copyWith(
          height: 1.3,
          color: habilitado
              ? corLetrasTelas.withValues(alpha: 0.72)
              : scheme.onSurface.withValues(alpha: 0.28),
        ) ??
        TextStyle(
          fontSize: 13,
          height: 1.3,
          color: habilitado
              ? corLetrasTelas.withValues(alpha: 0.72)
              : scheme.onSurface.withValues(alpha: 0.28),
        );

    final corIconeDesabilitado = scheme.onSurface.withValues(alpha: 0.38);
    final iconeBadge = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: habilitado
            ? corDestaque.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 26,
        color: habilitado ? corDestaque : corIconeDesabilitado,
      ),
    );

    final descricao = subtitulo?.trim() ?? '';
    final temSub = descricao.isNotEmpty;

    if (!temSub) {
      return SizedBox(
        height: 72,
        child: ElevatedButton(
          onPressed: habilitado ? onTap : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              iconeBadge,
              const SizedBox(width: 14),
              Text(titulo, style: estiloTitulo),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: habilitado ? onTap : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                iconeBadge,
                const SizedBox(width: 14),
                Text(titulo, style: estiloTitulo),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              descricao,
              style: estiloSub,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
