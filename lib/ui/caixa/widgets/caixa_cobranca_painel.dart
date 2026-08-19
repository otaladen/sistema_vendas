import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/venda_documento_rotulo_helper.dart';

/// Rodape com total em destaque (padrao PDV), compartilhado entre etapas do caixa.
class CaixaRodapeTotalDestaque extends StatelessWidget {
  const CaixaRodapeTotalDestaque({
    super.key,
    this.tituloSecaoPagamento = 'Pagamento',
    required this.rotuloPagamento,
    required this.totalFormatado,
    required this.formatarMoeda,
    this.descontoPdvOrcamento = 0,
    this.descontoCaixa = 0,
    this.valorRecebido,
    this.troco,
    this.onDesconto,
  });

  final String tituloSecaoPagamento;
  final String rotuloPagamento;
  final String totalFormatado;
  final String Function(double) formatarMoeda;
  final double descontoPdvOrcamento;
  final double descontoCaixa;
  final double? valorRecebido;
  final double? troco;
  final VoidCallback? onDesconto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exibirRecebido = valorRecebido != null;
    final trocoValor = troco ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.9)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tituloSecaoPagamento,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rotuloPagamento,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (descontoPdvOrcamento > 0.001) ...[
            const SizedBox(height: 4),
            Text(
              'Desconto (PDV): -${formatarMoeda(descontoPdvOrcamento)}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.tertiary,
              ),
            ),
          ],
          if (descontoCaixa > 0.001) ...[
            const SizedBox(height: 2),
            Text(
              'Desconto (caixa): -${formatarMoeda(descontoCaixa)}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.secondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'TOTAL',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (onDesconto != null)
                    TextButton.icon(
                      onPressed: onDesconto,
                      icon: const Icon(Icons.sell_outlined, size: 16),
                      label: const Text('Desconto (F6)'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    totalFormatado,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (exibirRecebido) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _chipValor(
                    context,
                    rotulo: 'Recebido',
                    valor: formatarMoeda(valorRecebido!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _chipValor(
                    context,
                    rotulo: 'Troco',
                    valor: formatarMoeda(trocoValor),
                    destaque: trocoValor > 0.009,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipValor(
    BuildContext context, {
    required String rotulo,
    required String valor,
    bool destaque = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: destaque
            ? scheme.primaryContainer.withValues(alpha: 0.65)
            : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: destaque
              ? scheme.primary.withValues(alpha: 0.45)
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: destaque ? scheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    this.descontoCaixa = 0,
    required this.formatarMoeda,
    this.onAlterarForma,
    this.onDesconto,
    required this.recebimento,
    required this.valorRecebidoExibicao,
    required this.troco,
    required this.acaoConfirmar,
  });

  final int numeroOrcamento;
  final String clienteNome;
  final int qtdItens;
  final String rotuloPagamento;
  final double totalComDesconto;
  final double descontoPdvOrcamento;
  final double descontoCaixa;
  final String Function(double) formatarMoeda;
  final VoidCallback? onAlterarForma;
  final VoidCallback? onDesconto;
  final Widget recebimento;
  final double valorRecebidoExibicao;
  final double troco;
  final Widget acaoConfirmar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numLabel = numeroOrcamento > 0
        ? VendaDocumentoRotuloHelper.rotuloControlePorNumero(numeroOrcamento)
        : 'Controle pendente';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
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
                          '$qtdItens item(ns)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
            ),
            const SizedBox(height: 12),
            Text(
              'Recebimento no caixa',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Confira ou ajuste os valores antes de confirmar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: recebimento,
              ),
            ),
            CaixaRodapeTotalDestaque(
              rotuloPagamento: rotuloPagamento,
              totalFormatado: formatarMoeda(totalComDesconto),
              formatarMoeda: formatarMoeda,
              descontoPdvOrcamento: descontoPdvOrcamento,
              descontoCaixa: descontoCaixa,
              valorRecebido: valorRecebidoExibicao,
              troco: troco,
              onDesconto: onDesconto,
            ),
            const SizedBox(height: 8),
            acaoConfirmar,
          ],
        ),
      ),
    );
  }
}

/// Campo padrao de valor recebido (dinheiro).
class CaixaCobrancaCampoDinheiro extends StatefulWidget {
  const CaixaCobrancaCampoDinheiro({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.totalAPagar,
    required this.troco,
    required this.formatarMoeda,
    required this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double totalAPagar;
  final double troco;
  final String Function(double) formatarMoeda;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CaixaCobrancaCampoDinheiro> createState() =>
      _CaixaCobrancaCampoDinheiroState();
}

class _CaixaCobrancaCampoDinheiroState extends State<CaixaCobrancaCampoDinheiro> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_selecionarTudoAoFocar);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.focusNode.hasFocus) {
        _selecionarTodoTexto();
      }
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_selecionarTudoAoFocar);
    super.dispose();
  }

  void _selecionarTudoAoFocar() {
    if (widget.focusNode.hasFocus) {
      _selecionarTodoTexto();
    }
  }

  void _selecionarTodoTexto() {
    final texto = widget.controller.text;
    if (texto.isEmpty) return;
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: texto.length,
    );
  }

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
            controller: widget.controller,
            focusNode: widget.focusNode,
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
              hintText: widget.formatarMoeda(widget.totalAPagar),
              border: const OutlineInputBorder(),
              isDense: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
            onTap: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _selecionarTodoTexto();
              });
            },
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
          ),
        ],
      ),
    );
  }
}

/// Painel lateral de cobranca na etapa de conferencia (checkout em uma tela).
class CaixaPainelCobrancaLateral extends StatelessWidget {
  const CaixaPainelCobrancaLateral({
    super.key,
    required this.rotuloPagamento,
    required this.totalComDesconto,
    required this.descontoPdvOrcamento,
    this.descontoCaixa = 0,
    required this.formatarMoeda,
    required this.recebimento,
    required this.valorRecebidoExibicao,
    required this.troco,
    required this.onFinalizar,
    this.onAlterarForma,
    this.onDesconto,
    this.onFechar,
  });

  final String rotuloPagamento;
  final double totalComDesconto;
  final double descontoPdvOrcamento;
  final double descontoCaixa;
  final String Function(double) formatarMoeda;
  final Widget recebimento;
  final double valorRecebidoExibicao;
  final double troco;
  final VoidCallback? onFinalizar;
  final VoidCallback? onAlterarForma;
  final VoidCallback? onDesconto;
  final VoidCallback? onFechar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Cobranca',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (onAlterarForma != null)
                  TextButton(
                    onPressed: onAlterarForma,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Alterar'),
                  ),
                if (onFechar != null)
                  IconButton(
                    tooltip: 'Fechar painel (Esc)',
                    onPressed: onFechar,
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
            Text(
              rotuloPagamento,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: recebimento,
              ),
            ),
            CaixaRodapeTotalDestaque(
              rotuloPagamento: rotuloPagamento,
              totalFormatado: formatarMoeda(totalComDesconto),
              formatarMoeda: formatarMoeda,
              descontoPdvOrcamento: descontoPdvOrcamento,
              descontoCaixa: descontoCaixa,
              valorRecebido: valorRecebidoExibicao,
              troco: troco,
              onDesconto: onDesconto,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: onFinalizar,
                icon: onFinalizar == null
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  onFinalizar == null
                      ? 'Processando...'
                      : 'Finalizar venda (Enter)',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Esc fecha o painel sem finalizar.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
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
