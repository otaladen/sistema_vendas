import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/funcionario_cadastro_catalogo.dart';
import '../domain/lancamento_funcionario_catalogo.dart';
import '../model/funcionario.dart';
import '../model/lancamento_funcionario.dart';

/// Gera PDF A4 com extrato financeiro do funcionario.
Future<Uint8List> gerarExtratoFuncionarioPdf({
  required Funcionario funcionario,
  required List<LancamentoFuncionario> lancamentos,
  required double salarioBase,
  required double descontoFixo,
  DateTime? mesReferencia,
}) async {
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final dataFmt = DateFormat('dd/MM/yyyy');
  final mesFmt = DateFormat('MMMM/yyyy', 'pt_BR');

  final ativos = lancamentos.where((l) => !l.estornado).toList();
  final totalVales = ativos
      .where((l) => l.tipo == LancamentoFuncionarioCatalogo.vale)
      .fold<double>(0, (a, l) => a + l.valor);
  final totalDesc = ativos
      .where((l) => l.tipo == LancamentoFuncionarioCatalogo.desconto)
      .fold<double>(0, (a, l) => a + l.valor);
  final totalBonus = ativos
      .where((l) => l.tipo == LancamentoFuncionarioCatalogo.bonus)
      .fold<double>(0, (a, l) => a + l.valor);
  final liquido = salarioBase - descontoFixo - totalVales - totalDesc + totalBonus;

  final periodo = mesReferencia == null
      ? 'Todos os lancamentos'
      : mesFmt.format(mesReferencia);

  final rh = FuncionarioCadastroCatalogo.resumoSetorFuncao(
    setor: funcionario.setor,
    funcao: funcionario.funcao,
    funcaoOutro: funcionario.funcaoOutro,
    cargoLegado: funcionario.cargo,
  );

  final doc = pw.Document();
  final font = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();

  pw.TextStyle estilo([bool bold = false, double size = 9]) => pw.TextStyle(
        fontSize: size,
        font: bold ? fontBold : font,
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Text('Extrato financeiro — funcionario', style: estilo(true, 14)),
        pw.SizedBox(height: 8),
        pw.Text(
          '${funcionario.nomeCompleto}  ·  Cod. ${funcionario.codigoInterno}',
          style: estilo(true, 11),
        ),
        if (rh.isNotEmpty)
          pw.Text(rh, style: estilo(false, 9)),
        pw.Text(
          'Periodo: $periodo  ·  Emitido em ${dataFmt.format(DateTime.now())}',
          style: estilo(false, 8),
        ),
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            _linhaResumo('Salario base', moeda.format(salarioBase), estilo),
            _linhaResumo('Desconto fixo (cadastro)', moeda.format(descontoFixo), estilo),
            _linhaResumo('(−) Vales no periodo', moeda.format(totalVales), estilo),
            _linhaResumo('(−) Descontos lancados', moeda.format(totalDesc), estilo),
            _linhaResumo('(+) Bonus', moeda.format(totalBonus), estilo),
            _linhaResumo(
              '(=) Liquido referencia',
              moeda.format(liquido),
              estilo,
              destaque: true,
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text('Lancamentos', style: estilo(true, 11)),
        pw.SizedBox(height: 6),
        if (lancamentos.isEmpty)
          pw.Text('Nenhum lancamento no periodo.', style: estilo())
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.1),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(0.9),
              3: const pw.FlexColumnWidth(2.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _celCab('Data', estilo),
                  _celCab('Tipo', estilo),
                  _celCab('Valor', estilo),
                  _celCab('Observacao', estilo),
                ],
              ),
              ...lancamentos.map((l) {
                final estornado = l.estornado ? ' [ESTORNADO]' : '';
                return pw.TableRow(
                  children: [
                    _cel(dataFmt.format(l.data.toLocal()), estilo),
                    _cel(
                      '${LancamentoFuncionarioCatalogo.rotulo(l.tipo)}$estornado',
                      estilo,
                    ),
                    _cel(
                      l.tipo == LancamentoFuncionarioCatalogo.observacao
                          ? '—'
                          : moeda.format(l.valor),
                      estilo,
                    ),
                    _cel(l.observacao, estilo),
                  ],
                );
              }),
            ],
          ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _celCab(String t, pw.TextStyle Function([bool, double]) estilo) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(t, style: estilo(true, 8)),
    );

pw.Widget _cel(String t, pw.TextStyle Function([bool, double]) estilo) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(t, style: estilo(false, 8)),
    );

pw.TableRow _linhaResumo(
  String rotulo,
  String valor,
  pw.TextStyle Function([bool, double]) estilo, {
  bool destaque = false,
}) {
  return pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(rotulo, style: estilo(destaque, destaque ? 10 : 9)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          valor,
          style: estilo(destaque, destaque ? 10 : 9),
          textAlign: pw.TextAlign.right,
        ),
      ),
    ],
  );
}
