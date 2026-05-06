import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';

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
          _RelatorioTile(
            icon: Icons.date_range_outlined,
            titulo: 'Vendas por periodo',
            descricao:
                'Lista vendas finalizadas no intervalo, totais e forma de pagamento.',
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
          _RelatorioTile(
            icon: Icons.trending_up_outlined,
            titulo: 'Produtos mais vendidos',
            descricao:
                'Quantidade e valor por produto no periodo (somente vendas finalizadas).',
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
          _RelatorioTile(
            icon: Icons.person_search_outlined,
            titulo: 'Vendas por vendedor',
            descricao:
                'Total vendido por representante no periodo — util para metas e comissao.',
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
          _RelatorioTile(
            icon: Icons.account_balance_wallet_outlined,
            titulo: 'Comissao de vendedores',
            descricao:
                'Percentual do cadastro, base sobre venda ou lucro, filtros e total a pagar.',
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
          _RelatorioTile(
            icon: Icons.groups_outlined,
            titulo: 'Clientes que mais compraram',
            descricao:
                'Ranking por valor no periodo — foco em obra e cliente recorrente.',
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
          _RelatorioTile(
            icon: Icons.inventory_2_outlined,
            titulo: 'Estoque abaixo do minimo',
            descricao:
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
          _RelatorioTile(
            icon: Icons.description_outlined,
            titulo: 'Orcamentos em aberto',
            descricao:
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

class _RelatorioTile extends StatelessWidget {
  const _RelatorioTile({
    required this.icon,
    required this.titulo,
    required this.descricao,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String descricao;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(descricao),
        isThreeLine: true,
        onTap: onTap,
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
          value: _preset,
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
    final total = _linhas.fold<double>(0, (s, v) => s + v.total);
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
              child: Text(
                '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                '${DateFormat('dd/MM/yyyy').format(_limites!.$2)} · '
                '${_linhas.length} venda(s) · Total ${_fmt(total)}',
                style: Theme.of(context).textTheme.titleSmall,
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
                          '#${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id} · ${_fmt(v.total)}',
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
    final lista = map.values.toList()
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
              value: _filtroVendedorId,
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
              child: Text(
                '${DateFormat('dd/MM/yyyy').format(_limites!.$1)} — '
                '${DateFormat('dd/MM/yyyy').format(_limites!.$2)}',
                style: Theme.of(context).textTheme.titleSmall,
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
                          'Orc. #${v.numeroOrcamento} · ${fmt(v.total)}',
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
