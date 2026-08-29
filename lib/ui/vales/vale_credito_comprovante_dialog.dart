import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/vale_credito_service.dart';

/// Mostra o codigo do vale grande o suficiente para o cliente anotar ou
/// fotografar, ja que o comprovante de papel se perde.
Future<void> mostrarComprovanteVale(
  BuildContext context, {
  required ValeCreditoResumo vale,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ComprovanteValeDialog(vale: vale),
  );
}

class _ComprovanteValeDialog extends StatelessWidget {
  const _ComprovanteValeDialog({required this.vale});

  final ValeCreditoResumo vale;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    final data = DateFormat('dd/MM/yyyy', 'pt_BR');
    final validade = vale.dataValidade;

    return AlertDialog(
      title: const Text('Vale de credito gerado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: tema.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tema.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Text(
                  'Codigo do vale',
                  style: tema.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  vale.codigoFormatado,
                  textAlign: TextAlign.center,
                  style: tema.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'R\$ ${moeda.format(vale.valorOriginal)}',
                  style: tema.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tema.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (vale.clienteNome.isNotEmpty)
            _Linha(rotulo: 'Cliente', valor: vale.clienteNome),
          if (vale.numeroVendaOrigem > 0)
            _Linha(rotulo: 'Da venda', valor: 'Orc. ${vale.numeroVendaOrigem}'),
          _Linha(rotulo: 'Emitido em', valor: data.format(vale.dataEmissao)),
          _Linha(
            rotulo: 'Validade',
            valor: validade == null ? 'Sem prazo' : data.format(validade),
          ),
          const SizedBox(height: 14),
          Text(
            vale.clienteNome.isEmpty
                ? 'Anote o codigo para o cliente. Como a venda nao tem cliente '
                    'cadastrado, quem apresentar o codigo usa o vale.'
                : 'O vale tambem esta no cadastro do cliente, entao da para '
                    'recuperar pelo nome se o cliente perder o codigo.',
            style: tema.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: vale.codigoFormatado),
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Codigo copiado.')),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar codigo'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Pronto'),
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              rotulo,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
