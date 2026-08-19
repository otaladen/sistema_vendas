import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/api/reajuste_preco_api_repository.dart';
import '../model/reajuste_preco.dart';
import '../model/usuario_sistema.dart';
import 'reajuste_preco_autorizacao.dart';
import 'widgets/lan_api_feedback.dart';

final _dataFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
final _moeda = NumberFormat('#,##0.00', 'pt_BR');

class ReajustePrecoHistoricoPage extends StatefulWidget {
  const ReajustePrecoHistoricoPage({
    super.key,
    required this.reajusteRepository,
    required this.usuarioRepository,
    required this.usuarioLogado,
  });

  final dynamic reajusteRepository;
  /// [UsuarioRepository] no PC1 ou [UsuarioApiRepository] no Terminal Leve.
  final dynamic usuarioRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<ReajustePrecoHistoricoPage> createState() =>
      _ReajustePrecoHistoricoPageState();
}

class _ReajustePrecoHistoricoPageState extends State<ReajustePrecoHistoricoPage> {
  List<ReajustePreco> _lista = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final repo = widget.reajusteRepository;
      if (repo is ReajustePrecoApiRepository) {
        await repo.hidratarHistorico();
      }
      if (!mounted) return;
      setState(() {
        _lista = List<ReajustePreco>.from(
          repo.listarHistorico() as List,
        );
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = LanApiFeedback.mensagem(e, fallback: '$e');
        _lista = const [];
      });
    }
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

    try {
      final repo = widget.reajusteRepository;
      if (repo is ReajustePrecoApiRepository) {
        await repo.hidratarItensDoReajuste(r.id);
      }
      final resultadoRaw = repo.estornar(
        reajusteId: r.id,
        usuario: widget.usuarioLogado,
      );
      final resultado =
          resultadoRaw is Future ? await resultadoRaw : resultadoRaw;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${resultado.produtosGravados} produto(s) com precos restaurados.',
          ),
        ),
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Estorno');
    }
  }

  Future<void> _verDetalhe(ReajustePreco r) async {
    final repo = widget.reajusteRepository;
    if (repo is ReajustePrecoApiRepository) {
      try {
        await repo.hidratarItensDoReajuste(r.id);
      } catch (e) {
        if (!mounted) return;
        LanApiFeedback.snackErro(context, e, prefixo: 'Detalhe');
        return;
      }
    }
    final itens = repo.listarItensDoReajuste(r.id) as List;
    if (!mounted) return;
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
                    Text(
                      'Motivo: ${r.motivo}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  Text(
                    _rotuloRegra(r),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: itens.isEmpty
                        ? const Center(child: Text('Sem itens neste reajuste.'))
                        : ListView.builder(
                            controller: scroll,
                            itemCount: itens.length,
                            itemBuilder: (_, i) {
                              final item = itens[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  item.nome as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'SKU ${item.codigoInterno} · '
                                  'P1 ${_moeda.format(item.preco1Antes)} → '
                                  '${_moeda.format(item.preco1Depois)}',
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
    final podeEstornar =
        usuarioPodeReajustePrecoLote(widget.usuarioLogado);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historico de reajustes'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _carregar,
                          child: const Text('Tentar de novo'),
                        ),
                      ],
                    ),
                  ),
                )
              : _lista.isEmpty
                  ? const Center(
                      child: Text('Nenhum reajuste registrado ainda.'),
                    )
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
                                decoration: estornado
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_dataFmt.format(r.criadoEm.toLocal())),
                                Text('${_rotuloRegra(r)} · ${r.usuarioLogin}'),
                                if (r.motivo.isNotEmpty) Text(r.motivo),
                                if (estornado && r.estornadoEm != null)
                                  Text(
                                    'Estornado em '
                                    '${_dataFmt.format(r.estornadoEm!.toLocal())} '
                                    'por ${r.estornadoPorLogin}',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
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
