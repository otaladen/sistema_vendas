import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/inventario_constantes.dart';
import 'package:sistema_vendas/domain/inventario_contagem.dart';
import 'package:sistema_vendas/model/item_inventario.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto piso() => Produto(
        id: 1,
        codigoInterno: '008858',
        nome: 'Piso teste',
        unidade: 'M2',
        unidadeCompra: 'CX',
        quantidadePorEmbalagem: 2.63,
        embalagemMultiplica: true,
        quantidadeMinima: 0,
        precoCusto: 32.99,
        custoMedio: 32.99,
        precoVenda: 49.90,
        permiteQuantidadeFracionada: true,
      );

  test('contagem zero e valida', () {
    expect(InventarioContagem.parseQuantidade('0', piso()), 0);
    expect(InventarioContagem.parseQuantidade('0,0', piso()), 0);
  });

  test('piso usa milésimos na escala de exibicao', () {
    final qtd = InventarioContagem.parseQuantidade('144,62', piso());
    expect(qtd, 144620);
  });

  test('estado pendente / ok / divergente', () {
    expect(
      InventarioContagem.estadoDe(
        conferido: false,
        quantidadeContada: 0,
        snapshotFisico: 10,
      ),
      InventarioItemEstado.pendente,
    );
    expect(
      InventarioContagem.estadoDe(
        conferido: true,
        quantidadeContada: 10,
        snapshotFisico: 10,
      ),
      InventarioItemEstado.conferidoOk,
    );
    expect(
      InventarioContagem.estadoDe(
        conferido: true,
        quantidadeContada: 8,
        snapshotFisico: 10,
      ),
      InventarioItemEstado.divergente,
    );
  });

  test('valor estimado usa custo e escala de exibicao', () {
    final item = ItemInventario(
      produtoId: 1,
      nomeSnapshot: 'Piso teste',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      permiteQuantidadeFracionada: true,
      snapshotFisico: 144620,
      quantidadeContada: 100000,
      conferido: true,
      custoUnitario: 32.99,
    );
    item.aplicarEstadoDaContagem();
    expect(item.estado, InventarioItemEstado.divergente);
    final valor = InventarioContagem.valorDiferencaAbs(
      item,
      item.deltaArmazenado,
      live: piso(),
    );
    expect(valor, closeTo(44.62 * 32.99, 0.05));
  });
}
