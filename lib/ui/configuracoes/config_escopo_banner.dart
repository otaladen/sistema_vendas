import 'package:flutter/material.dart';

enum ConfigEscopoTipo {
  lojaServidor,
  terminalLocal,
}

/// Faixa visual que separa configuracao sincronizada da loja vs deste terminal.
class ConfigEscopoBanner extends StatelessWidget {
  const ConfigEscopoBanner({
    super.key,
    required this.tipo,
    this.terminalLeve = false,
  });

  final ConfigEscopoTipo tipo;
  final bool terminalLeve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final loja = tipo == ConfigEscopoTipo.lojaServidor;

    final titulo = loja
        ? 'Configuracoes da Loja (Servidor)'
        : 'Configuracoes deste Terminal (Dispositivo Atual)';

    final subtitulo = loja
        ? (terminalLeve
            ? 'Sincronizadas do PC servidor. Alteracoes aqui exigem permissao no servidor ou refletem leitura da API.'
            : 'Compartilhadas com todos os terminais da rede (empresa, fiscal, politicas de venda e estilo do cupom).')
        : 'Salvas apenas neste computador: impressora, bobina, margens fisicas e auto-impressao no PDV.';

    final bg = loja
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : scheme.secondaryContainer.withValues(alpha: 0.45);
    final icon = loja ? Icons.cloud_sync_outlined : Icons.computer_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
