import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/app_config_repository.dart';
import '../../data/nfe_entrada_repository.dart';
import '../../data/produto_repository.dart';
import '../../services/xml_nfe_parser_service.dart';
import '../conferencia_xml_screen.dart';

/// Fluxo compartilhado de importacao de NF-e por XML.
abstract final class NfeImportacaoXmlFlow {
  NfeImportacaoXmlFlow._();

  static Future<void> executar(
    BuildContext context, {
    required ProdutoRepository produtoRepository,
    required AppConfigRepository appConfigRepository,
  }) async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      dialogTitle: 'Selecione o XML da NF-e',
    );
    if (pick == null || pick.files.isEmpty) return;
    final path = pick.files.single.path;
    if (path == null || path.isEmpty) return;
    try {
      final xml = await File(path).readAsString();
      final nfe = XmlParserService.parseNfeXmlString(xml);
      if (!context.mounted) return;
      final repo = NfeEntradaRepository(produtoRepository.objectBox);
      if (repo.chaveNfeJaImportada(nfe.chaveAcesso)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 7),
            content: Text(
              'Esta NF-e ja foi importada antes. Use "Notas ja importadas" para ver o registro.',
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ConferenciaXmlScreen(
            nfe: nfe,
            nfeRepository: repo,
            produtoRepository: produtoRepository,
            appConfigRepository: appConfigRepository,
            xmlOriginal: xml,
          ),
        ),
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML invalido: ${e.message}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel ler a NF-e: $e')),
      );
    }
  }
}
