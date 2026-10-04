import 'package:flutter/material.dart';

import '../../domain/via_cep_endereco_similaridade.dart';
import '../../services/viacep_endereco_service.dart';

/// Lista enderecos parecidos com o que o vendedor digitou (sempre exibe o modal).
Future<ViaCepEnderecoResultado?> mostrarSelecaoCepPorEnderecoDialog(
  BuildContext context, {
  required List<ViaCepEnderecoResultado> opcoes,
  required String enderecoReferencia,
  String bairroReferencia = '',
}) async {
  if (opcoes.isEmpty) return null;

  return showDialog<ViaCepEnderecoResultado>(
    context: context,
    builder: (ctx) => _SelecaoCepPorEnderecoDialog(
      opcoes: opcoes,
      enderecoReferencia: enderecoReferencia,
      bairroReferencia: bairroReferencia,
    ),
  );
}

class _SelecaoCepPorEnderecoDialog extends StatefulWidget {
  const _SelecaoCepPorEnderecoDialog({
    required this.opcoes,
    required this.enderecoReferencia,
    required this.bairroReferencia,
  });

  final List<ViaCepEnderecoResultado> opcoes;
  final String enderecoReferencia;
  final String bairroReferencia;

  @override
  State<_SelecaoCepPorEnderecoDialog> createState() =>
      _SelecaoCepPorEnderecoDialogState();
}

class _SelecaoCepPorEnderecoDialogState
    extends State<_SelecaoCepPorEnderecoDialog> {
  late final TextEditingController _filtroController;

  @override
  void initState() {
    super.initState();
    _filtroController = TextEditingController(
      text: extrairLogradouroParaBuscaCep(widget.enderecoReferencia),
    );
  }

  @override
  void dispose() {
    _filtroController.dispose();
    super.dispose();
  }

  List<ViaCepEnderecoResultado> _opcoesVisiveis() {
    final filtro = _filtroController.text.trim();
    var visiveis = widget.opcoes;
    if (filtro.length >= 2) {
      final fNorm = normalizarTextoEndereco(filtro);
      visiveis = widget.opcoes.where((o) {
        final blob = normalizarTextoEndereco(
          '${o.logradouro} ${o.bairro} ${o.complemento}',
        );
        return blob.contains(fNorm) ||
            fNorm.split(' ').where((t) => t.length >= 3).any(blob.contains);
      }).toList();
      if (visiveis.isEmpty) visiveis = widget.opcoes;
    }
    return visiveis;
  }

  @override
  Widget build(BuildContext context) {
    final refLog = widget.enderecoReferencia.trim();
    final refBairro = widget.bairroReferencia.trim();
    final visiveis = _opcoesVisiveis();

    return AlertDialog(
      title: const Text('Endereços parecidos'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Escolha o CEP que mais se parece com o que você informou.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (refLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Referência: $refLog${refBairro.isNotEmpty ? ' · $refBairro' : ''}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _filtroController,
              decoration: const InputDecoration(
                labelText: 'Refinar busca',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Nome da rua, bairro...',
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visiveis.isEmpty
                  ? const Center(child: Text('Nenhuma opção com esse filtro.'))
                  : ListView.separated(
                      itemCount: visiveis.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final o = visiveis[i];
                        final score = pontuarSimilaridadeEnderecoViaCep(
                          logradouroReferencia: refLog,
                          bairroReferencia: refBairro,
                          resultado: o,
                        );
                        final recomendado = i == 0 && score >= 40;
                        return ListTile(
                          leading: recomendado
                              ? const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: 22,
                                )
                              : null,
                          title: Text(
                            o.logradouro.isNotEmpty ? o.logradouro : '—',
                          ),
                          subtitle: Text(
                            [
                              if (o.bairro.isNotEmpty) o.bairro,
                              if (o.complemento.isNotEmpty) o.complemento,
                              '${o.cidade}/${o.uf}',
                              if (o.cep.length == 8)
                                '${o.cep.substring(0, 5)}-${o.cep.substring(5)}',
                            ].where((e) => e.isNotEmpty).join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, o),
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
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
