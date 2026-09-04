import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/data/venda_repository.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/model/produto.dart';

String? _prepararObjectBoxDll() {
  final candidates = [
    r'c:\Projetos\sistema_vendas\build\windows\x64\runner\Debug',
    r'c:\Projetos\sistema_vendas\build\windows\x64\runner\Release',
    r'c:\Projetos\sistema_vendas\build\windows\x64\_deps\objectbox-download-src\lib',
  ];
  for (final dir in candidates) {
    final dll = File('$dir${Platform.pathSeparator}objectbox.dll');
    if (dll.existsSync()) {
      try {
        final path = Platform.environment['PATH'] ?? '';
        if (!path.toLowerCase().contains(dir.toLowerCase())) {
          Platform.environment['PATH'] = '$dir${Platform.pathSeparator}$path';
        }
      } catch (_) {
        // Ambiente de teste pode ter Platform.environment imutavel.
      }
      break;
    }
  }
  Directory? probeDir;
  try {
    probeDir = Directory.systemTemp.createTempSync('sv_obx_probe_');
    final probe = ObjectBox.createForTest(probeDir);
    probe.close();
    return null;
  } catch (e) {
    return 'objectbox.dll indisponivel neste ambiente — '
        'teste de integracao pulado ($e)';
  } finally {
    try {
      probeDir?.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = _prepararObjectBoxDll();

  group(
    'estoque reserva ObjectBox',
    () {
  late Directory tempDir;
  late ObjectBox db;
  late VendaRepository vendas;

  setUp(() {
    enterSyncApplySilencioso();
    tempDir = Directory.systemTemp.createTempSync('sv_reserva_obx_');
    db = ObjectBox.createForTest(tempDir);
    vendas = VendaRepository(db);
  });

  tearDown(() {
    leaveSyncApplySilencioso();
    db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Produto produtoBase({int estoque = 47, int reservado = 0}) {
    final p = Produto(
      codigoInterno: '1389',
      nome: 'Abracadeira U 1 1/2"',
      unidade: 'UN',
      estoqueReal: estoque,
      estoqueReservado: reservado,
      estoqueAtual: estoque,
      quantidadeMinima: 0,
      precoCusto: 2,
      precoVenda: 3.5,
      preco1: 3.5,
      preco2: 3.5,
      preco3: 3.2,
      ativo: true,
    );
    final id = db.produtoBox.put(p);
    p.id = id;
    return p;
  }

  test(
    'finalizar orcamento retirada futura incrementa reservado e nao baixa fisico',
    () {
      final produto = produtoBase();
      final orcId = vendas.registrarOrcamento(
        [
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 5,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
          ),
        ],
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: 'dinheiro',
          quantidadeParcelas: 1,
        ),
        entrega: DadosEntregaOrcamento(
          tipoEntrega: EntregaVendaHelper.tipoRetiradaFutura,
          valorFrete: 0,
        ),
      );

      final itensAntes = vendas.listarItensPorVenda(orcId);
      expect(itensAntes, hasLength(1));
      expect(
        itensAntes.first.tipoEntregaItem,
        EntregaVendaHelper.tipoRetiradaFutura,
      );

      expect(db.produtoBox.get(produto.id)!.estoqueReservado, 0);
      expect(db.produtoBox.get(produto.id)!.estoqueReal, 47);

      vendas.converterOrcamentoParaVenda(orcId);

      final depois = db.produtoBox.get(produto.id)!;
      expect(depois.estoqueReservado, 5);
      expect(depois.estoqueReal, 47);
      expect(depois.estoqueLivreParaVenda, 42);

      final venda = vendas.obterPorId(orcId)!;
      expect(venda.status, 'finalizada');
      expect(venda.entregaPendente, isTrue);
    },
  );

  test('finalizar leva agora: baixa fisico e NAO incrementa reservado', () {
    final produto = produtoBase();
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 5,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoRetirada,
        valorFrete: 0,
      ),
    );

    // Flag stale nao pode promover leva agora a reserva.
    final orc = db.vendaBox.get(orcId)!;
    orc.entregaPendente = true;
    db.vendaBox.put(orc);

    vendas.converterOrcamentoParaVenda(orcId);

    final depois = db.produtoBox.get(produto.id)!;
    expect(depois.estoqueReal, 42);
    expect(depois.estoqueReservado, 0);
    expect(depois.estoqueLivreParaVenda, 42);

    final venda = vendas.obterPorId(orcId)!;
    expect(venda.status, 'finalizada');
    expect(venda.entregaPendente, isFalse);
    expect(venda.estoqueBaixadoCupom, isTrue);

    final item = vendas.listarItensPorVenda(orcId).first;
    expect(item.tipoEntregaItem, EntregaVendaHelper.tipoRetirada);
    expect(item.quantidadeJaRetirada, 5);
  });

  test('finalizar carreto: reserva e marca quantidadeNoCarreto', () {
    final produto = produtoBase();
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 4,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'pix',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
        valorFrete: 25,
        enderecoEntrega: 'Rua Teste 123',
      ),
    );

    vendas.converterOrcamentoParaVenda(orcId);

    final depois = db.produtoBox.get(produto.id)!;
    expect(depois.estoqueReal, 47);
    expect(depois.estoqueReservado, 4);

    final item = vendas.listarItensPorVenda(orcId).first;
    expect(item.quantidadeNoCarreto, 4);
    expect(vendas.obterPorId(orcId)!.carretoReservaAteSaida, isTrue);
  });

  test('finalizar misto 3 leva + 2 futura: fisico-3 e reservado+2', () {
    final produto = produtoBase();
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 3,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
        ),
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 2,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoMisto,
        valorFrete: 0,
      ),
    );

    vendas.converterOrcamentoParaVenda(orcId);

    final depois = db.produtoBox.get(produto.id)!;
    expect(depois.estoqueReal, 44);
    expect(depois.estoqueReservado, 2);
    expect(depois.estoqueLivreParaVenda, 42);
  });

  test(
    'finalizar misto 1 leva + 1 futura + 1 carreto: fisico-1 e reservado+2',
    () {
      final produto = produtoBase(); // real 47, reservado 0
      final orcId = vendas.registrarOrcamento(
        [
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 1,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
          ),
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 1,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
          ),
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 1,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
          ),
        ],
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: 'dinheiro',
          quantidadeParcelas: 1,
        ),
        entrega: DadosEntregaOrcamento(
          // Header stale "carreto" (bug do checkout) nao pode virar tudo reserva.
          tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
          valorFrete: 10,
          enderecoEntrega: 'Rua Teste 1',
        ),
      );

      final antesFinalizar = vendas.obterPorId(orcId)!;
      // registrarOrcamento ja deriva misto dos itens.
      expect(antesFinalizar.tipoEntrega, EntregaVendaHelper.tipoMisto);

      // Simula cabecalho stale gravado a mao (como o PDV fazia).
      antesFinalizar.tipoEntrega = EntregaVendaHelper.tipoEntregaLoja;
      db.vendaBox.put(antesFinalizar);

      vendas.converterOrcamentoParaVenda(orcId);

      final depois = db.produtoBox.get(produto.id)!;
      expect(depois.estoqueReal, 46); // -1 leva agora
      expect(depois.estoqueReservado, 2); // +1 futura +1 carreto
      expect(depois.estoqueLivreParaVenda, 44);

      final venda = vendas.obterPorId(orcId)!;
      expect(venda.tipoEntrega, EntregaVendaHelper.tipoMisto);
      final itens = vendas.listarItensPorVenda(orcId);
      expect(itens.length, 3);
      expect(
        itens.where((i) => i.tipoEntregaItem == EntregaVendaHelper.tipoRetirada).length,
        1,
      );
      expect(
        itens
            .where(
              (i) => i.tipoEntregaItem == EntregaVendaHelper.tipoRetiradaFutura,
            )
            .length,
        1,
      );
      expect(
        itens
            .where(
              (i) => i.tipoEntregaItem == EntregaVendaHelper.tipoEntregaLoja,
            )
            .length,
        1,
      );
    },
  );

  /// Ordem inversa: futura primeiro. Antes, `_marcarUltimaVendaNosProdutos`
  /// gravava a instancia stale da linha "leva" e zerava o reservado.
  test('finalizar misto futura-antes-leva tambem preserva reservado', () {
    final produto = produtoBase();
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 2,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
        ),
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 3,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoMisto,
        valorFrete: 0,
      ),
    );

    vendas.converterOrcamentoParaVenda(orcId);

    final depois = db.produtoBox.get(produto.id)!;
    expect(depois.estoqueReal, 44);
    expect(depois.estoqueReservado, 2);
  });

  test('misto que estoura o livre (reserva+leva) e bloqueado', () {
    final produto = produtoBase(estoque: 5);
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 3,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
        ),
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 3,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoMisto,
        valorFrete: 0,
      ),
    );

    expect(
      () => vendas.converterOrcamentoParaVenda(
        orcId,
        permitirVendaSemEstoque: false,
      ),
      throwsA(isA<StateError>()),
    );

    final depois = db.produtoBox.get(produto.id)!;
    // Transacao desfez: estoque intacto e reservado nao ficou negativo.
    expect(depois.estoqueReal, 5);
    expect(depois.estoqueReservado, 0);
    expect(depois.estoqueLivreParaVenda, 5);
  });

  test(
    'com permitirSemEstoque misto pode deixar disponivel negativo mas nao reservado',
    () {
      final produto = produtoBase(estoque: 5);
      final orcId = vendas.registrarOrcamento(
        [
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 3,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
          ),
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 3,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
          ),
        ],
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: 'dinheiro',
          quantidadeParcelas: 1,
        ),
        entrega: DadosEntregaOrcamento(
          tipoEntrega: EntregaVendaHelper.tipoMisto,
          valorFrete: 0,
        ),
      );

      vendas.converterOrcamentoParaVenda(
        orcId,
        permitirVendaSemEstoque: true,
      );

      final depois = db.produtoBox.get(produto.id)!;
      expect(depois.estoqueReal, 2);
      expect(depois.estoqueReservado, 3);
      expect(depois.estoqueLivreParaVenda, -1);
      expect(depois.estoqueReservado, greaterThanOrEqualTo(0));
    },
  );

  test('misto no limite do livre fecha com disponivel zero', () {
    final produto = produtoBase(estoque: 5);
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 2,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
        ),
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 3,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'dinheiro',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoMisto,
        valorFrete: 0,
      ),
    );

    vendas.converterOrcamentoParaVenda(
      orcId,
      permitirVendaSemEstoque: false,
    );

    final depois = db.produtoBox.get(produto.id)!;
    expect(depois.estoqueReal, 2);
    expect(depois.estoqueReservado, 2);
    expect(depois.estoqueLivreParaVenda, 0);
  });

  test('persiste tipoEntregaItem no ObjectBox apos registrarOrcamento', () {
    final produto = produtoBase();
    final orcId = vendas.registrarOrcamento(
      [
        ItemVendaInput(
          produtoId: produto.id,
          quantidade: 2,
          precoUnitario: 3.5,
          tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
        ),
      ],
      pagamento: DadosPagamentoOrcamento(
        formaPagamento: 'pix',
        quantidadeParcelas: 1,
      ),
      entrega: DadosEntregaOrcamento(
        tipoEntrega: EntregaVendaHelper.tipoRetiradaFutura,
        valorFrete: 0,
      ),
    );

    final fresh = db.itemVendaBox.get(
      vendas.listarItensPorVenda(orcId).first.id,
    )!;
    expect(fresh.tipoEntregaItem, EntregaVendaHelper.tipoRetiradaFutura);

    final venda = db.vendaBox.get(orcId)!;
    expect(venda.tipoEntrega, EntregaVendaHelper.tipoRetiradaFutura);
    expect(venda.entregaPendente, isTrue);
  });

  test(
    'finalizar preserva preco unitario manual do PDV (nao reaplica catalogo)',
    () {
      final produto = produtoBase();
      // Catalogo 3.50; PDV autorizou 2.80 manualmente.
      final orcId = vendas.registrarOrcamento(
        [
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 2,
            precoUnitario: 2.80,
            precoUnitarioManual: true,
            tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
          ),
        ],
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: 'dinheiro',
          quantidadeParcelas: 1,
        ),
        entrega: DadosEntregaOrcamento(
          tipoEntrega: EntregaVendaHelper.tipoRetirada,
          valorFrete: 0,
        ),
      );

      final antes = vendas.listarItensPorVenda(orcId).first;
      expect(antes.precoUnitario, closeTo(2.80, 0.001));
      expect(antes.precoUnitarioManual, isTrue);
      expect(vendas.obterPorId(orcId)!.total, closeTo(5.60, 0.001));

      vendas.converterOrcamentoParaVenda(orcId);

      final depois = vendas.listarItensPorVenda(orcId).first;
      expect(depois.precoUnitario, closeTo(2.80, 0.001));
      expect(depois.precoUnitarioManual, isTrue);
      expect(vendas.obterPorId(orcId)!.total, closeTo(5.60, 0.001));
    },
  );

  test(
    'cancelar venda leva agora com quantidadeJaRetirada (baixa cupom) e permitido',
    () {
      final produto = produtoBase(estoque: 20);
      final orcId = vendas.registrarOrcamento(
        [
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 2,
            precoUnitario: 3.5,
            tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
          ),
        ],
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: 'dinheiro',
          quantidadeParcelas: 1,
        ),
        entrega: DadosEntregaOrcamento(
          tipoEntrega: EntregaVendaHelper.tipoRetirada,
          valorFrete: 0,
        ),
      );

      vendas.converterOrcamentoParaVenda(orcId);
      final item = vendas.listarItensPorVenda(orcId).first;
      // Baixa automatica do cupom / leva agora.
      expect(item.quantidadeJaRetirada, greaterThan(0));
      expect(vendas.mensagemBloqueioCancelamentoVenda(orcId), isNull);

      vendas.cancelarVenda(orcId, motivo: 'Teste cancelamento NFC-e');
      final venda = vendas.obterPorId(orcId)!;
      expect(venda.cancelada, isTrue);
      expect(db.produtoBox.get(produto.id)!.estoqueReal, 20);
    },
  );

  test(
    'finalizar preserva preco divergente legado sem flag (inferencia manual)',
    () {
      final produto = produtoBase();
      final orcId = vendas.registrarOrcamento(
        [
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: 1,
            precoUnitario: 9.90,
            // Sem flag — orcamentos antigos antes da correcao.
            tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
          ),
        ],
        pagamento: DadosPagamentoOrcamento(
          formaPagamento: 'pix',
          quantidadeParcelas: 1,
        ),
        entrega: DadosEntregaOrcamento(
          tipoEntrega: EntregaVendaHelper.tipoRetirada,
          valorFrete: 0,
        ),
      );

      vendas.converterOrcamentoParaVenda(orcId);

      final item = vendas.listarItensPorVenda(orcId).first;
      expect(item.precoUnitario, closeTo(9.90, 0.001));
      expect(item.precoUnitarioManual, isTrue);
      expect(vendas.obterPorId(orcId)!.total, closeTo(9.90, 0.001));
    },
  );
    },
    skip: skipObjectBox,
  );
}
