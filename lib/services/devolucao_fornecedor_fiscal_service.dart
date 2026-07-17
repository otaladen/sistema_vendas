import 'dart:convert';

import '../config/focus_nfe_runtime.dart';
import '../data/devolucao_fornecedor_fiscal_store.dart';
import '../data/nfe_entrada_repository.dart';
import '../data/nfe_entrada_xml_store.dart';
import '../data/produto_repository.dart';
import '../domain/fiscal/espelho_devolucao_fornecedor.dart';
import '../domain/produto_nome_exibicao.dart';
import '../model/historico_entrada.dart';
import '../model/item_nota_temporario.dart';
import '../model/nfe_importada_registro.dart';
import '../model/produto.dart';
import '../services/fiscal_config_store.dart';
import '../services/focus_nfe_reconsulta_helper.dart';
import '../services/focus_nfe_service.dart';
import '../services/gerenciador_estoque_service.dart';
import '../services/xml_nfe_parser_service.dart';

class DevolucaoFornecedorLinha {
  DevolucaoFornecedorLinha({
    required this.historico,
    required this.produto,
    required this.quantidadeMaxima,
    required this.quantidade,
    required this.espelho,
    required this.icmsBaseOrigem,
    required this.icmsValorOrigem,
    required this.icmsBaseStOrigem,
    required this.icmsValorStOrigem,
    required this.ipiValorOrigem,
    required this.quantidadeEntradaOriginal,
  });

  final HistoricoEntrada historico;
  final Produto produto;
  final int quantidadeMaxima;
  int quantidade;
  final EspelhoDevolucaoFornecedorItem espelho;

  /// Totais de imposto de referencia (compra ou espelho importado).
  double icmsBaseOrigem;
  double icmsValorOrigem;
  double icmsBaseStOrigem;
  double icmsValorStOrigem;
  double ipiValorOrigem;
  int quantidadeEntradaOriginal;

  void aplicarQuantidade(int q) {
    quantidade = q.clamp(0, quantidadeMaxima);
    EspelhoDevolucaoFornecedorHelper.recalcularProporcional(
      espelho: espelho,
      quantidadeDevolver: quantidade,
      quantidadeEntradaOriginal: quantidadeEntradaOriginal,
      icmsBaseOrigem: icmsBaseOrigem,
      icmsValorOrigem: icmsValorOrigem,
      icmsBaseStOrigem: icmsBaseStOrigem,
      icmsValorStOrigem: icmsValorStOrigem,
      ipiValorOrigem: ipiValorOrigem,
    );
  }

  /// Aplica item do XML do espelho da fabrica (valores e qtd).
  void aplicarItemEspelhoXml(ItemNotaTemporario item) {
    final q = EspelhoDevolucaoFornecedorHelper.quantidadeEstoqueDoEspelho(
      quantidadeComercialXml: item.quantidadeComercial,
      quantidadeFornecedorEntrada: historico.quantidadeFornecedor,
      quantidadeEstoqueEntrada: historico.quantidadeEntradaEstoque,
      quantidadeMaxima: quantidadeMaxima,
    );
    espelho.aplicarDoItemXml(item);
    quantidade = q;
    // Nova referencia = valores do espelho nesta qtd (ajustes manuais de qtd
    // redistribuem impostos a partir daqui).
    quantidadeEntradaOriginal = q > 0 ? q : 1;
    icmsBaseOrigem = espelho.icmsBaseCalculo;
    icmsValorOrigem = espelho.icmsValor;
    icmsBaseStOrigem = espelho.icmsBaseCalculoSt;
    icmsValorStOrigem = espelho.icmsValorSt;
    ipiValorOrigem = espelho.ipiValor;
  }
}

class DevolucaoFornecedorOperacaoResultado {
  const DevolucaoFornecedorOperacaoResultado({
    required this.sucesso,
    this.mensagem = '',
    this.autorizada = false,
    this.chaveNfe = '',
    this.urlDanfe = '',
    this.referencia = '',
    this.numero = '',
    this.serie = '',
    this.urlXml = '',
  });

  final bool sucesso;
  final String mensagem;
  final bool autorizada;
  final String chaveNfe;
  final String urlDanfe;
  final String referencia;
  final String numero;
  final String serie;
  final String urlXml;

  factory DevolucaoFornecedorOperacaoResultado.erro(String msg) =>
      DevolucaoFornecedorOperacaoResultado(sucesso: false, mensagem: msg);

  factory DevolucaoFornecedorOperacaoResultado.ok({
    required String mensagem,
    required bool autorizada,
    required String chaveNfe,
    required String urlDanfe,
    required String referencia,
    required String numero,
    required String serie,
    required String urlXml,
  }) =>
      DevolucaoFornecedorOperacaoResultado(
        sucesso: true,
        mensagem: mensagem,
        autorizada: autorizada,
        chaveNfe: chaveNfe,
        urlDanfe: urlDanfe,
        referencia: referencia,
        numero: numero,
        serie: serie,
        urlXml: urlXml,
      );
}

/// Orquestra NF-e de devolucao de compra (focus) + baixa de estoque.
class DevolucaoFornecedorFiscalService {
  DevolucaoFornecedorFiscalService({
    required this.produtoRepository,
    FocusNfeService? focusNfe,
  }) : _focus = focusNfe ?? FocusNfeService(config: criarFocusNfeConfigPadrao());

  final ProdutoRepository produtoRepository;
  final FocusNfeService _focus;

  NfeEntradaRepository get _entradaRepo =>
      NfeEntradaRepository(produtoRepository.objectBox);

  DevolucaoFornecedorFiscalStore get _store => DevolucaoFornecedorFiscalStore(
        produtoRepository.objectBox.storeDirectoryPath,
      );

  NfeEntradaXmlStore get _xmlStore => NfeEntradaXmlStore(
        produtoRepository.objectBox.storeDirectoryPath,
      );

  GerenciadorEstoqueService get _estoque =>
      GerenciadorEstoqueService(produtoRepository.objectBox);

  List<NfeImportadaRegistro> listarNotasCompra() =>
      _entradaRepo.listarImportacoesNfeDesc();

  List<DevolucaoFornecedorFiscalRegistro> listarHistoricoEmissao() =>
      _store.listar()..sort((a, b) => b.emitidaEm.compareTo(a.emitidaEm));

  List<DevolucaoFornecedorLinha> carregarLinhas(String chaveNotaCompra) {
    final hist = _entradaRepo.listarHistoricoPorChaveNfe(chaveNotaCompra);
    final jaDev = _store.quantidadesJaDevolvidasPorHistorico(chaveNotaCompra);
    final xmlItens = _itensXml(chaveNotaCompra);
    final ufForn = _ufFornecedorXml(chaveNotaCompra);

    final linhas = <DevolucaoFornecedorLinha>[];
    for (final h in hist) {
      final produto = h.produto.target;
      if (produto == null) continue;
      final ja = jaDev[h.id] ?? 0;
      final max = (h.quantidadeEntradaEstoque - ja).clamp(0, 1 << 30);
      if (max <= 0) continue;

      final xmlItem = _casarItemXml(h, produto, xmlItens);
      final qOrig = h.quantidadeEntradaEstoque <= 0
          ? max
          : h.quantidadeEntradaEstoque;
      final cfopSug = EspelhoDevolucaoFornecedorHelper.cfopDevolucaoDeCompra(
        xmlItem?.cfop ?? '',
        produto: produto,
        ufFornecedor: ufForn,
      );
      final espelho = EspelhoDevolucaoFornecedorItem(
        cfop: cfopSug,
        valorUnitario: h.precoCustoUnitarioNota > 0
            ? h.precoCustoUnitarioNota
            : (xmlItem?.valorUnitarioComercial ?? 0),
        icmsOrigem: (xmlItem?.icmsOrigem.trim().isNotEmpty ?? false)
            ? xmlItem!.icmsOrigem
            : '0',
        icmsSituacaoTributaria: xmlItem?.icmsSituacaoTributaria ?? '',
        icmsAliquota: xmlItem?.icmsAliquota ?? 0,
        cfopCompraOrigem: xmlItem?.cfop ?? '',
      );

      final linha = DevolucaoFornecedorLinha(
        historico: h,
        produto: produto,
        quantidadeMaxima: max,
        quantidade: 0,
        espelho: espelho,
        icmsBaseOrigem: xmlItem?.icmsBaseCalculo ?? 0,
        icmsValorOrigem: xmlItem?.icmsValor ?? 0,
        icmsBaseStOrigem: xmlItem?.icmsBaseCalculoSt ?? 0,
        icmsValorStOrigem: xmlItem?.icmsValorSt ?? 0,
        ipiValorOrigem: xmlItem?.ipiValor ?? 0,
        quantidadeEntradaOriginal: qOrig,
      );
      linhas.add(linha);
    }
    return linhas;
  }

  /// Aplica XML do espelho da fabrica nas linhas da devolucao (mutando [linhas]).
  AplicacaoEspelhoXmlResultado aplicarEspelhoXml({
    required String xmlTexto,
    required List<DevolucaoFornecedorLinha> linhas,
  }) {
    final parsed = XmlParserService.parseNfeXmlString(xmlTexto);
    if (parsed.itens.isEmpty) {
      throw const FormatException('XML do espelho sem itens.');
    }
    final mapa = EspelhoDevolucaoFornecedorHelper.casarItensXmlComLinhas(
      itensXml: parsed.itens,
      linhas: [
        for (var i = 0; i < linhas.length; i++)
          (
            index: i,
            produto: linhas[i].produto,
            preco: linhas[i].historico.precoCustoUnitarioNota,
            qtdForn: linhas[i].historico.quantidadeFornecedor,
          ),
      ],
    );
    for (final e in mapa.entries) {
      linhas[e.key].aplicarItemEspelhoXml(e.value);
    }
    return AplicacaoEspelhoXmlResultado(
      itensCasados: mapa.length,
      itensXmlSemPar: parsed.itens.length - mapa.length,
      linhasSemPar: linhas.length - mapa.length,
    );
  }

  List<ItemNotaTemporario> _itensXml(String chave) {
    final xml = _xmlStore.lerXml(chave);
    if (xml == null || xml.trim().isEmpty) return const [];
    try {
      return XmlParserService.parseNfeXmlString(xml).itens;
    } catch (_) {
      return const [];
    }
  }

  String _ufFornecedorXml(String chave) {
    final xml = _xmlStore.lerXml(chave);
    if (xml == null || xml.trim().isEmpty) return '';
    try {
      return XmlParserService.parseNfeXmlString(xml).emitente.uf;
    } catch (_) {
      return '';
    }
  }

  ItemNotaTemporario? _casarItemXml(
    HistoricoEntrada h,
    Produto produto,
    List<ItemNotaTemporario> itens,
  ) {
    if (itens.isEmpty) return null;
    final eanProd = produto.codigoBarras.replaceAll(RegExp(r'\D'), '');
    if (eanProd.isNotEmpty) {
      for (final i in itens) {
        final e = i.codigoBarras.replaceAll(RegExp(r'\D'), '');
        if (e.isNotEmpty && e == eanProd) return i;
      }
    }
    final codigo = produto.codigoInterno.trim().toLowerCase();
    if (codigo.isNotEmpty) {
      for (final i in itens) {
        if (i.codigo.trim().toLowerCase() == codigo) return i;
      }
    }
    // Fallback: mesmo valor unitario e quantidade proxima.
    for (final i in itens) {
      final diff = (i.valorUnitarioComercial - h.precoCustoUnitarioNota).abs();
      if (diff < 0.02 &&
          (i.quantidadeComercial - h.quantidadeFornecedor).abs() < 0.01) {
        return i;
      }
    }
    return itens.length == 1 ? itens.first : null;
  }

  Future<DevolucaoFornecedorOperacaoResultado> emitir({
    required String chaveNotaCompra,
    required List<DevolucaoFornecedorLinha> linhasSelecionadas,
    required String motivo,
  }) async {
    if (!FiscalConfigStore.configurado) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        'Focus NFe nao configurada. Configure em Configuracoes.',
      );
    }

    final chave = chaveNotaCompra.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        'Chave da NF-e de compra invalida.',
      );
    }

    final selecionadas =
        linhasSelecionadas.where((l) => l.quantidade > 0).toList();
    if (selecionadas.isEmpty) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        'Informe a quantidade a devolver em ao menos um item.',
      );
    }
    for (final l in selecionadas) {
      if (l.quantidade > l.quantidadeMaxima) {
        return DevolucaoFornecedorOperacaoResultado.erro(
          'Quantidade acima do disponivel para '
          '${ProdutoNomeExibicao.paraImpressao(l.produto)}.',
        );
      }
      if (l.espelho.cfop.trim().length != 4) {
        return DevolucaoFornecedorOperacaoResultado.erro(
          'CFOP do espelho invalido em '
          '${ProdutoNomeExibicao.paraImpressao(l.produto)}.',
        );
      }
      if (l.espelho.valorUnitario <= 0) {
        return DevolucaoFornecedorOperacaoResultado.erro(
          'Valor unitario do espelho invalido em '
          '${ProdutoNomeExibicao.paraImpressao(l.produto)}.',
        );
      }
    }

    final xml = _xmlStore.lerXml(chave);
    if (xml == null || xml.trim().isEmpty) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        'XML da NF-e de compra nao encontrado. Reimporte a nota ou '
        'confira o arquivo local de entrada.',
      );
    }

    final NfeXmlParseResult parsed;
    try {
      parsed = XmlParserService.parseNfeXmlString(xml);
    } on FormatException catch (e) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        'Falha ao ler XML da compra: ${e.message}',
      );
    }

    final FocusNfeDestinatarioNfe destinatario;
    try {
      destinatario =
          FocusNfeDestinatarioNfe.fromEmitenteNfe(parsed.emitente);
    } on FocusNfeValidacaoException catch (e) {
      return DevolucaoFornecedorOperacaoResultado.erro(e.message);
    }

    final itensFiscais = <FocusNfeItemDevolucao>[];
    for (final l in selecionadas) {
      final e = l.espelho;
      itensFiscais.add(
        FocusNfeItemDevolucao(
          produto: l.produto,
          descricao: ProdutoNomeExibicao.paraImpressao(l.produto),
          quantidade: l.quantidade,
          valorUnitario: e.valorUnitario,
          cfopOverride: e.cfop,
          icmsOrigem: e.icmsOrigem,
          icmsSituacaoTributaria: e.icmsSituacaoTributaria,
          icmsBaseCalculo: e.icmsBaseCalculo > 0 ? e.icmsBaseCalculo : null,
          icmsAliquota: e.icmsAliquota > 0 ? e.icmsAliquota : null,
          icmsValor: e.icmsValor > 0 ? e.icmsValor : null,
          icmsBaseCalculoSt:
              e.icmsBaseCalculoSt > 0 ? e.icmsBaseCalculoSt : null,
          icmsAliquotaSt: e.icmsAliquotaSt > 0 ? e.icmsAliquotaSt : null,
          icmsValorSt: e.icmsValorSt > 0 ? e.icmsValorSt : null,
          ipiValor: e.ipiValor > 0 ? e.ipiValor : null,
        ),
      );
    }

    final seq = _store.proximaSequencia(chave);
    final referencia = FocusNfeService.referenciaDevolucaoCompra(
      chaveNotaCompra: chave,
      sequencia: seq,
    );

    try {
      _focus.validarConfiguracao();
    } on FocusNfeConfigIncompletaException catch (e) {
      return DevolucaoFornecedorOperacaoResultado.erro(e.message);
    }

    var resultado = await _focus.emitirNfeDevolucaoFornecedor(
      referencia: referencia,
      chaveNotaCompra: chave,
      destinatario: destinatario,
      itensDevolucao: itensFiscais,
      motivo: motivo,
    );

    if (!resultado.autorizada && !resultado.processando) {
      resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
        original: resultado,
        reconsultar: () => _focus.consultarNfe(referencia),
      );
    }

    if (!resultado.autorizada && !resultado.processando) {
      return DevolucaoFornecedorOperacaoResultado.erro(
        resultado.mensagem.isNotEmpty
            ? resultado.mensagem
            : 'NF-e de devolucao ao fornecedor rejeitada pela SEFAZ.',
      );
    }

    NfeImportadaRegistro? importacao;
    for (final r in _entradaRepo.listarImportacoesNfeDesc()) {
      if (r.chaveAcesso.replaceAll(RegExp(r'\D'), '') == chave) {
        importacao = r;
        break;
      }
    }

    final itensBaixa = selecionadas
        .map(
          (l) => {
            'historicoEntradaId': l.historico.id,
            'produtoId': l.produto.id,
            'quantidade': l.quantidade,
            'cfop': l.espelho.cfop,
            'valorUnitario': l.espelho.valorUnitario,
          },
        )
        .toList();

    final registro = DevolucaoFornecedorFiscalRegistro(
      chaveNotaCompra: chave,
      referenciaFocus: referencia,
      chaveNfe: resultado.chaveNfe,
      numero: resultado.numero,
      serie: resultado.serie,
      urlDanfe: resultado.urlDanfe,
      urlXml: resultado.urlXml,
      statusFocus: resultado.statusFocus.isNotEmpty
          ? resultado.statusFocus
          : (resultado.autorizada ? 'autorizado' : 'processando'),
      motivo: motivo,
      nomeFornecedor: importacao?.nomeFornecedor ?? parsed.emitente.razaoSocial,
      cnpjFornecedor: importacao?.cnpjFornecedor ?? parsed.emitente.cnpj,
      itensBaixaJson: jsonEncode(itensBaixa),
    );
    _store.salvar(registro);

    if (resultado.autorizada) {
      for (final l in selecionadas) {
        _estoque.baixarEstoqueDevolucaoFornecedor(
          produto: l.produto,
          quantidade: l.quantidade,
          chaveNotaCompra: chave,
          referenciaNfe: referencia,
        );
      }
    }

    return DevolucaoFornecedorOperacaoResultado.ok(
      mensagem: resultado.autorizada
          ? 'NF-e de devolucao ao fornecedor autorizada (nº ${resultado.numero}).'
          : 'NF-e enviada — aguardando autorizacao. Estoque sera baixado '
              'apos autorizacao (reconsulte no historico).',
      autorizada: resultado.autorizada,
      chaveNfe: resultado.chaveNfe,
      urlDanfe: resultado.urlDanfe,
      referencia: referencia,
      numero: resultado.numero,
      serie: resultado.serie,
      urlXml: resultado.urlXml,
    );
  }
}
