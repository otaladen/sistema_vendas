import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_config_repository.dart';
import '../../data/api/lan_api_client.dart';
import 'nfe_importacao_xml_flow.dart';
import '../widgets/hub_nav_button.dart';

/// Entrada de NF-e por XML (atalho direto do menu lateral).
class FiscalImportarNfePage extends StatelessWidget {
  const FiscalImportarNfePage({
    super.key,
    required this.produtoRepository,
    required this.appConfigRepository,
    this.lanApiClient,
  });

  final dynamic produtoRepository;
  final AppConfigRepository appConfigRepository;
  final LanApiClient? lanApiClient;

  void _importar(BuildContext context) {
    NfeImportacaoXmlFlow.executar(
      context,
      produtoRepository: produtoRepository,
      appConfigRepository: appConfigRepository,
      lanApiClient: lanApiClient,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => _importar(context),
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
        ): () => _importar(context),
      },
      child: Scaffold(
          appBar: AppBar(
            title: const Text('Importar NF-e (XML)'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    'F1 ou Ctrl+O',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 56,
                      color: HubNavColors.menuNotasFiscais(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Leia o XML da nota, confira os itens e lance a entrada no estoque.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _importar(context),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Selecionar XML (F1)'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}
