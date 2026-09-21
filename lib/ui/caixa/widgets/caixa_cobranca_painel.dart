import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/venda_documento_rotulo_helper.dart';
import '../../theme/app_semantic_colors.dart';

/// Altura util abaixo da qual o painel de cobranca usa espacamento compacto (ex.: 768px).
bool caixaCobrancaViewportCompacto(BuildContext context) {
  return MediaQuery.sizeOf(context).height < 820;
}

/// Banner de troco em destaque para leitura rapida no PDV.
class CaixaBannerTrocoDestaque extends StatelessWidget {
  const CaixaBannerTrocoDestaque({
    super.key,
    required this.valorFormatado,
    this.compact = false,
  });

  final String valorFormatado;
  final bool compact;

  static Color _verdeEscuro(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    return semantic?.successFg ?? Colors.green.shade900;
  }

  @override
  Widget build(BuildContext context) {
    final bg = _verdeEscuro(context);
    final valorSize = compact ? 24.0 : 30.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TROCO',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w800,
              fontSize: compact ? 13 : 15,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valorFormatado,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: valorSize,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    this.compact = false,
    this.exibirCabecalhoForma = true,
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
  final bool compact;
  final bool exibirCabecalhoForma;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exibirRecebido = valorRecebido != null;
    final trocoValor = troco ?? 0;
    final compact = this.compact;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 8 : 12,
        compact ? 10 : 14,
        compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.9)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (exibirCabecalhoForma) ...[
            Text(
              tituloSecaoPagamento,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 11 : null,
              ),
            ),
            SizedBox(height: compact ? 0 : 2),
            Text(
              rotuloPagamento,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: compact ? 14 : null,
              ),
            ),
          ],
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
          SizedBox(height: compact ? 6 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: compact ? 2 : 6),
                    child: Text(
                      'TOTAL',
                      style: (compact
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleLarge)
                          ?.copyWith(
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
                    style: (compact
                            ? theme.textTheme.headlineSmall
                            : theme.textTheme.displaySmall)
                        ?.copyWith(
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
            SizedBox(height: compact ? 4 : 8),
            if (trocoValor > 0.009) ...[
              _chipValor(
                context,
                rotulo: 'Recebido',
                valor: formatarMoeda(valorRecebido!),
                compact: compact,
              ),
              SizedBox(height: compact ? 4 : 8),
              CaixaBannerTrocoDestaque(
                valorFormatado: formatarMoeda(trocoValor),
                compact: compact,
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _chipValor(
                      context,
                      rotulo: 'Recebido',
                      valor: formatarMoeda(valorRecebido!),
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 10),
                  Expanded(
                    child: _chipValor(
                      context,
                      rotulo: 'TROCO',
                      valor: formatarMoeda(trocoValor),
                      compact: compact,
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
    bool destaqueVerde = false,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>();
    final fgVerde = semantic?.successFg ?? Colors.green.shade800;
    final bgVerde = semantic?.successBg ?? Colors.green.shade50;
    final bordaVerde = semantic?.successBorder ?? Colors.green.shade200;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 8,
      ),
      decoration: BoxDecoration(
        color: destaqueVerde
            ? bgVerde
            : destaque
                ? scheme.primaryContainer.withValues(alpha: 0.65)
                : scheme.surface,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(
          color: destaqueVerde
              ? bordaVerde
              : destaque
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
              color: destaqueVerde
                  ? fgVerde
                  : scheme.onSurfaceVariant,
              fontWeight: destaqueVerde ? FontWeight.w700 : null,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              softWrap: false,
              style: (compact
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(
                fontWeight: FontWeight.w800,
                color: destaqueVerde
                    ? fgVerde
                    : destaque
                        ? scheme.primary
                        : null,
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
        ? VendaDocumentoRotuloHelper.rotuloOrcamentoPorNumero(numeroOrcamento)
        : 'Orçamento';

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
            const SizedBox(height: 8),
            recebimento,
            const Spacer(),
            CaixaRodapeTotalDestaque(
              rotuloPagamento: rotuloPagamento,
              totalFormatado: formatarMoeda(totalComDesconto),
              formatarMoeda: formatarMoeda,
              descontoPdvOrcamento: descontoPdvOrcamento,
              descontoCaixa: descontoCaixa,
              valorRecebido: valorRecebidoExibicao,
              troco: troco,
              onDesconto: onDesconto,
              compact: caixaCobrancaViewportCompacto(context),
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
    this.compact = false,
    this.mostrarBannerTroco = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double totalAPagar;
  final double troco;
  final String Function(double) formatarMoeda;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool compact;
  final bool mostrarBannerTroco;

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

    final compact = widget.compact;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Dinheiro',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : null,
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                  ],
                  style: (compact
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'Valor recebido',
                    hintText: widget.formatarMoeda(widget.totalAPagar),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: compact ? 8 : 12,
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
              ),
            ],
          ),
          if (widget.mostrarBannerTroco && widget.troco > 0.009) ...[
            SizedBox(height: compact ? 6 : 10),
            CaixaBannerTrocoDestaque(
              valorFormatado: widget.formatarMoeda(widget.troco),
              compact: compact,
            ),
          ],
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
    this.processandoFinalizacao = false,
    this.finalizarHabilitado = true,
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
  final bool processandoFinalizacao;
  final bool finalizarHabilitado;
  final VoidCallback? onAlterarForma;
  final VoidCallback? onDesconto;
  final VoidCallback? onFechar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = caixaCobrancaViewportCompacto(context);

    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 12,
          compact ? 6 : 10,
          compact ? 8 : 12,
          compact ? 6 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Cobranca',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13 : null,
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
                    icon: Icon(Icons.close, size: compact ? 18 : 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: compact ? 28 : 32,
                      minHeight: compact ? 28 : 32,
                    ),
                  ),
              ],
            ),
            Text(
              rotuloPagamento,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: compact ? 13 : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: compact ? 6 : 10),
            recebimento,
            const Spacer(),
            CaixaRodapeTotalDestaque(
              rotuloPagamento: rotuloPagamento,
              totalFormatado: formatarMoeda(totalComDesconto),
              formatarMoeda: formatarMoeda,
              descontoPdvOrcamento: descontoPdvOrcamento,
              descontoCaixa: descontoCaixa,
              valorRecebido: valorRecebidoExibicao,
              troco: troco,
              onDesconto: onDesconto,
              compact: compact,
              exibirCabecalhoForma: false,
            ),
            SizedBox(height: compact ? 6 : 8),
            SizedBox(
              height: compact ? 40 : 46,
              child: FilledButton.icon(
                onPressed: processandoFinalizacao || !finalizarHabilitado
                    ? null
                    : onFinalizar,
                style: FilledButton.styleFrom(
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 16,
                    vertical: compact ? 8 : 12,
                  ),
                ),
                icon: processandoFinalizacao
                    ? SizedBox(
                        width: compact ? 16 : 18,
                        height: compact ? 16 : 18,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.check_circle_outline, size: compact ? 18 : 24),
                label: Text(
                  processandoFinalizacao
                      ? 'Processando...'
                      : 'Finalizar venda (Enter)',
                  style: compact
                      ? theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : null,
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
    this.compact = false,
  });

  final IconData icone;
  final String titulo;
  final String subtitulo;
  final String? detalhe;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = this.compact;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: compact ? 24 : 32, color: scheme.primary),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : null,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  subtitulo,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: compact ? 12 : null,
                  ),
                  maxLines: compact ? 3 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
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
