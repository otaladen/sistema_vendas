import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/venda_repository.dart';
import '../domain/pagamento_orcamento.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'clientes_page.dart';
import 'registrar_devolucao_troca_page.dart';

/// Lista vendas já finalizadas no Caixa (`status == finalizada`), com filtros e busca.
class ListagemVendasPage extends StatefulWidget {
  const ListagemVendasPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
    required this.produtoRepository,
    required this.usuarioAtual,
    required this.podeCancelarVendas,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;
  final ProdutoRepository produtoRepository;
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

  double _parseValorMonetario(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return 0;
    return double.tryParse(normalizado) ?? 0;
  }

  bool _podeRegistrarDevolucaoTroca(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    if (v.vendaOrigemFreteRetiradaId > 0) return false;
    return v.itens.any((i) => i.quantidade - i.quantidadeDevolvida > 0);
  }

  Future<void> _abrirRegistrarDevolucaoTroca(Venda v) async {
    if (!_podeRegistrarDevolucaoTroca(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Devolucao/troca nao disponivel para esta venda.',
          ),
        ),
      );
      return;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegistrarDevolucaoTrocaPage(
          vendaRepository: widget.vendaRepository,
          produtoRepository: widget.produtoRepository,
          vendaId: v.id,
          usuarioAtual: widget.usuarioAtual,
          podeRegistrarSemSenha: widget.podeCancelarVendas,
        ),
      ),
    );
    if (ok == true && mounted) {
      _pesquisar();
    }
  }

  bool _podePagarFreteCarreto(Venda v) {
    if (v.cancelada || v.status != 'finalizada') return false;
    if (v.tipoEntrega != 'retirada_futura' || !v.entregaPendente) return false;
    if (v.idOrcamentoFreteRetiradaAberto != 0) return false;
    return v.itens.any((i) => i.quantidadePendenteRetirada > 0);
  }

  String _montarEnderecoEntregaClienteListagem(Cliente cliente) {
    final partes = <String>[];
    final endereco = cliente.endereco.trim();
    final numero = cliente.numero.trim();
    final bairro = cliente.bairro.trim();
    final cidade = cliente.cidade.trim();
    final uf = cliente.uf.trim();
    final cep = cliente.cep.trim();
    if (endereco.isNotEmpty) {
      partes.add(numero.isNotEmpty ? '$endereco, $numero' : endereco);
    }
    if (bairro.isNotEmpty) {
      partes.add(bairro);
    }
    final cidadeUf = [cidade, uf].where((p) => p.isNotEmpty).join(' - ');
    if (cidadeUf.isNotEmpty) {
      partes.add(cidadeUf);
    }
    if (cep.isNotEmpty) {
      partes.add('CEP: $cep');
    }
    return partes.join(' | ');
  }

  Future<void> _abrirPagarFreteCarreto(Venda vIn) async {
    var v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!_podePagarFreteCarreto(v)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao e possivel gerar frete agora (verifique retirada futura, pendencia e se ja existe orcamento de frete).',
          ),
        ),
      );
      return;
    }

    if (_clienteDaVenda(v) == null) {
      if (!mounted) return;
      final c = await Navigator.push<Cliente>(
        context,
        MaterialPageRoute(
          builder: (_) => ClientesPage(
            clienteRepository: widget.clienteRepository,
            vendaRepository: widget.vendaRepository,
            retornarClienteAoSalvar: true,
          ),
        ),
      );
      if (!mounted || c == null) return;
      widget.vendaRepository.vincularClienteVendaFinalizada(v.id, c.id);
      v = widget.vendaRepository.obterPorId(v.id) ?? v;
    }

    final cliente = _clienteDaVenda(v);
    if (cliente == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre e vincule o cliente primeiro.')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DialogoFreteCarretoRetiradaFutura(
          vendaMae: v,
          cliente: cliente,
          enderecoInicial: _montarEnderecoEntregaClienteListagem(cliente),
          observacaoInicial: cliente.referencia.trim(),
          vendaRepository: widget.vendaRepository,
          formatarMoeda: _formatarMoeda,
          parseValor: _parseValorMonetario,
          onSucesso: () {
            _pesquisar();
          },
        );
      },
    );
  }

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
        return 'Carreto';
      case 'retirada_futura':
        return 'Retirada futura';
      case 'retirada':
      default:
        return 'Leva Agora';
    }
  }

  String _linhaRetiradaFutura(Venda v) {
    if (!v.entregaPendente) {
      return 'Retirada futura: Nao';
    }
    final unidades = v.itens.fold<int>(
      0,
      (a, i) => a + i.quantidadePendenteRetirada,
    );
    return 'Retirada futura: Pendente ($unidades un. a retirar)';
  }

  Future<void> _abrirRegistrarRetirada(Venda v) async {
    final atual = widget.vendaRepository.obterPorId(v.id);
    if (atual == null || atual.cancelada || !atual.entregaPendente) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'So e possivel registrar retirada em vendas com retirada futura pendente.',
          ),
        ),
      );
      return;
    }
    if (!atual.itens.any((i) => i.quantidadePendenteRetirada > 0)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha quantidade pendente de retirada nesta venda.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogRetiradaFutura(
        venda: atual,
        vendaRepository: widget.vendaRepository,
        usuario: widget.usuarioAtual,
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retirada registrada.')),
      );
      _pesquisar();
    }
  }

  /// Observacao de entrega (log com data/operador) ou itens com retirada ja registrada.
  bool _temRegistroRetiradaOuEntrega(Venda v) {
    if (v.observacaoEntrega.trim().isNotEmpty) return true;
    return v.itens.any((i) => i.quantidadeJaRetirada > 0);
  }

  Future<void> _mostrarHistoricoRetirada(Venda v) async {
    final atual = widget.vendaRepository.obterPorId(v.id) ?? v;
    final linhas = <String>[];
    if (atual.observacaoEntrega.trim().isNotEmpty) {
      linhas.add(atual.observacaoEntrega.trim());
    }
    final comRetirada =
        atual.itens.where((i) => i.quantidadeJaRetirada > 0).toList();
    if (comRetirada.isNotEmpty) {
      if (linhas.isNotEmpty) linhas.add('');
      linhas.add('Resumo — ja retirado por item:');
      for (final i in comRetirada) {
        linhas.add('- ${i.nomeProduto}: ${i.quantidadeJaRetirada} un.');
      }
    }
    final texto = linhas.isEmpty
        ? 'Nenhum registro de retirada ou texto de entrega nesta venda.'
        : linhas.join('\n');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Historico de retiradas e entrega'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(texto),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
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
                              if (v != null) {
                                setState(() => _formaPagamento = v);
                              }
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
                                child: Text('Leva Agora'),
                              ),
                              DropdownMenuItem(
                                value: 'retirada_futura',
                                child: Text('Retirada futura'),
                              ),
                              DropdownMenuItem(
                                value: 'entrega_loja',
                                child: Text('Carreto'),
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
                              if (v != null) {
                                setState(() => _entregaPendente = v);
                              }
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
                                  '${_linhaRetiradaFutura(v)} | '
                                  'Itens: ${v.itens.length}',
                                ),
                                if (!v.cancelada &&
                                    v.status == 'finalizada' &&
                                    (widget.vendaRepository
                                                .valorReferenciaDevolvidoAcumuladoVenda(
                                                  v.id,
                                                ) >
                                                0.005 ||
                                        widget.vendaRepository
                                                .valorSaidaTrocaAcumuladoVenda(
                                                  v.id,
                                                ) >
                                                0.005))
                                  Text(
                                    () {
                                      final dev = widget.vendaRepository
                                          .valorReferenciaDevolvidoAcumuladoVenda(
                                            v.id,
                                          );
                                      final troca = widget.vendaRepository
                                          .valorSaidaTrocaAcumuladoVenda(v.id);
                                      final liq = troca - dev;
                                      return 'Devolucao/troca acum.: devolvido '
                                          '${_formatarMoeda(dev)} · saida troca '
                                          '${_formatarMoeda(troca)} · liquido '
                                          '${_formatarMoeda(liq)}';
                                    }(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                if (v.idOrcamentoFreteRetiradaAberto != 0)
                                  Text(
                                    () {
                                      final filho = widget.vendaRepository
                                          .obterPorId(
                                        v.idOrcamentoFreteRetiradaAberto,
                                      );
                                      final n = filho?.numeroOrcamento ?? 0;
                                      final rot =
                                          n > 0 ? '#$n' : '(id ${filho?.id})';
                                      return 'Frete carreto: orcamento pendente no caixa $rot.';
                                    }(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .tertiary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                if (_temRegistroRetiradaOuEntrega(v))
                                  Text(
                                    'Rastreio: data e operador no log — menu Historico de retiradas.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
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
                                      if (value == 'historico') {
                                        _mostrarHistoricoRetirada(v);
                                      } else if (value == 'retirada') {
                                        _abrirRegistrarRetirada(v);
                                      } else if (value == 'pagar_frete') {
                                        _abrirPagarFreteCarreto(v);
                                      } else if (value == 'devolucao') {
                                        _abrirRegistrarDevolucaoTroca(v);
                                      } else if (value == 'cancelar') {
                                        _cancelarVenda(v);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (_podePagarFreteCarreto(v))
                                        const PopupMenuItem<String>(
                                          value: 'pagar_frete',
                                          child: Text('Pagar frete (carreto)'),
                                        ),
                                      if (v.entregaPendente && !v.cancelada)
                                        const PopupMenuItem<String>(
                                          value: 'retirada',
                                          child: Text('Registrar retirada'),
                                        ),
                                      if (_temRegistroRetiradaOuEntrega(v))
                                        const PopupMenuItem<String>(
                                          value: 'historico',
                                          child: Text(
                                            'Historico de retiradas',
                                          ),
                                        ),
                                      if (_podeRegistrarDevolucaoTroca(v))
                                        const PopupMenuItem<String>(
                                          value: 'devolucao',
                                          child: Text('Devolucao / troca'),
                                        ),
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

class _DialogoFreteCarretoRetiradaFutura extends StatefulWidget {
  const _DialogoFreteCarretoRetiradaFutura({
    required this.vendaMae,
    required this.cliente,
    required this.enderecoInicial,
    required this.observacaoInicial,
    required this.vendaRepository,
    required this.formatarMoeda,
    required this.parseValor,
    required this.onSucesso,
  });

  final Venda vendaMae;
  final Cliente cliente;
  final String enderecoInicial;
  final String observacaoInicial;
  final VendaRepository vendaRepository;
  final String Function(double) formatarMoeda;
  final double Function(String) parseValor;
  final VoidCallback onSucesso;

  @override
  State<_DialogoFreteCarretoRetiradaFutura> createState() =>
      _DialogoFreteCarretoRetiradaFuturaState();
}

class _DialogoFreteCarretoRetiradaFuturaState
    extends State<_DialogoFreteCarretoRetiradaFutura> {
  late final TextEditingController _endereco;
  late final TextEditingController _obs;
  late final TextEditingController _frete;
  String _prioridade = 'normal';
  String _janela = 'nao_definida';
  DateTime? _dataEntrega;

  @override
  void initState() {
    super.initState();
    _endereco = TextEditingController(text: widget.enderecoInicial);
    _obs = TextEditingController(text: widget.observacaoInicial);
    _frete = TextEditingController();
    _dataEntrega = DateTime.now();
  }

  @override
  void dispose() {
    _endereco.dispose();
    _obs.dispose();
    _frete.dispose();
    super.dispose();
  }

  Future<void> _gerar() async {
    final vf = widget.parseValor(_frete.text);
    if (_endereco.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o endereco de entrega.')),
      );
      return;
    }
    if (_prioridade == 'agendada' && _janela == 'nao_definida') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para entrega agendada, selecione janela Manha ou Tarde.',
          ),
        ),
      );
      return;
    }
    if (_dataEntrega == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Defina a data da entrega.')),
      );
      return;
    }

    if (vf <= 0) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Frete zerado'),
          content: const Text(
            'Confirmar orcamento de carreto com frete gratuito?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nao'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Frete gratuito'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      final pagamento = DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      );
      final idFilho = widget.vendaRepository.registrarOrcamentoFreteRetiradaFutura(
        vendaMaeId: widget.vendaMae.id,
        valorFreteCobrado: vf,
        pagamento: pagamento,
        enderecoEntrega: _endereco.text.trim(),
        observacaoEntrega: _obs.text.trim(),
        prioridadeEntrega: _prioridade,
        janelaEntrega: _janela,
        dataEntregaMarcada: _dataEntrega!,
        vendedorId: widget.vendaMae.vendedor.targetId == 0
            ? null
            : widget.vendaMae.vendedor.targetId,
      );
      await LanSyncScheduler.solicitarSyncImediato();
      if (!mounted) return;
      final filho = widget.vendaRepository.obterPorId(idFilho);
      final n = filho?.numeroOrcamento ?? 0;
      Navigator.of(context).pop();
      widget.onSucesso();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Orcamento de frete ${n > 0 ? '#$n' : '#$idFilho'} gerado. Finalize no Caixa.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref =
        widget.vendaMae.numeroOrcamento > 0
            ? '${widget.vendaMae.numeroOrcamento}'
            : '${widget.vendaMae.id}';
    return AlertDialog(
      title: Text('Frete carreto — ref. venda #$ref'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cliente: ${widget.cliente.nomeRazao}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _frete,
                decoration: const InputDecoration(
                  labelText: 'Valor do frete (R\$)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _endereco,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Endereco de entrega',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _obs,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observacoes da entrega',
                ),
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Prioridade da entrega',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _prioridade,
                    items: const [
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                      DropdownMenuItem(
                        value: 'agendada',
                        child: Text('Agendada'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _prioridade = v ?? 'normal';
                      if (_prioridade == 'agendada') {
                        if (_janela == 'nao_definida') {
                          _janela = 'manha';
                        }
                      } else {
                        _janela = 'nao_definida';
                      }
                    }),
                  ),
                ),
              ),
              if (_prioridade == 'agendada') ...[
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Janela',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _janela,
                      items: const [
                        DropdownMenuItem(
                          value: 'manha',
                          child: Text('Manha'),
                        ),
                        DropdownMenuItem(
                          value: 'tarde',
                          child: Text('Tarde'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _janela = v ?? 'manha'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final agora = DateTime.now();
                  final inicial = _dataEntrega ?? agora;
                  final escolhido = await showDatePicker(
                    context: context,
                    initialDate: inicial,
                    firstDate: DateTime(agora.year, agora.month, agora.day),
                    lastDate: DateTime(agora.year + 3, 12, 31),
                  );
                  if (!mounted || escolhido == null) return;
                  setState(() => _dataEntrega = escolhido);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _dataEntrega == null
                      ? 'Definir data da entrega'
                      : 'Data: ${_dataEntrega!.day.toString().padLeft(2, '0')}/'
                          '${_dataEntrega!.month.toString().padLeft(2, '0')}/'
                          '${_dataEntrega!.year}',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O total da venda #$ref nao e alterado; o frete entra em orcamento separado '
                'para pagamento no caixa. Ao pagar, a venda mae vira carreto e aparece em Entregas.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _gerar,
          child: const Text('Gerar orcamento de frete'),
        ),
      ],
    );
  }
}

class _DialogRetiradaFutura extends StatefulWidget {
  const _DialogRetiradaFutura({
    required this.venda,
    required this.vendaRepository,
    required this.usuario,
  });

  final Venda venda;
  final VendaRepository vendaRepository;
  final String usuario;

  @override
  State<_DialogRetiradaFutura> createState() => _DialogRetiradaFuturaState();
}

class _DialogRetiradaFuturaState extends State<_DialogRetiradaFutura> {
  late final Map<int, TextEditingController> _controllers;
  late final TextEditingController _quemRetirouController;

  @override
  void initState() {
    super.initState();
    _quemRetirouController = TextEditingController();
    _controllers = {
      for (final it in widget.venda.itens)
        it.id: TextEditingController(text: ''),
    };
  }

  @override
  void dispose() {
    _quemRetirouController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _preencherTudo() {
    for (final it in widget.venda.itens) {
      final c = _controllers[it.id];
      if (c != null && it.quantidadePendenteRetirada > 0) {
        c.text = '${it.quantidadePendenteRetirada}';
      }
    }
    setState(() {});
  }

  Future<void> _confirmar() async {
    final map = <int, int>{};
    for (final it in widget.venda.itens) {
      final c = _controllers[it.id];
      if (c == null) continue;
      final q = int.tryParse(c.text.trim()) ?? 0;
      if (q > 0) {
        map[it.id] = q;
      }
    }
    if (map.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos uma quantidade maior que zero.'),
        ),
      );
      return;
    }
    try {
      final quem = _quemRetirouController.text.trim();
      widget.vendaRepository.registrarRetiradaParcial(
        widget.venda.id,
        map,
        usuario: widget.usuario,
        retiradoPor: quem.isEmpty ? null : quem,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel registrar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Registrar retirada'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Informe quantas unidades o cliente esta retirando agora '
                '(parcial ou total).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _quemRetirouController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Quem retirou (opcional)',
                  hintText: 'Nome de quem leva a mercadoria',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              for (final it in widget.venda.itens)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.nomeProduto,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Pendente: ${it.quantidadePendenteRetirada} un.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _controllers[it.id],
                          enabled: it.quantidadePendenteRetirada > 0,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'Qtd',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _preencherTudo,
          child: const Text('Retirar tudo'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
