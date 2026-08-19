import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/fiscal_config.dart';
import '../data/app_config_repository.dart';
import '../model/config_layout_impressao.dart';
import 'cupom_nao_fiscal_venda_pdf.dart';
import 'cupom_pdf_gerado.dart';
import 'cupom_pdf_layout.dart';

/// PDF de exemplo para pre-visualizar layout (cupom ou orcamento).
class CupomLayoutPreviewPdf {
  CupomLayoutPreviewPdf._();

  static String _moeda(double v) => CupomNaoFiscalVendaPdf.formatarMoeda(v);

  static String _valor(double v) =>
      CupomNaoFiscalVendaPdf.formatarValorNumerico(v);

  static Future<Uint8List> gerarBytes({
    required EmpresaConfig empresa,
    required ConfigLayoutImpressao layout,
    required bool orcamento,
  }) async {
    return (await gerar(
      empresa: empresa,
      layout: layout,
      orcamento: orcamento,
    ))
        .bytes;
  }

  static Future<CupomPdfGerado> gerar({
    required EmpresaConfig empresa,
    required ConfigLayoutImpressao layout,
    required bool orcamento,
  }) async {
    final logoBytes = empresa.logoPath.trim().isNotEmpty
        ? await File(empresa.logoPath)
            .readAsBytes()
            .catchError((_) => Uint8List(0))
        : Uint8List(0);
    final comLogo = logoBytes.isNotEmpty;
    final agora = DateTime.now();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm:ss').format(agora);
    final qtdLegado = NumberFormat('#,##0.000', 'pt_BR');
    final modelo = empresaModeloPdfDeString(empresa.modeloPdf);
    final doc = CupomPdfLayout.criarDocumento(layout);

    final pageFormat = CupomPdfLayout.formatoPagina(
      modelo,
      layout: layout,
      linhasTexto: orcamento ? 16 : 42,
      qtdItens: 2,
      linhasExtras: 4,
      comLogo: comLogo,
      segundaVia: !orcamento,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          final itens = [
            (
              nome: 'Cimento CP II 50kg',
              qtd: 2,
              unit: 42.90,
            ),
            (
              nome: 'Tinta latex branca 18L',
              qtd: 1,
              unit: 189.50,
            ),
          ];
          final subtotal = itens.fold<double>(
            0,
            (s, i) => s + i.qtd * i.unit,
          );
          const frete = 15.0;
          final total = subtotal + frete;

          if (!orcamento && layout.estiloCupomNfce) {
            const numeroExemplo = '1042';
            const serieExemplo = '001';
            final chaveExemplo = CupomPdfLayout.gerarChaveAcessoDecorativaNfce(
              cnpj: FiscalConfig.cnpjEmitente,
              uf: FiscalConfig.ufEmitente,
              numeroNota: numeroExemplo,
              serie: serieExemplo,
              emissao: agora,
            );
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                ...CupomPdfLayout.cabecalhoLegadoLdv(
                  layout: layout,
                  razaoSocial: FiscalConfig.razaoSocialEmitente,
                  nomeLoja: empresa.nomeLoja,
                  cnpj: FiscalConfig.cnpjEmitente,
                  inscricaoEstadual: FiscalConfig.inscricaoEstadualEmitente,
                  telefone: empresa.telefone,
                  endereco: empresa.endereco,
                  logoBytes: null,
                ),
                CupomPdfLayout.faixaTituloDocumentoLegadoLdv(
                  layout: layout,
                  linha1: CupomPdfLayout.tituloDanfeNfceLegadoLinha1,
                  linha2: CupomPdfLayout.tituloDanfeNfceLegadoLinha2,
                ),
                CupomPdfLayout.cabecalhoTabelaItensLegadoLdv(layout),
                CupomPdfLayout.linhaItemLegadoLdv(
                  layout: layout,
                  item: '001',
                  codigo: '001',
                  unidade: 'SC',
                  descricao: itens[0].nome,
                  quantidade: qtdLegado.format(itens[0].qtd),
                  vlBruto: _valor(itens[0].qtd * itens[0].unit),
                  desconto: _valor(0),
                  vlUnit: _valor(itens[0].unit),
                  vlTotal: _valor(itens[0].qtd * itens[0].unit),
                ),
                CupomPdfLayout.linhaItemLegadoLdv(
                  layout: layout,
                  item: '002',
                  codigo: '002',
                  unidade: 'GL',
                  descricao: itens[1].nome,
                  quantidade: qtdLegado.format(itens[1].qtd),
                  vlBruto: _valor(itens[1].qtd * itens[1].unit),
                  desconto: _valor(0),
                  vlUnit: _valor(itens[1].unit),
                  vlTotal: _valor(itens[1].qtd * itens[1].unit),
                ),
                CupomPdfLayout.blocoTotaisLegadoLdv(
                  layout: layout,
                  qtdItens: itens.length,
                  subtotal: _valor(subtotal),
                  desconto: _valor(0),
                  frete: _valor(frete),
                  valorTotal: _valor(total),
                  exibirFrete: frete > 0,
                ),
                CupomPdfLayout.blocoPagamentoLegadoLdv(
                  layout: layout,
                  formaPagamento: 'Dinheiro',
                  valorPago: _valor(300),
                  troco: _valor(300 - total),
                ),
                CupomPdfLayout.faixaContingenciaAposPagamentoLegadoLdv(
                  layout: layout,
                ),
                CupomPdfLayout.rodapeIdentificacaoLegadoLdv(
                  layout: layout,
                  numero: numeroExemplo,
                  serie: serieExemplo,
                  emissao: dataHora,
                  via: 'VIA CONSUMIDOR',
                ),
                CupomPdfLayout.blocoConsultaChaveAcessoLegadoLdv(
                  layout: layout,
                  chaveAcesso: chaveExemplo,
                ),
                CupomPdfLayout.textoConsumidorLegadoLdv(
                  layout: layout,
                  textoPrincipal: 'CONSUMIDOR NAO IDENTIFICADO',
                ),
                CupomPdfLayout.qrCodeNfceDanfe(
                  layout: layout,
                  payload:
                      '${CupomPdfLayout.urlConsultaNfcePorUf()}?p=$chaveExemplo',
                ),
                CupomPdfLayout.espacoFinalDocumento(layout),
              ],
            );
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              ...CupomPdfLayout.cabecalhoEmpresa(
                layout: layout,
                nomeLoja: empresa.nomeLoja,
                logoBytes: comLogo ? logoBytes : null,
                telefone: empresa.telefone,
                endereco: empresa.endereco,
                cnpj: orcamento ? FiscalConfig.cnpjEmitente : null,
              ),
              CupomPdfLayout.faixaTipoDocumento(
                layout: layout,
                titulo: orcamento
                    ? layout.tituloDocumentoEfetivoOrcamento
                    : layout.tituloDocumentoEfetivoCupom,
                subtitulo: orcamento ? null : 'SEGUNDA VIA',
              ),
              CupomPdfLayout.tituloSecao(
                orcamento ? 'ORCAMENTO N. 1042' : 'CONTROLE 1042',
                layout,
              ),
              if (!orcamento)
                CupomPdfLayout.textoCorpo('NFC-e 4521', layout),
              CupomPdfLayout.textoCorpo(
                orcamento ? 'Emissao: $dataHora' : 'Data: $dataHora',
                layout,
                fontWeight: orcamento ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
              if (!orcamento)
                CupomPdfLayout.textoCorpo(
                  'Reimpressao: $dataHora',
                  layout,
                  fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
                ),
              CupomPdfLayout.textoCorpo('Cliente: Cliente Exemplo Ltda', layout),
              if (layout.exibirVendedor)
                CupomPdfLayout.textoCorpo(
                  orcamento
                      ? 'Vendedor/Atendente: 01 · Maria'
                      : 'Vendedor: 01 · Maria',
                  layout,
                ),
              if (!orcamento && layout.exibirDocumentoCliente)
                CupomPdfLayout.textoCorpo(
                  'Documento: 12.345.678/0001-99',
                  layout,
                ),
              if (layout.exibirTelefoneCliente)
                CupomPdfLayout.textoCorpo(
                  'Telefone: (11) 99999-0000',
                  layout,
                ),
              if (orcamento && layout.exibirValidadeOrcamento)
                CupomPdfLayout.textoCorpo(
                  'Validade: ${DateFormat('dd/MM/yyyy').format(agora.add(const Duration(days: 7)))} (7 dias)',
                  layout,
                  fontWeight: pw.FontWeight.bold,
                ),
              if (!orcamento && layout.exibirEntrega)
                CupomPdfLayout.textoCorpo('Entrega: Entrega na loja', layout),
              if (!orcamento && layout.exibirEnderecoEntrega)
                CupomPdfLayout.textoCorpo(
                  'Endereco: Rua das Flores, 100',
                  layout,
                ),
              if (!orcamento && layout.exibirObservacaoEntrega)
                CupomPdfLayout.textoCorpo(
                  'Obs: Entregar no periodo da tarde',
                  layout,
                ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('ITENS', layout),
              if (CupomPdfLayout.cabecalhoColunasItens(layout) != null)
                CupomPdfLayout.cabecalhoColunasItens(layout)!,
              ...itens.map(
                (i) => CupomPdfLayout.itemVenda(
                  layout: layout,
                  nomeProduto: i.nome,
                  codigoSku: orcamento ? 'SKU-01' : null,
                  modalidade: orcamento ? '[RETIRA LOGO]' : null,
                  quantidade: i.qtd,
                  quantidadeExibicao: orcamento ? '${i.qtd} UN' : null,
                  precoUnitario: i.unit,
                  subtotal: i.qtd * i.unit,
                  formatarMoeda: _moeda,
                ),
              ),
              if (layout.divisoriaDestaqueAntesTotais)
                CupomPdfLayout.divisoriaSecao(layout: layout, destaque: true),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Subtotal produtos:',
                valor: _moeda(subtotal),
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: orcamento ? 'Frete/Entrega:' : 'Frete:',
                valor: _moeda(frete),
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: orcamento ? 'VALOR TOTAL:' : 'TOTAL:',
                valor: _moeda(total),
                destaque: layout.destacarTotal || orcamento,
              ),
              if (orcamento)
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Pagamento:',
                  valor: 'PIX a vista',
                  colunas: layout.alinharPagamentoColunas,
                ),
              if (!orcamento) ...[
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Pagamento:',
                  valor: 'Dinheiro',
                  colunas: layout.alinharPagamentoColunas,
                ),
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Recebido:',
                  valor: _moeda(300),
                  colunas: layout.alinharPagamentoColunas,
                ),
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Troco:',
                  valor: _moeda(300 - total),
                  destaque: layout.destacarTroco,
                  colunas: layout.alinharPagamentoColunas,
                ),
              ],
              if (orcamento) ...[
                ...CupomPdfLayout.avisoCotacaoSemValorFiscal(layout),
              ],
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: orcamento
                    ? empresa.rodapeOrcamento
                    : empresa.rodapeNota,
              ),
              if (!orcamento) CupomPdfLayout.espacoFinalDocumento(layout),
            ],
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
