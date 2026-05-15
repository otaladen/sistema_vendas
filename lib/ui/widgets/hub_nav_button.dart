import 'package:flutter/material.dart';

/// Cores de destaque do hub (menu principal e telas filhas no mesmo padrao).
abstract final class HubNavColors {
  static const menuCadastros = Color(0xFF1565C0);
  static const menuEstoque = Color(0xFFE65100);
  static const menuNotasFiscais = Color(0xFF00838F);
  static const menuVendas = Color(0xFF2E7D32);
  static const menuConfig = Color(0xFF6A1B9A);
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
    final corLetrasTelas =
        tema.textTheme.bodyLarge?.color ?? const Color(0xFF1F2937);
    final estiloTitulo = (tema.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: habilitado
          ? corLetrasTelas
          : tema.colorScheme.onSurface.withValues(alpha: 0.38),
    );
    final estiloSub = tema.textTheme.bodySmall?.copyWith(
          height: 1.3,
          color: habilitado
              ? corLetrasTelas.withValues(alpha: 0.72)
              : tema.colorScheme.onSurface.withValues(alpha: 0.28),
        ) ??
        TextStyle(
          fontSize: 13,
          height: 1.3,
          color: habilitado
              ? corLetrasTelas.withValues(alpha: 0.72)
              : tema.colorScheme.onSurface.withValues(alpha: 0.28),
        );

    final iconeBadge = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: habilitado
            ? corDestaque.withValues(alpha: 0.22)
            : Colors.grey.withValues(alpha: 0.22),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 26,
        color: habilitado ? corDestaque : Colors.grey.shade600,
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
