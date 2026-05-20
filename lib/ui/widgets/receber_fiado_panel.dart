import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/cliente.dart';
import '../../model/titulo_receber.dart';

/// Resultado de um recebimento registrado (para auditoria/recibo no caixa).
class RecebimentoFiadoResultado {
  const RecebimentoFiadoResultado({
    required this.recebimentoId,
    required this.valorTotal,
    required this.formaPagamento,
    required this.cliente,
  });

  final int recebimentoId;
  final double valorTotal;
  final String formaPagamento;
  final Cliente cliente;
}

/// Painel de quitação de fiado (reutilizado no Caixa e na página legada).
class ReceberFiadoPanel extends StatefulWidget {
  const ReceberFiadoPanel({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    this.onRecebimentoRegistrado,
    this.clienteInicial,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final ValueChanged<RecebimentoFiadoResultado>? onRecebimentoRegistrado;
  final Cliente? clienteInicial;

  @override
  State<ReceberFiadoPanel> createState() => _ReceberFiadoPanelState();
}

class _ReceberFiadoPanelState extends State<ReceberFiadoPanel> {
  static final _fmtData = DateFormat('dd/MM/yyyy');
  static final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  final _buscaController = TextEditingController();
  Cliente? _clienteSelecionado;
  List<TituloReceber> _titulos = [];

  @override
  void initState() {
    super.initState();
    if (widget.clienteInicial != null) {
      _clienteSelecionado = widget.clienteInicial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _carregarTitulos());
    }
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _carregarTitulos() {
    final id = _clienteSelecionado?.id;
    if (id == null || id <= 0) {
      setState(() => _titulos = []);
      return;
    }
    widget.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    setState(() {
      _titulos = widget.vendaRepository.titulos.listarAbertosPorCliente(id);
    });
  }

  Future<void> _buscarCliente() async {
    final termo = _buscaController.text.trim();
    if (termo.isEmpty) return;
    final lista = widget.clienteRepository.pesquisar(termo);
    if (!mounted) return;
    if (lista.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum cliente encontrado.')),
      );
      return;
    }
    Cliente? escolhido;
    if (lista.length == 1) {
      escolhido = lista.first;
    } else {
      escolhido = await showDialog<Cliente>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Selecione o cliente'),
          children: lista
              .map(
                (c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text('${c.nomeRazao} · ${c.documento}'),
                ),
              )
              .toList(),
        ),
      );
    }
    if (escolhido == null) return;
    setState(() => _clienteSelecionado = escolhido);
    _carregarTitulos();
  }

  void _notificarRecebimento({
    required int recebimentoId,
    required double valor,
    required String forma,
  }) {
    final cliente = _clienteSelecionado;
    if (cliente == null || widget.onRecebimentoRegistrado == null) return;
    widget.onRecebimentoRegistrado!(
      RecebimentoFiadoResultado(
        recebimentoId: recebimentoId,
        valorTotal: valor,
        formaPagamento: forma,
        cliente: cliente,
      ),
    );
  }

  Future<void> _receberTitulo(TituloReceber titulo) async {
    final valorController = TextEditingController(
      text: titulo.saldo.toStringAsFixed(2).replaceAll('.', ','),
    );
    var forma = 'dinheiro';
    final obsController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            'Receber parcela ${titulo.numeroParcela}/${titulo.totalParcelas}',
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Saldo: ${_fmtMoeda.format(titulo.saldo)}'),
                Text(
                  'Vencimento: ${_fmtData.format(titulo.vencimento.toLocal())}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorController,
                  decoration: const InputDecoration(labelText: 'Valor recebido'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: forma,
                  decoration: const InputDecoration(labelText: 'Forma de pagamento'),
                  items: const [
                    DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                    DropdownMenuItem(value: 'pix', child: Text('PIX')),
                    DropdownMenuItem(
                      value: 'cartao_debito',
                      child: Text('Cartão débito'),
                    ),
                    DropdownMenuItem(
                      value: 'cartao_credito',
                      child: Text('Cartão crédito'),
                    ),
                    DropdownMenuItem(
                      value: 'transferencia',
                      child: Text('Transferência'),
                    ),
                  ],
                  onChanged: (v) => setDlg(() => forma = v ?? 'dinheiro'),
                ),
                TextField(
                  controller: obsController,
                  decoration: const InputDecoration(labelText: 'Observação (opcional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final valor = double.tryParse(
          valorController.text.replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0;
    try {
      final id = widget.vendaRepository.recebimentos.registrarRecebimentoTitulo(
        tituloId: titulo.id,
        valorRecebido: valor,
        formaPagamento: forma,
        observacao: obsController.text,
      );
      final rec = widget.vendaRepository.recebimentos.obterPorId(id);
      final valorEfetivo = rec?.valorTotal ?? valor;
      _notificarRecebimento(
        recebimentoId: id,
        valor: valorEfetivo,
        forma: forma,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recebimento registrado: ${_fmtMoeda.format(valor)}')),
      );
      _carregarTitulos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _receberFifo() async {
    if (_clienteSelecionado == null) return;
    final valorController = TextEditingController();
    var forma = 'dinheiro';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Receber valor (FIFO)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'O valor será aplicado nas parcelas mais antigas em aberto.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valorController,
                decoration: const InputDecoration(labelText: 'Valor recebido'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              DropdownButtonFormField<String>(
                initialValue: forma,
                decoration: const InputDecoration(labelText: 'Forma de pagamento'),
                items: const [
                  DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                  DropdownMenuItem(value: 'pix', child: Text('PIX')),
                  DropdownMenuItem(
                    value: 'cartao_debito',
                    child: Text('Cartão débito'),
                  ),
                  DropdownMenuItem(
                    value: 'cartao_credito',
                    child: Text('Cartão crédito'),
                  ),
                  DropdownMenuItem(
                    value: 'transferencia',
                    child: Text('Transferência'),
                  ),
                ],
                onChanged: (v) => setDlg(() => forma = v ?? 'dinheiro'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final valor = double.tryParse(
          valorController.text.replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0;
    try {
      final id = widget.vendaRepository.recebimentos.registrarRecebimentoFifo(
        clienteId: _clienteSelecionado!.id,
        valorRecebido: valor,
        formaPagamento: forma,
      );
      final rec = widget.vendaRepository.recebimentos.obterPorId(id);
      final valorEfetivo = rec?.valorTotal ?? valor;
      _notificarRecebimento(
        recebimentoId: id,
        valor: valorEfetivo,
        forma: forma,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recebimento registrado: ${_fmtMoeda.format(valorEfetivo)}',
          ),
        ),
      );
      _carregarTitulos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saldoTotal = _titulos.fold<double>(0, (s, t) => s + t.saldo);
    final cliente = _clienteSelecionado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _buscaController,
                decoration: const InputDecoration(
                  labelText: 'Cliente (nome, CPF/CNPJ)',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _buscarCliente(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _buscarCliente,
              child: const Text('Buscar'),
            ),
          ],
        ),
        if (cliente != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  cliente.nomeRazao,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                'Saldo: ${_fmtMoeda.format(saldoTotal)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _titulos.isEmpty ? null : _receberFifo,
                child: const Text('Receber valor'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _titulos.isEmpty
              ? Center(
                  child: Text(
                    cliente == null
                        ? 'Busque um cliente para ver parcelas em aberto.'
                        : 'Nenhum título em aberto.',
                  ),
                )
              : ListView.builder(
                  itemCount: _titulos.length,
                  itemBuilder: (context, i) {
                    final t = _titulos[i];
                    t.venda.target;
                    final venda = t.venda.target;
                    final vencido = t.vencido;
                    return ListTile(
                      title: Text(
                        'Venda ${venda?.numeroOrcamento ?? '-'} · '
                        'Parc. ${t.numeroParcela}/${t.totalParcelas}',
                      ),
                      subtitle: Text(
                        'Venc.: ${_fmtData.format(t.vencimento.toLocal())} · '
                        'Saldo: ${_fmtMoeda.format(t.saldo)}',
                      ),
                      trailing: FilledButton(
                        onPressed: () => _receberTitulo(t),
                        child: const Text('Receber'),
                      ),
                      tileColor: vencido
                          ? Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.35)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
