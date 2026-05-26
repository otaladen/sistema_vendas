import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/fechamento_fiscal_resumo.dart';
import 'package:sistema_vendas/domain/fiscal/nota_fiscal_fechamento_item.dart';
import 'package:sistema_vendas/services/fechamento_contabil_service.dart';

void main() {
  test('FechamentoFiscalResumo conta modelos e valores', () {
    final pacote = FechamentoContabilPacote(
      saidas: [
        NotaFiscalFechamentoItem(
          modelo: '55',
          dataEmissao: DateTime(2026, 5, 10),
          numero: '100',
          serie: '1',
          chaveAcesso: '29260512345678901234567890123456789012345678',
          documentoDestinatario: '32662298000191',
          valorTotal: 1500,
          status: 'Autorizada',
          statusFocus: 'autorizado',
          urlXml: 'http://x',
        ),
        NotaFiscalFechamentoItem(
          modelo: '65',
          dataEmissao: DateTime(2026, 5, 11),
          numero: '50',
          serie: '1',
          chaveAcesso: '29260512345678901234567890123456789012345679',
          documentoDestinatario: '',
          valorTotal: 200,
          status: 'Cancelada',
          statusFocus: 'cancelado',
          urlXml: '',
        ),
      ],
      entradas: const [],
    );
    final r = FechamentoFiscalResumo.calcular(5, 2026, pacote);
    expect(r.nfe55, 1);
    expect(r.nfce65, 1);
    expect(r.saidasAutorizadas, 1);
    expect(r.saidasCanceladas, 1);
    expect(r.valorSaidasAutorizadas, 1500);
  });
}
