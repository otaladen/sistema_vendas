import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../data/app_config_repository.dart';
import '../model/config_layout_impressao.dart';
import '../services/cupom_pdf_gerado.dart';
import '../services/cupom_pdf_layout.dart';
import '../services/print_service.dart';

/// Envelope para PDFs legados que ainda retornam apenas bytes.
Future<CupomPdfGerado> cupomPdfLegado({
  required Uint8List bytes,
  required EmpresaConfig config,
  required ConfigLayoutImpressao layout,
  int linhasTexto = 16,
  int qtdItens = 0,
  int linhasExtras = 2,
  bool comLogo = false,
}) async {
  final pageFormat = CupomPdfLayout.formatoPagina(
    empresaModeloPdfDeString(config.modeloPdf),
    layout: layout,
    linhasTexto: linhasTexto,
    qtdItens: qtdItens,
    linhasExtras: linhasExtras,
    comLogo: comLogo,
  );
  return CupomPdfGerado(
    bytes: bytes,
    pageFormat: pageFormat,
    layout: layout,
  );
}

Future<String?> escolherSalvarPdfCupomVenda({
  required Uint8List bytes,
  required String suggestedFileName,
  String? initialDirectory,
}) async {
  final selectedPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Escolha onde salvar o PDF',
    fileName: suggestedFileName,
    initialDirectory: initialDirectory,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (selectedPath == null) {
    return null;
  }
  final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
      ? selectedPath
      : '$selectedPath.pdf';
  final file = File(normalizedPath);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Dialogo padrao: imprimir, impressao direta ou PDF (mesmo fluxo do Caixa).
Future<void> mostrarFluxoImpressaoCupomVenda(
  BuildContext context, {
  required PrintService printService,
  required EmpresaConfig config,
  required Future<CupomPdfGerado> Function() gerarPdf,
  required String suggestedFileName,
  String title = 'Cupom da venda',
  String content = 'Deseja imprimir o cupom agora ou gerar PDF?',
}) async {
  if (!context.mounted) return;
  final acao = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'fechar'),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Mandar cupom em PDF'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'direto'),
            icon: const Icon(Icons.print),
            label: const Text('Impressao direta'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'imprimir'),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir cupom'),
          ),
        ],
      );
    },
  );
  if (!context.mounted || acao == null || acao == 'fechar') return;
  try {
    final pdf = await gerarPdf();
    if (!context.mounted) return;
    if (acao == 'imprimir') {
      await Printing.layoutPdf(onLayout: (_) async => pdf.bytes);
      return;
    }
    if (acao == 'direto') {
      final printer =
          await printService.resolverImpressoraPorNome(config.impressoraPadrao);
      if (printer == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impressora padrao nao configurada/encontrada.'),
          ),
        );
        return;
      }
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => pdf.bytes,
        name: suggestedFileName.replaceAll('.pdf', ''),
        format: config.modeloPdf == 'a4'
            ? PdfPageFormat.a4
            : CupomPdfLayout.formatoImpressaoDireta(
                layout: pdf.layout,
                formatoPdf: pdf.pageFormat,
              ),
      );
      return;
    }
    final path = await escolherSalvarPdfCupomVenda(
      bytes: pdf.bytes,
      suggestedFileName: suggestedFileName,
      initialDirectory: config.pastaPadraoPdf.trim().isEmpty
          ? null
          : config.pastaPadraoPdf.trim(),
    );
    if (!context.mounted || path == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('PDF salvo em: $path')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Nao foi possivel gerar/imprimir nota: $e')),
    );
  }
}
