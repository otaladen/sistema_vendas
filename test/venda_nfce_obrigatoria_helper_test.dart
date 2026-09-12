import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/fiscal/venda_nfce_obrigatoria_helper.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('VendaNfceObrigatoriaHelper', () {
    test('pix exige NFC-e', () {
      final v = Venda(formaPagamento: 'pix', status: 'finalizada');
      expect(VendaNfceObrigatoriaHelper.pagamentoExigeNfce(v), isTrue);
    });

    test('dinheiro nao exige NFC-e', () {
      final v = Venda(formaPagamento: 'dinheiro', status: 'finalizada');
      expect(VendaNfceObrigatoriaHelper.pagamentoExigeNfce(v), isFalse);
    });

    test('misto com pix exige NFC-e', () {
      final v = Venda(
        formaPagamento: 'misto',
        status: 'finalizada',
        pagamentosJson: PagamentoOrcamentoCodec.encode([
          const PagamentoOrcamentoLinha(meio: 'pix', valor: 50),
          const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 20),
        ]),
      );
      expect(VendaNfceObrigatoriaHelper.pagamentoExigeNfce(v), isTrue);
    });

    test('pendente emissao quando finalizada pix sem nfce', () {
      final v = Venda(formaPagamento: 'pix', status: 'finalizada', total: 100);
      expect(VendaNfceObrigatoriaHelper.ehPendenteEmissao(v), isTrue);
    });

    test('nao pendente quando nfce emitida', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        nfceChaveAcesso: '35260100000000000000550010000000001000000000',
      );
      expect(VendaNfceObrigatoriaHelper.ehPendenteEmissao(v), isFalse);
    });

    test('nao pendente quando aguardando SEFAZ', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        nfceStatusFocus: 'processando_autorizacao',
        nfceProtocolo: 'focus_pendente:abc',
      );
      expect(VendaNfceObrigatoriaHelper.ehPendenteEmissao(v), isFalse);
    });

    test('pendente quando chave so espacos (sem NFC-e real)', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        nfceChaveAcesso: '   ',
      );
      expect(VendaNfceObrigatoriaHelper.ehPendenteEmissao(v), isTrue);
    });

    test('filtro listagem inclui PIX aguardando SEFAZ', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        nfceStatusFocus: 'processando_autorizacao',
        nfceProtocolo: 'focus_pendente:abc',
      );
      expect(
        VendaNfceObrigatoriaHelper.correspondeFiltroListagemSemNfceEletronico(v),
        isTrue,
      );
      expect(VendaNfceObrigatoriaHelper.ehPendenteEmissao(v), isFalse);
    });

    test('filtro listagem exclui quando coluna mostraria NF-e 55 na venda', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        nfeStatusFocus: 'autorizado',
        nfeNumero: '123',
      );
      expect(
        VendaNfceObrigatoriaHelper.correspondeFiltroListagemSemNfceEletronico(v),
        isFalse,
      );
    });

    test('filtro listagem exclui venda que ja exibe NFC-e na listagem', () {
      final v = Venda(
        formaPagamento: 'cartao_credito',
        status: 'finalizada',
        nfceChaveAcesso: '35260100000000000000550010000000001000000000',
        nfceNumero: '59959',
        nfceStatusFocus: 'cancelado',
      );
      expect(
        VendaNfceObrigatoriaHelper.correspondeFiltroListagemSemNfceEletronico(v),
        isFalse,
      );
    });

    test('filtro listagem inclui PIX sem rotulo NFC-e na coluna documento', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        numeroControle: 640,
      );
      expect(
        VendaNfceObrigatoriaHelper.correspondeFiltroListagemSemNfceEletronico(v),
        isTrue,
      );
    });

    test('filtro somente nfce inclui venda com NFC-e na coluna documento', () {
      final v = Venda(
        formaPagamento: 'dinheiro',
        status: 'finalizada',
        nfceChaveAcesso: '35260100000000000000550010000000001000000000',
        nfceNumero: '60341',
      );
      expect(
        VendaNfceObrigatoriaHelper.correspondeFiltroListagemSomenteNfceEletronico(
          v,
        ),
        isTrue,
      );
    });

    test('filtro somente nfce exclui venda so com controle interno', () {
      final v = Venda(
        formaPagamento: 'pix',
        status: 'finalizada',
        numeroControle: 634,
      );
      expect(
        VendaNfceObrigatoriaHelper.correspondeFiltroListagemSomenteNfceEletronico(
          v,
        ),
        isFalse,
      );
    });

    test('pagamento exige nfce via json quando forma nao e misto', () {
      final v = Venda(
        formaPagamento: 'dinheiro',
        status: 'finalizada',
        pagamentosJson: PagamentoOrcamentoCodec.encode([
          const PagamentoOrcamentoLinha(meio: 'pix', valor: 80),
        ]),
      );
      expect(VendaNfceObrigatoriaHelper.pagamentoExigeNfce(v), isTrue);
    });
  });
}
