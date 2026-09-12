import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/produto_busca_util.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  group('produto interno sistema', () {
    test('identifica codigo __FRETE_RET_FUTURA__', () {
      final p = Produto(
        codigoInterno: kCodigoInternoFreteRetiradaFutura,
        nome: 'Servico: Frete carreto (retirada futura)',
        quantidadeMinima: 0,
        precoCusto: 0,
        precoVenda: 0,
      );
      expect(produtoEhCadastroInternoSistema(p), isTrue);
      expect(produtoEhCadastroInternoSistema(
        Produto(codigoInterno: 'TUBO-25', nome: 'Tubo', quantidadeMinima: 0, precoCusto: 0, precoVenda: 0),
      ), isFalse);
    });
  });

  group('consulta codigo barras', () {
    test('detecta EAN com 13 digitos', () {
      expect(consultaPareceCodigoBarras('7891234567890'), isTrue);
      expect(consultaEanProvavelCompleto('7891234567890'), isTrue);
    });

    test('ignora texto misto', () {
      expect(consultaEanProvavelCompleto('cimento 50kg'), isFalse);
    });

    test('normaliza digitos', () {
      expect(
        normalizarCodigoBarrasConsulta('789 1234 567890'),
        '7891234567890',
      );
    });
  });

  group('apelidos', () {
    test('parse separadores', () {
      expect(
        parseApelidosBusca('bacia sabara; kit c33\n7891234567890'),
        ['bacia sabara', 'kit c33', '7891234567890'],
      );
    });

    test('extrai EAN alternativo', () {
      expect(
        codigosBarrasAlternativosDeApelidos(['ref 8821', '7891234567890']),
        ['7891234567890'],
      );
    });
  });

  group('medidas', () {
    test('extrai mm e fracao', () {
      final tokens = extrairTokensMedidasDeTexto(
        'tubo pvc 50mm 3/4 polegada 2,44x1,22',
      );
      expect(tokens, contains('50mm'));
      expect(tokens, contains('3/4'));
      expect(tokens, contains('2,44x1,22'));
    });
  });

  group('sku numerico zeros a esquerda', () {
    test('remove zeros para indexacao', () {
      expect(skuNumericoSemZerosEsquerda('008858'), '8858');
      expect(skuNumericoSemZerosEsquerda('8858'), '8858');
      expect(skuNumericoSemZerosEsquerda('000'), '0');
    });

    test('match exato ignora zeros a esquerda', () {
      expect(skuBuscaCorrespondeExato('8858', '008858'), isTrue);
      expect(skuBuscaCorrespondeExato('008858', '8858'), isTrue);
      expect(skuBuscaCorrespondeExato('8858', '8858'), isTrue);
      expect(skuBuscaCorrespondeExato('8859', '008858'), isFalse);
    });

    test('pontuacao parcial para prefixo do sku', () {
      expect(skuBuscaPontuacaoParcial('8858', '008858'), 1000);
      expect(skuBuscaPontuacaoParcial('885', '008858'), 880);
      expect(skuBuscaPontuacaoParcial('858', '008858'), 720);
    });

    test('nao confunde sku alfanumerico', () {
      expect(skuNumericoSemZerosEsquerda('SKU-123'), isNull);
      expect(skuBuscaCorrespondeExato('123', 'SKU-123'), isFalse);
    });

    test('normaliza sku numerico para gravacao', () {
      expect(normalizarCodigoInternoPersistido('008858'), '8858');
      expect(normalizarCodigoInternoPersistido('8858'), '8858');
      expect(normalizarCodigoInternoPersistido('SKU-123'), 'SKU-123');
      expect(
        normalizarCodigoInternoPersistido('__FRETE_RET_FUTURA__'),
        '__FRETE_RET_FUTURA__',
      );
    });

    test('sequencia numerica curta ignora SKU- legado', () {
      expect(skuEhNumericoSequencial('8858'), isTrue);
      expect(skuEhNumericoSequencial('SKU-1783274764271'), isFalse);
      expect(skuComoInteiroSequencial('008858'), 8858);
      expect(
        proximoSkuNumericoSequencial(['8858', '1650', 'SKU-1783274764271']),
        '8859',
      );
      expect(proximoSkuNumericoSequencial(const []), '1');
      expect(skuPareceCodigoBarrasGtin('2890000040018'), isTrue);
      expect(skuEhNumericoSequencialCurto('2890000040018'), isFalse);
      expect(
        proximoSkuNumericoSequencial(['2890000040018', '2100000000012', '12']),
        '13',
      );
    });
  });

  group('tokenizar consulta obra', () {
    test('agrupa 1 1/2x13 sem token 1 solto', () {
      final p = tokenizarConsultaObra('prego 1 1/2x13');
      expect(p.tokensSignificativos, contains('prego'));
      expect(p.tokensSignificativos, contains('1 1/2x13'));
      expect(p.tokensSignificativos, isNot(contains('1')));
      expect(p.consultaCompacta, 'prego11/2x13');
    });

    test('1 nao casa dentro de 21', () {
      expect(textoContemTokenObra('prego 21/2x10', '1'), isFalse);
      expect(textoContemTokenObra('prego 1 1/2x13 15x18', '1'), isTrue);
    });

    test('3 letras casam prefixo no inicio da palavra', () {
      expect(textoContemTokenObra('tubo sod fortlev 25', 'tub'), isTrue);
      expect(textoContemTokenObra('tubo sod fortlev 25', 'tubo'), isTrue);
      expect(textoContemTokenObra('caputrola xyz', 'tub'), isFalse);
    });

    test('mantem bitola 25 na consulta tubo 25', () {
      final p = tokenizarConsultaObra('tubo 25');
      expect(p.tokensSignificativos, containsAll(['tubo', '25']));
      expect(p.frases, contains('tubo 25'));
    });

    test('sequencia tubo depois 25 no nome', () {
      expect(
        sequenciaTokensNoTexto(
          'tubo sod fortlev 25',
          const ['tubo', '25'],
        ),
        isTrue,
      );
      expect(
        sequenciaTokensNoTexto('tubo pvc 50mm', const ['tubo', '25']),
        isFalse,
      );
    });

    test('normalizar consulta curinga preserva percentual', () {
      final norm = normalizarConsultaCuringa(
        'Tub%Sod%20',
        (s) => s.toLowerCase(),
      );
      expect(norm, 'tub%sod%20');
      expect(consultaUsaModoCuringa(norm), isTrue);
      expect(parseConsultaCuringa(norm)?.segmentos, ['tub', 'sod', '20']);
    });

    test('curinga tub%sod%25 casa nome alvo', () {
      expect(consultaUsaModoCuringa('tub%sod%25'), isTrue);
      final p = parseConsultaCuringa('tub%sod%25');
      expect(p?.segmentos, ['tub', 'sod', '25']);
      final m = avaliarMatchCuringa('tubo sod fortlev 25', p!.segmentos);
      expect(m, isNotNull);
      expect(
        avaliarMatchCuringa('tubo pvc 50mm', p.segmentos),
        isNull,
      );
    });

    test('curinga tub casa dentro de tubo', () {
      final p = parseConsultaCuringa('tub%sod%25')!;
      expect(avaliarMatchCuringa('tubo sod fortlev 25', p.segmentos), isNotNull);
    });

    test('20 nao casa dentro de 25 no modo curinga', () {
      expect(indiceSegmentoCuringa('tubo sod fortlev 25', '20', 0), -1);
      expect(indiceSegmentoCuringa('tubo sod fortlev 25', '25', 0), greaterThan(0));
    });

    test('sem percentual nao ativa curinga', () {
      expect(consultaUsaModoCuringa('tubo sod 25'), isFalse);
    });

    test('compacto casa prego 1 1/2x13 no nome alvo', () {
      final consulta = tokenizarConsultaObra('prego 1 1/2x13');
      final nome = compactarTextoBuscaObra('prego 1 1/2x13 15x18');
      expect(nome.contains(consulta.consultaCompacta), isTrue);
      expect(
        compactarTextoBuscaObra('prego 21/2x10').contains(consulta.consultaCompacta),
        isFalse,
      );
    });
  });

  group('ordenacao cabos', () {
    test('extrai bitola mm com virgula ou ponto', () {
      expect(extrairBitolaMmProduto('Cabo 2,5mm Flex'), 2.5);
      expect(extrairBitolaMmProduto('Cabo 10mm Preto'), 10);
      expect(extrairBitolaMmProduto('Cabo p/Martelo 35cm'), isNull);
    });

    test('ordena por bitola e desempata marca na mesma bitola', () {
      final nomes = [
        'Cabo 10mm Flexivel 750v Preto',
        'Cabo 2.5mm SIL Flex',
        'Cabo 2.5mm Megatron Flex',
        'Cabo 2.5mm Cobrecom Flex',
        'Cabo 1.5mm Flexivel',
        'Cabo 4.0mm Flexivel',
        'Cabo 6.0mm Flex',
        'Cabo 2.5mm Conduscabos Flex',
        'Cabo p/Martelo 35cm',
        'Cabo Rj45 3m Rede LAN',
      ];
      nomes.sort(compararProdutosBuscaCabo);
      expect(
        nomes,
        [
          'Cabo 1.5mm Flexivel',
          'Cabo 2.5mm Cobrecom Flex',
          'Cabo 2.5mm Conduscabos Flex',
          'Cabo 2.5mm Megatron Flex',
          'Cabo 2.5mm SIL Flex',
          'Cabo 4.0mm Flexivel',
          'Cabo 6.0mm Flex',
          'Cabo 10mm Flexivel 750v Preto',
          'Cabo p/Martelo 35cm',
          'Cabo Rj45 3m Rede LAN',
        ],
      );
    });

    test('ordenacao contextual so quando consulta menciona cabo', () {
      expect(ordenacaoContextualCaboAtiva('cabo'), isTrue);
      expect(ordenacaoContextualCaboAtiva('cabo 2.5'), isTrue);
      expect(ordenacaoContextualCaboAtiva('tubo 25'), isFalse);
    });
  });

  group('pesquisarProdutosEmMemoria (terminal)', () {
    Produto p(String nome, {String codigo = '', bool ativo = true}) => Produto(
          codigoInterno: codigo.isEmpty ? nome : codigo,
          nome: nome,
          quantidadeMinima: 0,
          precoCusto: 0,
          precoVenda: 10,
          ativo: ativo,
        );

    test('curinga % casa trechos no nome', () {
      final lista = [
        p('Tubo Sod Fortlev 25mm'),
        p('Tubo PVC 50mm esgoto'),
        p('Cimento CP II 50kg'),
      ];
      final r = pesquisarProdutosEmMemoria(lista, 'tub%sod%25');
      expect(r.map((e) => e.nome), ['Tubo Sod Fortlev 25mm']);
    });

    test('literal % nao casa sem modo curinga valido', () {
      final lista = [p('Produto 100% original')];
      // "100%" sozinho: segmento curto apos split pode invalidar
      final r = pesquisarProdutosEmMemoria(lista, 'original');
      expect(r, hasLength(1));
    });

    test('busca normal ignora acento', () {
      final lista = [p('Conexão Joelho 90')];
      final r = pesquisarProdutosEmMemoria(lista, 'conexao');
      expect(r, hasLength(1));
    });

    test('exclui produtos internos do sistema', () {
      final lista = [
        p('Frete', codigo: kCodigoInternoFreteRetiradaFutura),
        p('Tubo PVC'),
      ];
      final r = pesquisarProdutosEmMemoria(
        lista,
        'tubo',
        excluirProdutosInternos: true,
      );
      expect(r.map((e) => e.nome), ['Tubo PVC']);
    });

    test('reordenar lista simula retorno da API fora de ordem', () {
      Produto p(String nome) => Produto(
            codigoInterno: nome,
            nome: nome,
            quantidadeMinima: 0,
            precoCusto: 0,
            precoVenda: 10,
          );
      final api = [
        p('Cabo 10mm Flexivel 750v Preto'),
        p('Cabo p/Martelo 35cm'),
        p('Cabo 2.5mm Cobrecom Flex'),
        p('Cabo Rj45 3m Rede LAN'),
        p('Cabo 1.5mm Flexivel'),
      ];
      final ordenado = reordenarResultadoBuscaProdutos(api, 'cabo');
      expect(
        ordenado.map((e) => e.nome),
        [
          'Cabo 1.5mm Flexivel',
          'Cabo 2.5mm Cobrecom Flex',
          'Cabo 10mm Flexivel 750v Preto',
          'Cabo p/Martelo 35cm',
          'Cabo Rj45 3m Rede LAN',
        ],
      );
    });

    test('busca cabo agrupa bitolas e desempata marcas', () {
      final lista = [
        p('Cabo 10mm Flexivel 750v Preto'),
        p('Cabo 2.5mm SIL Flex'),
        p('Cabo 2.5mm Megatron Flex'),
        p('Cabo 2.5mm Cobrecom Flex'),
        p('Cabo 1.5mm Flexivel'),
        p('Cabo 4.0mm Flexivel'),
        p('Cabo 6.0mm Flex'),
        p('Cabo 2.5mm Conduscabos Flex'),
        p('Cabo p/Martelo 35cm'),
        p('Cabo Rj45 3m Rede LAN'),
      ];
      final r = pesquisarProdutosEmMemoria(lista, 'cabo');
      expect(
        r.map((e) => e.nome),
        [
          'Cabo 1.5mm Flexivel',
          'Cabo 2.5mm Cobrecom Flex',
          'Cabo 2.5mm Conduscabos Flex',
          'Cabo 2.5mm Megatron Flex',
          'Cabo 2.5mm SIL Flex',
          'Cabo 4.0mm Flexivel',
          'Cabo 6.0mm Flex',
          'Cabo 10mm Flexivel 750v Preto',
          'Cabo p/Martelo 35cm',
          'Cabo Rj45 3m Rede LAN',
        ],
      );
    });
  });
}
