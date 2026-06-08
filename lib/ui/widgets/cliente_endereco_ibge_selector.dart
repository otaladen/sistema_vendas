import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/fiscal/municipios_ibge_frequentes.dart';

/// Seletor de IBGE com municipios frequentes + digitacao manual.
class ClienteEnderecoIbgeSelector extends StatefulWidget {
  const ClienteEnderecoIbgeSelector({
    super.key,
    required this.codigoIbgeController,
    this.cidadeController,
  });

  final TextEditingController codigoIbgeController;
  final TextEditingController? cidadeController;

  @override
  State<ClienteEnderecoIbgeSelector> createState() =>
      _ClienteEnderecoIbgeSelectorState();
}

class _ClienteEnderecoIbgeSelectorState extends State<ClienteEnderecoIbgeSelector> {
  String _selecao = '';

  @override
  void initState() {
    super.initState();
    widget.codigoIbgeController.addListener(_sincronizarSelecaoPeloController);
    widget.cidadeController?.addListener(_sugerirPelaCidadeSeVazio);
    _sincronizarSelecaoPeloController();
  }

  @override
  void dispose() {
    widget.codigoIbgeController.removeListener(_sincronizarSelecaoPeloController);
    widget.cidadeController?.removeListener(_sugerirPelaCidadeSeVazio);
    super.dispose();
  }

  void _sincronizarSelecaoPeloController() {
    final nova = MunicipiosIbgeFrequentes.selecaoParaCodigo(
      widget.codigoIbgeController.text,
    );
    if (nova != _selecao) {
      setState(() => _selecao = nova);
    }
  }

  void _sugerirPelaCidadeSeVazio() {
    final atual = widget.codigoIbgeController.text.replaceAll(RegExp(r'\D'), '');
    if (atual.length == 7) return;
    final sugestao = MunicipiosIbgeFrequentes.sugerirPorNomeCidade(
      widget.cidadeController?.text ?? '',
    );
    if (sugestao == null) return;
    widget.codigoIbgeController.text = sugestao.codigo;
    setState(() => _selecao = sugestao.codigo);
  }

  void _aoMudarDropdown(String? valor) {
    if (valor == null) return;
    setState(() => _selecao = valor);
    if (valor.isEmpty) {
      widget.codigoIbgeController.clear();
      return;
    }
    if (valor == MunicipiosIbgeFrequentes.valorManual) {
      return;
    }
    widget.codigoIbgeController.text = valor;
  }

  bool get _exibirCampoManual {
    if (_selecao == MunicipiosIbgeFrequentes.valorManual) return true;
    final digits =
        widget.codigoIbgeController.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == 7 &&
        MunicipiosIbgeFrequentes.porCodigo(digits) == null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey<String>('ibge_sel_$_selecao'),
          isExpanded: true,
          initialValue: _selecao.isEmpty ? null : _selecao,
          decoration: const InputDecoration(
            labelText: 'Municipio (IBGE) — NF-e',
            isDense: true,
            helperText:
                'Opcoes rapidas da regiao. Use "Outro" se a API nao preencher.',
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Selecione o municipio'),
            ),
            ...MunicipiosIbgeFrequentes.opcoes.map(
              (o) => DropdownMenuItem(
                value: o.codigo,
                child: Text(o.rotulo),
              ),
            ),
            const DropdownMenuItem(
              value: MunicipiosIbgeFrequentes.valorManual,
              child: Text('Outro municipio (informar codigo)'),
            ),
          ],
          onChanged: _aoMudarDropdown,
        ),
        if (_exibirCampoManual) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: 180,
            child: TextField(
              controller: widget.codigoIbgeController,
              decoration: const InputDecoration(
                labelText: 'Codigo IBGE manual',
                hintText: '7 digitos',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: (_) => _sincronizarSelecaoPeloController(),
            ),
          ),
        ],
      ],
    );
  }
}
