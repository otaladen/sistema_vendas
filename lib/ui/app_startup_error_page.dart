import 'package:flutter/material.dart';

/// Tela minima quando o banco local nao pode ser aberto no startup.
class AppStartupErrorPage extends StatelessWidget {
  const AppStartupErrorPage({super.key, required this.erro});

  final String erro;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Nao foi possivel iniciar o sistema',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      erro,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verifique permissoes da pasta de dados, antivirus bloqueando '
                  'o ObjectBox ou execute como administrador. Reinicie o app apos corrigir.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
