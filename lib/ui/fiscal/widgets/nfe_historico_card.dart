import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/nfe_saida_fiscal_store.dart';
import '../../../domain/fiscal/nfe_carta_correcao_registro.dart';
import '../../../domain/fiscal/nfe_historico_timeline.dart';

/// Card de um registro no historico NF-e (timeline + acoes).
class NfeHistoricoCard extends StatelessWidget {
  const NfeHistoricoCard({
    super.key,
    required this.registro,
    required this.emitindo,
    required this.onAbrirDanfe,
    required this.onAbrirXml,
    this.onAbrirXmlCancelamento,
    required this.onReconsultar,
    required this.onVerErro,
    required this.onCancelar,
    required this.onCartaCorrecao,
    required this.onReemitir,
    this.onEnviarEmail,
    this.onEnviarWhatsapp,
    this.onAbrirPdfCce,
    this.onAbrirXmlCce,
  });

  final NfeSaidaFiscalRegistro registro;
  final bool emitindo;
  final VoidCallback onAbrirDanfe;
  final VoidCallback onAbrirXml;
  final VoidCallback? onAbrirXmlCancelamento;
  final VoidCallback onReconsultar;
  final VoidCallback onVerErro;
  final VoidCallback onCancelar;
  final VoidCallback onCartaCorrecao;
  final VoidCallback onReemitir;
  final VoidCallback? onEnviarEmail;
  final VoidCallback? onEnviarWhatsapp;
  final void Function(NfeCartaCorrecaoRegistro cce)? onAbrirPdfCce;
  final void Function(NfeCartaCorrecaoRegistro cce)? onAbrirXmlCce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = registro;
    final cor = r.cancelada
        ? Colors.orange.shade800
        : r.autorizada
            ? Colors.green.shade700
            : r.processando
                ? theme.colorScheme.primary
                : theme.colorScheme.error;
    final timeline = NfeHistoricoTimelineBuilder.fromRegistro(r);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: cor),
                const SizedBox(width: 8),
                Text(
                  r.rotuloStatus,
                  style: theme.textTheme.titleMedium?.copyWith(color: cor),
                ),
                const Spacer(),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(r.emitidaEm.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Venda ${r.numeroOrcamento} · ${r.clienteNome}'),
            if (r.numero.isNotEmpty)
              Text(
                'NF-e nº ${r.numero}${r.serie.isNotEmpty ? ' · serie ${r.serie}' : ''}',
              ),
            if (r.chaveNfe.isNotEmpty)
              Text(
                r.chaveNfe,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (r.rejeitada && r.mensagemSefaz.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.mensagemSefaz,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _Timeline(timeline: timeline, theme: theme),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (r.autorizada && r.urlDanfe.isNotEmpty)
                  FilledButton.icon(
                    onPressed: onAbrirDanfe,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('DANFE'),
                  ),
                if (r.autorizada && r.urlXml.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: onAbrirXml,
                    icon: const Icon(Icons.code_outlined, size: 18),
                    label: const Text('XML'),
                  ),
                if (r.autorizada && onEnviarEmail != null)
                  OutlinedButton.icon(
                    onPressed: emitindo ? null : onEnviarEmail,
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('E-mail'),
                  ),
                if (r.autorizada &&
                    r.urlDanfe.isNotEmpty &&
                    onEnviarWhatsapp != null)
                  OutlinedButton.icon(
                    onPressed: emitindo ? null : onEnviarWhatsapp,
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                if (r.processando)
                  OutlinedButton.icon(
                    onPressed: emitindo ? null : onReconsultar,
                    icon: const Icon(Icons.refresh_outlined, size: 18),
                    label: const Text('Reconsultar'),
                  ),
                if (r.rejeitada) ...[
                  OutlinedButton.icon(
                    onPressed: onVerErro,
                    icon: const Icon(Icons.error_outline, size: 18),
                    label: const Text('Ver erro'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: emitindo ? null : onReemitir,
                    icon: const Icon(Icons.replay_outlined, size: 18),
                    label: const Text('Reemitir venda'),
                  ),
                ],
                if (r.autorizada && !r.cancelada) ...[
                  OutlinedButton.icon(
                    onPressed: emitindo ? null : onCartaCorrecao,
                    icon: const Icon(Icons.edit_note_outlined, size: 18),
                    label: Text(
                      r.totalCartasCorrecao > 0
                          ? 'Nova CC-e'
                          : 'CC-e',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: emitindo ? null : onCancelar,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancelar'),
                  ),
                ],
                for (final cce in r.cartasCorrecao) ...[
                  if (cce.urlPdf.isNotEmpty && onAbrirPdfCce != null)
                    OutlinedButton.icon(
                      onPressed: () => onAbrirPdfCce!(cce),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text('CC-e #${cce.numeroSequencia} PDF'),
                    ),
                  if (cce.urlXml.isNotEmpty && onAbrirXmlCce != null)
                    OutlinedButton.icon(
                      onPressed: () => onAbrirXmlCce!(cce),
                      icon: const Icon(Icons.article_outlined, size: 18),
                      label: Text('CC-e #${cce.numeroSequencia} XML'),
                    ),
                ],
                if (r.cancelada && r.urlXmlEventoCancelamento.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: onAbrirXmlCancelamento,
                    icon: const Icon(Icons.event_busy_outlined, size: 18),
                    label: const Text('XML cancelamento'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.timeline, required this.theme});

  final List<NfeHistoricoTimelineItem> timeline;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < timeline.length; i++)
          _TimelineRow(
            item: timeline[i],
            theme: theme,
            isLast: i == timeline.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.theme,
    required this.isLast,
  });

  final NfeHistoricoTimelineItem item;
  final ThemeData theme;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cor = item.erro
        ? theme.colorScheme.error
        : item.concluido
            ? theme.colorScheme.primary
            : theme.colorScheme.outline;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Icon(
                  item.concluido
                      ? (item.erro ? Icons.close : Icons.check_circle)
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: cor,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.dividerColor,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.titulo,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    item.subtitulo,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
