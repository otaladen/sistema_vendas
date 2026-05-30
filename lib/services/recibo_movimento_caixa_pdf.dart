import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import 'cupom_pdf_layout.dart';

/// Comprovante nao fiscal de suprimento ou sangria no caixa.
class ReciboMovimentoCaixaPdf {
  ReciboMovimentoCaixaPdf._();

  static final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  static final DateFormat _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');

  static String _formatarMoeda(double v) => 'R\$ ${_currency.format(v)}';

  static int _contarLinhas(String obs) {
    var n = 18;
    if (obs.trim().isNotEmpty) n++;
    return n;
  }

  static Future<Uint8List> gerarBytes({
    required bool suprimento,
    required double valor,
    required String observacao,
    required String operadorCaixa,
    required String terminalId,
    required DateTime dataHora,
    required EmpresaConfig config,
    double fundoInicial = 0,
    double totalSuprimentos = 0,
    double totalSangrias = 0,
  }) async {
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(config.logoPath)
            .readAsBytes()
            .catchError((_) => Uint8List(0))
        : Uint8List(0);
    final tipoTitulo = suprimento ? 'SUPRIMENTO' : 'SANGRIA';
    final tipoSub = suprimento
        ? 'ENTRADA DE VALOR NO CAIXA'
        : 'RETIRADA DE VALOR DO CAIXA';

    final doc = pw.Document();
    final modelo = empresaModeloPdfDeString(config.modeloPdf);
    final comLogo = logoBytes.isNotEmpty;
    final layout = config.layoutImpressao.cupom;
    final dataLocal = dataHora.toLocal();
    final obs = observacao.trim();

    final pageFormat = CupomPdfLayout.formatoPagina(
      modelo,
      layout: layout,
      linhasTexto: _contarLinhas(obs),
      qtdItens: 0,
      linhasExtras: 2,
      comLogo: comLogo,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
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
                titulo: 'COMPROVANTE DE $tipoTitulo',
                subtitulo: tipoSub,
              ),
              CupomPdfLayout.textoCorpo(
                'Data: ${_fmtDataHora.format(dataLocal)}',
                layout,
              ),
              if (operadorCaixa.trim().isNotEmpty)
                CupomPdfLayout.textoCorpo(
                  'Operador: ${operadorCaixa.trim()}',
                  layout,
                ),
              if (terminalId.trim().isNotEmpty)
                CupomPdfLayout.textoCorpo(
                  'Terminal: ${terminalId.trim()}',
                  layout,
                ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('MOVIMENTO', layout),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Valor:',
                valor: _formatarMoeda(valor),
                destaque: true,
              ),
              if (obs.isNotEmpty)
                CupomPdfLayout.textoCorpo('Obs.: $obs', layout),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('RESUMO DA SESSAO', layout),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Fundo inicial:',
                valor: _formatarMoeda(fundoInicial),
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Suprimentos (acum.):',
                valor: _formatarMoeda(totalSuprimentos),
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Sangrias (acum.):',
                valor: _formatarMoeda(totalSangrias),
              ),
              CupomPdfLayout.espacoBloco(layout),
              CupomPdfLayout.textoCorpo(
                'Documento interno — nao e documento fiscal.',
                layout,
              ),
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: config.rodapeNota,
              ),
              CupomPdfLayout.espacoFinalDocumento(layout),
            ],
          );
        },
      ),
    );
    return doc.save();
  }
}
