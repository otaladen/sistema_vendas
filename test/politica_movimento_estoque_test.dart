import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/estoque/tipo_movimento_estoque.dart';

void main() {
  test('cupom e entrada compra alteram estoque fisico', () {
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.cupomNaoFiscalVenda,
      ),
      isTrue,
    );
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.entradaNfeCompra,
      ),
      isTrue,
    );
  });

  test('NFC-e e NF-e de venda nao alteram estoque fisico', () {
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.nfceEmissao,
      ),
      isFalse,
    );
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.nfeVendaEmissao,
      ),
      isFalse,
    );
    expect(
      () => PoliticaMovimentoEstoque.validarNaoAlteraEstoque(
        TipoMovimentoEstoque.nfceEmissao,
      ),
      returnsNormally,
    );
  });

  test('entrada NF-e compra e ajuste manual alteram estoque fisico', () {
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.entradaNfeCompra,
      ),
      isTrue,
    );
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.estornoEntradaNfeCompra,
      ),
      isTrue,
    );
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.ajusteManual,
      ),
      isTrue,
    );
  });

  test('reserva de orcamento altera somente reserva', () {
    expect(
      PoliticaMovimentoEstoque.alteraSomenteReserva(
        TipoMovimentoEstoque.orcamentoReserva,
      ),
      isTrue,
    );
    expect(
      PoliticaMovimentoEstoque.alteraEstoqueFisico(
        TipoMovimentoEstoque.orcamentoReserva,
      ),
      isFalse,
    );
  });
}
