import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/relatorio_evolucao_mensal.dart';

/// PDF A4 para arquivamento: grafico de barras + resumo mensal.
Future<Uint8List> gerarPdfEvolucaoVendasMensal({
  required RelatorioEvolucaoMensal serie,
  EvolucaoGraficoTipo tipoGrafico = EvolucaoGraficoTipo.barras,
}) async {
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final dataFmt = DateFormat('dd/MM/yyyy HH:mm');
  final intervaloFmt = DateFormat('dd/MM/yyyy');

  final doc = pw.Document();
  final font = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.TextStyle estilo([bool bold = false, double size = 9]) => pw.TextStyle(
        fontSize: size,
        font: bold ? fontBold : font,
      );

  final melhor = serie.melhorMes;
  final tipoRotulo = switch (tipoGrafico) {
    EvolucaoGraficoTipo.barras => 'Barras',
    EvolucaoGraficoTipo.linhas => 'Linhas',
    EvolucaoGraficoTipo.area => 'Area',
  };

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Pagina ${ctx.pageNumber} de ${ctx.pagesCount}',
          style: estilo(false, 8).copyWith(color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.Text('Evolucao de vendas mensais', style: estilo(true, 16)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${serie.rotuloPeriodo}  ·  '
          '${intervaloFmt.format(serie.inicio)} — ${intervaloFmt.format(serie.fim)}',
          style: estilo(true, 10),
        ),
        pw.Text(
          'Emitido em ${dataFmt.format(DateTime.now())}  ·  Grafico: $tipoRotulo',
          style: estilo(false, 8).copyWith(color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.6),
            1: const pw.FlexColumnWidth(1.2),
          },
          children: [
            _kpiPdf('Faturamento total', moeda.format(serie.totalFaturamento), estilo),
            _kpiPdf('Media mensal', moeda.format(serie.mediaMensal), estilo),
            _kpiPdf('Notas no periodo', '${serie.totalNotas}', estilo),
            _kpiPdf(
              'Melhor mes',
              melhor == null
                  ? '—'
                  : '${melhor.rotuloLongo}  ·  ${moeda.format(melhor.faturamento)}',
              estilo,
              destaque: true,
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text('Grafico de faturamento', style: estilo(true, 11)),
        pw.SizedBox(height: 8),
        pw.Container(
          height: 210,
          padding: const pw.EdgeInsets.fromLTRB(8, 10, 8, 6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
            borderRadius: pw.BorderRadius.circular(4),
            color: PdfColors.grey50,
          ),
          child: _graficoPdf(serie, tipoGrafico, estilo),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Resumo mensal', style: estilo(true, 11)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.6),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(0.7),
            4: const pw.FlexColumnWidth(0.8),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              children: [
                _celCab('Mes/Ano', estilo),
                _celCab('Faturamento', estilo, direita: true),
                _celCab('Lucro', estilo, direita: true),
                _celCab('Notas', estilo, direita: true),
                _celCab('Var.', estilo, direita: true),
              ],
            ),
            ...[
              for (var i = 0; i < serie.meses.length; i++)
                pw.TableRow(
                  decoration: i.isOdd
                      ? const pw.BoxDecoration(color: PdfColors.grey100)
                      : null,
                  children: [
                    _cel(serie.meses[i].rotuloLongo, estilo),
                    _cel(
                      moeda.format(serie.meses[i].faturamento),
                      estilo,
                      direita: true,
                    ),
                    _cel(
                      moeda.format(serie.meses[i].lucro),
                      estilo,
                      direita: true,
                    ),
                    _cel('${serie.meses[i].qtdNotas}', estilo, direita: true),
                    _cel(
                      formatarVariacaoMes(
                        variacaoMesAnterior(serie.meses, i),
                      ),
                      estilo,
                      direita: true,
                    ),
                  ],
                ),
            ],
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey50),
              children: [
                _cel('Total', estilo, bold: true),
                _cel(moeda.format(serie.totalFaturamento), estilo, direita: true, bold: true),
                _cel(moeda.format(serie.totalLucro), estilo, direita: true, bold: true),
                _cel('${serie.totalNotas}', estilo, direita: true, bold: true),
                _cel('', estilo),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Totais de vendas finalizadas, com ajuste de devolucoes e trocas no mes. '
          'O mes corrente considera o faturamento ate a data de emissao.',
          style: estilo(false, 7).copyWith(color: PdfColors.grey700),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.TableRow _kpiPdf(
  String rotulo,
  String valor,
  pw.TextStyle Function([bool, double]) estilo, {
  bool destaque = false,
}) {
  return pw.TableRow(
    decoration: destaque
        ? const pw.BoxDecoration(color: PdfColors.blueGrey50)
        : null,
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(rotulo, style: estilo(false, 9)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(valor, style: estilo(destaque, 9)),
        ),
      ),
    ],
  );
}

pw.Widget _celCab(String t, pw.TextStyle Function([bool, double]) estilo, {bool direita = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Align(
      alignment: direita ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(t, style: estilo(true, 8)),
    ),
  );
}

pw.Widget _cel(
  String t,
  pw.TextStyle Function([bool, double]) estilo, {
  bool direita = false,
  bool bold = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Align(
      alignment: direita ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(t, style: estilo(bold, 8)),
    ),
  );
}

pw.Widget _graficoPdf(
  RelatorioEvolucaoMensal serie,
  EvolucaoGraficoTipo tipo,
  pw.TextStyle Function([bool, double]) estilo,
) {
  if (serie.meses.isEmpty) {
    return pw.Center(child: pw.Text('Sem meses no periodo.', style: estilo()));
  }
  final maxVal = serie.meses.fold<double>(
    0,
    (m, e) => e.faturamento > m ? e.faturamento : m,
  );
  if (maxVal < 0.01) {
    return pw.Center(
      child: pw.Text('Sem faturamento no periodo.', style: estilo()),
    );
  }

  const barColor = PdfColor.fromInt(0xFF3D6FA8);
  const lineColor = PdfColor.fromInt(0xFF2F5D8C);
  const areaFill = PdfColor.fromInt(0x553D6FA8);

  return pw.Column(
    children: [
      pw.Expanded(
        child: pw.CustomPaint(
          size: const PdfPoint(520, 160),
          painter: (PdfGraphics canvas, PdfPoint size) {
            const left = 8.0;
            const right = 8.0;
            const top = 8.0;
            const bottom = 8.0;
            final plotW = size.x - left - right;
            final plotH = size.y - top - bottom;
            final n = serie.meses.length;
            final slot = plotW / n;
            final ys = [
              for (final m in serie.meses)
                top + plotH * (1 - (m.faturamento / maxVal).clamp(0.0, 1.0)),
            ];
            final xs = [
              for (var i = 0; i < n; i++) left + slot * (i + 0.5),
            ];

            canvas
              ..setStrokeColor(PdfColors.grey300)
              ..setLineWidth(0.4);
            for (var g = 0; g <= 4; g++) {
              final gy = top + plotH * (g / 4);
              canvas.drawLine(left, gy, left + plotW, gy);
            }

            if (tipo == EvolucaoGraficoTipo.barras) {
              final barW = (slot * 0.55).clamp(6.0, 28.0);
              canvas.setFillColor(barColor);
              for (var i = 0; i < n; i++) {
                final h = (top + plotH) - ys[i];
                canvas.drawRect(xs[i] - barW / 2, ys[i], barW, h);
              }
              canvas.fillPath();
            } else {
              if (tipo == EvolucaoGraficoTipo.area && n >= 2) {
                canvas
                  ..setFillColor(areaFill)
                  ..moveTo(xs.first, top + plotH);
                for (var i = 0; i < n; i++) {
                  canvas.lineTo(xs[i], ys[i]);
                }
                canvas
                  ..lineTo(xs.last, top + plotH)
                  ..closePath()
                  ..fillPath();
              }
              canvas
                ..setStrokeColor(lineColor)
                ..setLineWidth(1.6)
                ..setLineCap(PdfLineCap.round)
                ..setLineJoin(PdfLineJoin.round);
              for (var i = 0; i < n; i++) {
                if (i == 0) {
                  canvas.moveTo(xs[i], ys[i]);
                } else {
                  canvas.lineTo(xs[i], ys[i]);
                }
              }
              canvas.strokePath();
              canvas.setFillColor(lineColor);
              for (var i = 0; i < n; i++) {
                canvas.drawEllipse(xs[i], ys[i], 2.2, 2.2);
              }
              canvas.fillPath();
            }
          },
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          for (final m in serie.meses)
            pw.Expanded(
              child: pw.Text(
                m.rotuloCurto,
                textAlign: pw.TextAlign.center,
                style: estilo(false, 6),
              ),
            ),
        ],
      ),
    ],
  );
}
