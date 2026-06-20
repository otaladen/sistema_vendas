import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/fiscal/fiscal_bloqueios_fechamento.dart';
import '../../../domain/venda_documento_rotulo_helper.dart';
import '../../../model/venda.dart';
/// Alerta de pendencias fiscais antes do fechamento contabil.
class FiscalBloqueiosBanner extends StatelessWidget {
  const FiscalBloqueiosBanner({
    super.key,
    required this.bloqueios,
    this.onAbrirPendencias,
  });

  final FiscalBloqueiosFechamento bloqueios;
  final VoidCallback? onAbrirPendencias;

  static final _data = DateFormat('dd/MM/yyyy');
  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    if (!bloqueios.temAviso) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final critico = bloqueios.temBloqueioCritico;
    final corFundo = critico ? Colors.red.shade50 : Colors.orange.shade50;
    final corTexto = critico ? Colors.red.shade900 : Colors.orange.shade900;

    final linhas = <String>[];
    if (bloqueios.bloqueiaExportacao) {
      linhas.add(
        '${bloqueios.qtdNfceProcessando} NFC-e aguardando SEFAZ — '
        'exportacao bloqueada ate regularizar.',
      );
    } else if (bloqueios.qtdNfceProcessando > 0) {
      linhas.add(
        '${bloqueios.qtdNfceProcessando} NFC-e aguardando SEFAZ '
        '(nao entram no ZIP ate autorizar).',
      );
    }
    if (bloqueios.qtdNfeProcessando > 0) {
      linhas.add(
        '${bloqueios.qtdNfeProcessando} NF-e modelo 55 em processamento.',
      );
    }
    if (bloqueios.qtdNfeRejeitadas > 0) {
      linhas.add(
        '${bloqueios.qtdNfeRejeitadas} NF-e rejeitada(s) no periodo '
        '(sem XML para o contador).',
      );
    }

    return Material(
      color: corFundo,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  critico ? Icons.warning_amber_rounded : Icons.info_outline,
                  color: corTexto,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    critico
                        ? 'Resolva antes de enviar ao contador'
                        : 'Atencao no fechamento',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: corTexto,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l,
                  style: theme.textTheme.bodyMedium?.copyWith(color: corTexto),
                ),
              ),
            if (bloqueios.vendasNfceProcessando.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...bloqueios.vendasNfceProcessando.take(5).map(_linhaNfce),
              if (bloqueios.vendasNfceProcessando.length > 5)
                Text(
                  '... e mais ${bloqueios.vendasNfceProcessando.length - 5}.',
                  style: theme.textTheme.bodySmall?.copyWith(color: corTexto),
                ),
            ],
            if (onAbrirPendencias != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onAbrirPendencias,
                  child: const Text('Abrir pendencias fiscais'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linhaNfce(Venda v) {
    return Text(
      '${VendaDocumentoRotuloHelper.rotuloIdentificacaoLista(v)} · '
      '${_data.format(v.data.toLocal())} · '
      'R\$ ${_moeda.format(v.total)}',
      style: TextStyle(
        fontSize: 12,
        color: Colors.red.shade800,
      ),
    );
  }
}
