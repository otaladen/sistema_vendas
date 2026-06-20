import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/nfe_saida_fiscal_store.dart';
import '../../../domain/fiscal/nfe_pendencias_filtro.dart';
import '../../../domain/fiscal/nfe_pendencias_service.dart';
import '../../../domain/venda_documento_rotulo_helper.dart';
import '../../../model/venda.dart';

/// Aba Pendencias — fila operacional NF-e (Fase 4).
class NfeAbaPendencias extends StatelessWidget {
  const NfeAbaPendencias({
    super.key,
    required this.vendasSemNfe,
    required this.filtro,
    required this.onFiltroChanged,
    required this.processando,
    required this.rejeitadas,
    required this.emitindo,
    required this.onEmitirVenda,
    required this.onReconsultar,
    required this.onReconsultarTodas,
    required this.onVerDetalheRegistro,
    required this.onReemitirRegistro,
    required this.onVerErroRegistro,
  });

  final List<NfePendenciaVenda> vendasSemNfe;
  final NfePendenciasFiltro filtro;
  final ValueChanged<NfePendenciasFiltro> onFiltroChanged;
  final List<NfeSaidaFiscalRegistro> processando;
  final List<NfeSaidaFiscalRegistro> rejeitadas;
  final bool emitindo;
  final ValueChanged<Venda> onEmitirVenda;
  final ValueChanged<NfeSaidaFiscalRegistro> onReconsultar;
  final VoidCallback onReconsultarTodas;
  final ValueChanged<NfeSaidaFiscalRegistro> onVerDetalheRegistro;
  final ValueChanged<NfeSaidaFiscalRegistro> onReemitirRegistro;
  final ValueChanged<NfeSaidaFiscalRegistro> onVerErroRegistro;

  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _data = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('So CNPJ'),
              selected: filtro.somenteCnpj,
              onSelected: (v) => onFiltroChanged(
                filtro.copyWith(somenteCnpj: v),
              ),
            ),
            FilterChip(
              label: const Text('Com entrega/carreto'),
              selected: filtro.somenteComEntrega,
              onSelected: (v) => onFiltroChanged(
                filtro.copyWith(somenteComEntrega: v),
              ),
            ),
            FilterChip(
              label: const Text('Valor >= R\$ 500'),
              selected: filtro.valorMinimo >= 500,
              onSelected: (v) => onFiltroChanged(
                filtro.copyWith(valorMinimo: v ? 500 : 0),
              ),
            ),
            if (filtro.ativo)
              TextButton(
                onPressed: () => onFiltroChanged(const NfePendenciasFiltro()),
                child: const Text('Limpar filtros'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _secao(
          theme,
          titulo: 'Vendas sem NF-e autorizada (30 dias)',
          subtitulo:
              'Orcamentos finalizados com cliente, ainda sem nota modelo 55.'
              '${filtro.ativo ? " · filtros ativos" : ""}',
          filho: vendasSemNfe.isEmpty
              ? const Text('Nenhuma venda pendente de faturamento NF-e.')
              : Column(
                  children: [
                    for (final p in vendasSemNfe)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                            '${VendaDocumentoRotuloHelper.rotuloControleInterno(p.venda)} · ${p.clienteNome}',
                          ),
                          subtitle: Text(
                            '${_data.format(p.venda.data.toLocal())} · '
                            'R\$ ${_moeda.format(p.venda.total)}'
                            '${p.ultimoStatusNfe.isNotEmpty ? " · ultima tentativa: ${p.ultimoStatusNfe}" : ""}',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: emitindo ? null : () => onEmitirVenda(p.venda),
                            child: const Text('Emitir'),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _secao(
          theme,
          titulo: 'NF-e aguardando SEFAZ',
          subtitulo: 'Processando autorizacao na Focus.',
          trailing: processando.isNotEmpty
              ? OutlinedButton.icon(
                  onPressed: emitindo ? null : onReconsultarTodas,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reconsultar todas'),
                )
              : null,
          filho: processando.isEmpty
              ? const Text('Nenhuma nota em processamento.')
              : Column(
                  children: [
                    for (final r in processando)
                      _cardRegistro(
                        context,
                        r,
                        trailing: OutlinedButton(
                          onPressed: emitindo ? null : () => onReconsultar(r),
                          child: const Text('Reconsultar'),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _secao(
          theme,
          titulo: 'NF-e rejeitadas',
          subtitulo: 'Corrija os dados e reemita pela venda.',
          filho: rejeitadas.isEmpty
              ? const Text('Nenhuma rejeicao recente.')
              : Column(
                  children: [
                    for (final r in rejeitadas)
                      _cardRegistro(
                        context,
                        r,
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => onVerErroRegistro(r),
                              child: const Text('Erro'),
                            ),
                            FilledButton.tonal(
                              onPressed:
                                  emitindo ? null : () => onReemitirRegistro(r),
                              child: const Text('Reemitir'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _secao(
    ThemeData theme, {
    required String titulo,
    required String subtitulo,
    required Widget filho,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: theme.textTheme.titleMedium),
                  Text(subtitulo, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 8),
        filho,
      ],
    );
  }

  Widget _cardRegistro(
    BuildContext context,
    NfeSaidaFiscalRegistro r, {
    required Widget trailing,
  }) {
    return Card(
      child: ListTile(
        onTap: () => onVerDetalheRegistro(r),
        title: Text(
          '${VendaDocumentoRotuloHelper.rotuloControlePorNumero(r.numeroOrcamento)} · ${r.clienteNome}',
        ),
        subtitle: Text(
          '${r.referenciaFocus}\n${r.mensagemSefaz.isNotEmpty ? r.mensagemSefaz : r.rotuloStatus}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: trailing,
      ),
    );
  }
}
