import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../data/venda_repository.dart';
import '../../domain/recebimento_fiado_codec.dart';
import '../../model/cliente.dart';
import '../../model/recebimento_fiado.dart';
import '../../model/titulo_receber.dart';
import '../../services/cliente_extrato_fiado_pdf.dart';

/// Extrato de fiado na aba Comercial do cadastro de clientes.
class ExtratoFiadoClienteCard extends StatelessWidget {
  const ExtratoFiadoClienteCard({
    super.key,
    required this.vendaRepository,
    required this.cliente,
    this.limiteCredito = 0,
  });

  final VendaRepository vendaRepository;
  final Cliente cliente;
  final double limiteCredito;

  static final _fmtData = DateFormat('dd/MM/yyyy');
  static final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  static String _rotuloForma(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartão crédito';
      case 'cartao_debito':
        return 'Cartão débito';
      case 'transferencia':
        return 'Transferência';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        return forma;
    }
  }

  Future<void> _exportarPdf(BuildContext context) async {
    vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final abertos = vendaRepository.titulos.listarAbertosPorCliente(cliente.id);
    final quitados =
        vendaRepository.titulos.listarQuitadosPorCliente(cliente.id, limite: 100);
    final recebimentos = vendaRepository.recebimentos.listarPorCliente(cliente.id);
    final saldo = vendaRepository.saldoFiadoEmAbertoCliente(cliente.id);

    if (abertos.isEmpty && quitados.isEmpty && recebimentos.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum movimento de fiado para exportar.')),
      );
      return;
    }

    ExtratoFiadoClienteDados dados;
    try {
      dados = await montarExtratoFiadoClienteDados(
        cliente: cliente,
        titulosAbertos: abertos,
        titulosQuitados: quitados,
        recebimentos: recebimentos,
        saldoEmAberto: saldo,
        limiteCredito: limiteCredito,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao preparar extrato: $e')),
      );
      return;
    }

    Uint8List bytes;
    try {
      bytes = await gerarExtratoFiadoClientePdf(dados);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar PDF: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extrato de fiado'),
        content: const Text('Como deseja entregar o extrato ao cliente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'salvar'),
            child: const Text('Salvar PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'imprimir'),
            child: const Text('Imprimir'),
          ),
        ],
      ),
    );
    if (acao == null || !context.mounted) return;

    if (acao == 'imprimir') {
      try {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e')),
        );
      }
      return;
    }

    final slug = cliente.nomeRazao
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    final nomeArquivo =
        'extrato_fiado_${cliente.id}_${slug}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar extrato de fiado',
      fileName: nomeArquivo,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
    if (selectedPath == null || !context.mounted) return;
    final path = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Extrato salvo em: $path')),
    );
  }

  @override
  Widget build(BuildContext context) {
    vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final abertos = vendaRepository.titulos.listarAbertosPorCliente(cliente.id);
    final quitados =
        vendaRepository.titulos.listarQuitadosPorCliente(cliente.id, limite: 20);
    final recebimentos =
        vendaRepository.recebimentos.listarPorCliente(cliente.id).take(20).toList();

    if (abertos.isEmpty && quitados.isEmpty && recebimentos.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Extrato fiado',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _exportarPdf(context),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
            ],
          ),
          if (abertos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Parcelas em aberto',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...abertos.map((t) => _linhaTitulo(context, t, emAberto: true)),
          ],
          if (recebimentos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Recebimentos recentes',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...recebimentos.map(_linhaRecebimento),
          ],
          if (quitados.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Parcelas quitadas',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...quitados.map((t) => _linhaTitulo(context, t, emAberto: false)),
          ],
        ],
      ),
    );
  }

  Widget _linhaTitulo(BuildContext context, TituloReceber t, {required bool emAberto}) {
    final venda = t.venda.target;
    final venc = _fmtData.format(t.vencimento.toLocal());
    final theme = Theme.of(context);
    final vencido = emAberto && t.vencido;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Venda ${venda?.numeroOrcamento ?? '-'} · '
                  'Parc. ${t.numeroParcela}/${t.totalParcelas}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  emAberto
                      ? 'Venc. $venc · Saldo ${_fmtMoeda.format(t.saldo)}'
                      : 'Quitada em ${t.dataQuitacao != null ? _fmtData.format(t.dataQuitacao!.toLocal()) : '-'} · '
                          '${_fmtMoeda.format(t.valorOriginal)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: vencido ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ),
          if (vencido)
            Text(
              'Vencido',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _linhaRecebimento(RecebimentoFiado r) {
    final data = _fmtData.format(r.data.toLocal());
    final aloc = RecebimentoFiadoCodec.decode(r.alocacoesJson);
    final detalhe = aloc.isEmpty
        ? ''
        : ' (${aloc.length} parcela${aloc.length == 1 ? '' : 's'})';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '$data · ${_fmtMoeda.format(r.valorTotal)} · '
        '${_rotuloForma(r.formaPagamento)}$detalhe',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
