import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../data/caixa_auditoria_repository.dart';
import '../../data/objectbox.dart';
import '../../domain/extrato_sessao_caixa.dart';
import '../../domain/sessao_caixa_referencia.dart';
import '../../services/configuracoes_service.dart';
import '../../services/extrato_sessao_caixa_pdf.dart';
import '../../services/print_service.dart';

/// Visualizacao e impressao do extrato detalhado de uma sessao de caixa.
class ExtratoSessaoCaixaPage extends StatefulWidget {
  const ExtratoSessaoCaixaPage({
    super.key,
    required this.sessao,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.configuracoesService,
    required this.printService,
    this.objectBox,
    this.lanApiClient,
  });

  final SessaoCaixaReferencia sessao;
  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final ConfiguracoesService configuracoesService;
  final PrintService printService;
  final ObjectBox? objectBox;
  final dynamic lanApiClient;

  @override
  State<ExtratoSessaoCaixaPage> createState() => _ExtratoSessaoCaixaPageState();
}

class _ExtratoSessaoCaixaPageState extends State<ExtratoSessaoCaixaPage> {
  final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');
  final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  ExtratoSessaoCaixaDados? _dados;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    unawaited(_montar());
  }

  Future<void> _montar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      List<CaixaAuditoriaRegistro> auditoria;
      if (widget.lanApiClient != null &&
          (widget.lanApiClient.configurado == true)) {
        final raw = await widget.lanApiClient.listarAuditoriaCaixa(limit: 800);
        auditoria = raw.map(CaixaAuditoriaRegistro.fromMap).toList();
      } else {
        auditoria =
            await CaixaAuditoriaRepository(db: widget.objectBox).listarTodos();
      }
      final dados = ExtratoSessaoCaixaMontador.montar(
        sessao: widget.sessao,
        vendaRepository: widget.vendaRepository,
        auditoria: auditoria,
        nomeCliente: (id) {
          if (id <= 0) return '';
          try {
            final c = widget.clienteRepository.obterPorId(id);
            return (c?.nomeRazao ?? '').toString();
          } catch (_) {
            return '';
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _dados = dados;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  Future<void> _imprimirOuSalvar({required bool termico, required String acao}) async {
    final dados = _dados;
    if (dados == null) return;
    final config = await widget.configuracoesService.carregarEfetiva();
    final bytes = await ExtratoSessaoCaixaPdf.gerarBytes(
      dados: dados,
      config: config,
      termico80mm: termico,
    );
    if (!mounted) return;
    if (acao == 'visualizar') {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      return;
    }
    if (acao == 'direto') {
      final printer = await widget.printService
          .resolverImpressoraPorNome(config.impressoraPadrao);
      if (!mounted) return;
      if (printer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impressora padrao nao configurada.')),
        );
        return;
      }
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        name: 'extrato_sessao_${widget.sessao.numero}',
        format: termico ? PdfPageFormat.roll80 : PdfPageFormat.a4,
      );
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar extrato PDF',
      fileName:
          'extrato_sessao_caixa_${widget.sessao.numero}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (path != null) {
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Salvo em: $path')),
      );
    }
  }

  Future<void> _menuImpressao() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Imprimir termico (80 mm)'),
              onTap: () => Navigator.pop(ctx, 'termico_imprimir'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF / A4 — visualizar'),
              onTap: () => Navigator.pop(ctx, 'a4_visualizar'),
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('PDF / A4 — impressao direta'),
              onTap: () => Navigator.pop(ctx, 'a4_direto'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Salvar PDF em disco'),
              onTap: () => Navigator.pop(ctx, 'a4_salvar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || escolha == null) return;
    switch (escolha) {
      case 'termico_imprimir':
        await _imprimirOuSalvar(termico: true, acao: 'visualizar');
        break;
      case 'a4_visualizar':
        await _imprimirOuSalvar(termico: false, acao: 'visualizar');
        break;
      case 'a4_direto':
        await _imprimirOuSalvar(termico: false, acao: 'direto');
        break;
      case 'a4_salvar':
        await _imprimirOuSalvar(termico: false, acao: 'salvar');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sessao;
    return Scaffold(
      appBar: AppBar(
        title: Text('Extrato sessao Nº ${s.numero}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimir relatorio',
            onPressed: _dados == null ? null : _menuImpressao,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!, textAlign: TextAlign.center))
              : _buildCorpo(context),
    );
  }

  Widget _buildCorpo(BuildContext context) {
    final dados = _dados!;
    final s = dados.sessao;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Identificacao',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Sessao Nº ${s.numero}'),
                Text('Operador: ${s.operador.isEmpty ? '-' : s.operador}'),
                if (s.terminalId.isNotEmpty) Text('Terminal: ${s.terminalId}'),
                Text('Abertura: ${_fmtDataHora.format(s.aberturaEm.toLocal())}'),
                Text(
                  s.aberta
                      ? 'Fechamento: em aberto'
                      : 'Fechamento: ${_fmtDataHora.format(s.fechamentoEm!.toLocal())}',
                ),
                Text(
                  'Fundo ${_fmtMoeda.format(s.fundoTroco)} · '
                  'Supr. ${_fmtMoeda.format(s.suprimentos)} · '
                  'Sang. ${_fmtMoeda.format(s.sangrias)}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumo por forma de pagamento',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _linhaResumo('Dinheiro', dados.resumo.dinheiro),
                _linhaResumo('PIX', dados.resumo.pix),
                _linhaResumo('Cartao debito', dados.resumo.cartaoDebito),
                _linhaResumo('Cartao credito', dados.resumo.cartaoCredito),
                _linhaResumo('Fiado', dados.resumo.fiado),
                if (dados.resumo.outros > 0.009)
                  _linhaResumo('Outros', dados.resumo.outros),
                if (dados.quantidadeRecebimentosFiado > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Inclui recebimentos de fiado no dinheiro, PIX e cartao.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const Divider(),
                _linhaResumo(
                  'Total vendas (${dados.quantidadeVendas})',
                  dados.totalVendas,
                  bold: true,
                ),
                if (dados.quantidadeRecebimentosFiado > 0)
                  _linhaResumo(
                    'Receb. fiado (${dados.quantidadeRecebimentosFiado})',
                    dados.totalRecebimentosFiado,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Vendas da sessao',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (dados.vendas.isEmpty)
          const Text('Nenhuma venda registrada neste turno.')
        else
          ...dados.vendas.map(
            (v) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Doc ${v.numeroDocumento} · ${v.hora} · ${v.nfceRotulo}',
              ),
              subtitle: Text('${v.cliente} · ${v.formaPagamento}'),
              trailing: Text(
                _fmtMoeda.format(v.valor),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Recebimentos de fiado',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (dados.recebimentos.isEmpty)
          const Text('Nenhum recebimento de fiado neste turno.')
        else
          ...dados.recebimentos.map(
            (rec) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Rec. ${rec.recebimentoId} · ${rec.hora}'),
              subtitle: Text('${rec.cliente} · ${rec.formaPagamento}'),
              trailing: Text(
                _fmtMoeda.format(rec.valor),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Suprimentos e sangrias',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (dados.movimentos.isEmpty)
          const Text('Nenhum movimento.')
        else
          ...dados.movimentos.map(
            (m) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                m.tipo == 'Suprimento'
                    ? Icons.add_circle_outline
                    : Icons.remove_circle_outline,
              ),
              title: Text('${m.tipo} · ${_fmtMoeda.format(m.valor)}'),
              subtitle: Text(
                '${_fmtDataHora.format(m.dataHora.toLocal())}'
                '${m.observacao.trim().isEmpty ? '' : ' · ${m.observacao}'}',
              ),
            ),
          ),
      ],
    );
  }

  Widget _linhaResumo(String rotulo, double valor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rotulo,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
            ),
          ),
          Text(
            _fmtMoeda.format(valor),
            style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
          ),
        ],
      ),
    );
  }
}

/// Abre o extrato a partir de um fechamento de auditoria.
Future<void> abrirExtratoSessaoCaixa(
  BuildContext context, {
  required SessaoCaixaReferencia sessao,
  required dynamic vendaRepository,
  required dynamic clienteRepository,
  required ConfiguracoesService configuracoesService,
  required PrintService printService,
  ObjectBox? objectBox,
  dynamic lanApiClient,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ExtratoSessaoCaixaPage(
        sessao: sessao,
        vendaRepository: vendaRepository,
        clienteRepository: clienteRepository,
        configuracoesService: configuracoesService,
        printService: printService,
        objectBox: objectBox,
        lanApiClient: lanApiClient,
      ),
    ),
  );
}
