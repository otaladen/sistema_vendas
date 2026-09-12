import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/configuracoes_service.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/nfe_entrada_api_repository.dart';
import '../../data/nfe_entrada_repository.dart';
import '../../model/item_nota_temporario.dart';
import '../../services/xml_nfe_parser_service.dart';
import '../conferencia_xml_screen.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';

/// Fluxo compartilhado de importacao de NF-e por XML.
abstract final class NfeImportacaoXmlFlow {
  NfeImportacaoXmlFlow._();

  /// Importa a partir do conteudo XML (ex.: download Focus NF-e recebida).
  static Future<void> executarComConteudoXml(
    BuildContext context, {
    required String xml,
    required dynamic produtoRepository,
    required ConfiguracoesService configuracoesService,
    LanApiClient? lanApiClient,
  }) async {
    if (xml.trim().isEmpty) return;
    await _processarXml(
      context,
      xml: xml,
      produtoRepository: produtoRepository,
      configuracoesService: configuracoesService,
      lanApiClient: lanApiClient,
    );
  }

  static Future<void> executar(
    BuildContext context, {
    required dynamic produtoRepository,
    required ConfiguracoesService configuracoesService,
    LanApiClient? lanApiClient,
  }) async {
    final client =
        lanApiClient ?? MainMenuDeps.maybeOf(context)?.lanApiClient;
    final viaApi = client != null;
    if (viaApi && !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }

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
      if (!context.mounted) return;
      await _processarXml(
        context,
        xml: xml,
        produtoRepository: produtoRepository,
        configuracoesService: configuracoesService,
        lanApiClient: lanApiClient,
      );
    } on LanApiException catch (e) {
      if (!context.mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'NF-e');
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML invalido: ${e.message}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Nao foi possivel ler a NF-e',
      );
    }
  }

  static Future<void> _processarXml(
    BuildContext context, {
    required String xml,
    required dynamic produtoRepository,
    required ConfiguracoesService configuracoesService,
    LanApiClient? lanApiClient,
  }) async {
    final client =
        lanApiClient ?? MainMenuDeps.maybeOf(context)?.lanApiClient;
    final viaApi = client != null;
    if (viaApi && !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }

    final NfeXmlParseResult nfe;
    final dynamic repo;
    List<SugestaoLinhaConferencia>? sugestoes;
    if (viaApi) {
      final api = NfeEntradaApiRepository(client, produtoRepository);
      final parse = await api.lerXmlRemoto(xml);
      if (!context.mounted) return;
      if (parse.jaImportada) {
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
      nfe = parse.nfe;
      sugestoes = parse.sugestoes.isEmpty ? null : parse.sugestoes;
      repo = api;
    } else {
      nfe = XmlParserService.parseNfeXmlString(xml);
      repo = NfeEntradaRepository(produtoRepository.objectBox);
      final jaImportada = repo.chaveNfeJaImportada(nfe.chaveAcesso) as bool;
      if (jaImportada) {
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
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConferenciaXmlScreen(
          nfe: nfe,
          nfeRepository: repo,
          produtoRepository: produtoRepository,
          configuracoesService: configuracoesService,
          xmlOriginal: xml,
          sugestoesIniciais: sugestoes,
        ),
      ),
    );
  }
}
