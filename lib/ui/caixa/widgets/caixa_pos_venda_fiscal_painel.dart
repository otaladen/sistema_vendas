import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/caixa_fiscal_status.dart';
import '../../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../../../model/cliente.dart';
import '../../../model/venda.dart';
import '../caixa_fiscal_chip.dart';

/// Painel fullscreen de emissao fiscal pos-pagamento (Fase 3).
class CaixaPosVendaFiscalPainel extends StatelessWidget {
  const CaixaPosVendaFiscalPainel({
    super.key,
    required this.venda,
    required this.cliente,
    required this.totalRecebido,
    required this.troco,
    required this.formatarMoeda,
    required this.exigeNfe55,
    required this.jaTemNfe55,
    required this.podeConcluir,
    required this.processando,
    required this.onCupomNaoFiscal,
    required this.onEmitirNfce,
    required this.onEmitirNfe55,
    required this.onConcluir,
    required this.onCancelarVenda,
  });

  final Venda venda;
  final Cliente? cliente;
  final double totalRecebido;
  final double troco;
  final String Function(double) formatarMoeda;
  final bool exigeNfe55;
  final bool jaTemNfe55;
  final bool podeConcluir;
  final bool processando;
  final VoidCallback onCupomNaoFiscal;
  final VoidCallback onEmitirNfce;
  final VoidCallback onEmitirNfe55;
  final VoidCallback onConcluir;
  final VoidCallback onCancelarVenda;

  int get _numCupom =>
      venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fiscalInfo = CaixaFiscalStatusHelper.deVenda(venda, orcamentoPendente: false);

    final bloqueiaNovaNfce = VendaDocumentoFiscalMutex.bloqueiaNovaNfce(venda);
    final atalhos = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.digit2): onCupomNaoFiscal,
      const SingleActivator(LogicalKeyboardKey.numpad2): onCupomNaoFiscal,
      const SingleActivator(LogicalKeyboardKey.digit4): onEmitirNfe55,
      const SingleActivator(LogicalKeyboardKey.numpad4): onEmitirNfe55,
    };
    if (!bloqueiaNovaNfce) {
      atalhos[const SingleActivator(LogicalKeyboardKey.digit3)] = onEmitirNfce;
      atalhos[const SingleActivator(LogicalKeyboardKey.numpad3)] = onEmitirNfce;
      atalhos[const SingleActivator(LogicalKeyboardKey.enter)] = onEmitirNfce;
      atalhos[const SingleActivator(LogicalKeyboardKey.numpadEnter)] =
          onEmitirNfce;
    }
    if (podeConcluir) {
      atalhos[const SingleActivator(LogicalKeyboardKey.digit1)] = onConcluir;
      atalhos[const SingleActivator(LogicalKeyboardKey.numpad1)] = onConcluir;
      atalhos[const SingleActivator(LogicalKeyboardKey.escape)] = onConcluir;
    }

    return CallbackShortcuts(
      bindings: atalhos,
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.surfaceContainerHighest,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: scheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagamento confirmado — Venda $_numCupom',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          cliente?.nomeRazao ?? 'Consumidor / sem cadastro',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  CaixaFiscalChip(info: fiscalInfo),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final empilhar = c.maxWidth < 720;
                  final resumo = _ResumoPosVenda(
                    formatarMoeda: formatarMoeda,
                    total: venda.total,
                    recebido: totalRecebido,
                    troco: troco,
                  );
                  final acoes = _AcoesFiscais(
                    processando: processando,
                    exigeNfe55: exigeNfe55,
                    jaTemNfe55: jaTemNfe55,
                    nfceEmitida: venda.nfceEmitida,
                    bloqueiaNovaNfce: bloqueiaNovaNfce,
                    onCupom: onCupomNaoFiscal,
                    onNfce: onEmitirNfce,
                    onNfe55: onEmitirNfe55,
                  );
                  if (empilhar) {
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          resumo,
                          const SizedBox(height: 12),
                          acoes,
                        ],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: resumo),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: acoes),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (!podeConcluir) ...[
              Material(
                color: scheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Obrigatorio registrar documento: use tecla 2, 3 ou 4. '
                          'So depois disso e possivel concluir (1 / Esc).',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              podeConcluir
                  ? 'Atalhos: Enter/3 = NFC-e · 2 = cupom · 4 = NF-e 55 · 1/Esc = concluir'
                  : 'Atalhos: Enter/3 = NFC-e · 2 = cupom · 4 = NF-e 55',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: processando ? null : onCancelarVenda,
                icon: const Icon(Icons.cancel_outlined),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                label: const Text('Cancelar esta venda'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: (processando || !podeConcluir) ? null : onConcluir,
                icon: const Icon(Icons.playlist_add_check),
                label: Text(
                  podeConcluir
                      ? 'Concluir e voltar ao inicio (Esc · 1)'
                      : 'Concluir (registre 2, 3 ou 4 antes)',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoPosVenda extends StatelessWidget {
  const _ResumoPosVenda({
    required this.formatarMoeda,
    required this.total,
    required this.recebido,
    required this.troco,
  });

  final String Function(double) formatarMoeda;
  final double total;
  final double recebido;
  final double troco;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Resumo do pagamento',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _linhaResumo(context, 'Total da venda', formatarMoeda(total), destaque: true),
            _linhaResumo(context, 'Total recebido', formatarMoeda(recebido)),
            _linhaResumo(
              context,
              'Troco',
              formatarMoeda(troco),
              cor: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Baixa de estoque (itens leva agora) ao autorizar NFC-e/NF-e ou '
              'ao cupom interno (2). Carreto e retirada futura: reserva.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaResumo(
    BuildContext context,
    String rotulo,
    String valor, {
    bool destaque = false,
    Color? cor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: theme.textTheme.bodyMedium)),
          Text(
            valor,
            style: (destaque ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)
                ?.copyWith(
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

class _AcoesFiscais extends StatelessWidget {
  const _AcoesFiscais({
    required this.processando,
    required this.exigeNfe55,
    required this.jaTemNfe55,
    required this.nfceEmitida,
    required this.bloqueiaNovaNfce,
    required this.onCupom,
    required this.onNfce,
    required this.onNfe55,
  });

  final bool processando;
  final bool exigeNfe55;
  final bool jaTemNfe55;
  final bool nfceEmitida;
  final bool bloqueiaNovaNfce;
  final VoidCallback onCupom;
  final VoidCallback onNfce;
  final VoidCallback onNfe55;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Emissao de documento',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (exigeNfe55 && !jaTemNfe55) ...[
              const SizedBox(height: 10),
              Material(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cliente CNPJ — emita NF-e modelo 55 (tecla 4) '
                          'para faturamento correto.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _botaoAcao(
              context,
              icone: Icons.receipt_outlined,
              titulo: 'Cupom nao fiscal',
              subtitulo: 'Cupom interno + baixa de estoque (leva agora)',
              atalho: '2',
              onPressed: processando ? null : onCupom,
            ),
            const SizedBox(height: 8),
            _botaoAcao(
              context,
              icone: Icons.receipt_long_outlined,
              titulo: bloqueiaNovaNfce
                  ? (jaTemNfe55
                      ? 'NFC-e indisponivel (ja tem NF-e)'
                      : 'NFC-e ja emitida')
                  : 'Emitir NFC-e',
              subtitulo: bloqueiaNovaNfce && jaTemNfe55
                  ? 'Uma venda nao pode ter NFC-e e NF-e juntas'
                  : 'Cupom fiscal eletronico (consumidor final)',
              atalho: bloqueiaNovaNfce ? '—' : '3 · Enter',
              destaque: !bloqueiaNovaNfce,
              onPressed: processando || bloqueiaNovaNfce ? null : onNfce,
            ),
            const SizedBox(height: 8),
            _botaoAcao(
              context,
              icone: Icons.description_outlined,
              titulo: jaTemNfe55 ? 'NF-e 55 autorizada — abrir' : 'Emitir NF-e modelo 55',
              subtitulo: exigeNfe55
                  ? 'Nota completa para CNPJ / construcao'
                  : 'Nota completa quando exigida pelo cliente',
              atalho: '4',
              onPressed: processando ? null : onNfe55,
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoAcao(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required String atalho,
    required VoidCallback? onPressed,
    bool destaque = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icone, size: 26, color: destaque ? scheme.onPrimary : scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: destaque ? scheme.onPrimary : null,
                      ),
                ),
                Text(
                  subtitulo,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: destaque
                            ? scheme.onPrimary.withValues(alpha: 0.9)
                            : scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: destaque
                  ? scheme.onPrimary.withValues(alpha: 0.15)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              atalho,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: destaque ? scheme.onPrimary : null,
                  ),
            ),
          ),
        ],
      ),
    );

    if (destaque) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
      ),
      child: child,
    );
  }
}
