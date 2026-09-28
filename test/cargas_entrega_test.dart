import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entregas/cargas_entrega.dart';

void main() {
  const cimento = ProdutoCarretoTotal(
    produtoId: 1,
    nomeProduto: 'Cimento 50kg',
    quantidade: 200,
    unidade: 'SC',
  );
  const areia = ProdutoCarretoTotal(
    produtoId: 2,
    nomeProduto: 'Areia media',
    quantidade: 4.5,
    unidade: 'M3',
    fracionado: true,
  );

  CargaEntrega carga(
    int numero,
    DateTime? data,
    List<LinhaCargaEntrega> linhas, {
    String status = CargaEntrega.statusPendente,
  }) =>
      CargaEntrega(numero: numero, data: data, linhas: linhas, status: status);

  LinhaCargaEntrega linha(ProdutoCarretoTotal p, double q) => LinhaCargaEntrega(
        produtoId: p.produtoId,
        nomeProduto: p.nomeProduto,
        quantidade: q,
      );

  group('CargasEntregaCodec', () {
    test('ida e volta preserva data, janela, status e linhas', () {
      final cargas = [
        carga(1, DateTime(2030, 5, 10), [linha(cimento, 120)]),
        CargaEntrega(
          numero: 2,
          data: DateTime(2030, 5, 12),
          janela: 'tarde',
          status: CargaEntrega.statusEntregue,
          linhas: [linha(cimento, 80), linha(areia, 4.5)],
        ),
      ];
      final decoded = CargasEntregaCodec.decode(
        CargasEntregaCodec.encode(cargas),
      );
      expect(decoded, hasLength(2));
      expect(decoded[0].data, DateTime(2030, 5, 10));
      expect(decoded[1].janela, 'tarde');
      expect(decoded[1].entregue, isTrue);
      expect(decoded[1].quantidadeDoProduto(2), 4.5);
    });

    test('menos de duas cargas vira plano vazio', () {
      expect(
        CargasEntregaCodec.encode([carga(1, DateTime(2030), [])]),
        isEmpty,
      );
      expect(CargasEntregaCodec.decode(''), isEmpty);
      expect(CargasEntregaCodec.decode('lixo'), isEmpty);
    });
  });

  group('validarPlano', () {
    final d1 = DateTime(2030, 5, 10);
    final d2 = DateTime(2030, 5, 12);

    test('aceita plano que soma exatamente o vendido', () {
      final cargas = CargasEntregaHelper.recalcularPrimeiraCarga(
        [cimento, areia],
        [
          carga(1, d1, []),
          carga(2, d2, [linha(cimento, 80), linha(areia, 1.5)]),
        ],
      );
      expect(cargas.first.quantidadeDoProduto(1), 120);
      expect(cargas.first.quantidadeDoProduto(2), 3);
      expect(CargasEntregaHelper.validarPlano(cargas, [cimento, areia]), isNull);
    });

    test('exige data em todas as cargas', () {
      final cargas = [
        carga(1, d1, [linha(cimento, 120)]),
        carga(2, null, [linha(cimento, 80)]),
      ];
      expect(
        CargasEntregaHelper.validarPlano(cargas, [cimento]),
        contains('data da carga 2'),
      );
    });

    test('carga seguinte nao pode ser antes da anterior', () {
      final cargas = [
        carga(1, d2, [linha(cimento, 120)]),
        carga(2, d1, [linha(cimento, 80)]),
      ];
      expect(
        CargasEntregaHelper.validarPlano(cargas, [cimento]),
        contains('antes da carga 1'),
      );
    });

    test('mesmo dia e permitido (duas viagens no dia)', () {
      final cargas = [
        carga(1, d1, [linha(cimento, 120)]),
        carga(2, d1, [linha(cimento, 80)]),
      ];
      expect(CargasEntregaHelper.validarPlano(cargas, [cimento]), isNull);
    });

    test('carga vazia e recusada', () {
      final cargas = [
        carga(1, d1, [linha(cimento, 200)]),
        carga(2, d2, []),
      ];
      expect(
        CargasEntregaHelper.validarPlano(cargas, [cimento]),
        contains('carga 2 esta vazia'),
      );
    });

    test('carrinho alterado depois da divisao e detectado', () {
      final cargas = [
        carga(1, d1, [linha(cimento, 120)]),
        carga(2, d2, [linha(cimento, 80)]),
      ];
      const menos = ProdutoCarretoTotal(
        produtoId: 1,
        nomeProduto: 'Cimento 50kg',
        quantidade: 150,
      );
      expect(
        CargasEntregaHelper.validarPlano(cargas, [menos]),
        contains('somam mais que o vendido'),
      );
      expect(
        CargasEntregaHelper.validarPlano(cargas, [cimento, areia]),
        contains('falta distribuir'),
      );
      expect(
        CargasEntregaHelper.validarPlano(cargas, [areia]),
        contains('nao esta mais no carreto'),
      );
    });
  });

  group('progresso', () {
    test('carga atual e rotulos', () {
      final cargas = [
        carga(
          1,
          DateTime(2030, 5, 10),
          [linha(cimento, 120)],
          status: CargaEntrega.statusEntregue,
        ),
        carga(2, DateTime(2030, 5, 12), [linha(cimento, 80)]),
      ];
      expect(CargasEntregaHelper.cargaAtual(cargas)!.numero, 2);
      expect(CargasEntregaHelper.rotuloCargaAtual(cargas), 'Carga 2/2');
      expect(
        CargasEntregaHelper.rotuloProgresso(cargas),
        'Entrega parcial (1/2)',
      );
    });
  });

  group('alocarPorLinha', () {
    test('mesmo produto em duas linhas: cargas enchem na ordem sem sobrepor',
        () {
      final alocacao = CargasEntregaHelper.alocarPorLinha(
        cargas: [
          carga(1, DateTime(2030), [linha(cimento, 120)]),
          carga(2, DateTime(2030), [linha(cimento, 80)]),
        ],
        linhas: const [
          LinhaVendaCarreto(itemVendaId: 10, produtoId: 1, quantidade: 50),
          LinhaVendaCarreto(itemVendaId: 12, produtoId: 1, quantidade: 150),
        ],
      );
      expect(alocacao[0], {10: 50, 12: 70});
      expect(alocacao[1], {12: 80});
    });

    test('produto so na carga 2 nao entra na carga 1', () {
      final alocacao = CargasEntregaHelper.alocarPorLinha(
        cargas: [
          carga(1, DateTime(2030), [linha(cimento, 200)]),
          carga(2, DateTime(2030), [linha(areia, 4.5)]),
        ],
        linhas: const [
          LinhaVendaCarreto(itemVendaId: 10, produtoId: 1, quantidade: 200),
          LinhaVendaCarreto(itemVendaId: 11, produtoId: 2, quantidade: 4.5),
        ],
      );
      expect(alocacao[0], {10: 200});
      expect(alocacao[1], {11: 4.5});
    });
  });

  group('CargaEntrega POD', () {
    test('comprovante da carga sobrevive ao codec', () {
      final cargas = [
        carga(1, DateTime(2030, 5, 10), [linha(cimento, 120)]).copyWith(
          status: CargaEntrega.statusEntregue,
          recebidoPor: 'Maria',
          podFotoPathServidor: 'pod/1.jpg',
        ),
        carga(2, DateTime(2030, 5, 12), [linha(cimento, 80)]),
      ];
      final c1 = CargasEntregaCodec.decode(
        CargasEntregaCodec.encode(cargas),
      ).first;
      expect(c1.recebidoPor, 'Maria');
      expect(c1.podFotoPathServidor, 'pod/1.jpg');
    });
  });
}
