import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/produto_repository.dart';
import '../../domain/estoque/movimento_estoque_helper.dart';
import '../../model/movimento_estoque.dart';

/// Lista kardex de movimentacoes de estoque de um produto.
class ExtratoMovimentoEstoquePanel extends StatefulWidget {
  const ExtratoMovimentoEstoquePanel({
    super.key,
    required this.produtoRepository,
    required this.produtoId,
  });

  final ProdutoRepository produtoRepository;
  final int? produtoId;

  @override
  State<ExtratoMovimentoEstoquePanel> createState() =>
      _ExtratoMovimentoEstoquePanelState();
}

class _ExtratoMovimentoEstoquePanelState
    extends State<ExtratoMovimentoEstoquePanel> {
  static final _dataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  List<MovimentoEstoque> _lista = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  @override
  void didUpdateWidget(covariant ExtratoMovimentoEstoquePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produtoId != widget.produtoId) _recarregar();
  }

  void _recarregar() {
    final id = widget.produtoId;
    if (id == null || id <= 0) {
      setState(() {
        _lista = const [];
        _carregando = false;
      });
      return;
    }
    setState(() => _carregando = true);
    final itens = widget.produtoRepository.listarMovimentosEstoquePorProduto(id);
    setState(() {
      _lista = itens;
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.produtoId == null || widget.produtoId! <= 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Salve o produto para ver o extrato de movimentacoes.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhuma movimentacao registrada ainda.\n'
            'Novos lancamentos passam a aparecer aqui automaticamente.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _recarregar(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _lista.length,
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final m = _lista[i];
          final tipo = MovimentoEstoqueHelper.rotuloTipo(m.tipoMovimento);
          final deltaFis = m.deltaFisico;
          final deltaRes = m.deltaReserva;
          final corDelta = deltaFis > 0 || deltaRes > 0
              ? Colors.green.shade700
              : deltaFis < 0 || deltaRes < 0
                  ? Colors.red.shade700
                  : Theme.of(context).colorScheme.outline;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(tipo, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dataHora.format(m.registradoEm.toLocal())),
                if (m.documentoReferencia.isNotEmpty)
                  Text('Doc: ${m.documentoReferencia}'),
                if (m.motivo.isNotEmpty) Text('Motivo: ${m.motivo}'),
                if (m.usuarioLogin.isNotEmpty) Text('Usuario: ${m.usuarioLogin}'),
                Text(
                  'Fisico: ${m.saldoFisicoAntes} → ${m.saldoFisicoDepois} · '
                  'Res: ${m.saldoReservaAntes} → ${m.saldoReservaDepois}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (deltaFis != 0)
                  Text(
                    'Fis ${MovimentoEstoqueHelper.formatarDelta(deltaFis)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: corDelta,
                    ),
                  ),
                if (deltaRes != 0)
                  Text(
                    'Res ${MovimentoEstoqueHelper.formatarDelta(deltaRes)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: corDelta,
                        ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
