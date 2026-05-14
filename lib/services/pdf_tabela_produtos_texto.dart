import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../model/produto.dart';

String _fmtMoeda(num valor) =>
    valor.toStringAsFixed(2).replaceAll('.', ',');

double _precoAVista(Produto produto) =>
    produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;

String _trunc(String s, int max) {
  if (s.length <= max) return s;
  if (max <= 1) return s.substring(0, max);
  return s.substring(0, max - 1);
}

String _cabecalhoColunas({
  required bool incluirCustos,
  required bool incluirEstoque,
}) {
  if (incluirEstoque) {
    if (incluirCustos) {
      return '${'CODIGO'.padRight(12)} ${'PRODUTO'.padRight(34)} '
          '${'EST'.padLeft(7)} ${'A_PRAZO'.padLeft(10)} '
          '${'A_VISTA'.padLeft(10)} ${'CUSTO'.padLeft(10)}';
    }
    return '${'CODIGO'.padRight(12)} ${'PRODUTO'.padRight(34)} '
        '${'EST'.padLeft(7)} ${'A_PRAZO'.padLeft(10)} ${'A_VISTA'.padLeft(10)}';
  }
  if (incluirCustos) {
    return '${'CODIGO'.padRight(12)} ${'PRODUTO'.padRight(40)} '
        '${'A_PRAZO'.padLeft(10)} ${'A_VISTA'.padLeft(10)} ${'CUSTO'.padLeft(10)}';
  }
  return '${'CODIGO'.padRight(12)} ${'PRODUTO'.padRight(42)} '
      '${'A_PRAZO'.padLeft(10)} ${'A_VISTA'.padLeft(10)}';
}

String _linha(
  Produto p, {
  required bool incluirCustos,
  required bool incluirEstoque,
}) {
  const wCod = 12;
  final c = _trunc(p.codigoInterno, wCod).padRight(wCod);
  if (incluirEstoque) {
    const wNome = 34;
    final n = _trunc(p.nome, wNome).padRight(wNome);
    final e = p.estoqueReal.toString().padLeft(7);
    final pr = _fmtMoeda(p.precoVenda).padLeft(10);
    final pv = _fmtMoeda(_precoAVista(p)).padLeft(10);
    if (!incluirCustos) return '$c $n $e $pr $pv';
    final cu = _fmtMoeda(p.precoCusto).padLeft(10);
    return '$c $n $e $pr $pv $cu';
  }
  const wNome40 = 40;
  const wNome42 = 42;
  if (incluirCustos) {
    final n = _trunc(p.nome, wNome40).padRight(wNome40);
    final pr = _fmtMoeda(p.precoVenda).padLeft(10);
    final pv = _fmtMoeda(_precoAVista(p)).padLeft(10);
    final cu = _fmtMoeda(p.precoCusto).padLeft(10);
    return '$c $n $pr $pv $cu';
  }
  final n = _trunc(p.nome, wNome42).padRight(wNome42);
  final pr = _fmtMoeda(p.precoVenda).padLeft(10);
  final pv = _fmtMoeda(_precoAVista(p)).padLeft(10);
  return '$c $n $pr $pv';
}

/// PDF simples (Courier, texto puro por pagina): bem mais leve que [pw.Table].
Future<Uint8List> gerarPdfTabelaProdutosTexto({
  required List<Produto> produtos,
  required bool incluirCustos,
  required String titulo,
  required bool incluirColunaEstoque,
}) async {
  final doc = pw.Document();
  const corpoPorPagina = 68;
  final dataStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
  final cabCols = _cabecalhoColunas(
    incluirCustos: incluirCustos,
    incluirEstoque: incluirColunaEstoque,
  );
  final sep = '-' * cabCols.length;

  final linhasDados = <String>[
    for (final p in produtos)
      _linha(
        p,
        incluirCustos: incluirCustos,
        incluirEstoque: incluirColunaEstoque,
      ),
  ];

  final totalPaginas = math.max(
    1,
    (linhasDados.length / corpoPorPagina).ceil(),
  );

  final f = pw.Font.courier();
  final estilo = pw.TextStyle.defaultStyle().copyWith(
    fontSize: 7,
    fontNormal: f,
    fontBold: pw.Font.courierBold(),
    fontItalic: pw.Font.courierOblique(),
    fontBoldItalic: pw.Font.courierBoldOblique(),
    lineSpacing: 0.35,
    height: 1.05,
  );

  for (var pag = 0; pag < totalPaginas; pag++) {
    final ini = pag * corpoPorPagina;
    final fim = math.min(ini + corpoPorPagina, linhasDados.length);
    final chunk = linhasDados.sublist(ini, fim);

    final buf = StringBuffer()
      ..writeln('$dataStr  $titulo  Pag ${pag + 1}/$totalPaginas')
      ..writeln()
      ..writeln(cabCols)
      ..writeln(sep);
    for (final l in chunk) {
      buf.writeln(l);
    }
    if (chunk.isEmpty) {
      buf.writeln('(nenhum produto)');
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Text(buf.toString(), style: estilo),
      ),
    );
  }

  return doc.save();
}
