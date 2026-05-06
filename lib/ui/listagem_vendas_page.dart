import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/cliente_repository.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import '../domain/pagamento_orcamento.dart';
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
    required this.usuarioAtual,
    required this.podeCancelarVendas,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;
  final String usuarioAtual;
  final bool podeCancelarVendas;

  @override
  State<ListagemVendasPage> createState() => _ListagemVendasPageState();
}

class _ListagemVendasPageState extends State<ListagemVendasPage> {
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  final _buscaController = TextEditingController();
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  String _periodoPreset = 'ultimos_30';
  String _formaPagamento = 'todos';
  String _tipoEntrega = 'todos';
  String _entregaPendente = 'todos';
  String _filtroCancelamento = 'ativas';
  String _canceladaPorFiltro = 'todos';
  int? _clienteIdFiltro;
  int? _vendedorIdFiltro;

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

  /// Numero da venda no cupom; se nao houver sequencial, cai no ID interno (caso raro).
  String _rotuloVendaUsuario(Venda v) {
    if (v.numeroOrcamento > 0) return 'Venda #${v.numeroOrcamento}';
    return 'Venda ${v.id}';
  }

  String _badgeNumeroVenda(Venda v) {
    if (v.numeroOrcamento > 0) return '#${v.numeroOrcamento}';
    return '${v.id}';
  }

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
        return 'Dinheiro';
      case 'misto':
        return 'Pagamento misto';
      default:
        return 'Dinheiro';
    }
  }

  String _rotuloPagamentoLinhaLista(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return '${_rotuloFormaPagamento(v.formaPagamento)}'
          '${v.formaPagamento == 'cartao_credito' ? ' ${v.quantidadeParcelas}x' : ''}';
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    return linhas
        .map(
          (l) =>
              '${_rotuloFormaPagamento(l.meio)} ${_formatarMoeda(l.valor)}'
              '${l.meio == 'cartao_credito' ? ' ${l.parcelas}x' : ''}',
        )
        .join(' | ');
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

    if (_filtroCancelamento == 'ativas') {
      it = it.where((v) => !v.cancelada);
    } else if (_filtroCancelamento == 'canceladas') {
      it = it.where((v) => v.cancelada);
    }
    if (_canceladaPorFiltro != 'todos') {
      final usuarioFiltro = _canceladaPorFiltro.trim().toLowerCase();
      it = it.where(
        (v) => v.cancelada && v.canceladaPor.trim().toLowerCase() == usuarioFiltro,
      );
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

    final lista = it.toList()
      ..sort((a, b) {
        if (_filtroCancelamento == 'canceladas') {
          final aCanceladaEm = a.canceladaEm ?? a.data;
          final bCanceladaEm = b.canceladaEm ?? b.data;
          return bCanceladaEm.compareTo(aCanceladaEm);
        }
        return b.data.compareTo(a.data);
      });

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
      _filtroCancelamento = 'ativas';
      _canceladaPorFiltro = 'todos';
      _clienteIdFiltro = null;
      _vendedorIdFiltro = null;
      _buscaController.clear();
    });
    _pesquisar();
  }

  String _csvEscape(String texto) => '"${texto.replaceAll('"', '""')}"';

  Future<void> _exportarCancelamentosCsv() async {
    final canceladas = _resultados.where((v) => v.cancelada).toList();
    if (canceladas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha vendas canceladas para exportar.')),
      );
      return;
    }
    final linhas = <String>[
      'venda_id,numero_venda,data_venda,cancelada_em,cancelada_por,motivo,total',
      ...canceladas.map((v) {
        final dataVenda = DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal());
        final canceladaEm = v.canceladaEm == null
            ? ''
            : DateFormat('dd/MM/yyyy HH:mm').format(v.canceladaEm!.toLocal());
        return [
          v.id.toString(),
          v.numeroOrcamento.toString(),
          _csvEscape(dataVenda),
          _csvEscape(canceladaEm),
          _csvEscape(v.canceladaPor.trim().isEmpty ? 'Nao informado' : v.canceladaPor),
          _csvEscape(v.motivoCancelamento),
          v.total.toStringAsFixed(2).replaceAll('.', ','),
        ].join(',');
      }),
    ];
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio de cancelamentos',
      fileName: 'cancelamentos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (selectedPath == null) return;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.csv')
        ? selectedPath
        : '$selectedPath.csv';
    final file = File(normalizedPath);
    await file.writeAsString(linhas.join('\n'), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Relatorio salvo em: $normalizedPath')),
    );
  }

  Future<Uint8List> _gerarCancelamentosPdfBytes(List<Venda> canceladas) async {
    final doc = pw.Document();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final totalCancelado = canceladas.fold<double>(0, (acc, v) => acc + v.total);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return [
            pw.Text(
              'Relatorio de Cancelamentos',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Gerado em: ${fmt.format(DateTime.now())}'),
            pw.Text('Quantidade: ${canceladas.length}'),
            pw.Text(
              'Total cancelado: ${_formatarMoeda(totalCancelado)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            ...canceladas.map((v) {
              final emVenda = fmt.format(v.data.toLocal());
              final emCancelada = v.canceladaEm == null
                  ? 'Nao informado'
                  : fmt.format(v.canceladaEm!.toLocal());
              final por = v.canceladaPor.trim().isEmpty
                  ? 'Nao informado'
                  : v.canceladaPor.trim();
              final motivo = v.motivoCancelamento.trim().isEmpty
                  ? 'Nao informado'
                  : v.motivoCancelamento.trim();
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _rotuloVendaUsuario(v),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('Data venda: $emVenda'),
                    pw.Text('Cancelada em: $emCancelada'),
                    pw.Text('Cancelada por: $por'),
                    pw.Text('Motivo: $motivo'),
                    pw.Text('Total: ${_formatarMoeda(v.total)}'),
                  ],
                ),
              );
            }),
          ];
        },
      ),
    );
    return doc.save();
  }

  Future<void> _exportarCancelamentosPdf() async {
    final canceladas = _resultados.where((v) => v.cancelada).toList();
    if (canceladas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha vendas canceladas para exportar.')),
      );
      return;
    }
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Relatorio de cancelamentos'),
          content: const Text('Deseja imprimir ou salvar em PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'salvar'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Salvar PDF'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    final pdfBytes = await _gerarCancelamentosPdfBytes(canceladas);
    if (acao == 'imprimir') {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
      return;
    }
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar relatorio de cancelamentos (PDF)',
      fileName:
          'cancelamentos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) return;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    await File(normalizedPath).writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Relatorio PDF salvo em: $normalizedPath')),
    );
  }

  Future<(bool autorizado, String usuarioAutorizador)>
  _autorizarCancelamento() async {
    if (widget.podeCancelarVendas) {
      return (true, widget.usuarioAtual);
    }
    final loginController = TextEditingController();
    final senhaController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Autorizacao para cancelamento'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Informe usuario com permissao (admin/financeiro/manutencao de caixa).',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: loginController,
                  decoration: const InputDecoration(labelText: 'Login'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: senhaController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Autorizar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      loginController.dispose();
      senhaController.dispose();
      return (false, '');
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final usuario = await _usuarioRepository.autenticar(login, senha);
    final autorizado = usuario != null &&
        usuario.ativo &&
        (usuario.admin ||
            usuario.podeFinanceiro ||
            usuario.podeManutencaoAuditoriaCaixa);
    if (!autorizado) {
      return (false, '');
    }
    return (true, usuario.login);
  }

  Future<void> _cancelarVenda(Venda venda) async {
    if (venda.cancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda ja esta cancelada.')),
      );
      return;
    }
    final autorizado = await _autorizarCancelamento();
    if (!mounted || !autorizado.$1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelamento nao autorizado.')),
        );
      }
      return;
    }
    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cancelamento'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cancelar ${_rotuloVendaUsuario(venda)}?',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: motivoController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar cancelamento'),
            ),
          ],
        );
      },
    );
    final motivo = motivoController.text.trim();
    motivoController.dispose();
    if (confirmar != true) return;
    try {
      widget.vendaRepository.cancelarVenda(
        venda.id,
        motivo: motivo,
        canceladaPor: autorizado.$2,
      );
      _pesquisar();
      if (!mounted) return;
      final sufixoMotivo = motivo.isEmpty ? '' : ' Motivo: $motivo';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_rotuloVendaUsuario(venda)} cancelada por ${autorizado.$2}.$sufixoMotivo',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel cancelar venda: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientes = widget.clienteRepository
        .listarTodos()
        .where((c) => c.ativo)
        .toList();
    final vendedores = widget.vendedorRepository.listarAtivos();
    final usuariosCancelamento = widget.vendaRepository
        .listarTodas()
        .where((v) => v.cancelada && v.canceladaPor.trim().isNotEmpty)
        .map((v) => v.canceladaPor.trim())
        .toSet()
        .toList()
      ..sort();

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
                            isExpanded: true,
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
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: _canceladaPorFiltro,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cancelada por',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'todos',
                                child: Text('Todos'),
                              ),
                              ...usuariosCancelamento.map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    u,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _canceladaPorFiltro = v);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: _formaPagamento,
                            isExpanded: true,
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
                                'misto',
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
                            isExpanded: true,
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
                            isExpanded: true,
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
                            isExpanded: true,
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
                            isExpanded: true,
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
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: _filtroCancelamento,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Cancelamento',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'ativas',
                                child: Text('Nao canceladas'),
                              ),
                              DropdownMenuItem(
                                value: 'canceladas',
                                child: Text('Somente canceladas'),
                              ),
                              DropdownMenuItem(
                                value: 'todas',
                                child: Text('Todas'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _filtroCancelamento = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 860,
                          child: TextField(
                            controller: _buscaController,
                            decoration: const InputDecoration(
                              labelText: 'Pesquisar venda',
                              hintText:
                                  'Numero da venda, ID, cliente, vendedor (nome/codigo) ou produto',
                              prefixIcon: Icon(Icons.search),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _pesquisar(),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _pesquisar,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text('Pesquisar'),
                        ),
                        OutlinedButton(
                          onPressed: _limparFiltros,
                          child: const Text('Limpar'),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'csv') {
                              _exportarCancelamentosCsv();
                            } else if (value == 'pdf') {
                              _exportarCancelamentosPdf();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'csv',
                              child: Text('Exportar CSV'),
                            ),
                            PopupMenuItem<String>(
                              value: 'pdf',
                              child: Text('Exportar/Imprimir PDF'),
                            ),
                          ],
                          child: OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Exportar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_resultados.length} venda(s) encontrada(s)',
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
                                _badgeNumeroVenda(v),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            title: Text(
                              '${_rotuloVendaUsuario(v)}'
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
                                  '${_rotuloPagamentoLinhaLista(v)}',
                                ),
                                Text(
                                  '${_rotuloTipoEntrega(v.tipoEntrega)} | '
                                  'Retirada futura: ${v.entregaPendente ? 'Sim' : 'Nao'} | '
                                  'Itens: ${v.itens.length}',
                                ),
                                if (v.cancelada)
                                  Text(
                                    'Cancelada por: ${v.canceladaPor.isEmpty ? 'Nao informado' : v.canceladaPor}'
                                    '${v.canceladaEm == null ? '' : ' | Em: ${_dataHora.format(v.canceladaEm!.toLocal())}'}'
                                    '${v.motivoCancelamento.isEmpty ? '' : ' | Motivo: ${v.motivoCancelamento}'}',
                                  ),
                              ],
                            ),
                            trailing: SizedBox(
                              width: 154,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatarMoeda(v.total),
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Acoes',
                                    onSelected: (value) {
                                      if (value == 'cancelar') {
                                        _cancelarVenda(v);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: 'cancelar',
                                        enabled: !v.cancelada,
                                        child: const Text('Cancelar venda'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
