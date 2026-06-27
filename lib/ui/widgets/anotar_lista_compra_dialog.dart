import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/lista_compra_repository.dart';
import '../../domain/lista_compra_item_constantes.dart';
import '../../model/produto.dart';

/// Dialogo reutilizavel para anotar item na lista de compras.
Future<bool> mostrarAnotarListaCompraDialog(
  BuildContext context, {
  required ListaCompraRepository repository,
  Produto? produto,
  String descricaoLivre = '',
  int quantidadeInicial = 1,
  String unidadeInicial = 'UN',
  String origem = ListaCompraItemOrigem.manual,
  String criadoPor = '',
  bool urgente = false,
  String observacaoInicial = '',
}) async {
  final itemLivre = produto == null;
  final nomeController = TextEditingController(
    text: itemLivre ? descricaoLivre.trim() : '',
  );
  final qtdController = TextEditingController(
    text: quantidadeInicial > 0 ? '$quantidadeInicial' : '1',
  );
  final unidadeController = TextEditingController(
    text: itemLivre
        ? unidadeInicial.trim().toUpperCase()
        : produto.unidade,
  );
  final obsController = TextEditingController(text: observacaoInicial);
  final fornecedorController = TextEditingController(
    text: produto?.fornecedor ?? '',
  );
  var prioridade = urgente
      ? ListaCompraItemPrioridade.urgente
      : ListaCompraItemPrioridade.normal;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Anotar para comprar'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (itemLivre)
                      TextField(
                        controller: nomeController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Nome do produto *',
                          hintText: 'Ex.: Telha colonial vermelha 6 ondas',
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          produto.nome.trim(),
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: qtdController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Quantidade *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: unidadeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Unidade',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fornecedorController,
                      decoration: const InputDecoration(
                        labelText: 'Fornecedor (opcional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: obsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observacao',
                        hintText: 'Ex.: cliente esperando, marca especifica...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Urgente'),
                      value: prioridade == ListaCompraItemPrioridade.urgente,
                      onChanged: (v) {
                        setLocal(() {
                          prioridade = v
                              ? ListaCompraItemPrioridade.urgente
                              : ListaCompraItemPrioridade.normal;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Anotar'),
              ),
            ],
          );
        },
      );
    },
  );

  final nomeDigitado =
      itemLivre ? nomeController.text.trim() : produto.nome.trim();
  final qtd = int.tryParse(qtdController.text) ?? 0;
  final fornecedor = fornecedorController.text;
  final obs = obsController.text;
  final unidade = unidadeController.text.trim().isNotEmpty
      ? unidadeController.text.trim().toUpperCase()
      : 'UN';

  nomeController.dispose();
  qtdController.dispose();
  unidadeController.dispose();
  obsController.dispose();
  fornecedorController.dispose();

  if (ok != true || !context.mounted) return false;

  if (itemLivre && nomeDigitado.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Informe o nome do produto.')),
    );
    return false;
  }

  if (qtd <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Informe uma quantidade valida.')),
    );
    return false;
  }

  try {
    repository.anotar(
      produto: produto,
      descricaoLivre: itemLivre ? nomeDigitado : '',
      quantidadeSugerida: qtd,
      unidade: unidade,
      fornecedorTexto: fornecedor,
      prioridade: prioridade,
      observacao: obs,
      origem: origem,
      criadoPor: criadoPor,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$nomeDigitado" anotado na lista de compras.'),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel anotar: $e')),
      );
    }
    return false;
  }
}
