import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    barrierDismissible: false,
    builder: (context) => _DialogoCupomVendaImpressao(
      title: title,
      content: content,
    ),
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

/// Cupom pos-venda: atalhos 1/Esc fechar · 2 PDF · 3 direta · 4/Enter imprimir.
class _DialogoCupomVendaImpressao extends StatefulWidget {
  const _DialogoCupomVendaImpressao({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  State<_DialogoCupomVendaImpressao> createState() =>
      _DialogoCupomVendaImpressaoState();
}

class _DialogoCupomVendaImpressaoState extends State<_DialogoCupomVendaImpressao> {
  final _focusImprimir = FocusNode(debugLabel: 'cupomVendaImprimir');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusImprimir.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusImprimir.dispose();
    super.dispose();
  }

  void _fechar(String acao) {
    if (!mounted) return;
    Navigator.pop(context, acao);
  }

  KeyEventResult _atalhoTeclado(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      _fechar('fechar');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      _fechar('pdf');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      _fechar('direto');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4 ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _fechar('imprimir');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _atalhoTeclado,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.content),
            const SizedBox(height: 10),
            Text(
              'Teclado: Esc ou 1 — fechar · 2 — PDF · 3 — impressao direta · '
              '4 ou Enter — imprimir',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _fechar('fechar'),
            child: const Text('Fechar (Esc · 1)'),
          ),
          OutlinedButton.icon(
            onPressed: () => _fechar('pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Mandar cupom em PDF (2)'),
          ),
          OutlinedButton.icon(
            onPressed: () => _fechar('direto'),
            icon: const Icon(Icons.print),
            label: const Text('Impressao direta (3)'),
          ),
          Focus(
            focusNode: _focusImprimir,
            child: FilledButton.icon(
              onPressed: () => _fechar('imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir cupom (4 · Enter)'),
            ),
          ),
        ],
      ),
    );
  }
}
