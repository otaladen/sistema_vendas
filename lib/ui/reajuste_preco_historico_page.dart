import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/reajuste_preco_repository.dart';
import '../data/usuario_repository.dart';
import '../model/reajuste_preco.dart';
import '../model/usuario_sistema.dart';

final _dataFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
final _moeda = NumberFormat('#,##0.00', 'pt_BR');

class ReajustePrecoHistoricoPage extends StatefulWidget {
  const ReajustePrecoHistoricoPage({
    super.key,
    required this.reajusteRepository,
    required this.usuarioRepository,
    required this.usuarioLogado,
  });

  final ReajustePrecoRepository reajusteRepository;
  final UsuarioRepository usuarioRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<ReajustePrecoHistoricoPage> createState() =>
      _ReajustePrecoHistoricoPageState();
}

class _ReajustePrecoHistoricoPageState extends State<ReajustePrecoHistoricoPage> {
  List<ReajustePreco> _lista = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    setState(() {
      _lista = widget.reajusteRepository.listarHistorico();
    });
  }

  String _rotuloRegra(ReajustePreco r) {
    if (r.modo == 'margem') {
      return 'Margem ${r.margemPercentual.toStringAsFixed(1)}% · ${r.baseCusto}';
    }
    return '${r.percentualSobrePreco >= 0 ? '+' : ''}'
        '${r.percentualSobrePreco.toStringAsFixed(1)}% no preco';
  }

  Future<void> _estornar(ReajustePreco r) async {
    if (r.estornado) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar reajuste'),
        content: Text(
          'Restaurar precos de ${r.totalAlterados} produto(s) do reajuste '
          '#${r.id} (${_dataFmt.format(r.criadoEm.toLocal())})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final resultado = widget.reajusteRepository.estornar(
      reajusteId: r.id,
      usuario: widget.usuarioLogado,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${resultado.produtosGravados} produto(s) com precos restaurados.',
        ),
      ),
    );
    _carregar();
  }

  void _verDetalhe(ReajustePreco r) {
    final itens = widget.reajusteRepository.listarItensDoReajuste(r.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Reajuste #${r.id}',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  Text(
                    '${_dataFmt.format(r.criadoEm.toLocal())} · ${r.usuarioNome}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (r.motivo.isNotEmpty)
                    Text('Motivo: ${r.motivo}', style: Theme.of(ctx).textTheme.bodySmall),
                  Text(_rotuloRegra(r), style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: itens.length,
                      itemBuilder: (_, i) {
                        final item = itens[i];
                        return ListTile(
                          dense: true,
                          title: Text(item.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            'SKU ${item.codigoInterno} · '
                            'P1 ${_moeda.format(item.preco1Antes)} → ${_moeda.format(item.preco1Depois)}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeEstornar = widget.usuarioLogado.admin ||
        widget.usuarioLogado.podeReajustePrecoLote ||
        widget.usuarioLogado.podeCadastros;

    return Scaffold(
      appBar: AppBar(title: const Text('Historico de reajustes')),
      body: _lista.isEmpty
          ? const Center(child: Text('Nenhum reajuste registrado ainda.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _lista.length,
              separatorBuilder: (_, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final r = _lista[index];
                final estornado = r.estornado;
                return Card(
                  child: ListTile(
                    title: Text(
                      '#${r.id} · ${r.totalAlterados} produto(s)',
                      style: TextStyle(
                        decoration: estornado ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_dataFmt.format(r.criadoEm.toLocal())),
                        Text('${_rotuloRegra(r)} · ${r.usuarioLogin}'),
                        if (r.motivo.isNotEmpty) Text(r.motivo),
                        if (estornado)
                          Text(
                            'Estornado em ${_dataFmt.format(r.estornadoEm!.toLocal())} '
                            'por ${r.estornadoPorLogin}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: estornado
                        ? const Chip(label: Text('Estornado'))
                        : podeEstornar
                            ? IconButton(
                                tooltip: 'Estornar',
                                icon: const Icon(Icons.undo),
                                onPressed: () => _estornar(r),
                              )
                            : null,
                    onTap: () => _verDetalhe(r),
                  ),
                );
              },
            ),
    );
  }
}
