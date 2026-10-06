import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_semantic_colors.dart';
import 'backup_controller.dart';

Future<void> mostrarDialogoSucessoBackupManual(
  BuildContext context, {
  required BackupManualConclusaoInfo info,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => BackupManualSucessoDialog(info: info),
  );
}

Future<void> mostrarDialogoErroBackupManual(
  BuildContext context, {
  required String mensagem,
  String titulo = 'Não foi possível concluir o backup',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => BackupManualErroDialog(titulo: titulo, mensagem: mensagem),
  );
}

class BackupManualSucessoDialog extends StatelessWidget {
  const BackupManualSucessoDialog({super.key, required this.info});

  final BackupManualConclusaoInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic =
        theme.extension<AppSemanticColors>() ?? AppSemanticColors.claro;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 48,
            color: semantic.successFg,
          ),
          const SizedBox(height: 12),
          Text(
            'Backup concluído',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (info.descricaoExtra != null) ...[
            const SizedBox(height: 8),
            Text(
              info.descricaoExtra!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _InfoCard(
            corFundo: semantic.successBg,
            corBorda: semantic.successBorder,
            rotulo: 'LOCAL DO ARQUIVO',
            valor: info.caminho,
            valorKey: const Key('backup_sucesso_caminho'),
          ),
          const SizedBox(height: 10),
          _InfoCard(
            corFundo: theme.colorScheme.surfaceContainerHighest,
            corBorda: theme.colorScheme.outlineVariant,
            rotulo: 'TAMANHO TOTAL',
            valor: info.tamanhoTotalFormatado,
            valorKey: const Key('backup_sucesso_tamanho'),
          ),
          const SizedBox(height: 10),
          _InfoCard(
            corFundo: theme.colorScheme.surfaceContainerHighest,
            corBorda: theme.colorScheme.outlineVariant,
            rotulo: 'CONCLUÍDO EM',
            valor: info.horarioConclusaoFormatado,
            valorKey: const Key('backup_sucesso_horario'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: info.caminho));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Caminho copiado.')),
            );
          },
          child: const Text('Copiar caminho'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class BackupManualErroDialog extends StatelessWidget {
  const BackupManualErroDialog({
    super.key,
    required this.titulo,
    required this.mensagem,
  });

  final String titulo;
  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic =
        theme.extension<AppSemanticColors>() ?? AppSemanticColors.claro;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: semantic.errorFg),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: semantic.errorBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: semantic.errorBorder.withValues(alpha: 0.7)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                mensagem,
                key: const Key('backup_erro_mensagem'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A tela de configurações permanece aberta. Corrija o problema e tente novamente.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.corFundo,
    required this.corBorda,
    required this.rotulo,
    required this.valor,
    this.valorKey,
  });

  final Color corFundo;
  final Color corBorda;
  final String rotulo;
  final String valor;
  final Key? valorKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: corFundo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: corBorda.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rotulo,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              valor,
              key: valorKey,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
