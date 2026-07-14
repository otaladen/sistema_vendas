import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/objectbox.dart';
import '../../data/produto_repository.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../../domain/loja_ao_vivo_service.dart';
import '../../model/usuario_sistema.dart';

/// Acompanhamento diario das metas de vendedores (meta mensal / dias do mes).
class RelatorioMetasVendedoresPage extends StatefulWidget {
  const RelatorioMetasVendedoresPage({
    super.key,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.produtoRepository,
    required this.objectBox,
    required this.usuarioLogado,
  });

  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final ProdutoRepository produtoRepository;
  final ObjectBox objectBox;
  final UsuarioSistema usuarioLogado;

  @override
  State<RelatorioMetasVendedoresPage> createState() =>
      _RelatorioMetasVendedoresPageState();
}

class _RelatorioMetasVendedoresPageState
    extends State<RelatorioMetasVendedoresPage> {
  final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  List<MetaVendedorDiaria> _metas = const [];
  bool _carregando = true;
  DateTime? _atualizadoEm;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _carregar();
    _autoRefresh = Timer.periodic(const Duration(seconds: 60), (_) => _carregar());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() => _carregando = true);
    final svc = LojaAoVivoService(
      vendaRepository: widget.vendaRepository,
      produtoRepository: widget.produtoRepository,
      vendedorRepository: widget.vendedorRepository,
      objectBox: widget.objectBox,
    );
    final snap = await svc.carregar(usuario: widget.usuarioLogado);
    if (!mounted) return;
    setState(() {
      _metas = snap.metasVendedores
        ..sort((a, b) => b.percentual.compareTo(a.percentual));
      _atualizadoEm = snap.atualizadoEm;
      _carregando = false;
    });
  }

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas de vendedores — hoje'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Meta diaria = meta mensal do cadastro ÷ dias do mes. '
              'Realizado = vendas finalizadas hoje.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_atualizadoEm != null) ...[
              const SizedBox(height: 6),
              Text(
                'Atualizado: ${DateFormat('HH:mm:ss').format(_atualizadoEm!)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_carregando && _metas.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_metas.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'Nenhum vendedor com meta mensal cadastrada.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              )
            else
              ..._metas.map((m) => _metaCard(context, m)),
          ],
        ),
      ),
    );
  }

  Widget _metaCard(BuildContext context, MetaVendedorDiaria m) {
    final theme = Theme.of(context);
    final pct = (m.percentual * 100).clamp(0, 200);
    final atingiu = pct >= 100;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.nome,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Chip(
                  label: Text('${pct.toStringAsFixed(0)}%'),
                  backgroundColor: atingiu
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: m.percentual > 1 ? 1 : m.percentual,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _valorCol(
                    context,
                    rotulo: 'Realizado hoje',
                    valor: _fmt(m.realizadoHoje),
                    destaque: true,
                  ),
                ),
                Expanded(
                  child: _valorCol(
                    context,
                    rotulo: 'Meta do dia',
                    valor: _fmt(m.metaDiaria),
                  ),
                ),
                Expanded(
                  child: _valorCol(
                    context,
                    rotulo: 'Falta',
                    valor: _fmt(
                      (m.metaDiaria - m.realizadoHoje).clamp(0, double.infinity),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _valorCol(
    BuildContext context, {
    required String rotulo,
    required String valor,
    bool destaque = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          valor,
          style: (destaque
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium)
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
