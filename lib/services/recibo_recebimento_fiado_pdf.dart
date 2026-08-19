import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../domain/recebimento_fiado_codec.dart';
import '../model/cliente.dart';
import '../model/recebimento_fiado.dart';
import '../model/titulo_receber.dart';
import 'cupom_nao_fiscal_venda_pdf.dart';
import 'cupom_pdf_layout.dart';

/// Recibo não fiscal de pagamento de fiado (quitação no caixa).
class ReciboRecebimentoFiadoPdf {
  ReciboRecebimentoFiadoPdf._();

  static final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  static final DateFormat _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _fmtData = DateFormat('dd/MM/yyyy');

  static String _rotuloForma(String forma) =>
      CupomNaoFiscalVendaPdf.rotuloFormaPagamento(forma);

  static String _formatarMoeda(double v) => 'R\$ ${_currency.format(v)}';

  static int _contarLinhas(
    RecebimentoFiado rec,
    List<({TituloReceber titulo, double valor})> alocacoes,
    double saldoRestante,
  ) {
    var n = 16 + alocacoes.length * 2;
    if (rec.observacao.trim().isNotEmpty) n++;
    if (saldoRestante > 0.001) n++;
    return n;
  }

  static Future<Uint8List> gerarBytes({
    required RecebimentoFiado recebimento,
    required Cliente cliente,
    required dynamic vendaRepository,
    required EmpresaConfig config,
    required String operadorCaixa,
    double? saldoRestanteOverride,
  }) async {
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(config.logoPath)
            .readAsBytes()
            .catchError((_) => Uint8List(0))
        : Uint8List(0);
    final alocacoesRaw = RecebimentoFiadoCodec.decode(recebimento.alocacoesJson);
    final alocacoes = <({TituloReceber titulo, double valor})>[];
    for (final a in alocacoesRaw) {
      TituloReceber? t;
      try {
        t = vendaRepository.titulos.obterPorId(a.tituloId) as TituloReceber?;
      } catch (_) {
        t = null;
      }
      if (t != null) {
        alocacoes.add((titulo: t, valor: a.valor));
      }
    }

    try {
      vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    } catch (_) {}

    double saldoRestante;
    if (saldoRestanteOverride != null) {
      saldoRestante = saldoRestanteOverride;
    } else {
      try {
        saldoRestante = (vendaRepository.titulos
                .listarAbertosPorCliente(cliente.id) as List)
            .fold<double>(0, (s, t) => s + (t as TituloReceber).saldo);
      } catch (_) {
        saldoRestante = 0;
      }
    }

    final doc = pw.Document();
    final modelo = empresaModeloPdfDeString(config.modeloPdf);
    final comLogo = logoBytes.isNotEmpty;
    final layout = config.layoutImpressao.cupom;
    final dataLocal = recebimento.data.toLocal();

    final pageFormat = CupomPdfLayout.formatoPagina(
      modelo,
      layout: layout,
      linhasTexto: _contarLinhas(recebimento, alocacoes, saldoRestante),
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
                titulo: 'RECIBO DE PAGAMENTO',
                subtitulo: 'FIADO / CONTAS A RECEBER',
              ),
              CupomPdfLayout.tituloSecao(
                'RECEBIMENTO ${recebimento.id}',
                layout,
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
              CupomPdfLayout.textoCorpo(
                'Cliente: ${cliente.nomeRazao}',
                layout,
              ),
              if (cliente.documento.trim().isNotEmpty)
                CupomPdfLayout.textoCorpo(
                  'Documento: ${cliente.documento}',
                  layout,
                ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('PAGAMENTO', layout),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Valor recebido:',
                valor: _formatarMoeda(recebimento.valorTotal),
                destaque: true,
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Forma:',
                valor: _rotuloForma(recebimento.formaPagamento),
              ),
              if (recebimento.observacao.trim().isNotEmpty)
                CupomPdfLayout.textoCorpo(
                  'Obs.: ${recebimento.observacao.trim()}',
                  layout,
                ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('PARCELAS QUITADAS', layout),
              if (alocacoes.isEmpty)
                CupomPdfLayout.textoCorpo(
                  'Detalhe das parcelas indisponivel.',
                  layout,
                )
              else
                ...alocacoes.map((a) {
                  a.titulo.venda.target;
                  final venda = a.titulo.venda.target;
                  final numVenda =
                      venda != null && venda.numeroOrcamento > 0
                          ? '${venda.numeroOrcamento}'
                          : '${venda?.id ?? '-'}';
                  return CupomPdfLayout.textoCorpo(
                    'Venda $numVenda - '
                    '${a.titulo.numeroParcela}/${a.titulo.totalParcelas}: '
                    '${_formatarMoeda(a.valor)} '
                    '(venc. ${_fmtData.format(a.titulo.vencimento.toLocal())})',
                    layout,
                  );
                }),
              CupomPdfLayout.divisoriaSecao(layout: layout, destaque: true),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Saldo em aberto do cliente:',
                valor: _formatarMoeda(saldoRestante),
              ),
              CupomPdfLayout.espacoBloco(layout),
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
