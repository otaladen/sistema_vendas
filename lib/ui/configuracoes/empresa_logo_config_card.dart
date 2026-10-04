import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'config_section_card.dart';

/// Card de logomarca sincronizada na rede (preview + escolher/remover).
class EmpresaLogoConfigCard extends StatelessWidget {
  const EmpresaLogoConfigCard({
    super.key,
    required this.logoPath,
    required this.somenteLeitura,
    required this.onEscolher,
    required this.onRemover,
  });

  final String logoPath;
  final bool somenteLeitura;
  final VoidCallback onEscolher;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final path = logoPath.trim();
    final temLogo = path.isNotEmpty && File(path).existsSync();
    final theme = Theme.of(context);

    return ConfigSectionCard(
      icon: Icons.image_outlined,
      title: 'Logomarca da empresa',
      subtitle:
          'Usada em cupons, orçamentos e impressão térmica. Sincronizada na rede.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recomendado: PNG com fundo transparente, proporção horizontal '
            'e largura até 800 px.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (temLogo)
            Center(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120, maxWidth: 280),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                ),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                ),
              ),
            )
          else
            Container(
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                somenteLeitura
                    ? 'Nenhuma logomarca no servidor'
                    : 'Nenhuma logomarca selecionada',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 12),
          if (!somenteLeitura) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEscolher,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(temLogo ? 'Trocar logo' : 'Escolher logo'),
                  ),
                ),
                if (temLogo) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onRemover,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover'),
                  ),
                ],
              ],
            ),
          ],
          if (temLogo) ...[
            const SizedBox(height: 8),
            Text(
              p.basename(path),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
