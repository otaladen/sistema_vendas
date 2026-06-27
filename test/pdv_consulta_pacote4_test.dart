import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/ui/pdv_consulta_produtos_page.dart';
import 'package:sistema_vendas/ui/widgets/pdv_consulta_linha_produto.dart';

Produto _produto({
  int id = 1,
  String codigoInterno = '',
  String nome = 'Cimento CP II',
}) =>
    Produto(
      id: id,
      codigoInterno: codigoInterno,
      nome: nome,
      unidade: 'SC',
      precoCusto: 30,
      precoVenda: 50,
      preco1: 50,
      quantidadeMinima: 1,
    );

void main() {
  test('PdvConsultaProdutoResult.inserirKit exige id e quantidade', () {
    final base = PdvConsultaProdutoResult(
      produto: _produto(),
      precoListaAtivo: 'preco1',
    );
    expect(base.inserirKit, isFalse);

    final comKit = PdvConsultaProdutoResult(
      produto: _produto(),
      precoListaAtivo: 'preco1',
      kitInserirId: 7,
      quantidadeKitsInserir: 2,
      abrirDialogoAdicionar: false,
    );
    expect(comKit.inserirKit, isTrue);
  });

  test('linha nao selecionada com SKU ganha altura extra', () {
    final semSku = _produto();
    final comSku = _produto(codigoInterno: '004025');

    expect(PdvConsultaLinhaProduto.exibirBadgesCompactos(semSku), isFalse);
    expect(PdvConsultaLinhaProduto.exibirBadgesCompactos(comSku), isTrue);
    expect(
      PdvConsultaLinhaProduto.alturaPara(expandido: false, produto: semSku),
      PdvConsultaLinhaProduto.alturaLinha,
    );
    expect(
      PdvConsultaLinhaProduto.alturaPara(expandido: false, produto: comSku),
      PdvConsultaLinhaProduto.alturaLinhaComBadges,
    );
  });
}
