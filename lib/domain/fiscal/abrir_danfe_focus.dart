import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../model/venda.dart';
import '../../services/focus_nfe_service.dart';
import 'focus_documento_fiscal_url.dart';
import 'pdf_documento_util.dart';
import '../../ui/fiscal/abrir_documento_fiscal.dart';

/// Abre ou imprime DANFE da Focus (NFC-e / NF-e) com URL normalizada e download autenticado.
Future<void> abrirDanfeFocus(
  BuildContext context, {
  required FocusNfeService focusNfe,
  required String urlSalva,
  Venda? venda,
  String referencia = '',
}) async {
  final base = focusNfe.config.baseUrl;
  var url = FocusDocumentoFiscalUrl.normalizar(urlSalva, apiBaseUrl: base);

  final ref = referencia.trim().isNotEmpty
      ? referencia.trim()
      : (venda != null ? FocusNfeService.referenciaVendaNfce(venda) : '');

  if (!FocusDocumentoFiscalUrl.urlAbsolutaValida(url) && ref.isNotEmpty) {
    final consulta = await focusNfe.consultarNfce(ref);
    if (consulta.urlDanfe.trim().isNotEmpty) {
      url = FocusDocumentoFiscalUrl.normalizar(
        consulta.urlDanfe,
        apiBaseUrl: base,
      );
    }
  }

  if (!FocusDocumentoFiscalUrl.urlAbsolutaValida(url)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Link do DANFE invalido ou indisponivel. '
          'Reconsulte a NFC-e no painel Focus ou tente novamente apos autorizacao.',
        ),
        duration: Duration(seconds: 8),
      ),
    );
    return;
  }

  Uint8List? pdf;
  if (url.toLowerCase().contains('focusnfe.com.br')) {
    pdf = await focusNfe.baixarDocumentoPdf(Uri.parse(url));
  }

  if (pdf != null && pdf.isNotEmpty) {
    try {
      final paginas = PdfDocumentoUtil.contarPaginas(pdf);
      var bytesImpressao = pdf;

      if (paginas > 1 && context.mounted) {
        final escolha = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('DANFE com mais de uma via'),
            content: Text(
              'O PDF da Focus tem $paginas paginas iguais '
              '(via do consumidor e via do estabelecimento — comum em NFC-e '
              'em contingencia).\n\n'
              'Para nao sair duplicado na bobina, escolha o que imprimir:',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'ambas'),
                child: const Text('Ambas as vias'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'cliente'),
                child: const Text('So via do cliente'),
              ),
            ],
          ),
        );
        if (!context.mounted || escolha == null) return;
        if (escolha == 'cliente') {
          bytesImpressao = await PdfDocumentoUtil.extrairPaginas(
            pdf,
            indices: const [0],
          );
        }
      }

      if (!context.mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytesImpressao);
      return;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir PDF do DANFE: $e')),
      );
      return;
    }
  }

  if (!context.mounted) return;
  await abrirUrlDocumentoFiscal(
    context,
    url,
    mensagemSeVazio: 'Link do DANFE nao disponivel.',
  );
}
