import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entrega_venda_helper.dart';
import '../../domain/venda_relacao_safe.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../services/entrega_fluxo_service.dart';
import 'conferencia_carga_consolidada_lista.dart';
import 'entrega_insucesso_faixa.dart';
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
    this.obterProduto,
  });

  final List<Venda> entregas;
  final int Function(Venda venda, ItemVenda item) quantidadeItemEntrega;
  final EntregasMontagemCallbacks callbacks;
  final bool podeGerenciarStatus;
  final dynamic conferenciaRepository;
  final String usuarioAtual;
  final Produto? Function(int id)? obterProduto;

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

  Future<void> _forcarSaidaRomaneioViagem() async {
    final v = _viagemAtual;
    if (v == null) return;
    final paraLiberar = v.vendas
        .where(
          (venda) =>
              EntregaFluxoService.podeLiberarSaida(venda) || !venda.cargaSaiu,
        )
        .toList();
    if (paraLiberar.isEmpty) return;
    for (final venda in paraLiberar) {
      if (venda.cargaSaiu && venda.statusEntrega == 'saiu_entrega') continue;
      final ok = await widget.callbacks.forcarSaidaRomaneio(venda);
      if (!ok) return;
    }
    if (!mounted) return;
    await widget.callbacks.recarregar();
  }

  Future<void> _liberarSaidaViagem() async {
    final v = _viagemAtual;
    if (v == null) return;
    final paraLiberar = v.vendas
        .where(EntregaFluxoService.podeLiberarSaida)
        .toList();
    if (paraLiberar.isEmpty) return;
    var okAlgum = false;
    for (final venda in paraLiberar) {
      final ok = await widget.callbacks.liberarSaida(
        venda,
        mostrarSnackSucesso: false,
      );
      if (!ok) {
        if (!mounted) return;
        return;
      }
      okAlgum = true;
    }
    if (!mounted) return;
    if (okAlgum) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saida liberada para a viagem.')),
      );
    }
    await widget.callbacks.recarregar();
  }

  Future<void> _marcarEntregueViagem() async {
    final v = _viagemAtual;
    if (v == null) return;
    for (final venda in v.vendas) {
      if (!EntregaFluxoService.podeMarcarEntregue(venda)) continue;
      final ok = await widget.callbacks.atualizarStatus(
        venda,
        'entregue',
        mostrarSnackSucesso: false,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Viagem marcada como entregue.')),
    );
    await widget.callbacks.recarregar();
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

    final motoristaAtual = _motoristaSelecionado ?? motoristas.first;
    final viagens = montagemViagensDoMotorista(
      widget.entregas,
      motoristaAtual,
    );
    final viagem = _viagemAtual;
    final linhasCarga = viagem == null
        ? const <RomaneioCargaConsolidadaLinha>[]
        : romaneioMergeCargaGrupo(
            viagem.vendas,
            widget.quantidadeItemEntrega,
            obterProduto: widget.obterProduto,
          );
    final paradasMotorista = motoristaLogisticaDefinido(motoristaAtual)
        ? _paradasMotoristaNoDia(motoristaAtual)
        : const <Venda>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final estreito = constraints.maxWidth < 900;
        final colViagens = estreito
            ? const BoxConstraints()
            : const BoxConstraints(maxWidth: 196, minWidth: 156);

        final seletorMotorista = _faixaMotoristas(
          motoristas,
          viagens: viagens,
          viagem: viagem,
          paradasMotorista: paradasMotorista,
        );
        final alertaSemMotorista = _faixaAlertaSemMotorista();
        final listaViagens = _listaViagens(viagens);
        final seletorViagensCompacto = _seletorViagensHorizontal(viagens);
        final painelPrincipal = _modoAgrupar
            ? _painelAgruparViagens(motoristaAtual)
            : viagem == null
                ? const Center(child: Text('Selecione uma viagem.'))
                : _painelViagem(viagem, linhasCarga);

        final cabecalho = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            seletorMotorista,
            alertaSemMotorista,
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
              const SizedBox(height: 4),
            ],
            if (estreito && !_modoAgrupar && viagens.isNotEmpty)
              seletorViagensCompacto,
          ],
        );

        final detalhe = estreito || _modoAgrupar
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
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cabecalho,
            Expanded(child: detalhe),
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
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  Widget _faixaMotoristas(
    List<String> motoristas, {
    required List<MontagemEntregaViagem> viagens,
    required MontagemEntregaViagem? viagem,
    required List<Venda> paradasMotorista,
  }) {
    final motorista = _motoristaSelecionado ?? motoristas.first;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
        child: Row(
          children: [
            Text(
              'Motorista',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final m in motoristas) ...[
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(m, style: const TextStyle(fontSize: 12)),
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
                      const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
            _menuAcoesPatio(
              motorista: motorista,
              viagens: viagens,
              viagem: viagem,
              paradasMotorista: paradasMotorista,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuAcoesPatio({
    required String motorista,
    required List<MontagemEntregaViagem> viagens,
    required MontagemEntregaViagem? viagem,
    required List<Venda> paradasMotorista,
  }) {
    final motIndef = !motoristaLogisticaDefinido(motorista);
    final podeRotaDia =
        widget.podeGerenciarStatus && paradasMotorista.length >= 2;
    return PopupMenuButton<String>(
      tooltip: 'Acoes da carga',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (acao) {
        switch (acao) {
          case 'agrupar':
            setState(() {
              _modoAgrupar = !_modoAgrupar;
              if (!_modoAgrupar) _idsSelecionadas.clear();
            });
          case 'rota_dia':
            unawaited(_abrirRotaMotoristaDia(motorista, paradasMotorista));
          case 'mapa_viagem':
            if (viagem != null) unawaited(_abrirMapaRota(viagem.vendasOrdenadas));
          case 'mapa_motorista':
            if (motIndef) {
              _avisarMotoristaIndefinido();
            } else if (paradasMotorista.isNotEmpty) {
              unawaited(_abrirMapaRota(paradasMotorista));
            }
          case 'impressao':
            if (motIndef) {
              _avisarMotoristaIndefinido();
            } else {
              unawaited(
                showMontagemImpressaoLoteSheet(
                  context: context,
                  callbacks: widget.callbacks,
                  motorista: motorista,
                  viagens: viagens,
                  viagemAtual: viagem,
                ),
              );
            }
        }
      },
      itemBuilder: (context) => [
        if (widget.podeGerenciarStatus)
          PopupMenuItem(
            value: 'agrupar',
            child: Text(_modoAgrupar ? 'Cancelar agrupar' : 'Agrupar viagens'),
          ),
        if (podeRotaDia)
          PopupMenuItem(
            value: 'rota_dia',
            child: Text('Rota do dia (${paradasMotorista.length})'),
          ),
        PopupMenuItem(
          value: 'mapa_viagem',
          enabled: viagem != null,
          child: const Text('Mapa — viagem'),
        ),
        PopupMenuItem(
          value: 'mapa_motorista',
          enabled: !motIndef && paradasMotorista.isNotEmpty,
          child: const Text('Mapa — motorista'),
        ),
        PopupMenuItem(
          value: 'impressao',
          enabled: !motIndef,
          child: const Text('Impressao em lote'),
        ),
      ],
    );
  }

  Widget _seletorViagensHorizontal(List<MontagemEntregaViagem> viagens) {
    if (viagens.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
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
                    onSelected: (_) => setState(() {
                      _viagemChaveSelecionada = v.chave;
                    }),
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
        final cliente = VendaRelacaoSafe.nomeCliente(v, fallback: 'Cliente');
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
                        onTap: () => setState(() {
                          _viagemChaveSelecionada = v.chave;
                        }),
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
    final jaSaiu = ordenadas.every((v) => v.cargaSaiu) ||
        ordenadas.every((v) => v.statusEntrega == 'saiu_entrega');
    final podeLiberar = widget.podeGerenciarStatus &&
        ordenadas.any(EntregaFluxoService.podeLiberarSaida);
    final podeEntregar = widget.podeGerenciarStatus &&
        ordenadas.any(EntregaFluxoService.podeMarcarEntregue);

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viagem.rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    '${ordenadas.length} parada(s) · ${viagem.motorista}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          jaSaiu
                              ? Icons.local_shipping
                              : Icons.schedule_outlined,
                          size: 16,
                          color: jaSaiu ? Colors.green.shade700 : scheme.outline,
                        ),
                        label: Text(
                          jaSaiu ? 'Em rota' : 'Aguardando motorista',
                        ),
                      ),
                      if (podeEntregar)
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _marcarEntregueViagem,
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('Marcar entregue'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais acoes',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz),
              onSelected: (acao) {
                switch (acao) {
                  case 'separacao':
                    widget.callbacks.emitirRelatorio(
                      tipo: RelatorioEntregaTipo.separacaoViagem,
                      viagem: ordenadas,
                      salvarPdf: false,
                    );
                  case 'romaneio':
                    if (!motoristaLogisticaDefinido(viagem.motorista)) {
                      _avisarMotoristaIndefinido();
                    } else {
                      widget.callbacks.emitirRelatorio(
                        tipo: RelatorioEntregaTipo.romaneioMotoristaDia,
                        motorista: viagem.motorista,
                        viagem: ordenadas,
                        salvarPdf: false,
                      );
                    }
                  case 'mapa':
                    unawaited(_abrirMapaRota(ordenadas));
                  case 'liberar':
                    unawaited(_liberarSaidaViagem());
                  case 'forcar_saida':
                    unawaited(_forcarSaidaRomaneioViagem());
                  case 'motorista':
                    if (viagem.ehGrupo) {
                      widget.callbacks.editarMotoristaGrupo(
                        viagem.grupoId,
                        viagem.motorista,
                      );
                    } else {
                      widget.callbacks.editarMotoristaPedido(ordenadas.first);
                    }
                }
              },
              itemBuilder: (context) => [
                if (podeLiberar)
                  const PopupMenuItem(
                    value: 'liberar',
                    child: Text('Liberar saida (se o motorista nao fez)'),
                  ),
                if (widget.podeGerenciarStatus && !jaSaiu)
                  const PopupMenuItem(
                    value: 'forcar_saida',
                    child: Text('Forcar saida do romaneio'),
                  ),
                const PopupMenuItem(
                  value: 'separacao',
                  child: Text('Separacao (PDF)'),
                ),
                const PopupMenuItem(
                  value: 'romaneio',
                  child: Text('Romaneio'),
                ),
                const PopupMenuItem(
                  value: 'mapa',
                  child: Text('Mapa da rota'),
                ),
                if (widget.podeGerenciarStatus)
                  const PopupMenuItem(
                    value: 'motorista',
                    child: Text('Alterar motorista'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoCargaConsolidada(
    MontagemEntregaViagem viagem,
    List<RomaneioCargaConsolidadaLinha> linhas, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(8, 4, 8, 4),
  }) {
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Carga da viagem',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              'O motorista libera a saida no celular. Se pedir material desta loja, aparece Separar aqui.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ConferenciaCargaConsolidadaLista(
                linhas: linhas,
                escopoViagem: viagem.chave,
                conferenciaRepository: widget.conferenciaRepository,
                usuarioAtual: widget.usuarioAtual,
                vendasGrupo: viagem.vendas,
                quantidadeEntrega: widget.quantidadeItemEntrega,
                expandir: true,
                podeConfirmarBuscarNaLoja: widget.podeGerenciarStatus,
                onConfirmarBuscarNaLoja:
                    widget.callbacks.confirmarBuscarNaLoja,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seletorSecaoViagem(MontagemEntregaViagem viagem, List<Venda> ordenadas) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: SegmentedButton<_PainelViagemSecao>(
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          const ButtonSegment(
            value: _PainelViagemSecao.carga,
            icon: Icon(Icons.inventory_2_outlined, size: 16),
            label: Text('Carga'),
          ),
          ButtonSegment(
            value: _PainelViagemSecao.rota,
            icon: const Icon(Icons.route_outlined, size: 16),
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
                      '${VendaRelacaoSafe.nomeCliente(v, fallback: 'Cliente')}',
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              'Rota — ordem das paradas',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
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
                    '${VendaRelacaoSafe.nomeCliente(v, fallback: 'Cliente')}',
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
                  EntregaInsucessoFaixa(venda: v),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalhoViagem(viagem, ordenadas),
        _seletorSecaoViagem(viagem, ordenadas),
        Expanded(
          child: _secaoViagem == _PainelViagemSecao.carga
              ? _secaoCargaConsolidada(
                  viagem,
                  linhas,
                  margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                )
              : _secaoRotaParadas(
                  viagem,
                  ordenadas,
                  margin: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                ),
        ),
      ],
    );
  }
}
