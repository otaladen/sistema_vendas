import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/conferencia_carga_repository.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import 'conferencia_carga_consolidada_lista.dart';
import 'entregas_barra_compacta.dart';
import 'entregas_montagem_callbacks.dart';
import 'logistica_entregas.dart';
import 'montagem_entrega_viagem.dart';
import 'montagem_impressao_lote.dart';
import 'montagem_mapa_rota.dart';
import 'romaneio_carga_consolidada.dart';
import 'romaneio_relatorios.dart';

enum _PainelViagemSecao { carga, rota }

/// Painel principal: dia + motorista + viagem → carga consolidada e paradas.
class PainelMontagemEntregas extends StatefulWidget {
  const PainelMontagemEntregas({
    super.key,
    required this.entregas,
    required this.quantidadeItemEntrega,
    required this.callbacks,
    required this.podeGerenciarStatus,
    required this.conferenciaRepository,
    required this.usuarioAtual,
  });

  final List<Venda> entregas;
  final int Function(Venda venda, ItemVenda item) quantidadeItemEntrega;
  final EntregasMontagemCallbacks callbacks;
  final bool podeGerenciarStatus;
  final ConferenciaCargaRepository conferenciaRepository;
  final String usuarioAtual;

  @override
  State<PainelMontagemEntregas> createState() => _PainelMontagemEntregasState();
}

class _PainelMontagemEntregasState extends State<PainelMontagemEntregas> {
  String? _motoristaSelecionado;
  String? _viagemChaveSelecionada;
  bool _modoAgrupar = false;
  final Set<int> _idsSelecionadas = {};
  _PainelViagemSecao _secaoViagem = _PainelViagemSecao.carga;

  @override
  void initState() {
    super.initState();
    _sincronizarSelecoes();
  }

  @override
  void didUpdateWidget(PainelMontagemEntregas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entregas != widget.entregas) {
      _sincronizarSelecoes();
    }
  }

  void _sincronizarSelecoes() {
    final motoristas = montagemMotoristasDasEntregas(widget.entregas);
    if (motoristas.isEmpty) {
      _motoristaSelecionado = null;
      _viagemChaveSelecionada = null;
      return;
    }
    if (_motoristaSelecionado == null ||
        !motoristas.contains(_motoristaSelecionado)) {
      _motoristaSelecionado = motoristas.first;
    }
    final viagens = montagemViagensDoMotorista(
      widget.entregas,
      _motoristaSelecionado!,
    );
    if (viagens.isEmpty) {
      _viagemChaveSelecionada = null;
      return;
    }
    if (_viagemChaveSelecionada == null ||
        !viagens.any((v) => v.chave == _viagemChaveSelecionada)) {
      _viagemChaveSelecionada = viagens.first.chave;
    }
  }

  List<Venda> _entregasAgrupaveisMotorista(String motorista) {
    return widget.entregas
        .where((v) => nomeMotoristaEntrega(v) == motorista)
        .where(
          (v) =>
              !v.cancelada &&
              v.status == 'finalizada' &&
              EntregaVendaHelper.vendaTemItensCarreto(v),
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  void _alternarSelecaoAgrupar(int vendaId) {
    setState(() {
      if (_idsSelecionadas.contains(vendaId)) {
        _idsSelecionadas.remove(vendaId);
      } else {
        _idsSelecionadas.add(vendaId);
      }
    });
  }

  Future<void> _confirmarAgrupamentoMontagem() async {
    await widget.callbacks.confirmarAgrupamento(
      Set<int>.from(_idsSelecionadas),
    );
    if (!mounted) return;
    setState(() {
      _idsSelecionadas.clear();
      _modoAgrupar = false;
    });
  }

  void _avisarMotoristaIndefinido() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Defina o motorista nos pedidos antes de usar mapa/impressao '
          'por motorista.',
        ),
      ),
    );
  }

  Set<int> _idsEntregasSemMotorista() => widget.entregas
      .where((v) => !motoristaLogisticaDefinido(nomeMotoristaEntrega(v)))
      .map((v) => v.id)
      .toSet();

  Future<void> _definirMotoristaEmLoteSemMotorista() async {
    final ids = _idsEntregasSemMotorista();
    if (ids.isEmpty) return;
    await widget.callbacks.definirMotoristaEmLote(ids);
  }

  Future<void> _abrirMapaRota(List<Venda> paradas) async {
    final ok = await abrirMapaRotaParadas(paradas);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir o mapa da rota.'),
        ),
      );
    }
  }

  List<Venda> _paradasMotoristaNoDia(String motorista) {
    return ordenarParadasMotoristaDia(
      filtrarVendasMotorista(widget.entregas, motorista),
    );
  }

  MontagemEntregaViagem? get _viagemAtual {
    final mot = _motoristaSelecionado;
    if (mot == null) return null;
    final lista = montagemViagensDoMotorista(widget.entregas, mot);
    if (lista.isEmpty) return null;
    return lista.firstWhere(
      (v) => v.chave == _viagemChaveSelecionada,
      orElse: () => lista.first,
    );
  }

  void _aplicarChecklistViagem(
    List<Venda> vendas, {
    bool? separado,
    bool? carregado,
    bool? saiu,
  }) {
    for (final v in vendas) {
      widget.callbacks.atualizarChecklist(
        v,
        separado: separado,
        carregado: carregado,
        saiu: saiu,
      );
    }
    widget.callbacks.recarregar();
  }

  Future<void> _statusViagem(String status) async {
    final v = _viagemAtual;
    if (v == null) return;
    for (final venda in v.vendas) {
      final ok = await widget.callbacks.atualizarStatus(
        venda,
        status,
        mostrarSnackSucesso: false,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status atualizado na viagem.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motoristas = montagemMotoristasDasEntregas(widget.entregas);

    if (widget.entregas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma entrega para o dia/filtros atuais.\n'
            'Ajuste o planejamento ou os filtros acima.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (motoristas.isEmpty) {
      return const Center(child: Text('Nenhuma entrega listada.'));
    }

    final viagens = montagemViagensDoMotorista(
      widget.entregas,
      _motoristaSelecionado!,
    );
    final viagem = _viagemAtual;
    final linhasCarga = viagem == null
        ? const <RomaneioCargaConsolidadaLinha>[]
        : romaneioMergeCargaGrupo(
            viagem.vendas,
            widget.quantidadeItemEntrega,
          );
    final paradasMotorista = motoristaLogisticaDefinido(_motoristaSelecionado!)
        ? _paradasMotoristaNoDia(_motoristaSelecionado!)
        : const <Venda>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final estreito = constraints.maxWidth < 900;
        final colViagens = estreito
            ? const BoxConstraints()
            : const BoxConstraints(maxWidth: 300, minWidth: 260);

        final seletorMotorista = _faixaMotoristas(motoristas);
        final alertaSemMotorista = _faixaAlertaSemMotorista();
        final barraAcoes = _barraAcoesMontagem(
          motorista: _motoristaSelecionado!,
          viagens: viagens,
          viagem: viagem,
          paradasMotorista: paradasMotorista,
        );
        final listaViagens = _listaViagens(viagens);
        final seletorViagensCompacto = _seletorViagensHorizontal(viagens);
        final painelPrincipal = _modoAgrupar
            ? _painelAgruparViagens(_motoristaSelecionado!)
            : viagem == null
                ? const Center(child: Text('Selecione uma viagem.'))
                : _painelViagem(viagem, linhasCarga);

        if (estreito) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              seletorMotorista,
              alertaSemMotorista,
              barraAcoes,
              if (_modoAgrupar) ...[
                EntregasBarraAgrupamentoMesmoCarro(
                  selecionadas: _idsSelecionadas.length,
                  onConfirmar: _idsSelecionadas.length >= 2
                      ? _confirmarAgrupamentoMontagem
                      : null,
                  onLimparSelecao: () => setState(_idsSelecionadas.clear),
                  onRemoverAgrupamento: () =>
                      widget.callbacks.removerAgrupamento(
                        Set<int>.from(_idsSelecionadas),
                      ),
                ),
                const SizedBox(height: 6),
              ],
              if (!_modoAgrupar && viagens.isNotEmpty) ...[
                const SizedBox(height: 6),
                seletorViagensCompacto,
                const SizedBox(height: 6),
              ],
              Expanded(child: painelPrincipal),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            seletorMotorista,
            alertaSemMotorista,
            barraAcoes,
            if (_modoAgrupar) ...[
              EntregasBarraAgrupamentoMesmoCarro(
                selecionadas: _idsSelecionadas.length,
                onConfirmar: _idsSelecionadas.length >= 2
                    ? _confirmarAgrupamentoMontagem
                    : null,
                onLimparSelecao: () => setState(_idsSelecionadas.clear),
                onRemoverAgrupamento: () => widget.callbacks.removerAgrupamento(
                  Set<int>.from(_idsSelecionadas),
                ),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 6),
            Expanded(
              child: _modoAgrupar
                  ? painelPrincipal
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: colViagens,
                          child: listaViagens,
                        ),
                        VerticalDivider(
                          width: 1,
                          color: scheme.outlineVariant,
                        ),
                        Expanded(child: painelPrincipal),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _faixaAlertaSemMotorista() {
    final qtd = contarEntregasSemMotorista(widget.entregas);
    if (qtd == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
              Text(
                '$qtd entrega(s) sem motorista neste dia.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onErrorContainer,
                ),
              ),
              if (widget.podeGerenciarStatus)
                FilledButton.tonal(
                  onPressed: _definirMotoristaEmLoteSemMotorista,
                  child: Text('Definir motorista ($qtd)'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faixaMotoristas(List<String> motoristas) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Motorista / caminhao',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final m in motoristas) ...[
                    FilterChip(
                      label: Text(m),
                      selected: _motoristaSelecionado == m,
                      onSelected: (_) {
                        setState(() {
                          _motoristaSelecionado = m;
                          final v = montagemViagensDoMotorista(
                            widget.entregas,
                            m,
                          );
                          _viagemChaveSelecionada =
                              v.isEmpty ? null : v.first.chave;
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraAcoesMontagem({
    required String motorista,
    required List<MontagemEntregaViagem> viagens,
    required MontagemEntregaViagem? viagem,
    required List<Venda> paradasMotorista,
  }) {
    final motIndef = !motoristaLogisticaDefinido(motorista);
    final podeRotaDia =
        widget.podeGerenciarStatus && paradasMotorista.length >= 2;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.podeGerenciarStatus)
            FilledButton.tonalIcon(
              onPressed: () => setState(() {
                _modoAgrupar = !_modoAgrupar;
                if (!_modoAgrupar) _idsSelecionadas.clear();
              }),
              icon: Icon(
                _modoAgrupar
                    ? Icons.close
                    : Icons.merge_type_outlined,
                size: 18,
              ),
              label: Text(
                _modoAgrupar ? 'Cancelar agrupar' : 'Agrupar viagens',
              ),
            ),
          if (podeRotaDia)
            OutlinedButton.icon(
              onPressed: () => _abrirRotaMotoristaDia(motorista, paradasMotorista),
              icon: const Icon(Icons.format_list_numbered_rounded, size: 18),
              label: Text('Rota do dia (${paradasMotorista.length})'),
            ),
          OutlinedButton.icon(
            onPressed: viagem == null
                ? null
                : () => _abrirMapaRota(viagem.vendasOrdenadas),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Mapa — viagem'),
          ),
          OutlinedButton.icon(
            onPressed: motIndef
                ? () => _avisarMotoristaIndefinido()
                : paradasMotorista.isEmpty
                    ? null
                    : () => _abrirMapaRota(paradasMotorista),
            icon: const Icon(Icons.alt_route, size: 18),
            label: const Text('Mapa — motorista'),
          ),
          OutlinedButton.icon(
            onPressed: motIndef
                ? () => _avisarMotoristaIndefinido()
                : () => showMontagemImpressaoLoteSheet(
                      context: context,
                      callbacks: widget.callbacks,
                      motorista: motorista,
                      viagens: viagens,
                      viagemAtual: viagem,
                    ),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Impressao em lote'),
          ),
        ],
      ),
    );
  }

  Widget _seletorViagensHorizontal(List<MontagemEntregaViagem> viagens) {
    if (viagens.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Viagens (${viagens.length})',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: viagens.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final v = viagens[i];
                  final sel = v.chave == _viagemChaveSelecionada;
                  final prog = montagemProgressoCargaViagem(v.vendas);
                  return ChoiceChip(
                    label: Text(
                      '${i + 1}. ${v.vendas.length} parada(s) · $prog/3',
                    ),
                    selected: sel,
                    onSelected: (_) => setState(
                      () => _viagemChaveSelecionada = v.chave,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirRotaMotoristaDia(
    String motorista,
    List<Venda> paradas,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final altura = MediaQuery.sizeOf(ctx).height * 0.72;
        return SafeArea(
          child: SizedBox(
            height: altura,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Rota do motorista no dia',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Ordene as ${paradas.length} paradas de $motorista. '
                    'Mapa e romaneio seguem esta sequencia.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _conteudoRotaMotoristaDia(motorista, paradas),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _painelAgruparViagens(String motorista) {
    final lista = _entregasAgrupaveisMotorista(motorista);
    if (lista.isEmpty) {
      return const Center(
        child: Text(
          'Nenhuma entrega de carreto finalizada para este motorista no dia.',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: lista.length,
      itemBuilder: (context, i) {
        final v = lista[i];
        final cliente = v.cliente.target?.nomeRazao ?? 'Cliente';
        final grupo = v.grupoEntregaFreteId;
        final subtituloGrupo = grupo > 0
            ? 'Ja no grupo $grupo'
            : 'Avulso — selecione para agrupar';
        return CheckboxListTile(
          value: _idsSelecionadas.contains(v.id),
          onChanged: (_) => _alternarSelecaoAgrupar(v.id),
          title: Text(
            'Pedido ${v.numeroOrcamento} · $cliente',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '$subtituloGrupo · ${v.enderecoEntrega}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _listaViagens(List<MontagemEntregaViagem> viagens) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              'Viagens (${viagens.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: viagens.isEmpty
                ? const Center(child: Text('Sem viagens'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: viagens.length,
                    itemBuilder: (context, i) {
                      final v = viagens[i];
                      final sel = v.chave == _viagemChaveSelecionada;
                      final prog = montagemProgressoCargaViagem(v.vendas);
                      return ListTile(
                        dense: true,
                        selected: sel,
                        title: Text(
                          v.rotulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${v.vendas.length} parada(s) · Carga $prog/3',
                        ),
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${i + 1}'),
                        ),
                        onTap: () =>
                            setState(() => _viagemChaveSelecionada = v.chave),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalhoViagem(
    MontagemEntregaViagem viagem,
    List<Venda> ordenadas,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final prog = montagemProgressoCargaViagem(ordenadas);
    final checklistOk = montagemChecklistViagemCompleto(ordenadas);

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              viagem.rotulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              '${ordenadas.length} parada(s) · Motorista: ${viagem.motorista}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('Separado'),
                  selected: ordenadas.every((v) => v.cargaSeparada),
                  onSelected: widget.podeGerenciarStatus
                      ? (v) => _aplicarChecklistViagem(ordenadas, separado: v)
                      : null,
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('Carregado'),
                  selected: ordenadas.every((v) => v.cargaCarregada),
                  onSelected: widget.podeGerenciarStatus
                      ? (v) => _aplicarChecklistViagem(ordenadas, carregado: v)
                      : null,
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('Saiu'),
                  selected: ordenadas.every((v) => v.cargaSaiu),
                  onSelected: widget.podeGerenciarStatus
                      ? (v) => _aplicarChecklistViagem(ordenadas, saiu: v)
                      : null,
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(
                    checklistOk ? Icons.check_circle : Icons.timelapse,
                    size: 18,
                    color: checklistOk ? Colors.green.shade700 : scheme.outline,
                  ),
                  label: Text('Carga $prog/3'),
                ),
                if (widget.podeGerenciarStatus) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _statusViagem('roteirizada'),
                    child: const Text('Roteirizar'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: checklistOk
                        ? () => _statusViagem('saiu_entrega')
                        : null,
                    child: const Text('Saiu p/ entrega'),
                  ),
                ],
              ],
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  'Mais acoes',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => widget.callbacks.emitirRelatorio(
                          tipo: RelatorioEntregaTipo.separacaoViagem,
                          viagem: ordenadas,
                          salvarPdf: false,
                        ),
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('Separacao (PDF)'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: motoristaLogisticaDefinido(viagem.motorista)
                            ? () => widget.callbacks.emitirRelatorio(
                                  tipo: RelatorioEntregaTipo.romaneioMotoristaDia,
                                  motorista: viagem.motorista,
                                  viagem: ordenadas,
                                  salvarPdf: false,
                                )
                            : _avisarMotoristaIndefinido,
                        icon: const Icon(Icons.assignment_outlined, size: 18),
                        label: const Text('Romaneio'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _abrirMapaRota(ordenadas),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Mapa rota'),
                      ),
                      if (widget.podeGerenciarStatus)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            if (viagem.ehGrupo) {
                              widget.callbacks.editarMotoristaGrupo(
                                viagem.grupoId,
                                viagem.motorista,
                              );
                            } else {
                              widget.callbacks.editarMotoristaPedido(
                                ordenadas.first,
                              );
                            }
                          },
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text('Motorista'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoCargaConsolidada(
    MontagemEntregaViagem viagem,
    List<RomaneioCargaConsolidadaLinha> linhas, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(8, 8, 8, 4),
  }) {
    return Card(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              'Carga consolidada (patio)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Marque ao separar. Quantidades somadas de todos os pedidos desta viagem.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ConferenciaCargaConsolidadaLista(
                linhas: linhas,
                escopoViagem: viagem.chave,
                conferenciaRepository: widget.conferenciaRepository,
                usuarioAtual: widget.usuarioAtual,
                vendasGrupo: viagem.vendas,
                quantidadeEntrega: widget.quantidadeItemEntrega,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seletorSecaoViagem(MontagemEntregaViagem viagem, List<Venda> ordenadas) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: SegmentedButton<_PainelViagemSecao>(
        segments: [
          const ButtonSegment(
            value: _PainelViagemSecao.carga,
            icon: Icon(Icons.inventory_2_outlined, size: 18),
            label: Text('Carga'),
          ),
          ButtonSegment(
            value: _PainelViagemSecao.rota,
            icon: const Icon(Icons.route_outlined, size: 18),
            label: Text('Rota (${ordenadas.length})'),
          ),
        ],
        selected: {_secaoViagem},
        onSelectionChanged: (s) => setState(() => _secaoViagem = s.first),
      ),
    );
  }

  Widget _conteudoRotaMotoristaDia(String motorista, List<Venda> paradas) {
    final dataFmt = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      itemCount: paradas.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 48),
      itemBuilder: (context, i) {
        final v = paradas[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.podeGerenciarStatus)
                Column(
                  children: [
                    IconButton(
                      tooltip: 'Subir',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 28,
                      ),
                      onPressed: i == 0
                          ? null
                          : () => widget.callbacks.trocarParadaMotorista(
                                motorista,
                                paradas,
                                i,
                                i - 1,
                              ),
                      icon: const Icon(Icons.arrow_upward, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Descer',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 28,
                      ),
                      onPressed: i == paradas.length - 1
                          ? null
                          : () => widget.callbacks.trocarParadaMotorista(
                                motorista,
                                paradas,
                                i,
                                i + 1,
                              ),
                      icon: const Icon(Icons.arrow_downward, size: 20),
                    ),
                  ],
                ),
              CircleAvatar(
                radius: 14,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido ${v.numeroOrcamento} · '
                      '${v.cliente.target?.nomeRazao ?? 'Cliente'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      v.enderecoEntrega,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      v.dataEntregaMarcada == null
                          ? 'Sem data marcada'
                          : 'Entrega: ${dataFmt.format(v.dataEntregaMarcada!.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _secaoRotaParadas(
    MontagemEntregaViagem viagem,
    List<Venda> ordenadas, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(8, 4, 8, 8),
  }) {
    return Card(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              'Rota — ordem das paradas',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: ordenadas.length,
              itemBuilder: (context, i) => _tileParadaRota(viagem, ordenadas, i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileParadaRota(
    MontagemEntregaViagem viagem,
    List<Venda> ordenadas,
    int i,
  ) {
    final v = ordenadas[i];
    final dataFmt = DateFormat('dd/MM/yyyy');
    final marcada = v.dataEntregaMarcada;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (viagem.ehGrupo) ...[
              Column(
                children: [
                  IconButton(
                    tooltip: 'Subir',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 28,
                    ),
                    onPressed: i == 0
                        ? null
                        : () => widget.callbacks.trocarParada(
                              viagem.grupoId,
                              ordenadas,
                              i,
                              i - 1,
                            ),
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Descer',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 28,
                    ),
                    onPressed: i == ordenadas.length - 1
                        ? null
                        : () => widget.callbacks.trocarParada(
                              viagem.grupoId,
                              ordenadas,
                              i,
                              i + 1,
                            ),
                    icon: const Icon(Icons.arrow_downward, size: 20),
                  ),
                ],
              ),
            ],
            CircleAvatar(
              radius: 16,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pedido ${v.numeroOrcamento} · '
                    '${v.cliente.target?.nomeRazao ?? 'Cliente'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    v.enderecoEntrega,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    marcada == null
                        ? 'Sem data marcada'
                        : 'Entrega: ${dataFmt.format(marcada.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Itens',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => widget.callbacks.abrirDetalheItens(v),
                ),
                IconButton(
                  tooltip: 'Navegar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.directions_rounded),
                  onPressed: () => widget.callbacks.abrirNavegacao(v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _painelViagem(
    MontagemEntregaViagem viagem,
    List<RomaneioCargaConsolidadaLinha> linhas,
  ) {
    final ordenadas = viagem.vendasOrdenadas;
    final cabecalho = _cabecalhoViagem(viagem, ordenadas);
    final seletor = _seletorSecaoViagem(viagem, ordenadas);
    final corpo = _secaoViagem == _PainelViagemSecao.carga
        ? _secaoCargaConsolidada(
            viagem,
            linhas,
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          )
        : _secaoRotaParadas(
            viagem,
            ordenadas,
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cabecalho,
        seletor,
        Expanded(child: corpo),
      ],
    );
  }
}
