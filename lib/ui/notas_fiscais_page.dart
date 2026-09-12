import 'package:flutter/material.dart';

import '../services/configuracoes_service.dart';
import '../data/api/lan_api_client.dart';
import '../domain/main_menu_sub_destino.dart';
import '../model/usuario_sistema.dart';
import 'fiscal/nfe_importacao_xml_flow.dart';
import 'layout/app_layout.dart';
import 'shell/hub_navigation.dart';
import 'widgets/hub_nav_button.dart';

/// Entrada de NF-e por XML e consulta do log de importacoes.
class NotasFiscaisPage extends StatelessWidget {
  const NotasFiscaisPage({
    super.key,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.configuracoesService,
    required this.usuarioLogado,
    this.terminalLeve = false,
    this.lanApiClient,
  });

  final dynamic produtoRepository;
  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final ConfiguracoesService configuracoesService;
  final UsuarioSistema usuarioLogado;
  final bool terminalLeve;
  final LanApiClient? lanApiClient;

  Future<void> _importarNfeXml(BuildContext context) async {
    if (terminalLeve && lanApiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conecte-se a API do PC servidor (:8788) para importar NF-e.',
          ),
        ),
      );
      return;
    }
    await NfeImportacaoXmlFlow.executar(
      context,
      produtoRepository: produtoRepository,
      configuracoesService: configuracoesService,
      lanApiClient: lanApiClient,
    );
  }

  void _abrirSub(BuildContext context, MainMenuSubDestino sub) {
    HubNavigation.abrirSub(context, sub);
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
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalNotasImportadas,
            ),
          ),
          HubNavButton(
            icon: Icons.move_to_inbox_outlined,
            corDestaque: HubNavColors.menuNotasFiscais(context),
            titulo: 'NF-e recebidas (Focus)',
            subtitulo:
                'Notas emitidas contra o CNPJ da loja: sync Focus, manifestacao MDe, XML e importacao.',
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalNotasRecebidas,
            ),
          ),
          HubNavButton(
            icon: Icons.assignment_return_outlined,
            corDestaque: HubNavColors.menuNotasFiscais(context),
            titulo: 'Devolucao ao fornecedor',
            subtitulo:
                'NF-e de saida (CFOP 5202/6202) referenciando a compra + baixa de estoque.',
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalDevolucaoFornecedor,
            ),
          ),
          HubNavButton(
            icon: Icons.pending_actions_outlined,
            corDestaque: HubNavColors.menuNotasFiscais(context),
            titulo: 'Pendencias fiscais',
            subtitulo:
                'NFC-e a emitir (PIX/cartao), aguardando SEFAZ e NF-e 55.',
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalPendencias,
            ),
          ),
          HubNavButton(
            icon: Icons.description_outlined,
            corDestaque: HubNavColors.menuNotasFiscais(context),
            titulo: 'NF-e de saida (Modelo 55)',
            subtitulo:
                'Faturamento para construtoras e cargas pesadas. Emissao Focus NFe.',
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalNfeSaida,
            ),
          ),
          HubNavButton(
            icon: Icons.analytics_outlined,
            corDestaque: HubNavColors.menuNotasFiscais(context),
            titulo: 'Relatorio fiscal do mes',
            subtitulo:
                'Resumo de saidas (NF-e/NFC-e), entradas e totais antes do ZIP.',
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalRelatorioMensal,
            ),
          ),
          HubNavButton(
            icon: Icons.folder_zip_outlined,
            corDestaque: HubNavColors.menuNotasFiscais(context),
            titulo: 'Exportar fechamento',
            subtitulo:
                'Pacote mensal para contabilidade (XML + relatorio + CSV).',
            onTap: () => _abrirSub(
              context,
              MainMenuSubDestino.fiscalExportarFechamento,
            ),
          ),
        ],
      ),
    );
  }
}
