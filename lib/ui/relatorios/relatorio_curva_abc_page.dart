import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import 'relatorio_abc_util.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioCurvaAbcPage extends StatefulWidget {
  const RelatorioCurvaAbcPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.produtoRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioCurvaAbcPage> createState() => _RelatorioCurvaAbcPageState();
}

class _RelatorioCurvaAbcPageState extends State<RelatorioCurvaAbcPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  List<RelatorioAbcItem> _clientes = [];
  List<RelatorioAbcItem> _produtos = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Cliente? _cliente(Venda v) {
    final t = v.cliente.target;
    if (t != null) return t;
    final id = v.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  void _calcular(LimitesPeriodo limites) {
    final vendas = relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final mapCli = <int, ({String nome, double valor})>{};
    for (final v in vendas) {
      final id = v.cliente.targetId;
      final c = _cliente(v);
      final nome = id == 0
          ? 'Sem cliente'
          : (c?.nomeRazao.trim().isNotEmpty == true
              ? c!.nomeRazao.trim()
              : 'Cliente #$id');
      final cur = mapCli[id];
      if (cur == null) {
        mapCli[id] = (nome: nome, valor: v.total);
      } else {
        mapCli[id] = (nome: cur.nome, valor: cur.valor + v.total);
      }
    }
    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(relatorioPeriodoFiltro(limites));
    for (final e in imp.porClienteFaturamento.entries) {
      final id = e.key;
      if (e.value.abs() < 0.0001) continue;
      final cli = id == 0 ? null : widget.clienteRepository.obterPorId(id);
      final nome = id == 0
          ? 'Sem cliente'
          : (cli?.nomeRazao ?? 'Cliente #$id');
      final cur = mapCli[id];
      if (cur == null) {
        mapCli[id] = (nome: nome, valor: e.value);
      } else {
        mapCli[id] = (nome: cur.nome, valor: cur.valor + e.value);
      }
    }

    final mapProd = <String, ({String nome, double valor, int produtoId})>{};
    for (final v in vendas) {
      for (final item in v.itens) {
        final pid = item.produto.targetId;
        final chave = pid > 0 ? 'id:$pid' : 'nome:${item.nomeProduto}';
        final nome = pid > 0
            ? (widget.produtoRepository.obterPorId(pid)?.nome ?? item.nomeProduto)
            : item.nomeProduto;
        final cur = mapProd[chave];
        if (cur == null) {
          mapProd[chave] = (nome: nome, valor: item.subtotal, produtoId: pid);
        } else {
          mapProd[chave] = (
            nome: cur.nome,
            valor: cur.valor + item.subtotal,
            produtoId: pid,
          );
        }
      }
    }

    setState(() {
      _limites = limites;
      _clientes = relatorioClassificarAbc(
        itens: mapCli.entries
            .map(
              (e) => (
                chave: 'c:${e.key}',
                nome: e.value.nome,
                valor: e.value.valor,
                detalheExtra: '',
              ),
            )
            .toList(),
      );
      _produtos = relatorioClassificarAbc(
        itens: mapProd.entries
            .map(
              (e) => (
                chave: e.key,
                nome: e.value.nome,
                valor: e.value.valor,
                detalheExtra: 'id:${e.value.produtoId}',
              ),
            )
            .toList(),
      );
    });
  }

  List<RelatorioAbcItem> get _listaAtual =>
      _tabs.index == 0 ? _clientes : _produtos;

  List<List<String>> _linhasCsv() => [
        ['Classe', 'Nome', 'Valor', 'Part %', 'Acum %'],
        ..._listaAtual.map(
          (i) => [
            i.classe,
            i.nome,
            _moeda.format(i.valor),
            i.participacaoPct.toStringAsFixed(1),
            i.acumuladoPct.toStringAsFixed(1),
          ],
        ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    final titulo = _tabs.index == 0 ? 'ABC CLIENTES' : 'ABC PRODUTOS';
    return relatorioMontarPaginasTabela(
      titulo: titulo,
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['Classe', 'Nome', 'Valor', 'Part%', 'Acum%'],
      linhas: _listaAtual
          .map(
            (i) => [
              i.classe,
              i.nome,
              _fmt(i.valor),
              i.participacaoPct.toStringAsFixed(1),
              i.acumuladoPct.toStringAsFixed(1),
            ],
          )
          .toList(),
    );
  }

  Color _corClasse(String c) {
    switch (c) {
      case 'A':
        return Colors.green.shade700;
      case 'B':
        return Colors.orange.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _listaAbc(List<RelatorioAbcItem> itens, {required bool clientes}) {
    if (itens.isEmpty) {
      return const Center(child: Text('Sem movimento no periodo.'));
    }
    return ListView.builder(
      itemCount: itens.length,
      itemBuilder: (context, i) {
        final item = itens[i];
        final idCliente = clientes && item.chave.startsWith('c:')
            ? int.tryParse(item.chave.substring(2)) ?? 0
            : 0;
        final idProduto = !clientes && item.detalheExtra.startsWith('id:')
            ? int.tryParse(item.detalheExtra.substring(3)) ?? 0
            : 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _corClasse(item.classe).withValues(alpha: 0.15),
            child: Text(
              item.classe,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _corClasse(item.classe),
              ),
            ),
          ),
          title: Text(item.nome),
          subtitle: Text(
            '${_fmt(item.valor)} · ${item.participacaoPct.toStringAsFixed(1)}% · '
            'acum. ${item.acumuladoPct.toStringAsFixed(1)}%',
          ),
          trailing: (clientes && idCliente > 0) || (!clientes && idProduto > 0)
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: () {
            if (clientes && idCliente > 0) {
              mostrarResumoClienteRelatorio(
                context,
                clienteRepository: widget.clienteRepository,
                vendaRepository: widget.vendaRepository,
                clienteId: idCliente,
              );
            } else if (!clientes && idProduto > 0) {
              abrirProdutoRelatorio(
                context,
                produtoRepository: widget.produtoRepository,
                produtoId: idProduto,
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curva ABC'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Clientes'),
            Tab(text: 'Produtos'),
          ],
        ),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: _tabs.index == 0 ? 'abc_clientes' : 'abc_produtos',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: _calcular,
            onAtualizar: _limites != null ? () => _calcular(_limites!) : null,
            resumo: _limites == null
                ? null
                : Text(
                    formatarIntervaloPeriodo(_limites!),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _listaAbc(_clientes, clientes: true),
                _listaAbc(_produtos, clientes: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
