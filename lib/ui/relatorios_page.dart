import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../services/pdf_relatorio_texto.dart';
import '../services/pdf_tabela_produtos_texto.dart';
import 'widgets/hub_nav_button.dart';

const Color _corRelVendasPeriodo = Color(0xFF1565C0);
const Color _corRelProdutosRanking = Color(0xFF2E7D32);
const Color _corRelVendasVendedor = Color(0xFF00897B);
const Color _corRelComissao = Color(0xFF6A1B9A);
const Color _corRelTopClientes = Color(0xFF0277BD);
const Color _corRelEstoqueMin = Color(0xFFE65100);
const Color _corRelOrcamentos = Color(0xFF3949AB);
const Color _corRelTabelaPrecos = Color(0xFF455A64);
const Color _corRelSaidasProduto = Color(0xFF5D4037);

/// Hub de relatorios gerenciais (material de construcao).
class RelatoriosPage extends StatelessWidget {
  const RelatoriosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
    required this.produtoRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;
  final ProdutoRepository produtoRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatorios')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HubNavButton(
            icon: Icons.date_range_outlined,
            corDestaque: _corRelVendasPeriodo,
            titulo: 'Vendas por periodo',
            subtitulo:
                'Lista vendas finalizadas no intervalo; inclui linha de ajuste por devolucoes/trocas registradas no periodo.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioVendasPeriodoPage(
                  vendaRepository: vendaRepository,
                  clienteRepository: clienteRepository,
                  vendedorRepository: vendedorRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.trending_up_outlined,
            corDestaque: _corRelProdutosRanking,
            titulo: 'Produtos mais vendidos',
            subtitulo:
                'Quantidade e valor no periodo: vendas finalizadas ajustadas por devolucoes/trocas cuja data do registro esta no intervalo.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioProdutosMaisVendidosPage(
                  vendaRepository: vendaRepository,
                  produtoRepository: produtoRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.person_search_outlined,
            corDestaque: _corRelVendasVendedor,
            titulo: 'Vendas por vendedor',
            subtitulo:
                'Total por representante no periodo, incluindo ajuste de devolucoes/trocas ligadas as vendas dele.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioVendasPorVendedorPage(
                  vendaRepository: vendaRepository,
                  vendedorRepository: vendedorRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.account_balance_wallet_outlined,
            corDestaque: _corRelComissao,
            titulo: 'Comissao de vendedores',
            subtitulo:
                'Percentual do cadastro; base sobre venda ou lucro (ambos ajustados por devolucoes/trocas no periodo).',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioComissaoVendedoresPage(
                  vendaRepository: vendaRepository,
                  vendedorRepository: vendedorRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.groups_outlined,
            corDestaque: _corRelTopClientes,
            titulo: 'Clientes que mais compraram',
            subtitulo:
                'Ranking por valor no periodo (vendas menos devolucoes/trocas atribuidas ao cliente).',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioTopClientesPage(
                  vendaRepository: vendaRepository,
                  clienteRepository: clienteRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.inventory_2_outlined,
            corDestaque: _corRelEstoqueMin,
            titulo: 'Estoque abaixo do minimo',
            subtitulo:
                'Produtos com saldo menor que a quantidade minima cadastrada.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioEstoqueMinimoPage(
                  produtoRepository: produtoRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.unarchive_outlined,
            corDestaque: _corRelSaidasProduto,
            titulo: 'Saidas por produto',
            subtitulo:
                'Lista vendas finalizadas do item no periodo: quantidade, valores, lucro e cliente.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioSaidasProdutoPage(
                  vendaRepository: vendaRepository,
                  produtoRepository: produtoRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.table_chart_outlined,
            corDestaque: _corRelTabelaPrecos,
            titulo: 'Tabela de precos',
            subtitulo:
                'PDF em ordem alfabetica com estoque; precos de venda ou preco com custo; opcao de listar somente ativos.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioTabelaPrecosPage(
                  produtoRepository: produtoRepository,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          HubNavButton(
            icon: Icons.description_outlined,
            corDestaque: _corRelOrcamentos,
            titulo: 'Orcamentos em aberto',
            subtitulo:
                'Orcamentos ainda nao finalizados no caixa — valor em “pipeline”.',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RelatorioOrcamentosAbertosPage(
                  vendaRepository: vendaRepository,
                  clienteRepository: clienteRepository,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Periodo (compartilhado) ---

typedef LimitesPeriodo = (DateTime inicio, DateTime fim);

class _SeletorPeriodo extends StatefulWidget {
  const _SeletorPeriodo({required this.onChanged});

  final void Function(LimitesPeriodo limites) onChanged;

  @override
  State<_SeletorPeriodo> createState() => _SeletorPeriodoState();
}

class _SeletorPeriodoState extends State<_SeletorPeriodo> {
  String _preset = 'mes_atual';
  DateTime? _customInicio;
  DateTime? _customFim;

  LimitesPeriodo _calcular() {
    final now = DateTime.now();
    final fimDia = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    switch (_preset) {
      case 'hoje':
        final i = DateTime(now.year, now.month, now.day);
        return (i, fimDia);
      case 'ultimos_7':
        final i = DateTime(now.year, now.month, now.day).subtract(
          const Duration(days: 6),
        );
        return (i, fimDia);
      case 'ultimos_30':
        final i = DateTime(now.year, now.month, now.day).subtract(
          const Duration(days: 29),
        );
        return (i, fimDia);
      case 'mes_atual':
        return (DateTime(now.year, now.month, 1), fimDia);
      case 'mes_anterior':
        final i = DateTime(now.year, now.month - 1, 1);
        final f = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return (i, f);
      case 'ano_atual':
        return (DateTime(now.year, 1, 1), fimDia);
      case 'personalizado':
        final a = _customInicio ?? DateTime(now.year, now.month, now.day);
        final b = _customFim ?? fimDia;
        final ini = DateTime(a.year, a.month, a.day);
        final f = DateTime(b.year, b.month, b.day, 23, 59, 59, 999);
        return (ini, f);
      default:
        return (DateTime(now.year, now.month, 1), fimDia);
    }
  }

  void _emitir() {
    widget.onChanged(_calcular());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitir());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(_preset),
          initialValue: _preset,
          decoration: const InputDecoration(labelText: 'Periodo'),
          items: const [
            DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
            DropdownMenuItem(value: 'ultimos_7', child: Text('Ultimos 7 dias')),
            DropdownMenuItem(value: 'ultimos_30', child: Text('Ultimos 30 dias')),
            DropdownMenuItem(value: 'mes_atual', child: Text('Mes atual')),
            DropdownMenuItem(value: 'mes_anterior', child: Text('Mes anterior')),
            DropdownMenuItem(value: 'ano_atual', child: Text('Ano atual')),
            DropdownMenuItem(value: 'personalizado', child: Text('Personalizado')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _preset = v);
            _emitir();
          },
        ),
        if (_preset == 'personalizado') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _customInicio ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setState(() => _customInicio = d);
                      _emitir();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _customInicio == null
                        ? 'Data inicial'
                        : DateFormat('dd/MM/yyyy').format(_customInicio!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _customFim ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setState(() => _customFim = d);
                      _emitir();
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _customFim == null
                        ? 'Data final'
                        : DateFormat('dd/MM/yyyy').format(_customFim!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

List<Venda> _vendasFinalizadasPeriodo(
  VendaRepository repo,
  LimitesPeriodo limites,
) {
  final lista = repo.listarPorPeriodo(
    PeriodoFiltro(inicio: limites.$1, fim: limites.$2),
  );
  return lista
      .where((v) => v.status == 'finalizada' && !v.cancelada)
      .toList()
    ..sort((a, b) => b.data.compareTo(a.data));
}

PeriodoFiltro _periodoFiltro(LimitesPeriodo limites) =>
    PeriodoFiltro(inicio: limites.$1, fim: limites.$2);

String _rotuloFormaPagamento(String forma) {
  switch (forma) {
    case 'pix':
      return 'PIX';
    case 'cartao_credito':
      return 'Credito';
    case 'cartao_debito':
      return 'Debito';
    case 'misto':
      return 'Misto';
    case 'dinheiro':
    default:
      return 'Dinheiro';
  }
}

// --- Vendas por periodo ---

class RelatorioVendasPeriodoPage extends StatefulWidget {
  const RelatorioVendasPeriodoPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;

  @override
  State<RelatorioVendasPeriodoPage> createState() =>
      _RelatorioVendasPeriodoPageState();
}

class _RelatorioVendasPeriodoPageState extends State<RelatorioVendasPeriodoPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final DateFormat _dh = DateFormat('dd/MM/yyyy HH:mm');
  LimitesPeriodo? _limites;
  List<Venda> _linhas = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  Cliente? _cliente(Venda v) {
    final t = v.cliente.target;
    if (t != null) return t;
    final id = v.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  Vendedor? _vendedor(Venda v) {
    final t = v.vendedor.target;
    if (t != null) return t;
    final id = v.vendedor.targetId;
    if (id == 0) return null;
    return widget.vendedorRepository.obterPorId(id);
  }

  String _nomeVendedor(Venda v) {
    final w = _vendedor(v);
    if (w == null) return '-';
    final n = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
    return n;
  }

  void _atualizar(LimitesPeriodo limites) {
    setState(() {
      _limites = limites;
      _linhas = _vendasFinalizadasPeriodo(widget.vendaRepository, limites);
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalNotas = _linhas.fold<double>(0, (s, v) => s + v.total);
    final imp = _limites != null
        ? widget.vendaRepository
            .calcularImpactosDevolucaoTrocaPeriodo(_periodoFiltro(_limites!))
        : null;
    final ajuste = imp?.impactoFaturamentoTotal ?? 0;
    final liquido = totalNotas + ajuste;
    return Scaffold(
      appBar: AppBar(title: const Text('Vendas por periodo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SeletorPeriodo(onChanged: _atualizar),
          ),
          if (_limites != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                    '${DateFormat('dd/MM/yyyy').format(_limites!.$2)} · '
                    '${_linhas.length} nota(s) · Total notas ${_fmt(totalNotas)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ajuste devolucao/troca (data do registro): ${_fmt(ajuste)} · '
                    'Liquido combinado: ${_fmt(liquido)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma venda finalizada neste periodo.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final v = _linhas[i];
                      final c = _cliente(v);
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id} · ${_fmt(v.total)}',
                        ),
                        subtitle: Text(
                          '${_dh.format(v.data.toLocal())} · '
                          '${c?.nomeRazao ?? 'Sem cliente'} · '
                          '${_nomeVendedor(v)} · ${_rotuloFormaPagamento(v.formaPagamento)}',
                          maxLines: 2,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Produtos mais vendidos ---

class _AggProd {
  _AggProd({required this.nome, required this.produtoId});

  final String nome;
  final int produtoId;
  int quantidade = 0;
  double valor = 0;
}

class RelatorioProdutosMaisVendidosPage extends StatefulWidget {
  const RelatorioProdutosMaisVendidosPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioProdutosMaisVendidosPage> createState() =>
      _RelatorioProdutosMaisVendidosPageState();
}

class _RelatorioProdutosMaisVendidosPageState
    extends State<RelatorioProdutosMaisVendidosPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  List<_AggProd> _ranking = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  void _calcular(LimitesPeriodo limites) {
    final vendas = _vendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <String, _AggProd>{};
    for (final v in vendas) {
      for (final item in v.itens) {
        final pid = item.produto.targetId;
        final chave = pid > 0 ? 'id:$pid' : 'nome:${item.nomeProduto}';
        final nome = pid > 0
            ? (widget.produtoRepository.obterPorId(pid)?.nome ?? item.nomeProduto)
            : item.nomeProduto;
        map.putIfAbsent(chave, () => _AggProd(nome: nome, produtoId: pid));
        final a = map[chave]!;
        a.quantidade += item.quantidade;
        a.valor += item.subtotal;
      }
    }
    for (final d in widget.vendaRepository.listarDeltasProdutosDevolucaoPeriodo(
          _periodoFiltro(limites),
        )) {
      map.putIfAbsent(
        d.chaveAgg,
        () => _AggProd(nome: d.nomeExibicao, produtoId: d.produtoId),
      );
      final a = map[d.chaveAgg]!;
      a.quantidade += d.deltaQuantidade;
      a.valor += d.deltaValor;
    }
    final lista = map.values
        .where((a) => a.quantidade > 0)
        .toList()
      ..sort((a, b) => b.quantidade.compareTo(a.quantidade));
    setState(() {
      _limites = limites;
      _ranking = lista;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Produtos mais vendidos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SeletorPeriodo(onChanged: _calcular),
          ),
          if (_limites != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                  '${DateFormat('dd/MM/yyyy').format(_limites!.$2)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _ranking.isEmpty
                ? const Center(child: Text('Nenhum item vendido no periodo.'))
                : ListView.builder(
                    itemCount: _ranking.length,
                    itemBuilder: (context, i) {
                      final a = _ranking[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(a.nome),
                        subtitle: Text('${a.quantidade} un. · ${_fmt(a.valor)}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Vendas por vendedor ---

class RelatorioVendasPorVendedorPage extends StatefulWidget {
  const RelatorioVendasPorVendedorPage({
    super.key,
    required this.vendaRepository,
    required this.vendedorRepository,
  });

  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;

  @override
  State<RelatorioVendasPorVendedorPage> createState() =>
      _RelatorioVendasPorVendedorPageState();
}

class _RelatorioVendasPorVendedorPageState
    extends State<RelatorioVendasPorVendedorPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  List<({String nome, int qtd, double total})> _linhas = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  String _nome(Vendedor? w) {
    if (w == null) return 'Sem vendedor';
    final n = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
    return n;
  }

  void _calcular(LimitesPeriodo limites) {
    final vendas = _vendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, ({String nome, int qtd, double total})>{};
    for (final v in vendas) {
      final id = v.vendedor.targetId;
      final w = v.vendedor.target ?? widget.vendedorRepository.obterPorId(id);
      final nome = _nome(w);
      final cur = map[id];
      if (cur == null) {
        map[id] = (nome: nome, qtd: 1, total: v.total);
      } else {
        map[id] = (
          nome: cur.nome,
          qtd: cur.qtd + 1,
          total: cur.total + v.total,
        );
      }
    }
    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(_periodoFiltro(limites));
    for (final e in imp.porVendedorFaturamento.entries) {
      final id = e.key;
      final adj = e.value;
      if (adj.abs() < 0.0001) continue;
      final w = id == 0 ? null : widget.vendedorRepository.obterPorId(id);
      final nome = _nome(w);
      final cur = map[id];
      if (cur == null) {
        map[id] = (nome: nome, qtd: 0, total: adj);
      } else {
        map[id] = (
          nome: cur.nome,
          qtd: cur.qtd,
          total: cur.total + adj,
        );
      }
    }
    final lista = map.entries.map((e) => e.value).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    setState(() {
      _limites = limites;
      _linhas = lista;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendas por vendedor')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SeletorPeriodo(onChanged: _calcular),
          ),
          if (_limites != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                '${DateFormat('dd/MM/yyyy').format(_limites!.$2)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma venda no periodo.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final r = _linhas[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(r.nome),
                        subtitle: Text('${r.qtd} venda(s) · ${_fmt(r.total)}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Comissao de vendedores ---

class _AggComissaoVendedor {
  _AggComissaoVendedor({required this.vendedorId});

  final int vendedorId;
  int quantidadeVendas = 0;
  double baseAcumulada = 0;
}

class RelatorioComissaoVendedoresPage extends StatefulWidget {
  const RelatorioComissaoVendedoresPage({
    super.key,
    required this.vendaRepository,
    required this.vendedorRepository,
  });

  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;

  @override
  State<RelatorioComissaoVendedoresPage> createState() =>
      _RelatorioComissaoVendedoresPageState();
}

class _RelatorioComissaoVendedoresPageState extends State<RelatorioComissaoVendedoresPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final NumberFormat _pctFmt = NumberFormat('#0.##', 'pt_BR');

  LimitesPeriodo? _limites;
  /// `venda` = percentual sobre soma do valor da venda; `lucro` = sobre soma do lucro.
  String _baseCalculo = 'venda';
  bool _somenteVendedoresAtivos = false;
  int? _filtroVendedorId;

  List<({
    int vendedorId,
    Vendedor? vendedor,
    String nomeExibicao,
    int qtd,
    double base,
    double pct,
    double comissao,
    bool inativo,
  })> _linhas = [];

  double _totalBase = 0;
  double _totalComissao = 0;

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  String _nomeVendedor(Vendedor? w, int id) {
    if (w == null) {
      return id == 0 ? 'Sem vendedor' : 'Vendedor #$id';
    }
    final n = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto.trim();
    final cod = w.codigoInterno.trim();
    return cod.isEmpty ? n : '$cod · $n';
  }

  void _recalcular() {
    final limites = _limites;
    if (limites == null) return;

    final vendas = _vendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, _AggComissaoVendedor>{};

    for (final v in vendas) {
      final id = v.vendedor.targetId;
      if (_filtroVendedorId != null && id != _filtroVendedorId) continue;

      final w = id == 0 ? null : (v.vendedor.target ?? widget.vendedorRepository.obterPorId(id));
      if (_somenteVendedoresAtivos && id != 0 && (w == null || !w.ativo)) {
        continue;
      }

      final parcelaBase = _baseCalculo == 'lucro' ? v.lucroTotal : v.total;
      map.putIfAbsent(id, () => _AggComissaoVendedor(vendedorId: id));
      final a = map[id]!;
      a.quantidadeVendas += 1;
      a.baseAcumulada += parcelaBase;
    }

    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(_periodoFiltro(limites));
    final porVend = _baseCalculo == 'lucro'
        ? imp.porVendedorLucro
        : imp.porVendedorFaturamento;
    for (final e in porVend.entries) {
      final id = e.key;
      final adj = e.value;
      if (adj.abs() < 0.0001) continue;
      if (_filtroVendedorId != null && id != _filtroVendedorId) continue;

      final w = id == 0 ? null : widget.vendedorRepository.obterPorId(id);
      if (_somenteVendedoresAtivos && id != 0 && (w == null || !w.ativo)) {
        continue;
      }

      map.putIfAbsent(id, () => _AggComissaoVendedor(vendedorId: id));
      map[id]!.baseAcumulada += adj;
    }

    final saida =
        <({
          int vendedorId,
          Vendedor? vendedor,
          String nomeExibicao,
          int qtd,
          double base,
          double pct,
          double comissao,
          bool inativo,
        })>[];

    var sumBase = 0.0;
    var sumCom = 0.0;

    for (final e in map.entries) {
      final id = e.key;
      final agg = e.value;
      final w = id == 0 ? null : widget.vendedorRepository.obterPorId(id);
      final pct = w?.percentualComissao ?? 0;
      final comissao = agg.baseAcumulada * pct / 100.0;
      final inativo = w != null && !w.ativo;
      saida.add((
        vendedorId: id,
        vendedor: w,
        nomeExibicao: _nomeVendedor(w, id),
        qtd: agg.quantidadeVendas,
        base: agg.baseAcumulada,
        pct: pct,
        comissao: comissao,
        inativo: inativo,
      ));
      sumBase += agg.baseAcumulada;
      sumCom += comissao;
    }

    saida.sort((a, b) => b.comissao.compareTo(a.comissao));

    setState(() {
      _linhas = saida;
      _totalBase = sumBase;
      _totalComissao = sumCom;
    });
  }

  void _onPeriodo(LimitesPeriodo limites) {
    _limites = limites;
    _recalcular();
  }

  @override
  Widget build(BuildContext context) {
    final vendedoresOpcoes = widget.vendedorRepository.listarTodos();

    return Scaffold(
      appBar: AppBar(title: const Text('Comissao de vendedores')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _SeletorPeriodo(onChanged: _onPeriodo),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'venda',
                  label: Text('Base: valor da venda'),
                  icon: Icon(Icons.shopping_cart_outlined),
                ),
                ButtonSegment<String>(
                  value: 'lucro',
                  label: Text('Base: lucro'),
                  icon: Icon(Icons.trending_up_outlined),
                ),
              ],
              emptySelectionAllowed: false,
              selected: {_baseCalculo},
              onSelectionChanged: (set) {
                setState(() => _baseCalculo = set.first);
                _recalcular();
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Somente vendedores ativos'),
            subtitle: const Text(
              'Oculta vendas ligadas a cadastros marcados como inativos.',
            ),
            value: _somenteVendedoresAtivos,
            onChanged: (v) {
              setState(() => _somenteVendedoresAtivos = v);
              _recalcular();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<int?>(
              key: ValueKey(_filtroVendedorId),
              initialValue: _filtroVendedorId,
              decoration: const InputDecoration(
                labelText: 'Filtrar por vendedor',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos'),
                ),
                const DropdownMenuItem<int?>(
                  value: 0,
                  child: Text('Sem vendedor'),
                ),
                ...vendedoresOpcoes.map(
                  (v) => DropdownMenuItem<int?>(
                    value: v.id,
                    child: Text(_nomeVendedor(v, v.id)),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() => _filtroVendedorId = val);
                _recalcular();
              },
            ),
          ),
          if (_limites != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                    '${DateFormat('dd/MM/yyyy').format(_limites!.$2)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Inclui ajuste por devolucoes/trocas registradas neste periodo '
                    '(atribuido ao vendedor da venda original).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total base no periodo: ${_fmt(_totalBase)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total de comissoes (a pagar): ${_fmt(_totalComissao)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'O percentual vem do cadastro de vendedores. '
                      'Base “valor da venda” segue a regra padrao do campo comissao (%). '
                      'Base “lucro” aplica o mesmo % sobre a soma do lucro das vendas.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _limites == null
                            ? 'Selecione o periodo.'
                            : 'Nenhuma venda no periodo com os filtros atuais.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final r = _linhas[i];
                      final w = r.vendedor;
                      String? refMeta;
                      if (w != null && w.metaMensalValor > 0 && r.base > 0) {
                        final ating =
                            (r.base / w.metaMensalValor * 100).clamp(0, 9999);
                        refMeta =
                            'Meta ref.: ${_fmt(w.metaMensalValor)} · '
                            '${_pctFmt.format(ating)}% do periodo em relacao a meta';
                      }
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text('${i + 1}'),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(r.nomeExibicao)),
                            if (r.inativo)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Chip(
                                  label: const Text('Inativo'),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.qtd} venda(s) · Base ${_fmt(r.base)} · '
                              '${_pctFmt.format(r.pct)}% · Comissao ${_fmt(r.comissao)}',
                            ),
                            if (refMeta != null)
                              Text(
                                refMeta,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        isThreeLine: refMeta != null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Top clientes ---

class RelatorioTopClientesPage extends StatefulWidget {
  const RelatorioTopClientesPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;

  @override
  State<RelatorioTopClientesPage> createState() => _RelatorioTopClientesPageState();
}

class _RelatorioTopClientesPageState extends State<RelatorioTopClientesPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  List<({String nome, int qtd, double total})> _linhas = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  Cliente? _cliente(Venda v) {
    final t = v.cliente.target;
    if (t != null) return t;
    final id = v.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  void _calcular(LimitesPeriodo limites) {
    final vendas = _vendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, ({String nome, int qtd, double total})>{};
    for (final v in vendas) {
      final id = v.cliente.targetId;
      final c = _cliente(v);
      final nome = id == 0
          ? 'Sem cliente'
          : (c?.nomeRazao.trim().isNotEmpty == true
              ? c!.nomeRazao.trim()
              : 'Cliente #$id');
      final cur = map[id];
      if (cur == null) {
        map[id] = (nome: nome, qtd: 1, total: v.total);
      } else {
        map[id] = (
          nome: cur.nome,
          qtd: cur.qtd + 1,
          total: cur.total + v.total,
        );
      }
    }
    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(_periodoFiltro(limites));
    for (final e in imp.porClienteFaturamento.entries) {
      final id = e.key;
      final adj = e.value;
      if (adj.abs() < 0.0001) continue;
      final cli = id == 0 ? null : widget.clienteRepository.obterPorId(id);
      final nomeFallback = id == 0
          ? 'Sem cliente'
          : (cli?.nomeRazao.trim().isNotEmpty == true
              ? cli!.nomeRazao.trim()
              : 'Cliente #$id');
      final cur = map[id];
      if (cur == null) {
        map[id] = (nome: nomeFallback, qtd: 0, total: adj);
      } else {
        map[id] = (
          nome: cur.nome,
          qtd: cur.qtd,
          total: cur.total + adj,
        );
      }
    }
    final lista = map.entries.map((e) => e.value).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    setState(() {
      _limites = limites;
      _linhas = lista;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes que mais compraram')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SeletorPeriodo(onChanged: _calcular),
          ),
          if (_limites != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                '${DateFormat('dd/MM/yyyy').format(_limites!.$2)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma venda no periodo.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final r = _linhas[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(r.nome),
                        subtitle: Text('${r.qtd} pedido(s) · ${_fmt(r.total)}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Estoque minimo ---

class RelatorioEstoqueMinimoPage extends StatefulWidget {
  const RelatorioEstoqueMinimoPage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioEstoqueMinimoPage> createState() =>
      _RelatorioEstoqueMinimoPageState();
}

class _RelatorioEstoqueMinimoPageState extends State<RelatorioEstoqueMinimoPage> {
  List<Produto> _lista = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    final todos = widget.produtoRepository.listarTodos();
    final critico = todos.where((p) => p.estoqueReal < p.quantidadeMinima).toList()
      ..sort((a, b) {
        final da = a.quantidadeMinima - a.estoqueReal;
        final db = b.quantidadeMinima - b.estoqueReal;
        return db.compareTo(da);
      });
    setState(() => _lista = critico);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque abaixo do minimo'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _lista.isEmpty
          ? const Center(child: Text('Nenhum produto abaixo do minimo.'))
          : ListView.builder(
              itemCount: _lista.length,
              itemBuilder: (context, i) {
                final p = _lista[i];
                final falta = p.quantidadeMinima - p.estoqueReal;
                return ListTile(
                  title: Text(p.nome),
                  subtitle: Text(
                    '${p.categoria.isNotEmpty ? '${p.categoria} · ' : ''}'
                    'Min: ${p.quantidadeMinima} ${p.unidade} · '
                    'Atual: ${p.estoqueReal} · Falta repor: $falta',
                  ),
                );
              },
            ),
    );
  }
}

// --- Orcamentos abertos ---

class RelatorioOrcamentosAbertosPage extends StatelessWidget {
  const RelatorioOrcamentosAbertosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;

  @override
  Widget build(BuildContext context) {
    final NumberFormat moeda = NumberFormat('#,##0.00', 'pt_BR');
    String fmt(double v) => 'R\$ ${moeda.format(v)}';
    final orcs = vendaRepository.listarOrcamentosPendentes()
      ..sort((a, b) => b.data.compareTo(a.data));
    final total = orcs.fold<double>(0, (s, v) => s + v.total);

    Cliente? cliente(Venda v) {
      final t = v.cliente.target;
      if (t != null) return t;
      final id = v.cliente.targetId;
      if (id == 0) return null;
      return clienteRepository.obterPorId(id);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Orcamentos em aberto')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${orcs.length} orcamento(s) · Valor total ${fmt(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: orcs.isEmpty
                ? const Center(child: Text('Nenhum orcamento pendente.'))
                : ListView.builder(
                    itemCount: orcs.length,
                    itemBuilder: (context, i) {
                      final v = orcs[i];
                      final c = cliente(v);
                      return ListTile(
                        title: Text(
                          'Orc. ${v.numeroOrcamento} · ${fmt(v.total)}',
                        ),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal())} · '
                          '${c?.nomeRazao ?? 'Sem cliente'} · '
                          '${v.itens.length} item(ns)',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Tabela de precos (export PDF) ---

class RelatorioTabelaPrecosPage extends StatefulWidget {
  const RelatorioTabelaPrecosPage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioTabelaPrecosPage> createState() =>
      _RelatorioTabelaPrecosPageState();
}

class _RelatorioTabelaPrecosPageState extends State<RelatorioTabelaPrecosPage> {
  bool _somenteAtivos = false;

  Future<void> _exportarPdf({required bool incluirCustos}) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar o PDF',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    try {
      final base = widget.produtoRepository.listarTodos();
      final filtrado = _somenteAtivos
          ? base.where((p) => p.ativo).toList()
          : List<Produto>.from(base);
      final produtos = filtrado
        ..sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
        );
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo =
          incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final sufixoAtivos = _somenteAtivos ? '_ativos_' : '_';
      final arquivo = File(
        p.join(
          pastaDestino,
          '${tipoArquivo}_relatorio$sufixoAtivos$timestamp.pdf',
        ),
      );
      final titulo = incluirCustos
          ? 'Tabela Preco+Custo (alfabetica)'
          : 'Tabela Precos (alfabetica)';

      final bytes = await gerarPdfTabelaProdutosTexto(
        produtos: produtos,
        incluirCustos: incluirCustos,
        titulo: titulo,
        incluirColunaEstoque: true,
      );
      await arquivo.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('PDF exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar PDF: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tabela de precos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Exporte o cadastro completo em ordem alfabetica por nome do produto. '
            'As colunas de preco seguem o mesmo padrao da exportacao em Estoque '
            '(a prazo = preco de venda principal; a vista = preco 2 quando informado). '
            'O PDF inclui a quantidade em estoque (saldo fisico). '
            'Formato leve: texto tabulado em Courier, sem grade nem sombras.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _somenteAtivos,
            onChanged: (v) => setState(() => _somenteAtivos = v),
            title: const Text('Somente produtos ativos'),
            subtitle: const Text(
              'Quando ligado, itens inativos no cadastro nao entram no PDF.',
            ),
            secondary: Icon(
              Icons.inventory_2_outlined,
              color: _corRelTabelaPrecos,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _corRelTabelaPrecos.withValues(alpha: 0.15),
                child: Icon(
                  Icons.picture_as_pdf_outlined,
                  color: _corRelTabelaPrecos,
                ),
              ),
              title: const Text('PDF — precos de venda'),
              subtitle: const Text(
                'Codigo, produto, estoque, a prazo e a vista (sem custo).',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _exportarPdf(incluirCustos: false),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _corRelTabelaPrecos.withValues(alpha: 0.15),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: _corRelTabelaPrecos,
                ),
              ),
              title: const Text('PDF — preco e custo'),
              subtitle: const Text(
                'Inclui estoque e coluna de custo cadastrado (preco de custo).',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _exportarPdf(incluirCustos: true),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Saidas por produto ---

class RelatorioSaidasProdutoPage extends StatefulWidget {
  const RelatorioSaidasProdutoPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioSaidasProdutoPage> createState() =>
      _RelatorioSaidasProdutoPageState();
}

class _RelatorioSaidasProdutoPageState extends State<RelatorioSaidasProdutoPage> {
  LimitesPeriodo? _limites;
  Produto? _produto;
  List<Produto> _cacheProdutos = [];
  List<SaidaProdutoRelatorioLinha> _linhas = [];

  final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  final NumberFormat _nfInt = NumberFormat('#,##0', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _cacheProdutos = widget.produtoRepository.listarTodos();
  }

  void _carregar() {
    final p = _produto;
    final lim = _limites;
    if (p == null || lim == null) {
      setState(() => _linhas = []);
      return;
    }
    final lista = widget.vendaRepository.listarSaidasProdutoPeriodo(
      produtoId: p.id,
      inicio: lim.$1,
      fim: lim.$2,
    );
    setState(() => _linhas = lista);
  }

  String _fmtMoeda(double v) => 'R\$ ${_nfMoeda.format(v)}';

  String _linhaPdf(SaidaProdutoRelatorioLinha l) {
    String t(String s, int w) =>
        s.length > w ? s.substring(0, w) : s.padRight(w);
    String n(String s, int w) => s.padLeft(w);
    final d = DateFormat('dd/MM/yyyy').format(l.dataVenda);
    return '${t(d, 12)} ${n(_nfInt.format(l.quantidade), 12)} '
        '${n(_nfMoeda.format(l.valorUnitario), 12)} '
        '${n(_nfMoeda.format(l.total), 12)} '
        '${n('${l.nota}', 8)} '
        '${n(_nfMoeda.format(l.lucro), 12)} '
        '${n(_nfMoeda.format(l.acrescimo), 10)} '
        '${t(l.clienteNome, 26)}';
  }

  List<String> _montarPaginasPdf(String tituloProduto, String periodoRotulo) {
    const maxLinhas = 52;
    final cab = StringBuffer()
      ..writeln('SAIDAS DO PRODUTO (vendas finalizadas)')
      ..writeln(tituloProduto)
      ..writeln('Periodo: $periodoRotulo')
      ..writeln()
      ..writeln(
        '${'DATA'.padRight(12)} ${'QTD'.padLeft(12)} ${'VLR_UNIT'.padLeft(12)} '
        '${'TOTAL'.padLeft(12)} ${'NOTA'.padLeft(8)} ${'LUCRO'.padLeft(12)} '
        '${'ACRESC'.padLeft(10)} ${'CLIENTE'.padRight(26)}',
      )
      ..writeln('-' * 96);

    for (final l in _linhas) {
      cab.writeln(_linhaPdf(l));
    }
    cab.writeln('-' * 96);
    final tQ = _linhas.fold<int>(0, (s, e) => s + e.quantidade);
    final tV = _linhas.fold<double>(0, (s, e) => s + e.total);
    final tL = _linhas.fold<double>(0, (s, e) => s + e.lucro);
    String pn(String s, int w) => s.padLeft(w);
    cab.writeln(
      '${'TOTAIS'.padRight(12)} ${pn(_nfInt.format(tQ), 12)} ${''.padLeft(12)} '
      '${pn(_nfMoeda.format(tV), 12)} ${''.padLeft(8)} ${pn(_nfMoeda.format(tL), 12)}',
    );

    final texto = cab.toString();
    final linhas = texto.split('\n');
    final paginas = <String>[];
    for (var i = 0; i < linhas.length; i += maxLinhas) {
      final fim = math.min(i + maxLinhas, linhas.length);
      paginas.add(linhas.sublist(i, fim).join('\n'));
    }
    return paginas.isEmpty ? <String>['(vazio)'] : paginas;
  }

  Future<void> _imprimirPdf() async {
    if (_produto == null || _limites == null || _linhas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione produto e periodo com linhas para imprimir.')),
      );
      return;
    }
    final ini = DateFormat('dd/MM/yyyy').format(_limites!.$1);
    final fim = DateFormat('dd/MM/yyyy').format(_limites!.$2);
    final bytes = await gerarPdfRelatorioTextoPaginas(
      _montarPaginasPdf(_produto!.nome, '$ini a $fim'),
    );
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _salvarPdf() async {
    if (_produto == null || _limites == null || _linhas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para exportar neste periodo.')),
      );
      return;
    }
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para salvar o PDF',
    );
    if (pasta == null || pasta.trim().isEmpty) return;
    final ini = DateFormat('yyyyMMdd').format(_limites!.$1);
    final fim = DateFormat('yyyyMMdd').format(_limites!.$2);
    final seguro = _produto!.codigoInterno.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final arquivo = File(p.join(pasta, 'saidas_produto_${seguro}_$ini-$fim.pdf'));
    try {
      final iniFmt = DateFormat('dd/MM/yyyy').format(_limites!.$1);
      final fimFmt = DateFormat('dd/MM/yyyy').format(_limites!.$2);
      final bytes = await gerarPdfRelatorioTextoPaginas(
        _montarPaginasPdf(_produto!.nome, '$iniFmt a $fimFmt'),
      );
      await arquivo.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF salvo: ${arquivo.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tQ = _linhas.fold<int>(0, (s, e) => s + e.quantidade);
    final tV = _linhas.fold<double>(0, (s, e) => s + e.total);
    final tL = _linhas.fold<double>(0, (s, e) => s + e.lucro);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saidas por produto'),
        actions: [
          IconButton(
            tooltip: 'Imprimir / PDF',
            onPressed: _imprimirPdf,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Salvar PDF na pasta',
            onPressed: _salvarPdf,
            icon: const Icon(Icons.save_alt_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Autocomplete<Produto>(
                  displayStringForOption: (p) => '${p.codigoInterno} · ${p.nome}',
                  optionsBuilder: (TextEditingValue te) {
                    final t = te.text.trim().toLowerCase();
                    if (t.length < 2) {
                      return const Iterable<Produto>.empty();
                    }
                    return _cacheProdutos.where((p) {
                      return p.nome.toLowerCase().contains(t) ||
                          p.codigoInterno.toLowerCase().contains(t);
                    }).take(40);
                  },
                  onSelected: (p) {
                    setState(() => _produto = p);
                    _carregar();
                  },
                  fieldViewBuilder:
                      (context, textEditingController, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Produto (digite 2+ caracteres)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onEditingComplete: onFieldSubmitted,
                    );
                  },
                ),
                const SizedBox(height: 12),
                _SeletorPeriodo(
                  onChanged: (lim) {
                    setState(() => _limites = lim);
                    _carregar();
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _carregar,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Atualizar listagem'),
                ),
              ],
            ),
          ),
          if (_produto != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Produto: ${_produto!.nome} (${_produto!.codigoInterno})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Quantidade total: ${_nfInt.format(tQ)} · Valor total: ${_fmtMoeda(tV)} · Lucro total: ${_fmtMoeda(tL)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? Center(
                    child: Text(
                      _produto == null
                          ? 'Selecione um produto acima.'
                          : 'Nenhuma saida no periodo (vendas finalizadas, quantidade liquida > 0).',
                    ),
                  )
                : Scrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _linhas.length,
                      itemBuilder: (context, i) {
                        final l = _linhas[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              '${DateFormat('dd/MM/yyyy').format(l.dataVenda)} · '
                              'Qtd ${_nfInt.format(l.quantidade)} · '
                              'Total ${_fmtMoeda(l.total)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Unit ${_fmtMoeda(l.valorUnitario)} · '
                              'Lucro ${_fmtMoeda(l.lucro)} · '
                              'Acresc ${_fmtMoeda(l.acrescimo)} · '
                              'Nota ${l.nota} · '
                              '${l.clienteNome}',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
