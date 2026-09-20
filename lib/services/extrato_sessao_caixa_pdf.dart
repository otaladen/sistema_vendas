import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/app_config_repository.dart';
import '../domain/extrato_sessao_caixa.dart';
import 'cupom_pdf_layout.dart';
import 'impressoes_service.dart';

/// PDF do extrato detalhado da sessao de caixa (termico 80 mm ou A4).
class ExtratoSessaoCaixaPdf {
  ExtratoSessaoCaixaPdf._();

  static final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  static final DateFormat _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm');

  static String _moeda(double v) => 'R\$ ${_currency.format(v)}';

  static Future<Uint8List> gerarBytes({
    required ExtratoSessaoCaixaDados dados,
    required EmpresaConfig config,
    required bool termico80mm,
  }) async {
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(config.logoPath)
            .readAsBytes()
            .catchError((_) => Uint8List(0))
        : Uint8List(0);
    final comLogo = logoBytes.isNotEmpty;
    final layout = ImpressoesService.layoutCupomEfetivo(config);
    final sessao = dados.sessao;
    final linhasVendas = dados.vendas.length;
    final linhasMov = dados.movimentos.length;
    final linhasTexto = 28 + linhasVendas * 2 + linhasMov * 2;

    final pageFormat = termico80mm
        ? CupomPdfLayout.formatoPagina(
            empresaModeloPdfDeString(config.modeloPdf),
            layout: layout,
            linhasTexto: linhasTexto,
            qtdItens: linhasVendas,
            linhasExtras: 12,
            comLogo: comLogo,
          )
        : PdfPageFormat.a4;

    final doc = pw.Document();
    final titulo = termico80mm
        ? 'EXTRATO SESSAO CAIXA'
        : 'EXTRATO DETALHADO DA SESSAO DE CAIXA';

    pw.Widget linha(String esq, String dir) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(esq, style: const pw.TextStyle(fontSize: 9))),
            pw.SizedBox(
              width: termico80mm ? 72 : 100,
              child: pw.Text(
                dir,
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: termico80mm
            ? const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8)
            : const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (comLogo && !termico80mm)
                pw.Center(
                  child: pw.Image(pw.MemoryImage(logoBytes), height: 48),
                ),
              pw.Center(
                child: pw.Text(
                  config.nomeLoja,
                  style: pw.TextStyle(
                    fontSize: termico80mm ? 10 : 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    fontSize: termico80mm ? 9 : 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Sessao Nº ${sessao.numero}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
              pw.Text(
                'Operador: ${sessao.operador.isEmpty ? '-' : sessao.operador}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (sessao.terminalId.trim().isNotEmpty)
                pw.Text(
                  'Terminal: ${sessao.terminalId}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'Abertura: ${_fmtDataHora.format(sessao.aberturaEm.toLocal())}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                sessao.aberta
                    ? 'Fechamento: (sessao aberta)'
                    : 'Fechamento: ${_fmtDataHora.format(sessao.fechamentoEm!.toLocal())}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'Resumo por forma de pagamento',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
              pw.SizedBox(height: 4),
              linha('Dinheiro', _moeda(dados.resumo.dinheiro)),
              linha('PIX', _moeda(dados.resumo.pix)),
              linha('Cartao (deb+cred)', _moeda(dados.resumo.cartao)),
              linha('Fiado', _moeda(dados.resumo.fiado)),
              if (dados.resumo.outros > 0.009)
                linha('Outros', _moeda(dados.resumo.outros)),
              linha('Total vendas', _moeda(dados.totalVendas)),
              pw.Text(
                '${dados.quantidadeVendas} venda(s)',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if (dados.quantidadeRecebimentosFiado > 0) ...[
                linha(
                  'Receb. fiado (${dados.quantidadeRecebimentosFiado})',
                  _moeda(dados.totalRecebimentosFiado),
                ),
                pw.Text(
                  'Resumo acima inclui quitacoes de fiado por forma de pagamento.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
              pw.SizedBox(height: 6),
              pw.Text(
                'Fundo inicial: ${_moeda(sessao.fundoTroco)} · '
                'Supr.: ${_moeda(sessao.suprimentos)} · '
                'Sang.: ${_moeda(sessao.sangrias)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'Vendas da sessao',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
              pw.SizedBox(height: 4),
              if (dados.vendas.isEmpty)
                pw.Text(
                  'Nenhuma venda no periodo.',
                  style: const pw.TextStyle(fontSize: 8),
                )
              else
                ...dados.vendas.map(
                  (v) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${v.hora} · Doc ${v.numeroDocumento} · ${v.nfceRotulo}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.Text(
                          '${v.cliente} · ${_moeda(v.valor)} · ${v.formaPagamento}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'Recebimentos de fiado',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
              pw.SizedBox(height: 4),
              if (dados.recebimentos.isEmpty)
                pw.Text(
                  'Nenhum recebimento no periodo.',
                  style: const pw.TextStyle(fontSize: 8),
                )
              else
                ...dados.recebimentos.map(
                  (rec) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Text(
                      '${rec.hora} · Rec ${rec.recebimentoId} · '
                      '${rec.cliente} · ${_moeda(rec.valor)} · ${rec.formaPagamento}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'Suprimentos e sangrias',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
              pw.SizedBox(height: 4),
              if (dados.movimentos.isEmpty)
                pw.Text(
                  'Nenhum movimento registrado.',
                  style: const pw.TextStyle(fontSize: 8),
                )
              else
                ...dados.movimentos.map(
                  (m) => pw.Text(
                    '${_fmtDataHora.format(m.dataHora.toLocal())} · '
                    '${m.tipo} ${_moeda(m.valor)}'
                    '${m.observacao.trim().isEmpty ? '' : ' · ${m.observacao.trim()}'}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }
}
