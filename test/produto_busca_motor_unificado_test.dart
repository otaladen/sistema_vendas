import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/api/lan_api_client.dart';
import 'package:sistema_vendas/data/api/produto_api_repository.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec.dart';
import 'package:sistema_vendas/domain/pdv_busca_inteligente.dart';
import 'package:sistema_vendas/domain/produto/produto_busca_util.dart';
import 'package:sistema_vendas/model/produto.dart';

var _proximoId = 1;

Produto _p(
  String nome, {
  String marca = '',
  String apelidos = '',
  String categoria = '',
  String codigoBarras = '',
  int estoque = 10,
  double vendaMediaDiaria = 0,
}) {
  final id = _proximoId++;
  return Produto(
    id: id,
    codigoInterno: '$id',
    nome: nome,
    marca: marca,
    apelidosBusca: apelidos,
    categoria: categoria,
    codigoBarras: codigoBarras,
    estoqueReal: estoque,
    vendaMediaDiaria: vendaMediaDiaria,
    quantidadeMinima: 0,
    precoCusto: 1,
    precoVenda: 2,
  );
}

List<String> _nomes(List<Produto> produtos) =>
    produtos.map((p) => p.nome).toList();

List<Produto> _buscar(List<Produto> catalogo, String termo) =>
    ProdutoBuscaUtil.pesquisar(
      ProdutoBuscaUtil.criarDocs(catalogo),
      termo,
      limite: 500,
      excluirProdutosInternos: true,
    );

/// Produto como chega ao terminal: serializado pelo servidor e lido de volta.
List<Produto> _viaRede(List<Produto> catalogo) => catalogo
    .map(
      (p) => SyncEntityCodec.produtoDeMap(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(SyncEntityCodec.produtoParaMap(p))) as Map,
        ),
      ),
    )
    .toList();

/// Responde `/api/produtos` com o ranking do motor, como a rota do PC servidor.
class _ServidorFake extends LanApiClient {
  _ServidorFake(this.catalogo) : super(baseUrl: 'http://127.0.0.1:1');

  final List<Produto> catalogo;

  @override
  Future<List<Produto>> listarProdutos({
    String q = '',
    int limit = 200,
    int offset = 0,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) async {
    final ranking = ProdutoBuscaUtil.pesquisar(
      ProdutoBuscaUtil.criarDocs(catalogo),
      q,
      offset: offset,
      limite: limit,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
    );
    return _viaRede(ranking);
  }
}

List<Produto> _catalogoLoja() => [
      _p('Cotovelo 90 PVC 25mm', marca: 'Tigre', apelidos: 'joelho; joelho 90'),
      _p('Tubo Soldavel 25mm 6m', marca: 'Tigre', categoria: 'Hidraulica'),
      _p('Tubo Soldavel 25mm 6m', marca: 'Amanco', categoria: 'Hidraulica'),
      _p('Luva Soldavel 25mm', marca: 'Amanco'),
      _p('Cimento Poty CP II 50kg', marca: 'Poty', categoria: 'Cimento'),
      _p('Argamassa AC1 20kg', marca: 'Quartzolit'),
      _p('Zarcão 900ml Renove', marca: 'Renove'),
      _p('Zarcão 3,6l Galvomax', marca: 'Galvomax'),
      _p('Zarcão 225ml Galvomax', marca: 'Galvomax'),
      _p('Zarcão 3,6l Renove Base Agua Cinza', marca: 'Renove'),
      _p('Zarcão 3,6l Renove', marca: 'Renove', vendaMediaDiaria: 4),
      _p('Zarcão 900ml Galvomax', marca: 'Galvomax', estoque: 0),
      _p('Cabo Flexivel 2,5mm Sil', marca: 'Sil'),
      _p('Cabo Flexivel 1,5mm Sil', marca: 'Sil'),
      _p('Cano Esgoto 100mm', marca: 'Tigre'),
      _p('Areia Media Lavada m3', estoque: 30),
      _p('Areia Fina m3', estoque: 0),
      _p('Areia Grossa m3', estoque: 12),
    ];

void main() {
  late List<Produto> catalogo;

  setUp(() {
    _proximoId = 1;
    catalogo = _catalogoLoja();
  });

  group('filtro obrigatorio aceita apelido, marca e erro de digitacao', () {
    test('apelido "joelho" encontra Cotovelo 90 PVC', () {
      final r = _buscar(catalogo, 'joelho');
      expect(_nomes(r), ['Cotovelo 90 PVC 25mm']);
    });

    test('marca "tigre" encontra produtos sem Tigre no nome', () {
      final r = _buscar(catalogo, 'tigre');
      expect(
        _nomes(r),
        unorderedEquals([
          'Cotovelo 90 PVC 25mm',
          'Tubo Soldavel 25mm 6m',
          'Cano Esgoto 100mm',
        ]),
      );
      expect(r.every((p) => p.marca == 'Tigre'), isTrue);
    });

    test('"cimeto" (erro de digitacao) traz Cimento Poty primeiro', () {
      final r = _buscar(catalogo, 'cimeto');
      expect(r, isNotEmpty);
      expect(r.first.nome, 'Cimento Poty CP II 50kg');
    });

    test('erro de digitacao nao se aplica quando a palavra existe no catalogo',
        () {
      // "cabo" existe: "Cano Esgoto" nao pode entrar como "erro" de cabo.
      final r = _buscar(catalogo, 'cabo');
      expect(
        _nomes(r),
        ['Cabo Flexivel 1,5mm Sil', 'Cabo Flexivel 2,5mm Sil'],
      );
    });

    test('termo no nome vem antes de termo so na marca', () {
      final r = _buscar(catalogo, 'tubo tigre');
      expect(r.first.nome, 'Tubo Soldavel 25mm 6m');
      expect(r.first.marca, 'Tigre');
    });
  });

  group('agrupamento por medida e desempate', () {
    test('"zarcao" agrupa 3,6l Galvomax e 3,6l Renove lado a lado', () {
      final nomes = _nomes(_buscar(catalogo, 'zarcao'));
      final iGalvomax = nomes.indexOf('Zarcão 3,6l Galvomax');
      final iRenove = nomes.indexOf('Zarcão 3,6l Renove');
      expect(iGalvomax, greaterThanOrEqualTo(0));
      expect(iRenove, iGalvomax + 1);
    });

    test('"zarcao" ordena por embalagem e sem estoque no fim de cada uma', () {
      expect(_nomes(_buscar(catalogo, 'zarcao')), [
        'Zarcão 225ml Galvomax',
        'Zarcão 900ml Renove',
        'Zarcão 900ml Galvomax',
        'Zarcão 3,6l Galvomax',
        'Zarcão 3,6l Renove',
        'Zarcão 3,6l Renove Base Agua Cinza',
      ]);
    });

    test('texto extra no fim do nome nao separa o produto do grupo', () {
      final nomes = _nomes(_buscar(catalogo, 'zarcao'));
      expect(
        nomes.indexOf('Zarcão 3,6l Renove Base Agua Cinza'),
        nomes.indexOf('Zarcão 3,6l Renove') + 1,
      );
    });

    test('"zarcao 3,6" traz todos os 3,6 antes, mesmo sem estoque', () {
      final lista = [
        _p('Zarcao 3,6l Renove Base Agua Cinza', estoque: 3),
        _p('Zarcao 225ml Zarcomax', estoque: 1),
        _p('Zarcao 900ml Universo Verm/Cinza', estoque: 3),
        _p('Zarcao 3,6l Galvomax Galv BR', estoque: 0),
        _p('Zarcao 225ml Natrielli Pitbull', estoque: 0),
        _p('Zarcao 900ml Iquine Galvomax Galv Branco', estoque: 0),
        _p('Zarcao 900ml Renove Base Agua', estoque: -1),
        _p('Zarcao 900ml Zarcofer', estoque: 0),
        _p('Zarcao 13,6kg Industrial', estoque: 5),
      ];
      for (final termo in ['zarcao 3,6', 'zarcao 3.6', 'zarcao 3,6l']) {
        final nomes = _nomes(_buscar(lista, termo));
        expect(
          nomes.take(2).toList(),
          [
            'Zarcao 3,6l Renove Base Agua Cinza',
            'Zarcao 3,6l Galvomax Galv BR',
          ],
          reason: termo,
        );
        expect(nomes, hasLength(lista.length), reason: termo);
      }
    });

    test('"zarcao" agrupa 225ml, 900ml e 3,6l mesmo com estoque misto', () {
      Produto z(String nome, int estoque, {String descricao = 'Zarcão anticorrosivo'}) {
        final p = _p(nome, estoque: estoque);
        p.descricao = descricao;
        return p;
      }

      final lista = [
        z('Zarcao 225ml Zarcomax', 1),
        z('Zarcao 900ml Universo Verm/Cinza', 3),
        z('Zarcao 3,6l Renove Base Agua Cinza', 3),
        z('Zarcao 225ml Natrielli Pitbull', 0),
        z('Zarcao 900ml Iquine Galvomax Galv Branco', 0),
        z('Zarcao 900ml Renove Base Agua', -1),
        z('Zarcao 3,6l Galvomax Galv BR', 0),
        z('Zarcao 900ml Zarcofer', 0, descricao: ''),
      ];
      expect(_nomes(_buscar(lista, 'zarcao')), [
        'Zarcao 225ml Zarcomax',
        'Zarcao 225ml Natrielli Pitbull',
        'Zarcao 900ml Universo Verm/Cinza',
        'Zarcao 900ml Iquine Galvomax Galv Branco',
        'Zarcao 900ml Renove Base Agua',
        'Zarcao 900ml Zarcofer',
        'Zarcao 3,6l Renove Base Agua Cinza',
        'Zarcao 3,6l Galvomax Galv BR',
      ]);
    });

    test('"tubo": nome que comeca com tubo vem antes de "... em Tubo"', () {
      final lista = [
        _p('Solda Especial 22g em Tubo', estoque: 6),
        _p('Adesivo 175g Amanco Plast p/Tubo PVC C/Pincel', estoque: 0),
        _p('Tubo PVC Soldavel Fortlev 25mm', estoque: 0),
        _p('Tubo PVC Soldavel Fortlev 20mm', estoque: 1),
        _p('mt Tubo ESG 40mm Tigre 1m', estoque: 0),
        _p('Tubo PVC Esgoto Fortlev 100mm', estoque: 500),
      ];
      expect(_nomes(_buscar(lista, 'tubo')), [
        'Tubo PVC Soldavel Fortlev 20mm',
        'Tubo PVC Soldavel Fortlev 25mm',
        'Tubo PVC Esgoto Fortlev 100mm',
        'mt Tubo ESG 40mm Tigre 1m',
        'Solda Especial 22g em Tubo',
        'Adesivo 175g Amanco Plast p/Tubo PVC C/Pincel',
      ]);
    });

    test('decimal da consulta nao casa dentro de outro numero', () {
      final r = _buscar(
        [_p('Zarcao 13,6kg Industrial'), _p('Zarcao 3,6l Renove')],
        'zarcao 3,6',
      );
      expect(r.first.nome, 'Zarcao 3,6l Renove');
    });

    test('extrai medida do nome bruto (virgula decimal)', () {
      expect(
        ProdutoBuscaUtil.extrairMedidaProduto('Zarcão 3,6l Galvomax'),
        const MedidaProduto(TipoMedidaProduto.volume, 3600),
      );
      expect(
        ProdutoBuscaUtil.extrairMedidaProduto('Zarcão 225ml'),
        const MedidaProduto(TipoMedidaProduto.volume, 225),
      );
      expect(
        ProdutoBuscaUtil.extrairMedidaProduto('Cimento 50kg'),
        const MedidaProduto(TipoMedidaProduto.massa, 50000),
      );
      expect(
        ProdutoBuscaUtil.extrairMedidaProduto('Cabo Rj45 3m Rede'),
        const MedidaProduto(TipoMedidaProduto.comprimento, 3000),
      );
      expect(ProdutoBuscaUtil.extrairMedidaProduto('Luva lisa'), isNull);
    });
  });

  group('estoque', () {
    test('sem estoque aparece no fim e nao some', () {
      final r = _buscar(catalogo, 'areia');
      expect(r, hasLength(3));
      expect(
        _nomes(r.take(2).toList()),
        unorderedEquals(['Areia Grossa m3', 'Areia Media Lavada m3']),
      );
      expect(r.last.nome, 'Areia Fina m3');
    });

    test('correspondencia fraca sem estoque continua na lista', () {
      final lista = [
        _p('Cimento Poty 50kg', estoque: 0),
        _p('Rejunte Cinza', categoria: 'Cimento', estoque: 0),
      ];
      final r = _buscar(lista, 'cimento');
      expect(_nomes(r), ['Cimento Poty 50kg', 'Rejunte Cinza']);
    });
  });

  group('mesmo ranking no servidor e no terminal', () {
    const consultas = [
      'zarcao',
      'tigre',
      'joelho',
      'cimeto',
      'tubo 25',
      'cabo',
      'areia',
      'sold%25',
      'tubo soldavel',
    ];

    test('ProdutoApiRepository.pesquisar == motor do servidor', () {
      final terminal = ProdutoApiRepository(_ServidorFake(catalogo))
        ..carregarCatalogoLocal(_viaRede(catalogo));
      for (final termo in consultas) {
        final servidor = ProdutoBuscaUtil.pesquisar(
          ProdutoBuscaUtil.criarDocs(catalogo),
          termo,
          excluirProdutosInternos: true,
        );
        expect(
          terminal.pesquisarPadraoPdv(termo).map((p) => p.id).toList(),
          servidor.map((p) => p.id).toList(),
          reason: 'consulta "$termo"',
        );
      }
    });

    test('pesquisarRemoto preserva a ordem devolvida pelo servidor', () async {
      final terminal = ProdutoApiRepository(_ServidorFake(catalogo));
      for (final termo in consultas) {
        final servidor = ProdutoBuscaUtil.pesquisar(
          ProdutoBuscaUtil.criarDocs(catalogo),
          termo,
          limite: 40,
        );
        final remoto = await terminal.pesquisarRemoto(termo);
        expect(
          remoto.map((p) => p.id).toList(),
          servidor.map((p) => p.id).toList(),
          reason: 'consulta "$termo"',
        );
      }
    });

    test('resolverPesquisaPdv igual nos dois lados', () {
      final terminal = ProdutoApiRepository(_ServidorFake(catalogo))
        ..carregarCatalogoLocal(_viaRede(catalogo));
      final docs = ProdutoBuscaUtil.criarDocs(catalogo);
      for (final termo in ['joelho', 'zarcao', '5']) {
        final a = ProdutoBuscaUtil.resolverPesquisaPdv(docs, termo);
        final b = terminal.resolverPesquisaPdv(termo);
        expect(b.produtoAuto?.id, a.produtoAuto?.id, reason: termo);
        expect(b.motivoAuto, a.motivoAuto, reason: termo);
        expect(
          b.produtos.map((p) => p.id).toList(),
          a.produtos.map((p) => p.id).toList(),
          reason: termo,
        );
      }
    });

    test('SKU exato seleciona sozinho', () {
      final docs = ProdutoBuscaUtil.criarDocs(catalogo);
      final r = ProdutoBuscaUtil.resolverPesquisaPdv(docs, '5');
      expect(r.motivoAuto, PdvBuscaAutoMotivo.codigoInterno);
      expect(r.produtoAuto?.nome, 'Cimento Poty CP II 50kg');
    });
  });
}
