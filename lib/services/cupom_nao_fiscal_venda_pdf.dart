import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/quantidade_venda_util.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/plano_fiado.dart';
import '../model/cliente.dart';
import '../model/config_layout_impressao.dart';
import '../model/item_venda.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'cupom_pdf_gerado.dart';
import 'cupom_pdf_layout.dart';

/// PDF do cupom nao fiscal (venda finalizada), reutilizado no Caixa e na listagem.
class CupomNaoFiscalVendaPdf {
  CupomNaoFiscalVendaPdf._();

  static final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');

  static String formatarMoeda(double valor) =>
      'R\$ ${_currency.format(valor)}';

  /// Valores numericos sem prefixo R\$ (estilo cupom termico antigo).
  static String formatarValorNumerico(double valor) =>
      _currency.format(valor);

  static String rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao de credito';
      case 'cartao_debito':
        return 'Cartao de debito';
      case 'fiado':
        return 'Fiado';
      case 'transferencia':
        return 'Transferencia';
      case 'misto':
        return 'Misto';
      case 'dinheiro':
      default:
        if (forma.startsWith('cartao')) return forma;
        return 'Dinheiro';
    }
  }

  static String _detalheLinhaPagamentoPdf(PagamentoOrcamentoLinha l) {
    final base =
        '${rotuloFormaPagamento(l.meio)} ${formatarMoeda(l.valor)}';
    if (l.meio == 'cartao_credito' && l.parcelas > 0) {
      final vp = l.valor / l.parcelas;
      return '$base ${l.parcelas}x de ${formatarMoeda(vp)}';
    }
    return base;
  }

  static String _textoDetalheLinhasPagamento(List<PagamentoOrcamentoLinha> linhas) {
    if (linhas.isEmpty) return '';
    return linhas.map(_detalheLinhaPagamentoPdf).join('; ');
  }

  static String rotuloPagamentoCabecalho(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      final rotulo = rotuloFormaPagamento(v.formaPagamento);
      if (v.formaPagamento == 'cartao_credito' && v.quantidadeParcelas > 0) {
        final vp = v.total / v.quantidadeParcelas;
        return '$rotulo ${formatarMoeda(v.total)} '
            '${v.quantidadeParcelas}x de ${formatarMoeda(vp)}';
      }
      return rotulo;
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    if (linhas.isEmpty) return 'Misto';
    return _textoDetalheLinhasPagamento(linhas);
  }

  static String rotuloTipoEntrega(String tipoEntrega) =>
      EntregaVendaHelper.rotuloTipoEntregaVenda(tipoEntrega);

  static String rotuloVendedorUmLinha(Vendedor? v) {
    if (v == null) return 'Sem vendedor';
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  /// Estimativa para segunda via (valores exatos de dinheiro nao ficam gravados).
  static ({double recebido, double troco}) inferirRecebidoTrocoSegundaVia(
    Venda v,
  ) {
    final t = v.total;
    if (v.formaPagamento == 'misto' && v.pagamentosJson.trim().isNotEmpty) {
      final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
      if (linhas.isEmpty) return (recebido: t, troco: 0.0);
      final soma = PagamentoOrcamentoCodec.soma(linhas);
      final troco = (soma - t).clamp(0.0, double.infinity).toDouble();
      return (recebido: soma, troco: troco);
    }
    return (recebido: t, troco: 0.0);
  }

  static int _contarLinhasCupom(Venda venda, Cliente? cliente, bool segundaVia) {
    var n = 14;
    if (cliente?.documento.trim().isNotEmpty ?? false) n++;
    if (cliente?.telefone.trim().isNotEmpty ?? false) n++;
    if (venda.enderecoEntrega.trim().isNotEmpty) n++;
    if (venda.descontoImplicitoTotal > 0) n++;
    if (segundaVia) n += 2;
    final pagamento = rotuloPagamentoCabecalho(venda);
    if (pagamento.length > 30) {
      n += (pagamento.length / 30).ceil() - 1;
    }
    n += PlanoFiadoCodec.contarLinhasPdf(venda);
    return n;
  }

  static int _contarLinhasCupomComLayout(
    Venda venda,
    Cliente? cliente,
    bool segundaVia,
    ConfigLayoutImpressao layout,
    String rodape,
  ) {
    if (layout.estiloCupomNfce) {
      return CupomPdfLayout.contarLinhasExtrasNfce(
        qtdItens: venda.itens.length,
        segundaVia: segundaVia,
        temDesconto: venda.descontoImplicitoTotal > 0,
        temEntrega: layout.exibirEntrega,
        temFiado: PlanoFiadoCodec.vendaTemPlanoQuitacao(venda),
        linhasFiado: PlanoFiadoCodec.contarLinhasPdf(venda),
        linhasRodape: 0,
        temChave: _chaveNfceValida(venda),
        contingenciaSefaz: !_chaveNfceValida(venda) ||
            _vendaNfceEmContingencia(venda),
      );
    }
    return _contarLinhasCupom(venda, cliente, segundaVia);
  }

  static ({String codigo, String unidade}) _dadosProdutoItem(ItemVenda item) {
    final p = item.produto.target;
    final codigo = p?.codigoInterno.trim();
    return (
      codigo: (codigo != null && codigo.isNotEmpty)
          ? codigo
          : (item.id > 0 ? '${item.id}' : '-'),
      unidade: (p?.unidade.trim().isNotEmpty ?? false) ? p!.unidade.trim() : 'UN',
    );
  }

  static String _rotuloFormaPagamentoResumo(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return rotuloFormaPagamento(v.formaPagamento);
    }
    return 'Misto';
  }

  static String _enderecoConsumidorDanfe(Cliente? cliente, Venda venda) {
    if (venda.enderecoEntrega.trim().isNotEmpty) {
      return venda.enderecoEntrega.trim();
    }
    if (cliente == null) return '';
    final padrao = cliente.enderecoPadraoEntrega();
    if (padrao != null && padrao.temDados) return padrao.resumo();
    if (cliente.endereco.trim().isNotEmpty) return cliente.endereco.trim();
    return '';
  }

  static String _textoConsumidorLegado(Cliente? cliente, Venda venda) {
    final doc = cliente?.documento.trim() ?? '';
    final nome = cliente?.nomeRazao.trim() ?? '';
    if (doc.isEmpty && nome.isEmpty) {
      return 'CONSUMIDOR NAO IDENTIFICADO';
    }
    final partes = <String>['CONSUMIDOR'];
    if (doc.isNotEmpty) {
      partes.add(
        doc.replaceAll(RegExp(r'\D'), '').length == 11
            ? 'CPF ${CupomPdfLayout.formatarDocumentoConsumidor(doc)}'
            : 'CNPJ ${CupomPdfLayout.formatarDocumentoConsumidor(doc)}',
      );
    }
    if (nome.isNotEmpty) {
      partes.add(nome);
    }
    final endereco = _enderecoConsumidorDanfe(cliente, venda);
    if (endereco.isNotEmpty) partes.add(endereco);
    return partes.join(' - ');
  }

  static String _numeroNfceExibicao(Venda venda) {
    if (venda.nfceNumero.trim().isNotEmpty) return venda.nfceNumero.trim();
    return '${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}';
  }

  static String _serieNfceExibicao(Venda venda) {
    if (venda.nfceSerie.trim().isNotEmpty) return venda.nfceSerie.trim();
    return '1';
  }

  static String _payloadQrNfce(Venda venda, String chaveRodape) {
    final urlDanfe = venda.nfceUrlDanfe.trim();
    if (urlDanfe.isNotEmpty) return urlDanfe;
    final chave = CupomPdfLayout.chaveAcessoSomenteDigitos(chaveRodape);
    final url = CupomPdfLayout.urlConsultaNfcePorUf();
    if (chave.length == 44) return '$url?p=$chave';
    return url;
  }

  static DateTime _dataEmissaoCupom(Venda venda, String dataLinhaPrincipal) {
    if (venda.nfceEmitidaEm != null) return venda.nfceEmitidaEm!.toLocal();
    for (final fmt in [
      'dd/MM/yyyy HH:mm:ss',
      'dd/MM/yyyy HH:mm',
    ]) {
      try {
        return DateFormat(fmt).parse(dataLinhaPrincipal);
      } catch (_) {}
    }
    return DateTime.now();
  }

  static String _chaveRodapeCupom({
    required Venda venda,
    required String numeroDocumento,
    required String serieDocumento,
    required String dataLinhaPrincipal,
  }) {
    if (_chaveNfceValida(venda)) return venda.nfceChaveAcesso;
    return CupomPdfLayout.gerarChaveAcessoDecorativaNfce(
      cnpj: FiscalConfig.cnpjEmitente,
      uf: FiscalConfig.ufEmitente,
      numeroNota: numeroDocumento,
      serie: serieDocumento,
      emissao: _dataEmissaoCupom(venda, dataLinhaPrincipal),
    );
  }

  static String _quantidadeItemLegado(ItemVenda item) {
    final q = item.quantidadeVendaEfetiva;
    return NumberFormat('#,##0.000', 'pt_BR').format(q);
  }

  static bool _chaveNfceValida(Venda venda) =>
      CupomPdfLayout.chaveAcessoSomenteDigitos(venda.nfceChaveAcesso).length ==
      44;

  static bool _vendaNfceEmContingencia(Venda venda) =>
      _chaveNfceValida(venda) &&
      CupomPdfLayout.chaveNfceIndicaContingencia(venda.nfceChaveAcesso);

  static String _quantidadeItemNfce(ItemVenda item) {
    final fracionada =
        item.produto.target?.permiteQuantidadeFracionada ?? false;
    return QuantidadeVendaUtil.formatarExibicao(
      item.quantidadeVendaEfetiva,
      fracionada: fracionada,
    );
  }

  static String _numeroCupomInterno(Venda venda) =>
      '${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}';

  static String _emissaoLegadoComSegundos(String dataHora) {
    final t = dataHora.trim();
    if (RegExp(r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$').hasMatch(t)) {
      return '$t:00';
    }
    return t;
  }

  static List<pw.Widget> _buildCorpoNfce({
    required Venda venda,
    required EmpresaConfig config,
    required ConfigLayoutImpressao layout,
    Cliente? cliente,
    Vendedor? vendedor,
    required double totalRecebido,
    required double troco,
    required bool segundaVia,
    required String dataLinhaPrincipal,
    String? dataReimpressao,
    Uint8List? logoBytes,
  }) {
    final descontoNota = venda.descontoImplicitoTotal;
    final chaveValida = _chaveNfceValida(venda);
    final contingenciaSefaz = _vendaNfceEmContingencia(venda);
    final exibirAvisoContingencia = !chaveValida || contingenciaSefaz;
    final temNfceIdentificada =
        chaveValida || venda.nfceNumero.trim().isNotEmpty;
    final linhasMisto = venda.formaPagamento == 'misto' &&
            venda.pagamentosJson.trim().isNotEmpty
        ? PagamentoOrcamentoCodec.decode(venda.pagamentosJson)
            .map(
              (l) => (
                forma: rotuloFormaPagamento(l.meio),
                valor: formatarValorNumerico(l.valor),
              ),
            )
            .toList()
        : const <({String forma, String valor})>[];

    final numeroDocumento = temNfceIdentificada
        ? _numeroNfceExibicao(venda)
        : _numeroCupomInterno(venda);
    final serieDocumento =
        temNfceIdentificada ? _serieNfceExibicao(venda) : '001';
    final chaveRodape = _chaveRodapeCupom(
      venda: venda,
      numeroDocumento: numeroDocumento,
      serieDocumento: serieDocumento,
      dataLinhaPrincipal: dataLinhaPrincipal,
    );

    final widgets = <pw.Widget>[
      ...CupomPdfLayout.cabecalhoLegadoLdv(
        layout: layout,
        razaoSocial: FiscalConfig.razaoSocialEmitente,
        nomeLoja: config.nomeLoja,
        cnpj: FiscalConfig.cnpjEmitente,
        inscricaoEstadual: FiscalConfig.inscricaoEstadualEmitente,
        telefone: config.telefone,
        endereco: config.endereco,
        logoBytes: null,
      ),
      CupomPdfLayout.faixaTituloDocumentoLegadoLdv(
        layout: layout,
        linha1: CupomPdfLayout.tituloDanfeNfceLegadoLinha1,
        linha2: CupomPdfLayout.tituloDanfeNfceLegadoLinha2,
      ),
      CupomPdfLayout.cabecalhoTabelaItensLegadoLdv(layout),
      ...venda.itens.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final dados = _dadosProdutoItem(item);
        final nomeImp = ProdutoNomeExibicao.paraImpressaoItem(item);
        final qtd = item.quantidadeVendaEfetiva;
        final vlBruto = qtd * item.precoUnitario;
        final descLinha =
            (vlBruto - item.subtotal).clamp(0.0, double.infinity).toDouble();
        return CupomPdfLayout.linhaItemLegadoLdv(
          layout: layout,
          item: (idx + 1).toString().padLeft(3, '0'),
          codigo: dados.codigo,
          unidade: dados.unidade,
          descricao: nomeImp,
          quantidade: _quantidadeItemLegado(item),
          vlBruto: formatarValorNumerico(vlBruto),
          desconto: formatarValorNumerico(descLinha),
          vlUnit: formatarValorNumerico(item.precoUnitario),
          vlTotal: formatarValorNumerico(item.subtotal),
        );
      }),
      CupomPdfLayout.blocoTotaisLegadoLdv(
        layout: layout,
        qtdItens: venda.itens.length,
        subtotal: formatarValorNumerico(venda.somaSubtotalItens),
        desconto: formatarValorNumerico(descontoNota),
        frete: formatarValorNumerico(venda.valorFrete),
        valorTotal: formatarValorNumerico(venda.total),
        exibirFrete: venda.valorFrete > 0,
      ),
      CupomPdfLayout.blocoPagamentoLegadoLdv(
        layout: layout,
        formaPagamento: _rotuloFormaPagamentoResumo(venda),
        valorPago: formatarValorNumerico(totalRecebido),
        troco: formatarValorNumerico(troco),
        linhasMisto: linhasMisto,
      ),
      if (exibirAvisoContingencia)
        CupomPdfLayout.faixaContingenciaAposPagamentoLegadoLdv(layout: layout),
      CupomPdfLayout.rodapeIdentificacaoLegadoLdv(
        layout: layout,
        numero: numeroDocumento,
        serie: serieDocumento,
        emissao: temNfceIdentificada && venda.nfceEmitidaEm != null
            ? DateFormat('dd/MM/yyyy HH:mm:ss')
                .format(venda.nfceEmitidaEm!.toLocal())
            : _emissaoLegadoComSegundos(dataLinhaPrincipal),
        via: segundaVia ? 'SEGUNDA VIA' : 'VIA CONSUMIDOR',
        linhaExtra: segundaVia && dataReimpressao != null
            ? 'Reimpressao: $dataReimpressao'
            : null,
      ),
      CupomPdfLayout.blocoConsultaChaveAcessoLegadoLdv(
        layout: layout,
        chaveAcesso: chaveRodape,
      ),
      CupomPdfLayout.textoConsumidorLegadoLdv(
        layout: layout,
        textoPrincipal: _textoConsumidorLegado(cliente, venda),
      ),
      CupomPdfLayout.qrCodeNfceDanfe(
        layout: layout,
        payload: _payloadQrNfce(venda, chaveRodape),
      ),
      CupomPdfLayout.espacoFinalDocumento(layout),
    ];
    return widgets;
  }

  static List<pw.Widget> _buildCorpoClassico({
    required Venda venda,
    required EmpresaConfig config,
    required ConfigLayoutImpressao layout,
    Cliente? cliente,
    Vendedor? vendedor,
    required double totalRecebido,
    required double troco,
    required bool segundaVia,
    required String dataLinhaPrincipal,
    String? dataReimpressao,
    required bool comLogo,
    required Uint8List logoBytes,
  }) {
    final descontoNota = venda.descontoImplicitoTotal;
    return [
      ...CupomPdfLayout.cabecalhoEmpresa(
        layout: layout,
        nomeLoja: config.nomeLoja,
        logoBytes: comLogo ? logoBytes : null,
        telefone: config.telefone,
        endereco: config.endereco,
      ),
      CupomPdfLayout.faixaTipoDocumento(
        layout: layout,
        titulo: layout.tituloDocumentoEfetivoCupom,
        subtitulo: segundaVia ? 'SEGUNDA VIA' : null,
      ),
      CupomPdfLayout.tituloSecao(
        'VENDA ${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}',
        layout,
      ),
      CupomPdfLayout.textoCorpo(
        segundaVia
            ? 'Data da venda: $dataLinhaPrincipal'
            : 'Data: $dataLinhaPrincipal',
        layout,
      ),
      if (dataReimpressao != null)
        CupomPdfLayout.textoCorpo(
          'Reimpressao: $dataReimpressao',
          layout,
          fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
        ),
      CupomPdfLayout.textoCorpo(
        'Cliente: ${cliente?.nomeRazao ?? 'Sem cliente'}',
        layout,
      ),
      if (layout.exibirVendedor)
        CupomPdfLayout.textoCorpo(
          'Vendedor: ${rotuloVendedorUmLinha(vendedor)}',
          layout,
        ),
      if (layout.exibirDocumentoCliente &&
          (cliente?.documento.trim().isNotEmpty ?? false))
        CupomPdfLayout.textoCorpo(
          'Documento: ${cliente!.documento}',
          layout,
        ),
      if (layout.exibirTelefoneCliente &&
          (cliente?.telefone.trim().isNotEmpty ?? false))
        CupomPdfLayout.textoCorpo(
          'Telefone: ${cliente!.telefone}',
          layout,
        ),
      if (layout.exibirEntrega)
        pw.RichText(
          text: pw.TextSpan(
            style: CupomPdfLayout.estilo(
              layout,
              fontSize: layout.tamanhoFonteCorpo.fontSizeCorpo,
            ),
            children: [
              const pw.TextSpan(text: 'Entrega: '),
              pw.TextSpan(
                text: EntregaVendaHelper.textoEntregaCabecalhoVenda(venda),
                style: CupomPdfLayout.estilo(
                  layout,
                  fontSize: layout.tamanhoFonteCorpo.fontSizeCorpo,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (EntregaVendaHelper.vendaTemItensCarreto(venda))
                pw.TextSpan(
                  text: ' | Frete: ${formatarMoeda(venda.valorFrete)}',
                ),
            ],
          ),
        ),
      if (layout.exibirEnderecoEntrega &&
          venda.enderecoEntrega.trim().isNotEmpty)
        CupomPdfLayout.textoCorpo(
          'Endereco: ${venda.enderecoEntrega}',
          layout,
        ),
      CupomPdfLayout.divisoriaSecao(layout: layout),
      CupomPdfLayout.tituloSecao('ITENS', layout),
      if (CupomPdfLayout.cabecalhoColunasItens(layout) != null)
        CupomPdfLayout.cabecalhoColunasItens(layout)!,
      ...venda.itens.map(
        (item) => CupomPdfLayout.itemVenda(
          layout: layout,
          nomeProduto: ProdutoNomeExibicao.paraImpressaoItem(item),
          quantidade: item.quantidade,
          quantidadeExibicao: _quantidadeItemNfce(item),
          precoUnitario: item.precoUnitario,
          subtotal: item.subtotal,
          formatarMoeda: formatarMoeda,
          sufixoEntrega: EntregaVendaHelper.sufixoEntregaItemPdf(item),
        ),
      ),
      if (layout.divisoriaDestaqueAntesTotais)
        CupomPdfLayout.divisoriaSecao(layout: layout, destaque: true),
      CupomPdfLayout.linhaTotal(
        layout: layout,
        rotulo: 'Subtotal produtos:',
        valor: formatarMoeda(venda.somaSubtotalItens),
      ),
      CupomPdfLayout.linhaTotal(
        layout: layout,
        rotulo: 'Frete:',
        valor: formatarMoeda(venda.valorFrete),
      ),
      if (descontoNota > 0)
        CupomPdfLayout.linhaTotal(
          layout: layout,
          rotulo: 'Desconto:',
          valor: '- ${formatarMoeda(descontoNota)}',
        ),
      CupomPdfLayout.linhaTotal(
        layout: layout,
        rotulo: 'TOTAL:',
        valor: formatarMoeda(venda.total),
        destaque: layout.destacarTotal,
      ),
      CupomPdfLayout.linhaTotal(
        layout: layout,
        rotulo: 'Pagamento:',
        valor: rotuloPagamentoCabecalho(venda),
        colunas: layout.alinharPagamentoColunas,
      ),
      if (PlanoFiadoCodec.vendaTemPlanoQuitacao(venda)) ...[
        CupomPdfLayout.textoCorpo(
          'Condicao de quitacao (fiado):',
          layout,
          fontWeight: pw.FontWeight.bold,
        ),
        ...PlanoFiadoCodec.linhasTextoPdf(venda).map(
          (linha) => CupomPdfLayout.textoCorpo(
            linha,
            layout,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
      CupomPdfLayout.linhaTotal(
        layout: layout,
        rotulo: 'Recebido:',
        valor: formatarMoeda(totalRecebido),
        colunas: layout.alinharPagamentoColunas,
      ),
      CupomPdfLayout.linhaTotal(
        layout: layout,
        rotulo: 'Troco:',
        valor: formatarMoeda(troco),
        destaque: layout.destacarTroco,
        colunas: layout.alinharPagamentoColunas,
      ),
      CupomPdfLayout.espacoFinalDocumento(layout),
    ];
  }

  static Future<Uint8List> gerarBytes({
    required Venda venda,
    required EmpresaConfig config,
    Cliente? cliente,
    Vendedor? vendedor,
    required double totalRecebido,
    required double troco,
    bool segundaVia = false,
    DateTime? dataCabecalhoVenda,
  }) async {
    return (await gerar(
      venda: venda,
      config: config,
      cliente: cliente,
      vendedor: vendedor,
      totalRecebido: totalRecebido,
      troco: troco,
      segundaVia: segundaVia,
      dataCabecalhoVenda: dataCabecalhoVenda,
    ))
        .bytes;
  }

  static Future<CupomPdfGerado> gerar({
    required Venda venda,
    required EmpresaConfig config,
    Cliente? cliente,
    Vendedor? vendedor,
    required double totalRecebido,
    required double troco,
    bool segundaVia = false,
    DateTime? dataCabecalhoVenda,
  }) async {
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(
            config.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
    final agora = DateTime.now();
    final dataLinhaPrincipal = DateFormat('dd/MM/yyyy HH:mm').format(
      (dataCabecalhoVenda ?? agora).toLocal(),
    );
    final dataReimpressao = segundaVia
        ? DateFormat('dd/MM/yyyy HH:mm').format(agora.toLocal())
        : null;
    final modelo = empresaModeloPdfDeString(config.modeloPdf);
    final comLogo = logoBytes.isNotEmpty;
    final layout = config.layoutImpressao.cupom;

    late final int linhasTexto;
    late final int qtdItens;
    late final int linhasExtras;
    if (layout.estiloCupomNfce) {
      linhasTexto = 0;
      qtdItens = 0;
      linhasExtras = _contarLinhasCupomComLayout(
        venda,
        cliente,
        segundaVia,
        layout,
        config.rodapeNota,
      );
    } else {
      linhasTexto = _contarLinhasCupom(venda, cliente, segundaVia);
      linhasExtras = CupomPdfLayout.linhasTexto(config.rodapeNota).length + 2;
      final unidades = CupomPdfLayout.unidadesAlturaItensTermico(
        venda.itens.map(ProdutoNomeExibicao.paraImpressaoItem),
      );
      qtdItens = unidades > 0 ? unidades : venda.itens.length;
    }

    final pageFormat = CupomPdfLayout.formatoPagina(
      modelo,
      layout: layout,
      linhasTexto: linhasTexto,
      qtdItens: qtdItens,
      linhasExtras: linhasExtras,
      comLogo: comLogo,
      segundaVia: segundaVia,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          final corpo = layout.estiloCupomNfce
              ? _buildCorpoNfce(
                  venda: venda,
                  config: config,
                  layout: layout,
                  cliente: cliente,
                  vendedor: vendedor,
                  totalRecebido: totalRecebido,
                  troco: troco,
                  segundaVia: segundaVia,
                  dataLinhaPrincipal: dataLinhaPrincipal,
                  dataReimpressao: dataReimpressao,
                  logoBytes: comLogo ? logoBytes : null,
                )
              : _buildCorpoClassico(
                  venda: venda,
                  config: config,
                  layout: layout,
                  cliente: cliente,
                  vendedor: vendedor,
                  totalRecebido: totalRecebido,
                  troco: troco,
                  segundaVia: segundaVia,
                  dataLinhaPrincipal: dataLinhaPrincipal,
                  dataReimpressao: dataReimpressao,
                  comLogo: comLogo,
                  logoBytes: logoBytes,
                );
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: corpo,
          );
        },
      ),
    );
    return CupomPdfGerado(
      bytes: await doc.save(),
      pageFormat: pageFormat,
      layout: layout,
    );
  }
}
