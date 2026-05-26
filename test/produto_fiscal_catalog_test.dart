import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/grupo_tributario_produto.dart';
import 'package:sistema_vendas/domain/fiscal/produto_fiscal_catalog.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('CEST obrigatorio apenas para ST', () {
    expect(
      ProdutoFiscalCatalog.validarCestParaGrupo(
        cestDigitos: '',
        grupoTributarioCodigo: GrupoTributarioProduto.substituicaoTributaria.codigo,
      ),
      isNotNull,
    );
    expect(
      ProdutoFiscalCatalog.validarCestParaGrupo(
        cestDigitos: '1234567',
        grupoTributarioCodigo: GrupoTributarioProduto.tributado.codigo,
      ),
      isNull,
    );
    expect(
      ProdutoFiscalCatalog.validarCestParaGrupo(
        cestDigitos: '',
        grupoTributarioCodigo: GrupoTributarioProduto.tributado.codigo,
      ),
      isNull,
    );
  });

  test('resolver CST ICMS usa cadastro ou grupo', () {
    final tributado = Produto(
      codigoInterno: 'A',
      nome: 'A',
      grupoTributario: 'tributado',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 2,
    );
    expect(
      ProdutoFiscalCatalog.resolverIcmsSituacaoTributaria(
        tributado,
        icmsPadraoLoja: '00',
      ),
      '00',
    );

    final st = Produto(
      codigoInterno: 'B',
      nome: 'B',
      grupoTributario: 'substituicao_tributaria',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 2,
    );
    expect(
      ProdutoFiscalCatalog.resolverIcmsSituacaoTributaria(
        st,
        icmsPadraoLoja: '00',
      ),
      '60',
    );

    final custom = Produto(
      codigoInterno: 'C',
      nome: 'C',
      grupoTributario: 'substituicao_tributaria',
      icmsSituacaoTributaria: '10',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 2,
    );
    expect(
      ProdutoFiscalCatalog.resolverIcmsSituacaoTributaria(
        custom,
        icmsPadraoLoja: '00',
      ),
      '10',
    );
  });
}
