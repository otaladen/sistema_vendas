import 'package:flutter/material.dart';

import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';

/// Faixa horizontal de atalhos favoritos no dashboard.
class MainMenuFavoritosStrip extends StatelessWidget {
  const MainMenuFavoritosStrip({
    super.key,
    required this.favoritos,
    required this.onTap,
  });

  final List<MainMenuDestino> favoritos;
  final void Function(MainMenuDestino destino) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in favoritos)
          ActionChip(
            avatar: Icon(d.icone, size: 18, color: d.cor),
            label: Text(d.titulo),
            onPressed: () => onTap(d),
          ),
      ],
    );
  }
}

/// Titulo de secao no menu principal (Operacao, Fiscal, etc.).
class MainMenuSectionHeader extends StatelessWidget {
  const MainMenuSectionHeader({super.key, required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        titulo,
        style: tema.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: tema.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Indicador compacto no topo do menu (vendas, caixa, entregas).
class MainMenuKpiCard extends StatelessWidget {
  const MainMenuKpiCard({
    super.key,
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.cor,
    this.detalhe,
    this.onTap,
    this.carregando = false,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final String? detalhe;
  final Color cor;
  final VoidCallback? onTap;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final filho = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: cor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: tema.textTheme.labelMedium?.copyWith(
                    color: tema.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 2),
                if (carregando)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  Text(
                    valor,
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detalhe != null && detalhe!.trim().isNotEmpty)
                    Text(
                      detalhe!,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Material(
      color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? filho
          : InkWell(
              onTap: onTap,
              child: filho,
            ),
    );
  }
}

/// Tile de modulo para grade do menu principal.
class MainMenuModuleTile extends StatelessWidget {
  const MainMenuModuleTile({
    super.key,
    required this.icon,
    required this.corDestaque,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
    this.habilitado = true,
    this.alturaMinima = 104,
    this.favorito = false,
    this.onAlternarFavorito,
  });

  final IconData icon;
  final Color corDestaque;
  final String titulo;
  final String? subtitulo;
  final VoidCallback onTap;
  final bool habilitado;
  final double alturaMinima;
  final bool favorito;
  final VoidCallback? onAlternarFavorito;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final corTexto = habilitado
        ? (tema.textTheme.bodyLarge?.color ?? const Color(0xFF1F2937))
        : tema.colorScheme.onSurface.withValues(alpha: 0.38);

    return SizedBox(
      width: double.infinity,
      height: alturaMinima,
      child: Material(
        color: tema.colorScheme.surface,
        elevation: habilitado ? 0.5 : 0,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: habilitado ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: tema.dividerColor.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: habilitado
                              ? corDestaque.withValues(alpha: 0.18)
                              : Colors.grey.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 24,
                          color:
                              habilitado ? corDestaque : Colors.grey.shade600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        titulo,
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: corTexto,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo!,
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: corTexto.withValues(alpha: 0.72),
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (onAlternarFavorito != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: favorito
                          ? 'Remover dos favoritos'
                          : 'Fixar nos favoritos',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: onAlternarFavorito,
                      icon: Icon(
                        favorito ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: favorito
                            ? const Color(0xFFF9A825)
                            : tema.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
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

/// Tile em destaque para Vendas (PDV + atalhos).
class MainMenuFeaturedVendasTile extends StatelessWidget {
  const MainMenuFeaturedVendasTile({
    super.key,
    required this.habilitado,
    required this.onAbrirVendas,
    required this.onNovaVenda,
    required this.onCaixa,
    this.podePdv = false,
    this.podeCaixa = false,
  });

  final bool habilitado;
  final VoidCallback onAbrirVendas;
  final VoidCallback onNovaVenda;
  final VoidCallback onCaixa;
  final bool podePdv;
  final bool podeCaixa;

  static const _cor = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final corTexto = habilitado
        ? (tema.textTheme.bodyLarge?.color ?? const Color(0xFF1F2937))
        : tema.colorScheme.onSurface.withValues(alpha: 0.38);

    return Material(
      color: _cor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: habilitado ? onAbrirVendas : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: _cor.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _cor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.point_of_sale_outlined,
                        color: habilitado ? _cor : Colors.grey.shade600,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vendas',
                            style: tema.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: corTexto,
                            ),
                          ),
                          Text(
                            'PDV, caixa, listagem e relatorios',
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: corTexto.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (habilitado)
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: corTexto.withValues(alpha: 0.45),
                      ),
                  ],
                ),
                if (habilitado && (podePdv || podeCaixa)) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (podePdv)
                        FilledButton.icon(
                          onPressed: onNovaVenda,
                          icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                          label: const Text('Nova venda'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _cor,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      if (podeCaixa)
                        OutlinedButton.icon(
                          onPressed: onCaixa,
                          icon: const Icon(Icons.receipt_long_outlined, size: 18),
                          label: const Text('Caixa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _cor,
                            side: BorderSide(color: _cor.withValues(alpha: 0.55)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cabecalho contextual do menu (loja, data, sync).
class MainMenuContextHeader extends StatelessWidget {
  const MainMenuContextHeader({
    super.key,
    required this.nomeLoja,
    required this.dataHoraFormatada,
    this.syncAtivo = false,
    this.syncSucesso,
    this.syncMensagem,
  });

  final String nomeLoja;
  final String dataHoraFormatada;
  final bool syncAtivo;
  final bool? syncSucesso;
  final String? syncMensagem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nomeLoja.trim().isEmpty ? 'Loja' : nomeLoja.trim(),
                    style: tema.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dataHoraFormatada,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      color: tema.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            if (syncAtivo) _SyncBadge(sucesso: syncSucesso, mensagem: syncMensagem),
          ],
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({this.sucesso, this.mensagem});

  final bool? sucesso;
  final String? mensagem;

  @override
  Widget build(BuildContext context) {
    final ok = sucesso == true;
    final falha = sucesso == false;
    final cor = ok
        ? const Color(0xFF2E7D32)
        : falha
            ? const Color(0xFFC62828)
            : Colors.blueGrey;
    final rotulo = ok
        ? 'Sync OK'
        : falha
            ? 'Sync falhou'
            : 'Sync LAN';

    return Tooltip(
      message: mensagem?.trim().isNotEmpty == true ? mensagem!.trim() : rotulo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok
                  ? Icons.cloud_done_outlined
                  : falha
                      ? Icons.cloud_off_outlined
                      : Icons.sync_outlined,
              size: 16,
              color: cor,
            ),
            const SizedBox(width: 6),
            Text(
              rotulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
