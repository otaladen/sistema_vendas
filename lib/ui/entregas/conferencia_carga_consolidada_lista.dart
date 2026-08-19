import 'package:flutter/material.dart';

import '../../data/api/lan_api_event_hub.dart';
import '../../domain/entregas/buscar_na_loja.dart';
import '../../domain/entregas/romaneio_carga_merge.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../widgets/lan_api_feedback.dart';
import 'romaneio_carga_consolidada.dart';

/// Lista da carga da viagem: itens + alerta para separar nesta loja.
class ConferenciaCargaConsolidadaLista extends StatefulWidget {
  const ConferenciaCargaConsolidadaLista({
    super.key,
    required this.linhas,
    required this.escopoViagem,
    required this.conferenciaRepository,
    required this.usuarioAtual,
    this.vendasGrupo,
    this.quantidadeEntrega,
    this.mensagemVazia = 'Nenhum item com quantidade para separar.',
    this.expandir = false,
    this.podeConfirmarBuscarNaLoja = false,
    this.onConfirmarBuscarNaLoja,
  });

  final List<RomaneioCargaConsolidadaLinha> linhas;
  final String escopoViagem;
  final dynamic conferenciaRepository;
  final String usuarioAtual;
  final List<Venda>? vendasGrupo;
  final int Function(Venda venda, ItemVenda item)? quantidadeEntrega;
  final String mensagemVazia;
  final bool expandir;
  final bool podeConfirmarBuscarNaLoja;

  /// Patio confirma itens solicitados pelo motorista (vendaId → itemIds).
  final Future<void> Function(int vendaId, List<int> itemIds)?
      onConfirmarBuscarNaLoja;

  @override
  State<ConferenciaCargaConsolidadaLista> createState() =>
      _ConferenciaCargaConsolidadaListaState();
}

class _ConferenciaCargaConsolidadaListaState
    extends State<ConferenciaCargaConsolidadaLista> {
  @override
  void initState() {
    super.initState();
    LanApiEventHub.instance.addListener(_aoAtualizarRede);
  }

  @override
  void dispose() {
    LanApiEventHub.instance.removeListener(_aoAtualizarRede);
    super.dispose();
  }

  void _aoAtualizarRede() {
    if (!mounted) return;
    final ent = LanApiEventHub.instance.ultimaEntidade;
    if (ent != 'entrega' && ent != 'venda') return;
    setState(() {});
  }

  Widget _conteudoVazio(BuildContext context) {
    final vendas = widget.vendasGrupo;
    final qtdFn = widget.quantidadeEntrega;
    if (vendas != null && qtdFn != null && vendas.isNotEmpty) {
      final msg = explicarCargaConsolidadaSemItens(vendas, qtdFn);
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    msg.titulo,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final p in msg.paragrafos)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(p, style: Theme.of(context).textTheme.bodyMedium),
              ),
            if (msg.dicas.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final d in msg.dicas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $d',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ],
        ),
      );
    }
    return Text(widget.mensagemVazia);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.linhas.isEmpty) {
      return _conteudoVazio(context);
    }
    return Column(
      key: ValueKey(widget.escopoViagem),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expandir)
          Expanded(
            child: ListView.builder(
              itemCount: widget.linhas.length,
              itemBuilder: (context, i) => _tileItem(widget.linhas[i]),
            ),
          )
        else
          ...widget.linhas.map(_tileItem),
      ],
    );
  }

  Map<int, List<int>> _pendentesBuscarDaLinha(RomaneioCargaConsolidadaLinha l) {
    final porVenda = <int, List<int>>{};
    for (final v in widget.vendasGrupo ?? const <Venda>[]) {
      for (final item in RomaneioCargaMerge.itensDaVendaSafe(v)) {
        if (item.id <= 0) continue;
        if (RomaneioCargaMerge.chaveMergeDeItem(item) != l.chaveMerge) {
          continue;
        }
        if (!BuscarNaLoja.ehSolicitado(item.buscarNaLojaStatus)) continue;
        porVenda.putIfAbsent(v.id, () => []).add(item.id);
      }
    }
    return porVenda;
  }

  String _textoPendenteBuscar(
    RomaneioCargaConsolidadaLinha l,
    Map<int, List<int>> pendentes,
  ) {
    final rotulo = _rotuloQtdPendente(l, pendentes);
    if (rotulo == null) {
      return 'Motorista: não tem na outra loja — separar aqui';
    }
    return 'Motorista: buscar $rotulo nesta loja';
  }

  String _rotuloBotaoSeparar(
    RomaneioCargaConsolidadaLinha l,
    Map<int, List<int>> pendentes,
  ) {
    final rotulo = _rotuloQtdPendente(l, pendentes);
    if (rotulo == null || rotulo.endsWith('x')) return 'Separar aqui';
    return 'Separar $rotulo aqui';
  }

  String? _rotuloQtdPendente(
    RomaneioCargaConsolidadaLinha l,
    Map<int, List<int>> pendentes,
  ) {
    ItemVenda? unico;
    Venda? vendaDoItem;
    var n = 0;
    for (final v in widget.vendasGrupo ?? const <Venda>[]) {
      final ids = pendentes[v.id];
      if (ids == null || ids.isEmpty) continue;
      for (final item in RomaneioCargaMerge.itensDaVendaSafe(v)) {
        if (!ids.contains(item.id)) continue;
        if (RomaneioCargaMerge.chaveMergeDeItem(item) != l.chaveMerge) {
          continue;
        }
        n++;
        unico = item;
        vendaDoItem = v;
      }
    }
    if (n != 1 || unico == null || vendaDoItem == null) return null;
    return BuscarNaLoja.rotuloQuantidade(vendaDoItem, unico);
  }

  bool _linhaSeparadaNestaLoja(RomaneioCargaConsolidadaLinha l) {
    var algum = false;
    for (final v in widget.vendasGrupo ?? const <Venda>[]) {
      for (final item in RomaneioCargaMerge.itensDaVendaSafe(v)) {
        if (RomaneioCargaMerge.chaveMergeDeItem(item) != l.chaveMerge) {
          continue;
        }
        if (BuscarNaLoja.ehSeparado(item.buscarNaLojaStatus)) algum = true;
        if (BuscarNaLoja.ehSolicitado(item.buscarNaLojaStatus)) return false;
      }
    }
    return algum;
  }

  Future<void> _confirmarBuscarLinha(RomaneioCargaConsolidadaLinha l) async {
    final cb = widget.onConfirmarBuscarNaLoja;
    if (cb == null) return;
    final mapa = _pendentesBuscarDaLinha(l);
    if (mapa.isEmpty) return;
    try {
      for (final e in mapa.entries) {
        await cb(e.key, e.value);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Falha ao separar nesta loja',
      );
    }
  }

  Widget _tileItem(RomaneioCargaConsolidadaLinha l) {
    final pendentes = _pendentesBuscarDaLinha(l);
    final temPendente = pendentes.isNotEmpty;
    final separadoAqui = !temPendente && _linhaSeparadaNestaLoja(l);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.nomeProduto,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'SKU ${l.codigoSku} · ${l.unidade} · Qtd total: ${l.quantidadeTotal}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (temPendente)
                  Text(
                    _textoPendenteBuscar(l, pendentes),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                if (separadoAqui)
                  Text(
                    'Separado nesta loja',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
              ],
            ),
          ),
          if (temPendente &&
              widget.podeConfirmarBuscarNaLoja &&
              widget.onConfirmarBuscarNaLoja != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _confirmarBuscarLinha(l),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.orange.shade800,
              ),
              child: Text(_rotuloBotaoSeparar(l, pendentes)),
            ),
          ],
        ],
      ),
    );
  }
}
