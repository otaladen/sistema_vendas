import 'package:flutter/material.dart';

import '../../data/conferencia_carga_repository.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import 'romaneio_carga_consolidada.dart';

/// Lista de conferencia de carga consolidada (persistida por [escopoViagem], sync LAN).
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
  });

  final List<RomaneioCargaConsolidadaLinha> linhas;
  final String escopoViagem;
  final ConferenciaCargaRepository conferenciaRepository;
  final String usuarioAtual;
  final List<Venda>? vendasGrupo;
  final int Function(Venda venda, ItemVenda item)? quantidadeEntrega;
  final String mensagemVazia;

  @override
  State<ConferenciaCargaConsolidadaLista> createState() =>
      _ConferenciaCargaConsolidadaListaState();
}

class _ConferenciaCargaConsolidadaListaState
    extends State<ConferenciaCargaConsolidadaLista> {
  final Map<String, bool> _conferencia = {};

  @override
  void initState() {
    super.initState();
    _recarregarDoBanco();
    SyncRefreshHub.instance.addListener(_aoAtualizarRede);
  }

  @override
  void dispose() {
    SyncRefreshHub.instance.removeListener(_aoAtualizarRede);
    super.dispose();
  }

  void _aoAtualizarRede() {
    if (!mounted) return;
    _recarregarDoBanco();
  }

  @override
  void didUpdateWidget(ConferenciaCargaConsolidadaLista oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.escopoViagem != widget.escopoViagem ||
        oldWidget.linhas != widget.linhas) {
      _recarregarDoBanco();
    }
  }

  void _recarregarDoBanco() {
    setState(() {
      _conferencia
        ..clear()
        ..addAll(
          widget.conferenciaRepository.mapaPorEscopo(widget.escopoViagem),
        );
    });
  }

  void _marcar(String chave, bool? marcado) {
    final valor = marcado ?? false;
    setState(() => _conferencia[chave] = valor);
    widget.conferenciaRepository.salvarConferencia(
      escopoViagem: widget.escopoViagem,
      chaveProduto: chave,
      conferido: valor,
      usuarioLogin: widget.usuarioAtual,
    );
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
    final conferidos = widget.conferenciaRepository.contarConferidos(
      widget.escopoViagem,
      widget.linhas.map((l) => l.chaveMerge),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$conferidos/${widget.linhas.length} conferidos (gravado · sincroniza na rede). '
          'Obrigatorio antes de marcar "Saiu".',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        ...widget.linhas.map(
          (l) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _conferencia[l.chaveMerge] ?? false,
            onChanged: (v) => _marcar(l.chaveMerge, v),
            title: Text(
              l.nomeProduto,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'SKU ${l.codigoSku} · ${l.unidade} · Qtd total: ${l.quantidadeTotal}',
            ),
          ),
        ),
      ],
    );
  }
}
