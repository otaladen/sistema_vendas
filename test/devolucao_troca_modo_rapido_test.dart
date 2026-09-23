import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/data/venda_repository.dart';
import 'package:sistema_vendas/domain/devolucao_troca_modo_fluxo.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/troca_diferenca_caixa.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'helpers/objectbox_dll_for_tests.dart';

@Tags(['objectbox'])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final skipObjectBox = prepararObjectBoxDllParaTestes();

  group('DevolucaoTrocaModoPolitica', () {
    test('modo estoque/caixa nao emite NF-e mesmo com NFC-e autorizada', () {
      expect(
        DevolucaoTrocaModoPolitica.deveEmitirNfeDevolucaoSefaz(
          modo: DevolucaoTrocaModoFluxo.estoqueCaixa,
          nfceAutorizadaAtiva: true,
          nfe55Autorizada: false,
        ),
        isFalse,
      );
      expect(
        DevolucaoTrocaModoPolitica.exibirAvisoFiscalObrigatorio(
          modo: DevolucaoTrocaModoFluxo.estoqueCaixa,
          nfceAutorizadaAtiva: true,
          nfe55Autorizada: true,
        ),
        isFalse,
      );
    });

    test('modo fiscal emite NF-e quando venda tem nota', () {
      expect(
        DevolucaoTrocaModoPolitica.deveEmitirNfeDevolucaoSefaz(
          modo: DevolucaoTrocaModoFluxo.nfDevolucaoSefaz,
          nfceAutorizadaAtiva: true,
          nfe55Autorizada: false,
        ),
        isTrue,
      );
    });

    test('terminal leve so bloqueia se operador pediu fiscal com nota', () {
      expect(
        DevolucaoTrocaModoPolitica.bloqueiaRegistroTerminalLevePorFiscal(
          modo: DevolucaoTrocaModoFluxo.estoqueCaixa,
          nfceAutorizadaAtiva: true,
          nfe55Autorizada: false,
          repositorioRemoto: true,
        ),
        isFalse,
      );
      expect(
        DevolucaoTrocaModoPolitica.bloqueiaRegistroTerminalLevePorFiscal(
          modo: DevolucaoTrocaModoFluxo.nfDevolucaoSefaz,
          nfceAutorizadaAtiva: true,
          nfe55Autorizada: false,
          repositorioRemoto: true,
        ),
        isTrue,
      );
    });
  });

  group(
    'troca modo rapido (estoque e caixa)',
    () {
      late Directory tempDir;
      late ObjectBox db;
      late VendaRepository vendas;

      setUp(() {
        enterSyncApplySilencioso();
        tempDir = Directory.systemTemp.createTempSync('sv_troca_rapida_');
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

      Produto novoProduto({
        required String codigo,
        required String nome,
        int estoque = 20,
        double preco = 10,
      }) {
        final p = Produto(
          codigoInterno: codigo,
          nome: nome,
          unidade: 'UN',
          estoqueReal: estoque,
          estoqueAtual: estoque,
          quantidadeMinima: 0,
          precoCusto: preco * 0.5,
          precoVenda: preco,
          preco1: preco,
          preco2: preco,
          preco3: preco,
          ativo: true,
        );
        final id = db.produtoBox.put(p);
        p.id = id;
        return p;
      }

      test(
        'registra troca com entrada e saida de estoque sem exigir dados fiscais',
        skip: skipObjectBox,
        () {
          final vendido = novoProduto(codigo: 'A1', nome: 'Produto A', estoque: 50);
          final troca = novoProduto(codigo: 'B1', nome: 'Produto B', estoque: 30);

          final orcId = vendas.registrarOrcamento(
            [
              ItemVendaInput(
                produtoId: vendido.id,
                quantidade: 2,
                precoUnitario: 10,
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

          final venda = vendas.obterPorId(orcId)!;
          venda.nfceChaveAcesso =
              '35250900000000000000550010000000011000000001';
          db.vendaBox.put(venda);
          expect(venda.nfceAutorizadaAtiva, isTrue);

          expect(db.produtoBox.get(vendido.id)!.estoqueReal, 48);
          expect(db.produtoBox.get(troca.id)!.estoqueReal, 30);

          final item = vendas.listarItensPorVenda(orcId).first;
          final registroId = vendas.registrarDevolucaoOuTroca(
            vendaOrigemId: orcId,
            tipo: 'troca',
            motivo: 'Troca rapida balcao',
            observacaoFinanceira: '',
            registradoPor: 'teste',
            entradas: [
              LinhaDevolucaoEntradaInput(
                itemVendaId: item.id,
                quantidade: 1,
              ),
            ],
            saidasTroca: [
              LinhaTrocaSaidaInput(
                produtoId: troca.id,
                quantidade: 1,
                precoUnitario: 12,
                precoTipo: 'preco1',
                precoCustoUnitario: troca.precoCusto,
              ),
            ],
          );

          expect(registroId, greaterThan(0));
          expect(db.produtoBox.get(vendido.id)!.estoqueReal, 49);
          expect(db.produtoBox.get(troca.id)!.estoqueReal, 29);
          expect(
            vendas.listarItensPorVenda(orcId).first.quantidadeDevolvida,
            1,
          );

          final diff = TrocaDiferencaCaixa.diferenca(
            valorSaida: 12,
            valorDevolvido: 10,
          );
          expect(TrocaDiferencaCaixa.clientePaga(diff), isTrue);

          final caixa = vendas.registrarOrcamentoComplementoTroca(
            vendaOrigemId: orcId,
            registroDevolucaoId: registroId,
            valor: diff,
            formaPagamento: 'dinheiro',
          );
          expect(caixa.numeroOrcamento, greaterThan(0));

          final orcCaixa = db.vendaBox.get(caixa.orcamentoId)!;
          expect(orcCaixa.status, 'orcamento');
          expect(orcCaixa.total, closeTo(2, 0.01));
        },
      );
    },
    skip: skipObjectBox,
  );
}
