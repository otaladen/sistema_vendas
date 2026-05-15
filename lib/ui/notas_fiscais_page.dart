import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/nfe_entrada_repository.dart';
import '../data/produto_repository.dart';
import '../services/xml_nfe_parser_service.dart';
import 'conferencia_xml_screen.dart';
import 'nfe_importadas_page.dart';
import 'widgets/hub_nav_button.dart';

/// Entrada de NF-e por XML e consulta do log de importacoes.
class NotasFiscaisPage extends StatelessWidget {
  const NotasFiscaisPage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  Future<void> _importarNfeXml(BuildContext context) async {
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
              'Esta NF-e ja foi importada antes. Use "Notas ja importadas" nesta tela para ver o registro.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas Fiscais'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HubNavButton(
              icon: Icons.receipt_long_outlined,
              corDestaque: HubNavColors.menuNotasFiscais,
              titulo: 'Importar NF-e (XML)',
              subtitulo:
                  'Leia o XML da nota, confira os itens e lance a entrada no estoque.',
              onTap: () => _importarNfeXml(context),
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.fact_check_outlined,
              corDestaque: HubNavColors.menuNotasFiscais,
              titulo: 'Notas ja importadas',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => NfeImportadasPage(
                      produtoRepository: produtoRepository,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
