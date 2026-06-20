import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/nfe_entrada_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../model/usuario_sistema.dart';
import '../services/xml_nfe_parser_service.dart';
import 'conferencia_xml_screen.dart';
import 'fiscal/exportar_fechamento_page.dart';
import 'fiscal/nfe_gerenciamento_page.dart';
import 'fiscal/pendencias_fiscais_page.dart';
import 'fiscal/relatorio_fiscal_mensal_page.dart';
import 'nfe_importadas_page.dart';
import 'layout/app_layout.dart';
import 'widgets/hub_nav_button.dart';

/// Entrada de NF-e por XML e consulta do log de importacoes.
class NotasFiscaisPage extends StatelessWidget {
  const NotasFiscaisPage({
    super.key,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.appConfigRepository,
    required this.usuarioLogado,
  });

  final ProdutoRepository produtoRepository;
  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final AppConfigRepository appConfigRepository;
  final UsuarioSistema usuarioLogado;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas Fiscais'),
      ),
      body: AdaptiveHubBody(
        children: [
            HubNavButton(
              icon: Icons.receipt_long_outlined,
              corDestaque: HubNavColors.menuNotasFiscais(context),
              titulo: 'Importar NF-e (XML)',
              subtitulo:
                  'Leia o XML da nota, confira os itens e lance a entrada no estoque.',
              onTap: () => _importarNfeXml(context),
            ),
            HubNavButton(
              icon: Icons.fact_check_outlined,
              corDestaque: HubNavColors.menuNotasFiscais(context),
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
            HubNavButton(
              icon: Icons.pending_actions_outlined,
              corDestaque: HubNavColors.menuNotasFiscais(context),
              titulo: 'Pendencias fiscais',
              subtitulo:
                  'NFC-e aguardando SEFAZ (reconsulta manual) e atalho para NF-e 55.',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => PendenciasFiscaisPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      appConfigRepository: appConfigRepository,
                      usuarioLogado: usuarioLogado,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.description_outlined,
              corDestaque: HubNavColors.menuNotasFiscais(context),
              titulo: 'NF-e de saida (Modelo 55)',
              subtitulo:
                  'Faturamento para construtoras e cargas pesadas. Emissao Focus NFe.',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => NfeGerenciamentoPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      appConfigRepository: appConfigRepository,
                      usuarioLogado: usuarioLogado,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.analytics_outlined,
              corDestaque: HubNavColors.menuNotasFiscais(context),
              titulo: 'Relatorio fiscal do mes',
              subtitulo:
                  'Resumo de saidas (NF-e/NFC-e), entradas e totais antes do ZIP.',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => RelatorioFiscalMensalPage(
                      vendaRepository: vendaRepository,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.folder_zip_outlined,
              corDestaque: HubNavColors.menuNotasFiscais(context),
              titulo: 'Exportar Fechamento do Mes',
              subtitulo:
                  'ZIP com XMLs autorizados e planilha Excel para a contabilidade.',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ExportarFechamentoPage(
                      vendaRepository: vendaRepository,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
