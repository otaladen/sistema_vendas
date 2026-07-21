import 'package:flutter/material.dart';

import '../../domain/fiscal/ncm_materiais_catalogo.dart';

/// Resultado do seletor de NCM.
sealed class NcmSelecaoResultado {
  const NcmSelecaoResultado();
}

/// Usuario escolheu um item da tabela.
class NcmSelecaoDaLista extends NcmSelecaoResultado {
  const NcmSelecaoDaLista(this.item);
  final NcmCatalogoItem item;
}

/// Usuario optou por digitar NCM fora da lista (como no sistema antigo).
class NcmSelecaoManual extends NcmSelecaoResultado {
  const NcmSelecaoManual();
}

/// Dialogo no estilo do sistema antigo: lista filtravel de NCM de materiais,
/// com opcao de nao usar a lista (digitar manualmente no cadastro).
Future<NcmSelecaoResultado?> mostrarSeletorNcmMateriais(
  BuildContext context, {
  String? ncmAtual,
}) {
  return showDialog<NcmSelecaoResultado>(
    context: context,
    builder: (ctx) => _SeletorNcmMateriaisDialog(ncmAtual: ncmAtual),
  );
}

class _SeletorNcmMateriaisDialog extends StatefulWidget {
  const _SeletorNcmMateriaisDialog({this.ncmAtual});

  final String? ncmAtual;

  @override
  State<_SeletorNcmMateriaisDialog> createState() =>
      _SeletorNcmMateriaisDialogState();
}

class _SeletorNcmMateriaisDialogState extends State<_SeletorNcmMateriaisDialog> {
  late final TextEditingController _busca;
  late List<NcmCatalogoItem> _resultados;
  String? _codigoSelecionado;

  @override
  void initState() {
    super.initState();
    _busca = TextEditingController();
    final atual = (widget.ncmAtual ?? '').replaceAll(RegExp(r'\D'), '');
    _codigoSelecionado = atual.length == 8 ? atual : null;
    _resultados = List<NcmCatalogoItem>.from(NcmMateriaisCatalogo.itens);
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _filtrar(String termo) {
    setState(() {
      _resultados = NcmMateriaisCatalogo.buscar(termo, limite: 120);
    });
  }

  @override
  Widget build(BuildContext context) {
    final altura =
        (MediaQuery.sizeOf(context).height * 0.72).clamp(360.0, 640.0);
    return AlertDialog(
      title: const Text('Selecionar NCM'),
      content: SizedBox(
        width: 720,
        height: altura,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tabela pratica de materiais de construcao '
              '(${NcmMateriaisCatalogo.itens.length} itens). '
              'Se preferir outro codigo, use "Nao utilizar da lista".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _busca,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar por codigo ou descricao',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filtrar,
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Nao utilizar da lista de sugestao'),
              subtitle: const Text(
                'Fecha e permite digitar qualquer NCM no campo',
              ),
              onTap: () =>
                  Navigator.pop(context, const NcmSelecaoManual()),
            ),
            const Divider(height: 1),
            Expanded(
              child: _resultados.isEmpty
                  ? const Center(
                      child: Text('Nenhum NCM encontrado nesta tabela.'),
                    )
                  : ListView.builder(
                      itemCount: _resultados.length,
                      itemBuilder: (context, index) {
                        final item = _resultados[index];
                        final selecionado =
                            item.codigo == _codigoSelecionado;
                        return ListTile(
                          dense: true,
                          selected: selecionado,
                          title: Text(
                            item.codigoFormatado,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            item.descricao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(
                            context,
                            NcmSelecaoDaLista(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
