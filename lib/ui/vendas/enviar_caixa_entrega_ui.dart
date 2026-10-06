import 'package:flutter/material.dart';

import '../../domain/entregas/observacao_carreto.dart';

/// Blocos visuais do modal "Enviar ao caixa" (secao entrega / carreto).
abstract final class EnviarCaixaEntregaUi {
  EnviarCaixaEntregaUi._();

  /// Texto discreto abaixo do endereco/CEP no bloco **Onde**.
  static String? textoPontoReferenciaDiscreto(String referencia) {
    final t = referencia.trim();
    if (t.isEmpty) return null;
    return '📌 Ref.: $t';
  }
}

/// Ponto de referencia do cadastro — somente leitura, tom secundario.
class EnviarCaixaPontoReferenciaLinha extends StatelessWidget {
  const EnviarCaixaPontoReferenciaLinha({
    super.key,
    required this.referencia,
  });

  final String referencia;

  @override
  Widget build(BuildContext context) {
    final texto = EnviarCaixaEntregaUi.textoPontoReferenciaDiscreto(referencia);
    if (texto == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        texto,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Preview do card **Observacoes do carreto** (F8): so texto digitado no modal.
class EnviarCaixaObservacoesCarretoResumo extends StatelessWidget {
  const EnviarCaixaObservacoesCarretoResumo({
    super.key,
    required this.observacaoGravada,
    this.onTap,
    this.acaoTitulo,
  });

  final String observacaoGravada;
  final VoidCallback? onTap;
  final Widget? acaoTitulo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linhas = ObservacaoCarreto.linhasDigitadas(observacaoGravada);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'OBSERVAÇÕES DO CARRETO',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ?acaoTitulo,
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: linhas.isEmpty
                    ? theme.colorScheme.outlineVariant
                    : theme.colorScheme.onSurface,
                width: linhas.isEmpty ? 1 : 1.4,
              ),
            ),
            child: linhas.isEmpty
                ? Text(
                    'Nenhuma observação. Ex.: portão azul, ligar antes de sair.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in linhas)
                        Text(
                          '> ${l.toUpperCase()}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
