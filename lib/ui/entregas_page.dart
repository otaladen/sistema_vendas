import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/venda_repository.dart';
import '../model/venda.dart';

class EntregasPage extends StatefulWidget {
  const EntregasPage({super.key, required this.vendaRepository});

  final VendaRepository vendaRepository;

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final _bairroController = TextEditingController();
  final _statuses = const [
    'todos',
    'pendente',
    'roteirizada',
    'saiu_entrega',
    'entregue',
    'reagendada',
    'cancelada',
  ];

  List<Venda> _entregas = [];
  String _statusSelecionado = 'todos';
  DateTime? _inicio;
  DateTime? _fim;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _inicio = DateTime(now.year, now.month, now.day);
    _fim = _inicio!.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    _carregarEntregas();
  }

  @override
  void dispose() {
    _bairroController.dispose();
    super.dispose();
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  String _rotuloStatusEntrega(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'roteirizada':
        return 'Roteirizada';
      case 'saiu_entrega':
        return 'Saiu para entrega';
      case 'entregue':
        return 'Entregue';
      case 'reagendada':
        return 'Reagendada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Nao aplicavel';
    }
  }

  String _rotuloStatusFiltro(String status) {
    if (status == 'todos') return 'Todos';
    return _rotuloStatusEntrega(status);
  }

  Color _corStatus(ColorScheme scheme, String status) {
    switch (status) {
      case 'entregue':
        return Colors.green.shade700;
      case 'saiu_entrega':
        return Colors.blue.shade700;
      case 'reagendada':
        return Colors.orange.shade700;
      case 'cancelada':
        return scheme.error;
      case 'roteirizada':
        return Colors.purple.shade700;
      case 'pendente':
      default:
        return scheme.primary;
    }
  }

  void _carregarEntregas() {
    setState(() {
      _entregas = widget.vendaRepository.listarEntregas(
        statusEntrega: _statusSelecionado,
        bairroTermo: _bairroController.text,
        inicio: _inicio,
        fim: _fim,
      );
    });
  }

  void _aplicarPeriodoRapido(String periodo) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    setState(() {
      if (periodo == 'hoje') {
        _inicio = todayStart;
        _fim = todayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      } else if (periodo == '7dias') {
        _inicio = todayStart.subtract(const Duration(days: 6));
        _fim = now;
      } else if (periodo == '30dias') {
        _inicio = todayStart.subtract(const Duration(days: 29));
        _fim = now;
      } else {
        _inicio = null;
        _fim = null;
      }
    });
    _carregarEntregas();
  }

  Future<void> _atualizarStatusEntrega(Venda venda, String novoStatus) async {
    try {
      widget.vendaRepository.atualizarStatusEntrega(venda.id, novoStatus);
      _carregarEntregas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status de entrega atualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Entregas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusSelecionado,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: _statuses
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s,
                                child: Text(_rotuloStatusFiltro(s)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _statusSelecionado = value);
                          _carregarEntregas();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _bairroController,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por bairro/endereco',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        onSubmitted: (_) => _carregarEntregas(),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _carregarEntregas,
                      child: const Text('Aplicar filtro'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('hoje'),
                      child: const Text('Hoje'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('7dias'),
                      child: const Text('7 dias'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('30dias'),
                      child: const Text('30 dias'),
                    ),
                    OutlinedButton(
                      onPressed: () => _aplicarPeriodoRapido('todos'),
                      child: const Text('Todos'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _entregas.isEmpty
                  ? const Center(child: Text('Nenhuma entrega encontrada para os filtros.'))
                  : ListView.builder(
                      itemCount: _entregas.length,
                      itemBuilder: (context, index) {
                        final venda = _entregas[index];
                        final statusCor = _corStatus(Theme.of(context).colorScheme, venda.statusEntrega);
                        return Card(
                          child: ListTile(
                            title: Text(
                              'Orcamento #${venda.numeroOrcamento} - ${_formatarMoeda(venda.total)}',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Cliente: ${venda.cliente.target?.nomeRazao ?? 'Sem cliente'}'),
                                Text('Endereco: ${venda.enderecoEntrega}'),
                                Text('Frete: ${_formatarMoeda(venda.valorFrete)}'),
                                Text('Criado em: ${dateFormat.format(venda.data)}'),
                                if (venda.observacaoEntrega.trim().isNotEmpty)
                                  Text('Obs: ${venda.observacaoEntrega}'),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(99),
                                    color: statusCor.withValues(alpha: 0.12),
                                    border: Border.all(color: statusCor.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    _rotuloStatusEntrega(venda.statusEntrega),
                                    style: TextStyle(color: statusCor, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (venda.statusEntrega != 'entregue')
                                  TextButton.icon(
                                    onPressed: () => _atualizarStatusEntrega(venda, 'entregue'),
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Marcar entregue'),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: 'Mais status',
                                  onSelected: (value) => _atualizarStatusEntrega(venda, value),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'pendente', child: Text('Pendente')),
                                    PopupMenuItem(value: 'roteirizada', child: Text('Roteirizada')),
                                    PopupMenuItem(value: 'saiu_entrega', child: Text('Saiu para entrega')),
                                    PopupMenuItem(value: 'entregue', child: Text('Entregue')),
                                    PopupMenuItem(value: 'reagendada', child: Text('Reagendada')),
                                    PopupMenuItem(value: 'cancelada', child: Text('Cancelada')),
                                  ],
                                ),
                              ],
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
