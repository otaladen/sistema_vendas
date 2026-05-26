import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  test('deRespostaFocus identifica autorizacao pela chave e status 100', () {
    final r = FocusNfeEmissaoResultado.deRespostaFocus(
      {
        'status': 'autorizado',
        'status_sefaz': '100',
        'mensagem_sefaz': 'Autorizado o uso da NF-e',
        'chave_nfe': 'NFe41190607504505000132550010000000221923094166',
        'caminho_danfe': 'https://focusnfe.s3.amazonaws.com/arquivo.pdf',
        'numero': '22',
        'serie': '1',
      },
      referencia: 'NFCE-VENDA-10',
    );

    expect(r.autorizada, isTrue);
    expect(r.rejeitada, isFalse);
    expect(r.chaveNfe, contains('NFe'));
    expect(r.urlDanfe, contains('https://'));
    expect(r.referencia, 'NFCE-VENDA-10');
  });

  test('deRespostaFocus identifica rejeicao SEFAZ', () {
    final r = FocusNfeEmissaoResultado.deRespostaFocus(
      {
        'status': 'erro_autorizacao',
        'status_sefaz': '598',
        'mensagem_sefaz':
            'NF-e emitida em ambiente de homologacao com Razao Social invalida',
      },
      referencia: 'NFE-VENDA-5',
    );

    expect(r.autorizada, isFalse);
    expect(r.rejeitada, isTrue);
    expect(r.mensagem, contains('homologacao'));
  });
}
