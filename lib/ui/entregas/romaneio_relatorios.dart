import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../model/item_venda.dart';
import '../../model/venda.dart';
import 'logistica_entregas.dart';
import 'romaneio_carga_consolidada.dart';
import 'romaneio_pdf.dart';

/// Tipos de relatorio da aba Entregas (galpao x motorista).
enum RelatorioEntregaTipo {
  /// Motorista: todos os pedidos dele no dia, por parada, sem consolidada.
  romaneioMotoristaDia,

  /// Galpao: soma de produtos de uma viagem (grupo / mesmo carro).
  separacaoViagem,

  /// Galpao: soma de todas as viagens do motorista no dia.
  separacaoMotoristaDia,

  /// Galpao: soma de todas as entregas do periodo filtrado.
  separacaoTotalDia,
}

extension RelatorioEntregaTipoExt on RelatorioEntregaTipo {
  String get rotulo {
    switch (this) {
      case RelatorioEntregaTipo.romaneioMotoristaDia:
        return 'Romaneio do motorista (dia inteiro, por pedido)';
      case RelatorioEntregaTipo.separacaoViagem:
        return 'Separacao — viagem (carga consolidada)';
      case RelatorioEntregaTipo.separacaoMotoristaDia:
        return 'Separacao — motorista no dia (carga consolidada)';
      case RelatorioEntregaTipo.separacaoTotalDia:
        return 'Separacao — total do dia (carga consolidada)';
    }
  }

  bool get exigeMotorista =>
      this == RelatorioEntregaTipo.romaneioMotoristaDia ||
      this == RelatorioEntregaTipo.separacaoMotoristaDia;

  bool get exigeViagem => this == RelatorioEntregaTipo.separacaoViagem;
}

String tituloPdfRelatorioEntrega({
  required RelatorioEntregaTipo tipo,
  required String tituloPeriodo,
  String? motorista,
  List<Venda>? viagem,
}) {
  switch (tipo) {
    case RelatorioEntregaTipo.romaneioMotoristaDia:
      return 'Romaneio — $motorista — $tituloPeriodo';
    case RelatorioEntregaTipo.separacaoViagem:
      return 'Separacao viagem — ${rotuloGrupoLogistica(viagem ?? const [])} — $tituloPeriodo';
    case RelatorioEntregaTipo.separacaoMotoristaDia:
      return 'Separacao — $motorista — $tituloPeriodo';
    case RelatorioEntregaTipo.separacaoTotalDia:
      return 'Separacao total do dia — $tituloPeriodo';
  }
}

String nomeArquivoRelatorioEntrega({
  required RelatorioEntregaTipo tipo,
  required String tituloPeriodo,
  String? motorista,
  bool bobina80 = false,
}) {
  final suf = bobina80 ? '_bobina80' : '';
  final dia = tituloPeriodo.replaceAll('/', '').replaceAll(' ', '_');
  final motSlug = (motorista ?? 'x')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  switch (tipo) {
    case RelatorioEntregaTipo.romaneioMotoristaDia:
      return 'romaneio_${motSlug}_$dia$suf.pdf';
    case RelatorioEntregaTipo.separacaoViagem:
      return 'separacao_viagem_$dia$suf.pdf';
    case RelatorioEntregaTipo.separacaoMotoristaDia:
      return 'separacao_${motSlug}_$dia$suf.pdf';
    case RelatorioEntregaTipo.separacaoTotalDia:
      return 'separacao_total_$dia$suf.pdf';
  }
}

Future<Uint8List> gerarRelatorioEntregaPdfBytes({
  required RelatorioEntregaTipo tipo,
  required List<Venda> entregasPeriodo,
  required String tituloPeriodo,
  required DateTime emissao,
  required pw.Widget Function(Venda venda, {int? parada}) pdfUmaEntrega,
  required int Function(Venda venda, ItemVenda item) quantidadeEntrega,
  String? motorista,
  List<Venda>? viagem,
  RomaneioPdfLayout layout = RomaneioPdfLayout.a4,
}) async {
  final doc = pw.Document();
  final bobina = layout == RomaneioPdfLayout.bobina80mm;
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

  final tituloPdf = tituloPdfRelatorioEntrega(
    tipo: tipo,
    tituloPeriodo: tituloPeriodo,
    motorista: motorista,
    viagem: viagem,
  );
  final horaEmissao = DateFormat('dd/MM/yyyy HH:mm').format(emissao);
  final fsTitulo = bobina ? 10.0 : 16.0;
  final fsMeta = bobina ? 7.5 : 12.0;

  final corpo = _montarCorpoRelatorio(
    tipo: tipo,
    entregasPeriodo: entregasPeriodo,
    pdfUmaEntrega: pdfUmaEntrega,
    quantidadeEntrega: quantidadeEntrega,
    motorista: motorista,
    viagem: viagem,
    bobina: bobina,
    estiloBase: estiloBase,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: bobina ? null : const pw.EdgeInsets.all(24),
      build: (context) {
        return [
          pw.Text(
            tituloPdf,
            style: estiloBase.copyWith(
              fontSize: fsTitulo,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: bobina ? 3 : 4),
          pw.Text(
            'Emitido em: $horaEmissao',
            style: estiloBase.copyWith(fontSize: fsMeta),
          ),
          if (tipo == RelatorioEntregaTipo.romaneioMotoristaDia &&
              motorista != null) ...[
            pw.Text(
              'Motorista: $motorista',
              style: estiloBase.copyWith(fontSize: fsMeta),
            ),
            pw.Text(
              'Pedidos: ${filtrarVendasMotorista(entregasPeriodo, motorista).length}',
              style: estiloBase.copyWith(fontSize: fsMeta),
            ),
          ] else
            pw.Text(
              'Entregas no periodo: ${entregasPeriodo.length}',
              style: estiloBase.copyWith(fontSize: fsMeta),
            ),
          if (bobina)
            pw.Text(
              'Formato: bobina 80 mm',
              style: estiloBase.copyWith(fontSize: fsMeta - 0.5),
            ),
          pw.SizedBox(height: bobina ? 6 : 10),
          pw.Divider(thickness: bobina ? 0.6 : 1.0),
          ...corpo,
        ];
      },
    ),
  );
  return doc.save();
}

List<pw.Widget> _montarCorpoRelatorio({
  required RelatorioEntregaTipo tipo,
  required List<Venda> entregasPeriodo,
  required pw.Widget Function(Venda venda, {int? parada}) pdfUmaEntrega,
  required int Function(Venda venda, ItemVenda item) quantidadeEntrega,
  required String? motorista,
  required List<Venda>? viagem,
  required bool bobina,
  required pw.TextStyle estiloBase,
}) {
  switch (tipo) {
    case RelatorioEntregaTipo.romaneioMotoristaDia:
      return _corpoRomaneioMotoristaDia(
        entregasPeriodo: entregasPeriodo,
        motorista: motorista ?? '',
        pdfUmaEntrega: pdfUmaEntrega,
        bobina: bobina,
        estiloBase: estiloBase,
      );
    case RelatorioEntregaTipo.separacaoViagem:
      final bloco = viagem ?? const <Venda>[];
      return [
        pwRomaneioSecaoCargaConsolidada(
          linhas: romaneioMergeCargaGrupo(bloco, quantidadeEntrega),
          bobina: bobina,
          estiloBase: estiloBase,
          titulo: 'Separacao desta viagem',
          subtitulo:
              '${rotuloGrupoLogistica(bloco)} — ${bloco.length} pedido(s).',
        ),
      ];
    case RelatorioEntregaTipo.separacaoMotoristaDia:
      final vendas = ordenarRomaneioMotorista(
        filtrarVendasMotorista(entregasPeriodo, motorista ?? ''),
      );
      return [
        pwRomaneioSecaoCargaConsolidada(
          linhas: romaneioMergeCargaGrupo(vendas, quantidadeEntrega),
          bobina: bobina,
          estiloBase: estiloBase,
          titulo: 'Separacao — $motorista (dia inteiro)',
          subtitulo:
              'Soma de todas as viagens do motorista no periodo (${vendas.length} pedido(s)).',
        ),
      ];
    case RelatorioEntregaTipo.separacaoTotalDia:
      return [
        pwRomaneioSecaoCargaConsolidada(
          linhas: romaneioMergeCargaGrupo(entregasPeriodo, quantidadeEntrega),
          bobina: bobina,
          estiloBase: estiloBase,
          titulo: 'Separacao — total do dia',
          subtitulo:
              'Todos os motoristas e entregas do periodo (${entregasPeriodo.length} pedido(s)).',
        ),
      ];
  }
}

List<pw.Widget> _corpoRomaneioMotoristaDia({
  required List<Venda> entregasPeriodo,
  required String motorista,
  required pw.Widget Function(Venda venda, {int? parada}) pdfUmaEntrega,
  required bool bobina,
  required pw.TextStyle estiloBase,
}) {
  final vendas = ordenarRomaneioMotorista(
    filtrarVendasMotorista(entregasPeriodo, motorista),
  );
  if (vendas.isEmpty) {
    return [
      pw.Text(
        'Nenhuma entrega do motorista "$motorista" no periodo.',
        style: estiloBase,
      ),
    ];
  }

  final fsGrupoTitulo = bobina ? 7.8 : 11.0;
  final fsGrupoSub = bobina ? 7.0 : 9.5;
  final padGrupo = bobina ? 4.0 : 6.0;
  final gapGrupoBottom = bobina ? 5.0 : 8.0;
  final saida = <pw.Widget>[];

  final porGrupo = <int, List<Venda>>{};
  for (final v in vendas) {
    porGrupo.putIfAbsent(v.grupoEntregaFreteId, () => []).add(v);
  }
  final chavesGrupo = porGrupo.keys.toList()..sort();

  for (final g in chavesGrupo) {
    final viagem = ordenarBlocoMesmoCarro(porGrupo[g]!);
    if (g > 0 && viagem.length >= 2) {
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
              pw.Text(
                rotuloGrupoLogistica(viagem),
                style: estiloBase.copyWith(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: fsGrupoTitulo,
                ),
              ),
              pw.Text(
                'Conferir entregas na ordem das paradas abaixo.',
                style: estiloBase.copyWith(fontSize: fsGrupoSub),
              ),
              pw.SizedBox(height: bobina ? 3 : 4),
              ...viagem.map(
                (pedido) => pdfUmaEntrega(
                  pedido,
                  parada: numeroParadaNaViagem(pedido, viagem),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      for (final pedido in viagem) {
        saida.add(
          pdfUmaEntrega(
            pedido,
            parada: pedido.ordemEntrega > 0 ? pedido.ordemEntrega : null,
          ),
        );
      }
    }
  }
  return saida;
}
