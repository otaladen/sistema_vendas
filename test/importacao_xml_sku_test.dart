import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/nfe_entrada_repository.dart';
import 'package:sistema_vendas/data/objectbox.dart';
import 'package:sistema_vendas/data/produto_busca_util.dart';
import 'package:sistema_vendas/data/sync/sync_write_trigger.dart';
import 'package:sistema_vendas/domain/conferencia_nfe_opcoes.dart';
import 'package:sistema_vendas/domain/produto/sanitizar_skus_importados_util.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/vinculo_fornecedor_produto.dart';
import 'package:sistema_vendas/services/xml_nfe_parser_service.dart';

import 'helpers/objectbox_dll_for_tests.dart';

const _chave = '35260912345678000199550010000012341989739282';

String _xmlNfe({required String cProd, required String cEan}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe">
  <NFe>
    <infNFe Id="NFe$_chave" versao="4.00">
      <ide><nNF>1234</nNF><dhEmi>2026-09-20T10:00:00-03:00</dhEmi></ide>
      <emit>
        <CNPJ>12345678000199</CNPJ>
        <xNome>Distribuidora Teste LTDA</xNome>
        <xFant>Distribuidora Teste</xFant>
      </emit>
      <det nItem="2">
        <prod>
          <cProd>$cProd</cProd>
          <cEAN>$cEan</cEAN>
          <xProd>ARGAMASSA AC-II 20KG</xProd>
          <NCM>32149000</NCM>
          <CFOP>5102</CFOP>
          <uCom>SC</uCom>
          <qCom>10.0000</qCom>
          <vUnCom>25.00</vUnCom>
          <cEANTrib>$cEan</cEANTrib>
          <uTrib>SC</uTrib>
          <qTrib>10.0000</qTrib>
          <vUnTrib>25.00</vUnTrib>
        </prod>
      </det>
      <total><ICMSTot><vNF>250.00</vNF></ICMSTot></total>
    </infNFe>
  </NFe>
</nfeProc>
''';

Produto _produto(String sku, {String nome = 'Produto', int id = 0}) => Produto(
  id: id,
  codigoInterno: sku,
  nome: nome,
  quantidadeMinima: 0,
  precoCusto: 1,
  precoVenda: 2,
);

void main() {
  group('apelidosBuscaComCodigoFornecedor', () {
    test('acrescenta cProd sem duplicar nem repetir o EAN', () {
      expect(
        apelidosBuscaComCodigoFornecedor('', codigoFornecedor: 'AC2-20'),
        'AC2-20',
      );
      expect(
        apelidosBuscaComCodigoFornecedor(
          'argamassa cinza',
          codigoFornecedor: 'AC2-20',
        ),
        'argamassa cinza; AC2-20',
      );
      expect(
        apelidosBuscaComCodigoFornecedor(
          'ac2-20',
          codigoFornecedor: 'AC2-20',
        ),
        'ac2-20',
      );
      expect(
        apelidosBuscaComCodigoFornecedor(
          '',
          codigoFornecedor: '7891234567895',
          codigoBarras: '7891234567895',
        ),
        '',
      );
    });
  });

  group('SanitizarSkusImportadosUtil.planejar', () {
    test('troca NFE- por SKU sequencial e guarda cProd e SKU antigo', () {
      final plano = SanitizarSkusImportadosUtil.planejar(
        [
          _produto('3424', id: 1),
          _produto('7891234567895', id: 2),
          _produto('NFE-98973928-3', id: 4),
          _produto('NFE-98973928-2', id: 3),
        ],
        codigosFornecedorPorProduto: {
          3: ['AC2-20'],
        },
      );

      expect(plano.map((p) => p.produtoId), [3, 4]);
      expect(plano.map((p) => p.skuNovo), ['3425', '3426']);
      expect(
        parseApelidosBusca(plano.first.apelidosBuscaNovos),
        ['AC2-20', 'NFE-98973928-2'],
      );
    });

    test('ignora produtos que ja possuem SKU normal', () {
      final plano = SanitizarSkusImportadosUtil.planejar([
        _produto('10', id: 1),
        _produto('SKU-ABC', id: 2),
      ]);
      expect(plano, isEmpty);
    });
  });

  group(
    'importacao XML -> SKU sequencial (ObjectBox)',
    () {
      late Directory tempDir;
      late ObjectBox db;
      late NfeEntradaRepository repo;

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        enterSyncApplySilencioso();
        tempDir = Directory.systemTemp.createTempSync('sv_nfe_sku_');
        db = ObjectBox.createForTest(tempDir);
        repo = NfeEntradaRepository(db);
      });

      tearDown(() {
        leaveSyncApplySilencioso();
        db.close();
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      List<int> importar(String xml) {
        final nfe = XmlParserService.parseNfeXmlString(xml);
        final sugestoes = repo.prepararSugestoesConferencia(nfe);
        return repo.confirmarEntrada(
          nfe: nfe,
          linhas: [
            for (final s in sugestoes)
              ConferenciaNfeLinhaConfirmacao(
                item: s.item,
                fatorConversao: s.fatorInicial,
                unidadeInterna: s.unidadeInternaInicial,
                embalagemMultiplica: s.embalagemMultiplicaInicial,
                produtoExistenteId: s.produtoExistenteId,
              ),
          ],
          opcoes: const ConferenciaNfeOpcoes(gerarContasPagar: false),
        );
      }

      test(
        'produto novo recebe SKU numerico sequencial e guarda cProd/EAN',
        () {
          db.produtoBox.putMany([
            _produto('3424', nome: 'Cimento'),
            _produto('7891000100103', nome: 'GTIN usado como SKU'),
            _produto('SKU-ANTIGO', nome: 'Alfanumerico'),
          ]);

          final xml = _xmlNfe(cProd: 'AC2-20', cEan: '7891234567895');
          final nfe = XmlParserService.parseNfeXmlString(xml);
          expect(
            repo.prepararSugestoesConferencia(nfe).single.produtoNovo,
            isTrue,
          );

          final ids = importar(xml);
          final novo = db.produtoBox.get(ids.single)!;

          expect(novo.codigoInterno, '3425');
          expect(novo.codigoInterno.startsWith('NFE-'), isFalse);
          expect(novo.codigoBarras, '7891234567895');
          expect(parseApelidosBusca(novo.apelidosBusca), contains('AC2-20'));
          expect(novo.estoqueReal, 10);

          final vinculos = db.vinculoFornecedorProdutoBox
              .getAll()
              .where((v) => v.produto.targetId == novo.id)
              .toList();
          expect(
            vinculos.map((v) => v.codigoProdutoFornecedor),
            ['AC2-20'],
          );
        },
      );

      test('estorno ainda remove o produto criado pela propria nota', () {
        db.produtoBox.put(_produto('3424', nome: 'Cimento'));
        final ids = importar(_xmlNfe(cProd: 'AC2-20', cEan: ''));
        final novoId = ids.single;
        expect(db.produtoBox.get(novoId)!.codigoInterno, '3425');

        final registro = repo.obterImportacaoPorChave(_chave)!;
        repo.estornarImportacaoNfe(registro.id);

        expect(db.produtoBox.get(novoId), isNull);
      });

      test('aplicar sanitizacao preserva id, estoque e vinculo', () {
        db.produtoBox.put(_produto('3424', nome: 'Cimento'));
        final legado = _produto('NFE-98973928-2', nome: 'Argamassa')
          ..estoqueReal = 37
          ..estoqueAtual = 37;
        legado.id = db.produtoBox.put(legado);
        final vinculo = VinculoFornecedorProduto(
          codigoProdutoFornecedor: 'AC2-20',
          fatorConversao: 1,
        )..produto.targetId = legado.id;
        db.vinculoFornecedorProdutoBox.put(vinculo);

        final simulado = SanitizarSkusImportadosUtil.aplicar(
          db,
          simular: true,
        );
        expect(simulado.single.skuNovo, '3425');
        expect(db.produtoBox.get(legado.id)!.codigoInterno, 'NFE-98973928-2');

        SanitizarSkusImportadosUtil.aplicar(db);
        final depois = db.produtoBox.get(legado.id)!;
        expect(depois.codigoInterno, '3425');
        expect(depois.estoqueReal, 37);
        expect(
          parseApelidosBusca(depois.apelidosBusca),
          containsAll(['AC2-20', 'NFE-98973928-2']),
        );
        expect(
          db.vinculoFornecedorProdutoBox.getAll().single.produto.targetId,
          legado.id,
        );
      });
    },
    skip: prepararObjectBoxDllParaTestes(),
  );
}
