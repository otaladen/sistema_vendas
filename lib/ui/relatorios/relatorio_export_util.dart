import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Monta paginas de texto tabulado para PDF de relatorios.
List<String> relatorioMontarPaginasTabela({
  required String titulo,
  String? subtitulo,
  required List<String> cabecalho,
  required List<List<String>> linhas,
  int maxLinhasPorPagina = 52,
}) {
  final buf = StringBuffer()
    ..writeln(titulo);
  if (subtitulo != null && subtitulo.trim().isNotEmpty) {
    buf.writeln(subtitulo);
  }
  buf.writeln();
  buf.writeln(cabecalho.join(' | '));
  buf.writeln('-' * 96);
  for (final row in linhas) {
    buf.writeln(row.join(' | '));
  }
  final texto = buf.toString();
  final partes = texto.split('\n');
  if (partes.isEmpty) return <String>['(vazio)'];
  final paginas = <String>[];
  for (var i = 0; i < partes.length; i += maxLinhasPorPagina) {
    final fim = math.min(i + maxLinhasPorPagina, partes.length);
    paginas.add(partes.sublist(i, fim).join('\n'));
  }
  return paginas;
}

String _escapeCampoCsv(String valor) {
  final v = valor.replaceAll('\r', ' ').replaceAll('\n', ' ');
  if (v.contains(';') || v.contains('"')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// CSV com separador `;` (padrao Excel BR).
String relatorioMontarCsv(List<List<String>> linhas) {
  return linhas
      .map((row) => row.map(_escapeCampoCsv).join(';'))
      .join('\n');
}

Future<void> relatorioSalvarCsv(
  BuildContext context, {
  required String nomeArquivoSemExtensao,
  required List<List<String>> linhas,
  String? mensagemSeVazio,
}) async {
  if (linhas.isEmpty) {
    if (context.mounted && mensagemSeVazio != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagemSeVazio)),
      );
    }
    return;
  }
  final pasta = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Pasta para salvar o CSV',
  );
  if (pasta == null || pasta.trim().isEmpty) return;
  final seguro = nomeArquivoSemExtensao.replaceAll(RegExp(r'[^\w\-]+'), '_');
  final arquivo = File(p.join(pasta, '$seguro.csv'));
  try {
    await arquivo.writeAsString('${relatorioMontarCsv(linhas)}\n');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV salvo: ${arquivo.path}')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro ao salvar CSV: $e')),
    );
  }
}
