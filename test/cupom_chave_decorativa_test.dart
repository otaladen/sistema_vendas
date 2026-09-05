import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/model/cliente.dart';
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

  test('linhas consumidor sem cliente', () {
    expect(
      CupomPdfLayout.linhasIdentificacaoConsumidor(null),
      ['CONSUMIDOR NAO IDENTIFICADO'],
    );
  });

  test('linhas consumidor CPF e nome', () {
    final cliente = Cliente(
      nomeRazao: 'JOAO DA SILVA',
      documento: '12345678909',
      tipoPessoa: 'fisica',
    );
    expect(
      CupomPdfLayout.linhasIdentificacaoConsumidor(cliente),
      [
        'CPF: 123.456.789-09',
        'NOME: JOAO DA SILVA',
      ],
    );
  });

  test('linhas consumidor CNPJ e razao social', () {
    final cliente = Cliente(
      nomeRazao: 'EMPRESA LTDA',
      documento: '12345678000190',
      tipoPessoa: 'juridica',
    );
    expect(
      CupomPdfLayout.linhasIdentificacaoConsumidor(cliente),
      [
        'CNPJ: 12.345.678/0001-90',
        'RAZAO SOCIAL: EMPRESA LTDA',
      ],
    );
  });
}
