import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:sistema_vendas/model/config_layout_impressao.dart';
import 'package:sistema_vendas/services/cupom_pdf_layout.dart';

void main() {
  test('formatoPaginaOrcamentoSalvar termico usa altura ilimitada', () {
    const layout = ConfigLayoutImpressao();
    final fmt = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: EmpresaModeloPdf.bobina,
      layout: layout,
    );
    expect(fmt.height, double.infinity);
    expect(fmt.width, greaterThan(0));
  });

  test('formatoPaginaOrcamentoSalvar a4 mantem A4', () {
    const layout = ConfigLayoutImpressao();
    final fmt = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: EmpresaModeloPdf.a4,
      layout: layout,
    );
    expect(fmt.width, PdfPageFormat.a4.width);
    expect(fmt.height, PdfPageFormat.a4.height);
  });
}
