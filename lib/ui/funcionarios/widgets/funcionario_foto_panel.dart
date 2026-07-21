import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/funcionario_imagem_service.dart';

/// Painel de foto do funcionario (camera no celular; arquivo no PC).
class FuncionarioFotoPanel extends StatelessWidget {
  const FuncionarioFotoPanel({
    super.key,
    required this.previewPath,
    required this.onTirarFoto,
    required this.onEscolherArquivo,
    required this.onRemover,
    this.compact = false,
  });

  final String? previewPath;
  final VoidCallback onTirarFoto;
  final VoidCallback onEscolherArquivo;
  final VoidCallback onRemover;
  final bool compact;

  bool get _temFoto {
    final p = previewPath?.trim() ?? '';
    return p.isNotEmpty && File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tamanho = compact ? 88.0 : 112.0;
    final camera = FuncionarioImagemService.cameraDisponivel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: tamanho,
            height: tamanho,
            child: _temFoto
                ? Image.file(
                    File(previewPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(scheme),
                  )
                : _placeholder(scheme),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Foto do funcionario',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                camera
                    ? 'Tire a foto com a camera ou escolha da galeria.'
                    : 'Escolha uma imagem do computador (JPG/PNG).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (camera)
                    FilledButton.tonalIcon(
                      onPressed: onTirarFoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Tirar foto'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onEscolherArquivo,
                    icon: Icon(
                      camera ? Icons.photo_library_outlined : Icons.folder_open,
                      size: 18,
                    ),
                    label: Text(camera ? 'Galeria' : 'Escolher arquivo'),
                  ),
                  if (_temFoto)
                    TextButton.icon(
                      onPressed: onRemover,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remover'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return Center(
      child: Icon(
        Icons.person_outline,
        size: 40,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }
}
