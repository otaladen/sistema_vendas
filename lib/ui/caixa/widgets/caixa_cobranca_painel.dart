import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Layout padronizado da etapa Cobranca do caixa (Fase operacional).
class CaixaCobrancaPainel extends StatelessWidget {
  const CaixaCobrancaPainel({
    super.key,
    required this.numeroOrcamento,
    required this.clienteNome,
    required this.qtdItens,
    required this.rotuloPagamento,
    required this.totalComDesconto,
    required this.descontoPdvOrcamento,
    required this.formatarMoeda,
    this.onAlterarForma,
    required this.recebimento,
    required this.rodape,
  });

  final int numeroOrcamento;
  final String clienteNome;
  final int qtdItens;
  final String rotuloPagamento;
  final double totalComDesconto;
  final double descontoPdvOrcamento;
  final String Function(double) formatarMoeda;
  final VoidCallback? onAlterarForma;
  final Widget recebimento;
  final Widget rodape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numLabel =
        numeroOrcamento > 0 ? 'Orc. $numeroOrcamento' : 'Venda';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cobranca — $numLabel',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          clienteNome,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '$qtdItens item(ns) · $rotuloPagamento',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total a pagar',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        formatarMoeda(totalComDesconto),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                      if (descontoPdvOrcamento > 0.001) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Desc. PDV: -${formatarMoeda(descontoPdvOrcamento)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recebimento no caixa',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Forma definida no PDV. Confira ou ajuste os valores abaixo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onAlterarForma != null)
                  TextButton.icon(
                    onPressed: onAlterarForma,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Alterar forma'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: recebimento,
              ),
            ),
            const SizedBox(height: 8),
            rodape,
          ],
        ),
      ),
    );
  }
}

/// Campo padrao de valor recebido (dinheiro).
class CaixaCobrancaCampoDinheiro extends StatelessWidget {
  const CaixaCobrancaCampoDinheiro({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.totalAPagar,
    required this.troco,
    required this.formatarMoeda,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double totalAPagar;
  final double troco;
  final String Function(double) formatarMoeda;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dinheiro',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
            ],
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Valor recebido',
              hintText: formatarMoeda(totalAPagar),
              border: const OutlineInputBorder(),
              isDense: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoChip(
                  context,
                  rotulo: 'A pagar',
                  valor: formatarMoeda(totalAPagar),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoChip(
                  context,
                  rotulo: 'Troco',
                  valor: formatarMoeda(troco),
                  destaque: troco > 0.009,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(
    BuildContext context, {
    required String rotulo,
    required String valor,
    bool destaque = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: destaque
            ? scheme.primaryContainer
            : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: destaque
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            valor,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: destaque ? scheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensagem padrao quando nao ha valor a digitar (PIX, cartao, fiado integral).
class CaixaCobrancaConfirmacaoSimples extends StatelessWidget {
  const CaixaCobrancaConfirmacaoSimples({
    super.key,
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    this.detalhe,
  });

  final IconData icone;
  final String titulo;
  final String subtitulo;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 32, color: scheme.primary),
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
                  style: theme.textTheme.bodyMedium,
                ),
                if (detalhe != null && detalhe!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    detalhe!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
