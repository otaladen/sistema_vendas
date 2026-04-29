import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/cliente_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';

/// Lista vendas já finalizadas no Caixa (`status == finalizada`), com filtros e busca.
class ListagemVendasPage extends StatefulWidget {
  const ListagemVendasPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;

  @override
  State<ListagemVendasPage> createState() => _ListagemVendasPageState();
}

class _ListagemVendasPageState extends State<ListagemVendasPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final _buscaController = TextEditingController();

  String _periodoPreset = 'ultimos_30';
  String _formaPagamento = 'todos';
  String _tipoEntrega = 'todos';
  String _entregaPendente = 'todos';
  int? _clienteIdFiltro;
  int? _vendedorIdFiltro;
  bool _incluirCanceladas = false;

  List<Venda> _resultados = [];

  @override
  void initState() {
    super.initState();
    _pesquisar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  Cliente? _clienteDaVenda(Venda venda) {
    final ligado = venda.cliente.target;
    if (ligado != null) return ligado;
    final id = venda.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    final ligado = venda.vendedor.target;
    if (ligado != null) return ligado;
    final id = venda.vendedor.targetId;
    if (id == 0) return null;
    return widget.vendedorRepository.obterPorId(id);
  }

  String _rotuloVendedorUmLinha(Venda venda) {
    final v = _vendedorDaVenda(venda);
    if (v == null) return 'Sem vendedor';
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  (DateTime?, DateTime?) _limitesPeriodo() {
    final now = DateTime.now();
    final fimDia = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    switch (_periodoPreset) {
      case 'hoje':
        final inicio = DateTime(now.year, now.month, now.day);
        return (inicio, fimDia);
      case 'ultimos_7':
        final inicio = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        return (inicio, fimDia);
      case 'ultimos_30':
        final inicio = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));
        return (inicio, fimDia);
      case 'mes_atual':
        return (DateTime(now.year, now.month, 1), fimDia);
      case 'mes_anterior':
        final inicio = DateTime(now.year, now.month - 1, 1);
        final fim = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return (inicio, fim);
      case 'ano_atual':
        return (DateTime(now.year, 1, 1), fimDia);
      case 'todo':
      default:
        return (null, null);
    }
  }

  String _rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao de credito';
      case 'cartao_debito':
        return 'Cartao de debito';
      case 'fiado':
        return 'Fiado';
      case 'transferencia':
        return 'Transferencia';
      case 'dinheiro':
      default:
        return 'Dinheiro';
    }
  }

  String _rotuloTipoEntrega(String tipo) {
    switch (tipo) {
      case 'entrega_loja':
        return 'Entrega da loja';
      case 'retirada':
      default:
        return 'Retirada na loja';
    }
  }

  void _pesquisar() {
    final todas = widget.vendaRepository.listarTodas();
    Iterable<Venda> it = todas.where((v) => v.status == 'finalizada');

    if (!_incluirCanceladas) {
      it = it.where((v) => !v.cancelada);
    }

    final range = _limitesPeriodo();
    if (range.$1 != null && range.$2 != null) {
      final inicioUtc = range.$1!.toUtc();
      final fimUtc = range.$2!.toUtc();
      it = it.where((v) {
        final d = v.data.toUtc();
        return !d.isBefore(inicioUtc) && !d.isAfter(fimUtc);
      });
    }

    if (_formaPagamento != 'todos') {
      it = it.where((v) => v.formaPagamento == _formaPagamento);
    }
    if (_tipoEntrega != 'todos') {
      it = it.where((v) => v.tipoEntrega == _tipoEntrega);
    }
    if (_entregaPendente == 'sim') {
      it = it.where((v) => v.entregaPendente);
    } else if (_entregaPendente == 'nao') {
      it = it.where((v) => !v.entregaPendente);
    }
    if (_clienteIdFiltro != null) {
      final cid = _clienteIdFiltro!;
      it = it.where((v) => v.cliente.targetId == cid);
    }
    if (_vendedorIdFiltro != null) {
      final vid = _vendedorIdFiltro!;
      it = it.where((v) => v.vendedor.targetId == vid);
    }

    final q = _buscaController.text.trim();
    if (q.isNotEmpty) {
      final lower = q.toLowerCase();
      final asInt = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), ''));
      it = it.where((v) {
        if (asInt != null) {
          if (v.id == asInt || v.numeroOrcamento == asInt) return true;
        }
        final cliente = _clienteDaVenda(v);
        if (cliente != null &&
            cliente.nomeRazao.toLowerCase().contains(lower)) {
          return true;
        }
        final vend = _vendedorDaVenda(v);
        if (vend != null) {
          final camposV = [
            vend.codigoInterno,
            vend.nomeCompleto,
            vend.apelido,
          ].map((e) => e.toLowerCase());
          if (camposV.any((c) => c.contains(lower))) return true;
        }
        for (final item in v.itens) {
          if (item.nomeProduto.toLowerCase().contains(lower)) return true;
        }
        return false;
      });
    }

    final lista = it.toList()..sort((a, b) => b.data.compareTo(a.data));

    setState(() {
      _resultados = lista;
    });
  }

  void _limparFiltros() {
    setState(() {
      _periodoPreset = 'ultimos_30';
      _formaPagamento = 'todos';
      _tipoEntrega = 'todos';
      _entregaPendente = 'todos';
      _clienteIdFiltro = null;
      _vendedorIdFiltro = null;
      _incluirCanceladas = false;
      _buscaController.clear();
    });
    _pesquisar();
  }

  @override
  Widget build(BuildContext context) {
    final clientes = widget.clienteRepository
        .listarTodos()
        .where((c) => c.ativo)
        .toList();
    final vendedores = widget.vendedorRepository.listarAtivos();

    return Scaffold(
      appBar: AppBar(title: const Text('Listagem de Vendas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Filtros',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: _periodoPreset,
                            decoration: const InputDecoration(
                              labelText: 'Periodo',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'hoje',
                                child: Text('Hoje'),
                              ),
                              DropdownMenuItem(
                                value: 'ultimos_7',
                                child: Text('Ultimos 7 dias'),
                              ),
                              DropdownMenuItem(
                                value: 'ultimos_30',
                                child: Text('Ultimos 30 dias'),
                              ),
                              DropdownMenuItem(
                                value: 'mes_atual',
                                child: Text('Mes atual'),
                              ),
                              DropdownMenuItem(
                                value: 'mes_anterior',
                                child: Text('Mes anterior'),
                              ),
                              DropdownMenuItem(
                                value: 'ano_atual',
                                child: Text('Ano atual'),
                              ),
                              DropdownMenuItem(
                                value: 'todo',
                                child: Text('Todo o periodo'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _periodoPreset = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: _formaPagamento,
                            decoration: const InputDecoration(
                              labelText: 'Pagamento',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'todos',
                                child: Text('Todos'),
                              ),
                              ...[
                                'dinheiro',
                                'pix',
                                'cartao_credito',
                                'cartao_debito',
                                'fiado',
                                'transferencia',
                              ].map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(_rotuloFormaPagamento(f)),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null)
                                setState(() => _formaPagamento = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: _tipoEntrega,
                            decoration: const InputDecoration(
                              labelText: 'Entrega',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'todos',
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: 'retirada',
                                child: Text('Retirada na loja'),
                              ),
                              DropdownMenuItem(
                                value: 'entrega_loja',
                                child: Text('Entrega da loja'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _tipoEntrega = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: _entregaPendente,
                            decoration: const InputDecoration(
                              labelText: 'Retirada futura',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'todos',
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: 'nao',
                                child: Text('Entregue (normal)'),
                              ),
                              DropdownMenuItem(
                                value: 'sim',
                                child: Text('Pendente'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null)
                                setState(() => _entregaPendente = v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: DropdownButtonFormField<int?>(
                            initialValue: _clienteIdFiltro,
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Todos'),
                              ),
                              ...clientes.map(
                                (c) => DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text(
                                    c.nomeRazao,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _clienteIdFiltro = v),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<int?>(
                            initialValue: _vendedorIdFiltro,
                            decoration: const InputDecoration(
                              labelText: 'Vendedor',
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('Todos'),
                              ),
                              ...vendedores.map(
                                (vd) => DropdownMenuItem<int?>(
                                  value: vd.id,
                                  child: Text(
                                    vd.apelido.trim().isNotEmpty
                                        ? vd.apelido
                                        : vd.nomeCompleto,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _vendedorIdFiltro = v),
                          ),
                        ),
                        FilterChip(
                          label: const Text('Incluir canceladas'),
                          selected: _incluirCanceladas,
                          onSelected: (v) =>
                              setState(() => _incluirCanceladas = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buscaController,
                            decoration: const InputDecoration(
                              labelText: 'Pesquisar nota',
                              hintText:
                                  'N. orcamento, ID, cliente, vendedor (nome/codigo) ou produto',
                              prefixIcon: Icon(Icons.search),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _pesquisar(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _pesquisar,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text('Pesquisar'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _limparFiltros,
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_resultados.length} nota(s) encontrada(s)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _resultados.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma venda finalizada com os filtros atuais.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _resultados.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final v = _resultados[index];
                        final cliente = _clienteDaVenda(v);
                        final rotuloVend = _rotuloVendedorUmLinha(v);
                        return Card(
                          child: ListTile(
                            isThreeLine: true,
                            leading: CircleAvatar(
                              child: Text(
                                v.numeroOrcamento > 0
                                    ? '#${v.numeroOrcamento}'
                                    : '${v.id}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            title: Text(
                              'Orcamento #${v.numeroOrcamento} | Venda ID ${v.id}'
                              '${v.cancelada ? ' (cancelada)' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: v.cancelada
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_dataHora.format(v.data.toLocal())),
                                Text(
                                  'Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'} | '
                                  'Vendedor: $rotuloVend | '
                                  '${_rotuloFormaPagamento(v.formaPagamento)}'
                                  '${v.formaPagamento == 'cartao_credito' ? ' ${v.quantidadeParcelas}x' : ''}',
                                ),
                                Text(
                                  '${_rotuloTipoEntrega(v.tipoEntrega)} | '
                                  'Retirada futura: ${v.entregaPendente ? 'Sim' : 'Nao'} | '
                                  'Itens: ${v.itens.length}',
                                ),
                              ],
                            ),
                            trailing: Text(
                              _formatarMoeda(v.total),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
