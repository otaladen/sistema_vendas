import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/venda_relacao_safe.dart';
import '../../model/venda.dart';
import 'logistica_entregas.dart';
import 'romaneio_carga_consolidada.dart';

/// Endereco completo para romaneio/PDF (entrega ou cadastro do cliente).
String enderecoExibicaoRomaneio(Venda venda, {dynamic clienteRepository}) {
  final entrega = venda.enderecoEntrega.trim();
  if (entrega.isNotEmpty) return entrega;
  final cli = VendaRelacaoSafe.cliente(
    venda,
    clienteRepository: clienteRepository,
  );
  if (cli == null) return '';
  final enderecos = cli.listarEnderecos();
  if (enderecos.isNotEmpty) return enderecos.first.resumo();
  return '';
}

/// Tabela da carga consolidada (PDF) — impressao unica do total do carro.
pw.Widget pwRomaneioSecaoCargaConsolidada({
  required List<RomaneioCargaConsolidadaLinha> linhas,
  required bool bobina,
  pw.TextStyle? estiloBase,
  String titulo = 'Carga consolidada',
  String subtitulo =
      'Resumo para separacao no patio (soma de produtos iguais).',
}) {
  final base = estiloBase ?? const pw.TextStyle(fontSize: 10);
  if (linhas.isEmpty) {
    return pw.Text(
      'Sem itens para consolidar neste grupo.',
      style: base.copyWith(fontSize: bobina ? 6.5 : 10),
    );
  }
  final fsTit = bobina ? 7.5 : 12.0;
  final fsLin = bobina ? 6.5 : 10.0;
  final fsCab = bobina ? 6.2 : 9.5;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        titulo,
        style: base.copyWith(fontWeight: pw.FontWeight.bold, fontSize: fsTit),
      ),
      pw.SizedBox(height: bobina ? 2 : 4),
      pw.Text(
        subtitulo,
        style: base.copyWith(
          fontSize: fsCab,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
      pw.SizedBox(height: bobina ? 3 : 6),
      pw.Table(
        border: pw.TableBorder.all(width: bobina ? 0.35 : 0.5),
        columnWidths: bobina
            ? {
                0: const pw.FlexColumnWidth(3.2),
                1: const pw.FlexColumnWidth(1.3),
                2: const pw.FlexColumnWidth(0.7),
                3: const pw.FlexColumnWidth(0.9),
              }
            : {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(1),
              },
        children: [
          pw.TableRow(
            children: [
              _pwCelCabRomaneio('Produto', fsCab, base),
              _pwCelCabRomaneio('SKU', fsCab, base),
              _pwCelCabRomaneio('Und', fsCab, base),
              _pwCelCabRomaneio('Qtd total', fsCab, base),
            ],
          ),
          ...linhas.map(
            (l) => pw.TableRow(
              children: [
                _pwCelCorpoRomaneio(
                  l.rotuloLote.trim().isEmpty
                      ? l.nomeProduto
                      : '${l.nomeProduto}\n${l.rotuloLote}',
                  fsLin,
                  base,
                ),
                _pwCelCorpoRomaneio(l.codigoSku, fsLin, base),
                _pwCelCorpoRomaneio(l.unidade, fsLin, base),
                _pwCelCorpoRomaneio(
                  '${l.quantidadeTotal}',
                  fsLin,
                  base,
                  negrito: true,
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: bobina ? 4 : 8),
    ],
  );
}

pw.Widget _pwCelCabRomaneio(String texto, double fs, pw.TextStyle base) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(3),
    child: pw.Text(
      texto,
      style: base.copyWith(fontSize: fs, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _pwCelCorpoRomaneio(
  String texto,
  double fs,
  pw.TextStyle base, {
  bool negrito = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(3),
    child: pw.Text(
      texto,
      style: base.copyWith(
        fontSize: fs,
        fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

/// Formato de pagina do PDF do romaneio de entregas.
enum RomaneioPdfLayout {
  /// Pagina A4 (padrao).
  a4,

  /// Bobina termica 80 mm (varias paginas de altura fixa).
  bobina80mm,
}

List<pw.Widget> _montarWidgetsCorpoRomaneio({
  required List<Venda> entregasDia,
  required pw.Widget Function(Venda venda) pdfUmaEntrega,
  required bool bobina,
  List<RomaneioCargaConsolidadaLinha> Function(List<Venda> blocoGrupo)?
      itensCargaConsolidadaGrupo,
  required pw.TextStyle estiloBase,
}) {
  final fsGrupoTitulo = bobina ? 7.8 : 11.0;
  final fsGrupoSub = bobina ? 7.0 : 9.5;
  final padGrupo = bobina ? 4.0 : 6.0;
  final gapGrupoBottom = bobina ? 5.0 : 8.0;

  final saida = <pw.Widget>[];
  for (final bloco in blocosEntregaComCarretoAgrupado(entregasDia)) {
    if (bloco.length >= 2 && bloco.first.grupoEntregaFreteId > 0) {
      saida.add(
        pw.Container(
          margin: pw.EdgeInsets.only(bottom: gapGrupoBottom),
          padding: pw.EdgeInsets.all(padGrupo),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: bobina ? 0.5 : 0.7),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (itensCargaConsolidadaGrupo != null) ...[
                pwRomaneioSecaoCargaConsolidada(
                  linhas: itensCargaConsolidadaGrupo(bloco),
                  bobina: bobina,
                  estiloBase: estiloBase,
                ),
                pw.Divider(thickness: bobina ? 0.6 : 1.0),
              ],
              pw.Text(
                rotuloGrupoLogistica(bloco),
                style: estiloBase.copyWith(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: fsGrupoTitulo,
                ),
              ),
              pw.Text(
                '${bloco.length} pedidos no mesmo veiculo',
                style: estiloBase.copyWith(fontSize: fsGrupoSub),
              ),
              pw.SizedBox(height: bobina ? 3 : 4),
              ...bloco.map(pdfUmaEntrega),
            ],
          ),
        ),
      );
    } else {
      for (final v in bloco) {
        saida.add(pdfUmaEntrega(v));
      }
    }
  }
  return saida;
}

Future<Uint8List> gerarEntregasRomaneioPdfBytes({
  required List<Venda> entregasDia,
  required String tituloPeriodo,
  required DateTime emissao,
  required pw.Widget Function(Venda venda) pdfUmaEntrega,
  RomaneioPdfLayout layout = RomaneioPdfLayout.a4,
  /// Quando informado, cada bloco "mesmo carro" inclui secao de carga consolidada antes dos pedidos.
  List<RomaneioCargaConsolidadaLinha> Function(List<Venda> blocoGrupo)?
      itensCargaConsolidadaGrupo,
}) async {
  final doc = pw.Document();
  final horaEmissao = DateFormat('dd/MM/yyyy HH:mm').format(emissao);
  final bobina = layout == RomaneioPdfLayout.bobina80mm;

  // Courier suporta acentos comuns (enderecos, nomes) melhor que Helvetica padrao.
  final fonte = pw.Font.courier();
  final estiloBase = pw.TextStyle(
    fontSize: bobina ? 7.5 : 10,
    font: fonte,
    fontNormal: fonte,
    fontBold: pw.Font.courierBold(),
  );

  final pageFormat = bobina
      ? PdfPageFormat(
          80 * PdfPageFormat.mm,
          297 * PdfPageFormat.mm,
          marginAll: 6 * PdfPageFormat.mm,
        )
      : PdfPageFormat.a4;

  final fsTitulo = bobina ? 10.0 : 16.0;
  final fsMeta = bobina ? 7.5 : 12.0;
  final gapAposTitulo = bobina ? 3.0 : 4.0;
  final gapAntesLista = bobina ? 6.0 : 10.0;

  final corpo = _montarWidgetsCorpoRomaneio(
    entregasDia: entregasDia,
    pdfUmaEntrega: pdfUmaEntrega,
    bobina: bobina,
    itensCargaConsolidadaGrupo: itensCargaConsolidadaGrupo,
    estiloBase: estiloBase,
  );

  // Uma unica Column em pw.Page corta o restante do romaneio (pagina em branco).
  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: bobina ? null : const pw.EdgeInsets.all(24),
      build: (context) {
        return [
          pw.Text(
            'Romaneio de Entregas - $tituloPeriodo',
            style: estiloBase.copyWith(
              fontSize: fsTitulo,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: gapAposTitulo),
          pw.Text(
            'Emitido em: $horaEmissao',
            style: estiloBase.copyWith(fontSize: fsMeta),
          ),
          pw.Text(
            'Total de entregas: ${entregasDia.length}',
            style: estiloBase.copyWith(fontSize: fsMeta),
          ),
          if (bobina)
            pw.Text(
              'Formato: bobina 80 mm',
              style: estiloBase.copyWith(fontSize: fsMeta - 0.5),
            ),
          pw.SizedBox(height: gapAntesLista),
          pw.Divider(thickness: bobina ? 0.6 : 1.0),
          ...corpo,
        ];
      },
    ),
  );
  return doc.save();
}
