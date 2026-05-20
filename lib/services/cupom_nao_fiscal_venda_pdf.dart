import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../domain/entrega_venda_helper.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/plano_fiado.dart';
import '../model/cliente.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import 'cupom_pdf_layout.dart';

/// PDF do cupom nao fiscal (venda finalizada), reutilizado no Caixa e na listagem.
class CupomNaoFiscalVendaPdf {
  CupomNaoFiscalVendaPdf._();

  static final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');

  static String formatarMoeda(double valor) =>
      'R\$ ${_currency.format(valor)}';

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
    final descontoNota = venda.descontoImplicitoTotal;
    final modelo = empresaModeloPdfDeString(config.modeloPdf);
    final comLogo = logoBytes.isNotEmpty;
    final layout = config.layoutImpressao.cupom;

    doc.addPage(
      pw.Page(
        pageFormat: CupomPdfLayout.formatoPagina(
          modelo,
          linhasTexto: _contarLinhasCupom(venda, cliente, segundaVia),
          qtdItens: venda.itens.length,
          linhasExtras: 2,
          comLogo: comLogo,
          segundaVia: segundaVia,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
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
                          text:
                              ' | Frete: ${formatarMoeda(venda.valorFrete)}',
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
                  nomeProduto: item.nomeProduto,
                  quantidade: item.quantidade,
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
              if (segundaVia)
                CupomPdfLayout.textoCorpo(
                  'Valores recebido/troco podem ser aproximados na segunda via.',
                  layout,
                  fontSize: layout.tamanhoFonteCorpo.fontSizeContato - 1,
                ),
              CupomPdfLayout.espacoBloco(layout),
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: config.rodapeNota,
              ),
              pw.SizedBox(height: CupomPdfLayout.feedCorteMm * PdfPageFormat.mm),
            ],
          );
        },
      ),
    );
    return doc.save();
  }
}
