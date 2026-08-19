import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/lan_api_client.dart';
import '../../data/api/produto_api_repository.dart';
import '../../data/lote_produto_repository.dart';
import '../../data/sync/sync_entity_codec_operacional.dart';
import '../../domain/lote_validade_config.dart';
import '../../model/lote_produto.dart';
import '../../model/produto.dart';
import '../theme/app_semantic_helper.dart';

/// Painel de monitoramento de lotes por semaforo de validade.
class EstoqueValidadePanel extends StatefulWidget {
  const EstoqueValidadePanel({
    super.key,
    required this.produtoRepository,
    this.lanApiClient,
  });

  final dynamic produtoRepository;
  final LanApiClient? lanApiClient;

  @override
  State<EstoqueValidadePanel> createState() => _EstoqueValidadePanelState();
}

class _EstoqueValidadePanelState extends State<EstoqueValidadePanel> {
  bool _carregando = true;
  String? _erro;
  List<_LoteValidadeVm> _lotes = const [];
  LoteValidadeSemaforo? _filtro;
  String _busca = '';
  final _buscaCtrl = TextEditingController();

  bool get _local => widget.produtoRepository is! ProdutoApiRepository;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      if (_local) {
        final repo = LoteProdutoRepository(widget.produtoRepository.objectBox);
        repo.desativarVencidos(notificar: false);
        final todos = repo.listarTodos();
        final vms = <_LoteValidadeVm>[];
        for (final l in todos) {
          if (!l.ativo && l.quantidadeEstoque <= 0) continue;
          final p = l.produto.target ??
              widget.produtoRepository.obterPorId(l.produtoId);
          if (p is! Produto) continue;
          if (!p.controlaLoteValidade) continue;
          vms.add(_LoteValidadeVm.fromLote(l, p));
        }
        vms.sort(_ordenar);
        if (!mounted) return;
        setState(() {
          _lotes = vms;
          _carregando = false;
        });
        return;
      }
      final client = widget.lanApiClient;
      if (client == null) {
        throw StateError('API indisponivel para listar lotes.');
      }
      final raw = await client.listarLotesEstoque();
      final vms = <_LoteValidadeVm>[];
      for (final m in raw) {
        final lote = SyncEntityCodecOperacional.loteProdutoDeMap(m);
        if (!lote.ativo && lote.quantidadeEstoque <= 0) continue;
        final pid = (m['produtoId'] as num?)?.toInt() ?? lote.produtoId;
        final p = widget.produtoRepository.obterPorId(pid);
        if (p is! Produto) continue;
        if (!p.controlaLoteValidade) continue;
        vms.add(_LoteValidadeVm.fromLote(lote, p));
      }
      vms.sort(_ordenar);
      if (!mounted) return;
      setState(() {
        _lotes = vms;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  int _ordenar(_LoteValidadeVm a, _LoteValidadeVm b) {
    final da = a.diasParaVencer ?? 99999;
    final db = b.diasParaVencer ?? 99999;
    final c = da.compareTo(db);
    if (c != 0) return c;
    return a.nomeProduto.toLowerCase().compareTo(b.nomeProduto.toLowerCase());
  }

  List<_LoteValidadeVm> get _filtrados {
    final q = _busca.trim().toLowerCase();
    return _lotes.where((l) {
      if (_filtro != null && l.semaforo != _filtro) return false;
      if (q.isEmpty) return true;
      return l.nomeProduto.toLowerCase().contains(q) ||
          l.numeroLote.toLowerCase().contains(q) ||
          l.sku.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _desativar(_LoteValidadeVm vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar lote'),
        content: Text(
          'Desativar lote ${vm.numeroLote} de ${vm.nomeProduto}?\n'
          'Ele deixa de entrar no FEFO e no disponivel do PDV.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (_local) {
        final repo = LoteProdutoRepository(widget.produtoRepository.objectBox);
        final lote = repo.obterPorId(vm.loteId);
        if (lote == null) return;
        lote.ativo = false;
        repo.gravar(lote);
      } else {
        final client = widget.lanApiClient;
        if (client == null) return;
        await client.desativarLoteEstoque(vm.loteId);
      }
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao desativar: $e')),
      );
    }
  }

  Color _corSemaforo(LoteValidadeSemaforo s, BuildContext context) {
    final sem = context.semanticColors;
    return switch (s) {
      LoteValidadeSemaforo.verde => Colors.green.shade700,
      LoteValidadeSemaforo.amarelo => Colors.amber.shade800,
      LoteValidadeSemaforo.laranja => Colors.orange.shade800,
      LoteValidadeSemaforo.vermelho => sem.errorFg,
      LoteValidadeSemaforo.semValidade =>
        Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtrados = _filtrados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscaCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Buscar produto, SKU ou lote',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _busca = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregando ? null : _carregar,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Todos'),
                selected: _filtro == null,
                onSelected: (_) => setState(() => _filtro = null),
              ),
              const SizedBox(width: 6),
              for (final s in LoteValidadeSemaforo.values) ...[
                FilterChip(
                  label: Text(LoteValidadeSemaforoUtil.rotulo(s)),
                  selected: _filtro == s,
                  selectedColor: _corSemaforo(s, context).withValues(alpha: 0.25),
                  onSelected: (_) => setState(() => _filtro = s),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_erro!, style: TextStyle(color: theme.colorScheme.error)),
          )
        else
          Expanded(
            child: filtrados.isEmpty
                ? Center(
                    child: Text(
                      _lotes.isEmpty
                          ? 'Nenhum lote com controle de validade.'
                          : 'Nenhum lote neste filtro.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: filtrados.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final vm = filtrados[i];
                      final cor = _corSemaforo(vm.semaforo, context);
                      final valTxt = vm.dataValidade == null
                          ? 'sem validade'
                          : DateFormat('dd/MM/yyyy')
                              .format(vm.dataValidade!.toLocal());
                      final dias = vm.diasParaVencer;
                      final diasTxt = dias == null
                          ? ''
                          : dias < 0
                              ? ' · vencido ha ${-dias}d'
                              : ' · ${dias}d';
                      return Material(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: cor.withValues(alpha: 0.55),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: cor.withValues(alpha: 0.15),
                            child: Icon(Icons.inventory_2_outlined, color: cor),
                          ),
                          title: Text(
                            vm.nomeProduto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'SKU ${vm.sku} · Lote ${vm.numeroLote}\n'
                            'Qtd ${vm.quantidade} · Validade $valTxt$diasTxt'
                            '${vm.ativo ? '' : ' · inativo'}',
                          ),
                          isThreeLine: true,
                          trailing: vm.ativo
                              ? IconButton(
                                  tooltip: 'Desativar lote',
                                  onPressed: () => _desativar(vm),
                                  icon: const Icon(Icons.block),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}

class _LoteValidadeVm {
  const _LoteValidadeVm({
    required this.loteId,
    required this.nomeProduto,
    required this.sku,
    required this.numeroLote,
    required this.quantidade,
    required this.dataValidade,
    required this.diasParaVencer,
    required this.semaforo,
    required this.ativo,
  });

  final int loteId;
  final String nomeProduto;
  final String sku;
  final String numeroLote;
  final int quantidade;
  final DateTime? dataValidade;
  final int? diasParaVencer;
  final LoteValidadeSemaforo semaforo;
  final bool ativo;

  factory _LoteValidadeVm.fromLote(LoteProduto l, Produto p) {
    final dias = l.diasParaVencer;
    return _LoteValidadeVm(
      loteId: l.id,
      nomeProduto: p.nome,
      sku: p.codigoInterno,
      numeroLote: l.numeroLote,
      quantidade: l.quantidadeEstoque,
      dataValidade: l.dataValidade,
      diasParaVencer: dias,
      semaforo: LoteValidadeSemaforoUtil.deDiasRestantes(dias),
      ativo: l.ativo,
    );
  }
}
