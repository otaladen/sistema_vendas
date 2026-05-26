import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../data/nfe_saida_fiscal_store.dart';

/// Detalhe completo de um registro NF-e (copiar chave, referencia).
Future<void> showNfeRegistroDetalheDialog(
  BuildContext context,
  NfeSaidaFiscalRegistro registro,
) async {
  final fmt = DateFormat('dd/MM/yyyy HH:mm');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('NF-e — ${registro.rotuloStatus}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _linha('Emitida em', fmt.format(registro.emitidaEm.toLocal())),
              _linha('Venda / orcamento', '${registro.vendaId} / ${registro.numeroOrcamento}'),
              _linha('Cliente', registro.clienteNome),
              _linha('Referencia Focus', registro.referenciaFocus),
              if (registro.numero.isNotEmpty)
                _linha('Numero / serie', '${registro.numero} / ${registro.serie}'),
              if (registro.chaveNfe.isNotEmpty) _linha('Chave', registro.chaveNfe),
              if (registro.protocolo.isNotEmpty) _linha('Protocolo', registro.protocolo),
              if (registro.mensagemSefaz.isNotEmpty)
                _linha('Mensagem SEFAZ', registro.mensagemSefaz),
              if (registro.numeroCartaCorrecao > 0)
                _linha('CC-e', 'Sequencia ${registro.numeroCartaCorrecao}'),
            ],
          ),
        ),
      ),
      actions: [
        if (registro.chaveNfe.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: registro.chaveNfe));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Chave copiada.')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar chave'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

Widget _linha(String titulo, String valor) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 2),
        SelectableText(valor),
      ],
    ),
  );
}
