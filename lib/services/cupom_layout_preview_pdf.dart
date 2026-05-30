import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../model/config_layout_impressao.dart';
import 'cupom_nao_fiscal_venda_pdf.dart';
import 'cupom_pdf_gerado.dart';
import 'cupom_pdf_layout.dart';

/// PDF de exemplo para pre-visualizar layout (cupom ou orcamento).
class CupomLayoutPreviewPdf {
  CupomLayoutPreviewPdf._();

  static String _moeda(double v) => CupomNaoFiscalVendaPdf.formatarMoeda(v);

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
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(agora);
    final modelo = empresaModeloPdfDeString(empresa.modeloPdf);
    final doc = pw.Document();

    final pageFormat = CupomPdfLayout.formatoPagina(
      modelo,
      layout: layout,
      linhasTexto: orcamento ? 16 : 18,
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
              ),
              CupomPdfLayout.faixaTipoDocumento(
                layout: layout,
                titulo: orcamento
                    ? layout.tituloDocumentoEfetivoOrcamento
                    : layout.tituloDocumentoEfetivoCupom,
                subtitulo: orcamento ? null : 'SEGUNDA VIA',
              ),
              CupomPdfLayout.tituloSecao(
                orcamento ? 'ORCAMENTO 1042' : 'VENDA 1042',
                layout,
              ),
              CupomPdfLayout.textoCorpo('Data: $dataHora', layout),
              if (!orcamento)
                CupomPdfLayout.textoCorpo(
                  'Reimpressao: $dataHora',
                  layout,
                  fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
                ),
              CupomPdfLayout.textoCorpo('Cliente: Cliente Exemplo Ltda', layout),
              if (layout.exibirVendedor)
                CupomPdfLayout.textoCorpo('Vendedor: 01 · Maria', layout),
              if (layout.exibirDocumentoCliente)
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
                  'Validade do orcamento: ${DateFormat('dd/MM/yyyy').format(agora.add(const Duration(days: 7)))} (7 dias)',
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
                  quantidade: i.qtd,
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
                rotulo: 'Frete:',
                valor: _moeda(frete),
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: orcamento ? 'Total:' : 'TOTAL:',
                valor: _moeda(total),
                destaque: layout.destacarTotal,
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
              ] else
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Pagamento:',
                  valor: 'A combinar',
                  colunas: layout.alinharPagamentoColunas,
                ),
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: orcamento
                    ? empresa.rodapeOrcamento
                    : empresa.rodapeNota,
              ),
              CupomPdfLayout.espacoFinalDocumento(layout),
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
