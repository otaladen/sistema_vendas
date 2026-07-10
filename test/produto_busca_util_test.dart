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
}
