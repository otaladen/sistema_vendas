import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../services/pdf_relatorio_texto.dart';

/// Acoes padrao de PDF (imprimir e salvar em pasta) para relatorios.
class RelatorioPdfAcoes {
  RelatorioPdfAcoes._();

  static Future<void> imprimirPaginas(
    BuildContext context, {
    required List<String> paginas,
    String? mensagemSeVazio,
  }) async {
    if (paginas.isEmpty || (paginas.length == 1 && paginas.first == '(vazio)')) {
      if (context.mounted && mensagemSeVazio != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagemSeVazio)),
        );
      }
      return;
    }
    final bytes = await gerarPdfRelatorioTextoPaginas(paginas);
    if (!context.mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<void> salvarPaginas(
    BuildContext context, {
    required List<String> paginas,
    required String nomeArquivoSemExtensao,
    String? mensagemSeVazio,
  }) async {
    if (paginas.isEmpty || (paginas.length == 1 && paginas.first == '(vazio)')) {
      if (context.mounted && mensagemSeVazio != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagemSeVazio)),
        );
      }
      return;
    }
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para salvar o PDF',
    );
    if (pasta == null || pasta.trim().isEmpty) return;
    final seguro = nomeArquivoSemExtensao.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final arquivo = File(p.join(pasta, '$seguro.pdf'));
    try {
      final bytes = await gerarPdfRelatorioTextoPaginas(paginas);
      await arquivo.writeAsBytes(bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF salvo: ${arquivo.path}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  /// Botoes de impressao e salvar para [AppBar.actions].
  static List<Widget> appBarBotoes({
    required VoidCallback onImprimir,
    required VoidCallback onSalvar,
  }) {
    return [
      IconButton(
        tooltip: 'Imprimir / visualizar PDF',
        onPressed: onImprimir,
        icon: const Icon(Icons.print_outlined),
      ),
      IconButton(
        tooltip: 'Salvar PDF na pasta',
        onPressed: onSalvar,
        icon: const Icon(Icons.save_alt_outlined),
      ),
    ];
  }
}
