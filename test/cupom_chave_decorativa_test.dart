import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/services/cupom_pdf_layout.dart';

void main() {
  test('chave decorativa tem 44 digitos e DV valido', () {
    final chave = CupomPdfLayout.gerarChaveAcessoDecorativaNfce(
      cnpj: FiscalConfig.cnpjEmitente,
      uf: FiscalConfig.ufEmitente,
      numeroNota: '119',
      serie: '001',
      emissao: DateTime(2026, 6, 6, 10, 42),
    );
    final d = CupomPdfLayout.chaveAcessoSomenteDigitos(chave);
    expect(d.length, 44);
    final base = d.substring(0, 43);
    final dv = int.parse(d[43]);
    expect(dv, CupomPdfLayout.digitoVerificadorChaveNfce(base));
    expect(d.substring(25, 34), '000000119');
    expect(CupomPdfLayout.chaveNfceIndicaContingencia(chave), isTrue);
  });

  test('chave decorativa e deterministica para o mesmo numero', () {
    final a = CupomPdfLayout.gerarChaveAcessoDecorativaNfce(
      cnpj: FiscalConfig.cnpjEmitente,
      uf: 'BA',
      numeroNota: '94027',
      serie: '001',
      emissao: DateTime(2026, 6, 6, 9, 26, 34),
    );
    final b = CupomPdfLayout.gerarChaveAcessoDecorativaNfce(
      cnpj: FiscalConfig.cnpjEmitente,
      uf: 'BA',
      numeroNota: '94027',
      serie: '001',
      emissao: DateTime(2026, 6, 6, 9, 26, 34),
    );
    expect(a, b);
  });
}
