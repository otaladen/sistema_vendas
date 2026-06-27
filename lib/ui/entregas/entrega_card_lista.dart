import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entrega_venda_helper.dart';
import '../../model/venda.dart';
import 'entrega_pod_chip.dart';
import 'logistica_entregas.dart';

/// Callbacks da linha compacta de entrega (aba Lista).
class EntregaCardListaCallbacks {
  const EntregaCardListaCallbacks({
    required this.formatarMoeda,
    required this.rotuloStatus,
    required this.rotuloJanela,
    required this.rotuloPrioridade,
    required this.extrairBairro,
    required this.nomeMotorista,
    required this.nomeVendedor,
    required this.progressoCarga,
    required this.corProgressoCarga,
    required this.corStatus,
    required this.observacaoSemMotorista,
    required this.textoResumoComplemento,
    required this.podeDevolucaoPosCarreto,
    required this.podeRetiradaLojaAntesSaida,
    required this.onTapDetalhes,
    required this.onAlternarSelecao,
    required this.onNavegar,
    required this.onHistorico,
    required this.onMotorista,
    required this.onChecklistCarga,
    required this.onMarcarData,
    required this.onAcaoPrincipal,
    required this.onPopupSelected,
    required this.labelAcaoPrincipal,
    required this.podeGerenciarStatus,
  });

  final String Function(double) formatarMoeda;
  final String Function(String status) rotuloStatus;
  final String Function(String janela) rotuloJanela;
  final String Function(String prioridade) rotuloPrioridade;
  final String Function(Venda) extrairBairro;
  final String Function(Venda) nomeMotorista;
  final String Function(Venda) nomeVendedor;
  final int Function(Venda) progressoCarga;
  final Color Function(BuildContext context, int progresso) corProgressoCarga;
  final Color Function(ColorScheme scheme, String status) corStatus;
  final String Function(Venda) observacaoSemMotorista;
  final String? Function(Venda) textoResumoComplemento;
  final bool Function(Venda) podeDevolucaoPosCarreto;
  final bool Function(Venda) podeRetiradaLojaAntesSaida;
  final VoidCallback onTapDetalhes;
  final VoidCallback onAlternarSelecao;
  final VoidCallback onNavegar;
  final VoidCallback onHistorico;
  final VoidCallback onMotorista;
  final VoidCallback onChecklistCarga;
  final VoidCallback onMarcarData;
  final Future<void> Function() onAcaoPrincipal;
  final void Function(String value) onPopupSelected;
  final String? Function(Venda) labelAcaoPrincipal;
  final bool podeGerenciarStatus;
}

class EntregaCardLista extends StatelessWidget {
  const EntregaCardLista({
    super.key,
    required this.venda,
    required this.dateFormat,
    required this.dataMarcadaFmt,
    required this.callbacks,
    this.dentroDeGrupoCarreto = false,
    this.modoSelecao = false,
    this.selecionada = false,
    this.paradaNoMesmoCarro,
  });

  final Venda venda;
  final DateFormat dateFormat;
  final DateFormat dataMarcadaFmt;
  final EntregaCardListaCallbacks callbacks;
  final bool dentroDeGrupoCarreto;
  final bool modoSelecao;
  final bool selecionada;
  final int? paradaNoMesmoCarro;

  static const _kMenuMarcarData = '__acao_marcar_data_entrega__';
  static const _kMenuLimparData = '__acao_limpar_data_entrega__';
  static const _kMenuDevolucao = '__acao_devolucao_pos_carreto__';
  static const _kMenuRetiradaLoja = '__acao_retirada_loja_carreto__';
  static const _kMenuHistorico = '__acao_historico__';
  static const _kMenuComplemento = '__acao_complemento__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusCor = callbacks.corStatus(scheme, venda.statusEntrega);
    final progressoCarga = callbacks.progressoCarga(venda);
    final corCarga = callbacks.corProgressoCarga(context, progressoCarga);
    final acaoLabel = callbacks.labelAcaoPrincipal(venda);
    final cliente = venda.cliente.target?.nomeRazao ?? 'Sem cliente';
    final bairro = callbacks.extrairBairro(venda);
    final motorista = callbacks.nomeMotorista(venda);
    final semMotorista = !motoristaLogisticaDefinido(motorista);
    final resumoComp = callbacks.textoResumoComplemento(venda);

    return Card(
      elevation: dentroDeGrupoCarreto ? 0 : null,
      margin: dentroDeGrupoCarreto
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 8),
      color: dentroDeGrupoCarreto ? scheme.surface : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: modoSelecao ? callbacks.onAlternarSelecao : callbacks.onTapDetalhes,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (modoSelecao)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: selecionada,
                  onChanged: (_) => callbacks.onAlternarSelecao(),
                  title: const Text('Selecionar'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              if (paradaNoMesmoCarro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: Text('Parada #$paradaNoMesmoCarro'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: scheme.primary,
                      labelStyle: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${venda.numeroOrcamento} · $cliente',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$bairro · ${callbacks.formatarMoeda(venda.total)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _chipStatus(statusCor, callbacks.rotuloStatus(venda.statusEntrega)),
                            Text(
                              semMotorista ? 'Sem motorista' : motorista,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: semMotorista ? scheme.error : null,
                                fontWeight:
                                    semMotorista ? FontWeight.w700 : null,
                              ),
                            ),
                            Text(
                              callbacks.rotuloJanela(venda.janelaEntrega),
                              style: theme.textTheme.labelSmall,
                            ),
                            InkWell(
                              onTap: callbacks.onChecklistCarga,
                              child: Text(
                                'Carga $progressoCarga/3',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: corCarga,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (venda.dataEntregaMarcada != null)
                              Text(
                                dataMarcadaFmt.format(
                                  venda.dataEntregaMarcada!.toLocal(),
                                ),
                                style: theme.textTheme.labelSmall,
                              ),
                            if (venda.tipoEntrega == EntregaVendaHelper.tipoMisto)
                              Chip(
                                label: const Text('Mista'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            EntregaPodChip(venda: venda),
                          ],
                        ),
                        if (resumoComp != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              resumoComp,
                              style: TextStyle(
                                color: Colors.deepOrange.shade900,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (acaoLabel != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: () => callbacks.onAcaoPrincipal(),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(acaoLabel),
                      ),
                    ),
                  if (acaoLabel != null) const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Navegar',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: callbacks.onNavegar,
                    icon: const Icon(Icons.directions_rounded, size: 22),
                  ),
                  IconButton(
                    tooltip: 'Ver itens',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: callbacks.onTapDetalhes,
                    icon: const Icon(Icons.receipt_long_outlined, size: 22),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Mais acoes',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: callbacks.onPopupSelected,
                    itemBuilder: (context) => _itensMenu(context),
                  ),
                ],
              ),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: Text(
                    'Detalhes',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Endereco: ${venda.enderecoEntrega}'),
                          Text('Vendedor: ${callbacks.nomeVendedor(venda)}'),
                          Text('Frete: ${callbacks.formatarMoeda(venda.valorFrete)}'),
                          Text(
                            venda.dataEntregaMarcada == null
                                ? 'Entrega marcada: sem data'
                                : 'Entrega marcada: ${dataMarcadaFmt.format(venda.dataEntregaMarcada!.toLocal())}',
                          ),
                          Text(
                            'Prioridade: ${callbacks.rotuloPrioridade(venda.prioridadeEntrega)}',
                          ),
                          Text(
                            'Criado em: ${dateFormat.format(venda.data.toLocal())}',
                          ),
                          if (callbacks.observacaoSemMotorista(venda).trim().isNotEmpty)
                            Text('Obs: ${callbacks.observacaoSemMotorista(venda)}'),
                          if (venda.tipoEntrega == EntregaVendaHelper.tipoMisto)
                            Text(
                              EntregaVendaHelper.resumoContagem(
                                venda.itens.map((i) => i.tipoEntregaItem),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: callbacks.onHistorico,
                                icon: const Icon(Icons.history, size: 18),
                                label: const Text('Historico'),
                              ),
                              TextButton.icon(
                                onPressed: callbacks.onMotorista,
                                icon: const Icon(Icons.person_outline, size: 18),
                                label: const Text('Motorista'),
                              ),
                              if (callbacks.podeGerenciarStatus)
                                TextButton(
                                  onPressed: callbacks.onMarcarData,
                                  child: Text(
                                    venda.dataEntregaMarcada == null
                                        ? 'Definir data'
                                        : 'Alterar data',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipStatus(Color cor, String rotulo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: cor.withValues(alpha: 0.12),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        rotulo,
        style: TextStyle(
          color: cor,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _itensMenu(BuildContext context) {
    return [
      const PopupMenuItem(
        value: _kMenuHistorico,
        child: Text('Historico'),
      ),
      if (callbacks.podeRetiradaLojaAntesSaida(venda))
        PopupMenuItem(
          enabled: callbacks.podeGerenciarStatus,
          value: _kMenuRetiradaLoja,
          child: const Text('Retirada na loja (antes do carro sair)'),
        ),
      PopupMenuItem(
        enabled: callbacks.podeGerenciarStatus,
        value: _kMenuMarcarData,
        child: Text(
          venda.dataEntregaMarcada == null
              ? 'Marcar data de entrega'
              : 'Alterar data de entrega',
        ),
      ),
      if (venda.dataEntregaMarcada != null)
        PopupMenuItem(
          enabled: callbacks.podeGerenciarStatus,
          value: _kMenuLimparData,
          child: const Text('Limpar data de entrega'),
        ),
      if (venda.statusEntrega == 'saiu_entrega')
        PopupMenuItem(
          enabled: callbacks.podeGerenciarStatus,
          value: _kMenuComplemento,
          child: const Text('Faltou item (complemento)'),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        enabled: callbacks.podeGerenciarStatus,
        value: 'pendente',
        child: const Text('Status: Pendente'),
      ),
      PopupMenuItem(
        enabled: callbacks.podeGerenciarStatus,
        value: 'roteirizada',
        child: const Text('Status: Roteirizada'),
      ),
      PopupMenuItem(
        enabled: callbacks.podeGerenciarStatus,
        value: 'saiu_entrega',
        child: const Text('Status: Saiu para entrega'),
      ),
      if (venda.statusEntrega != 'saiu_entrega' &&
          venda.statusEntrega != 'entregue_complemento_pendente')
        PopupMenuItem(
          enabled: callbacks.podeGerenciarStatus,
          value: 'entregue',
          child: const Text('Status: Entregue'),
        ),
      PopupMenuItem(
        enabled: callbacks.podeGerenciarStatus,
        value: 'reagendada',
        child: const Text('Status: Reagendada'),
      ),
      PopupMenuItem(
        enabled: callbacks.podeGerenciarStatus,
        value: 'cancelada',
        child: const Text('Status: Cancelada'),
      ),
      if (callbacks.podeDevolucaoPosCarreto(venda)) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _kMenuDevolucao,
          child: const Text('Devolucao / troca (mercadoria voltou)'),
        ),
      ],
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'prioridade:normal',
        child: Text('Prioridade: Normal'),
      ),
      const PopupMenuItem(
        value: 'prioridade:urgente',
        child: Text('Prioridade: Urgente'),
      ),
      const PopupMenuItem(
        value: 'prioridade:agendada',
        child: Text('Prioridade: Agendada'),
      ),
    ];
  }
}
