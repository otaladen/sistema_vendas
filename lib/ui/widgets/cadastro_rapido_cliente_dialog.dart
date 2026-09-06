import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/cliente_api_repository.dart';
import '../../data/api/lan_api_client.dart';
import '../../model/cliente.dart';
import 'mascaras_cadastro_input.dart';

/// Dialogo de cadastro rapido (CPF/CNPJ + nome). Retorna [Cliente] salvo ou null.
Future<Cliente?> mostrarCadastroRapidoClienteDialog(
  BuildContext context, {
  required dynamic clienteRepository,
}) async {
  final nomeController = TextEditingController();
  final documentoController = TextEditingController();
  final cpfFormatter = CpfInputFormatter();
  final cnpjFormatter = CnpjInputFormatter();
  final nomeFocus = FocusNode();
  var tipoPessoa = 'fisica';

  TextInputFormatter documentoFormatterAtual() =>
      tipoPessoa == 'juridica' ? cnpjFormatter : cpfFormatter;

  void aplicarMascaraDocumento() {
    final fmt = documentoFormatterAtual();
    final d = somenteDigitos(documentoController.text);
    documentoController.value = fmt.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: d),
    );
  }

  final salvar = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final juridica = tipoPessoa == 'juridica';
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                Navigator.pop(ctx, false);
              },
              const SingleActivator(LogicalKeyboardKey.enter): () {
                Navigator.pop(ctx, true);
              },
            },
            child: AlertDialog(
              title: const Text('Cadastro rapido de cliente'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'fisica',
                          label: Text('Pessoa Fisica'),
                        ),
                        ButtonSegment(
                          value: 'juridica',
                          label: Text('Pessoa Juridica'),
                        ),
                      ],
                      selected: {tipoPessoa},
                      onSelectionChanged: (sel) {
                        setDialogState(() {
                          tipoPessoa = sel.first;
                          aplicarMascaraDocumento();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: documentoController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [documentoFormatterAtual()],
                      decoration: InputDecoration(
                        labelText: juridica ? 'CNPJ *' : 'CPF *',
                      ),
                      onSubmitted: (_) => Navigator.pop(ctx, true),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nomeController,
                      focusNode: nomeFocus,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText:
                            juridica ? 'Razao Social *' : 'Nome completo *',
                      ),
                      onSubmitted: (_) => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salvar (Enter)'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (salvar != true) {
    nomeFocus.dispose();
    nomeController.dispose();
    documentoController.dispose();
    return null;
  }

  final nome = nomeController.text.trim();
  final documento = somenteDigitos(documentoController.text);
  final tipo = tipoPessoa;
  nomeFocus.dispose();
  nomeController.dispose();
  documentoController.dispose();

  if (nome.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tipo == 'juridica'
                ? 'Informe a razao social do cliente.'
                : 'Informe o nome do cliente.',
          ),
        ),
      );
    }
    return null;
  }
  if (documento.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tipo == 'juridica'
                ? 'Informe o CNPJ do cliente.'
                : 'Informe o CPF do cliente.',
          ),
        ),
      );
    }
    return null;
  }
  if (!documentoCpfCnpjValidoOuVazio(documento, tipoPessoa: tipo)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tipo == 'juridica' ? 'CNPJ invalido.' : 'CPF invalido.',
          ),
        ),
      );
    }
    return null;
  }

  final agora = DateTime.now().toUtc();
  final cliente = Cliente(
    tipoPessoa: tipo,
    nomeRazao: nome,
    documento: documento,
    segmento: 'consumidor',
    origemCadastro: 'balcao',
    ativo: true,
    criadoEm: agora,
    atualizadoEm: agora,
  );

  try {
    final int id;
    if (clienteRepository is ClienteApiRepository) {
      id = await clienteRepository.salvarRemoto(cliente);
    } else {
      id = clienteRepository.salvar(cliente) as int;
    }
    final salvo = clienteRepository.obterPorId(id) as Cliente?;
    return salvo;
  } on LanApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return null;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel cadastrar cliente: $e')),
      );
    }
    return null;
  }
}
