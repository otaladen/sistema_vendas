import 'package:flutter/material.dart';

import '../../../model/cliente.dart';
import '../../../model/venda.dart';
import '../../../services/orcamento_pdf_service.dart';
import '../../../services/orcamento_whatsapp_launcher.dart';
import '../../widgets/mascaras_cadastro_input.dart';
import 'selecionar_cliente_dialog.dart';

const EdgeInsets _acaoBotaoPadding = EdgeInsets.symmetric(vertical: 12);
const Size _acaoBotaoMinSize = Size(double.infinity, 48);

/// Abre o dialogo para enviar resumo do orcamento via WhatsApp (wa.me).
Future<void> mostrarEnviarWhatsappDialog(
  BuildContext context, {
  required Venda venda,
  Cliente? cliente,
  required double valorTotal,
  required String nomeLoja,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => EnviarWhatsappDialog(
      venda: venda,
      cliente: cliente,
      valorTotal: valorTotal,
      nomeLoja: nomeLoja,
    ),
  );
}

/// Dialogo de envio de orcamento/comprovante via WhatsApp ([url_launcher]).
class EnviarWhatsappDialog extends StatefulWidget {
  const EnviarWhatsappDialog({
    super.key,
    required this.venda,
    this.cliente,
    required this.valorTotal,
    required this.nomeLoja,
  });

  /// Venda/orcamento salvo no PDV ([Venda] com status orcamento).
  final Venda venda;
  final Cliente? cliente;
  final double valorTotal;
  final String nomeLoja;

  @override
  State<EnviarWhatsappDialog> createState() => _EnviarWhatsappDialogState();
}

class _EnviarWhatsappDialogState extends State<EnviarWhatsappDialog> {
  final _formKey = GlobalKey<FormState>();
  final _telefoneFocusNode = FocusNode();
  late final TextEditingController _telefoneController;
  late final TextEditingController _mensagemController;
  bool _enviando = false;

  int get _numeroOrcamento {
    final n = widget.venda.numeroOrcamento;
    return n > 0 ? n : widget.venda.id;
  }

  bool get _clienteMensagemGenerica =>
      _clienteSemIdentificacaoParaWhatsapp(widget.cliente);

  String get _nomeClienteExibicao {
    final c = widget.cliente;
    if (c == null || _clienteMensagemGenerica) return '';
    return nomeExibicaoClienteListaPdv(c);
  }

  String get _nomeLojaExibicao {
    final n = widget.nomeLoja.trim();
    return n.isEmpty ? 'nossa loja' : n;
  }

  static bool _nomeClienteGenerico(String nome) {
    final n = nome.trim().toLowerCase();
    if (n.isEmpty) return true;
    const rotulos = {'cliente', 'consumidor final', 'consumidor'};
    return rotulos.contains(n);
  }

  /// Sem cliente, Consumidor Final, rotulo "Cliente" ou nome vazio.
  static bool _clienteSemIdentificacaoParaWhatsapp(Cliente? cliente) {
    if (cliente == null) return true;
    if (_nomeClienteGenerico(cliente.nomeRazao)) return true;
    if (_nomeClienteGenerico(cliente.nomeFantasia)) return true;
    if (_nomeClienteGenerico(nomeExibicaoClienteListaPdv(cliente))) {
      return true;
    }
    return false;
  }

  /// Apenas digitos do cadastro, sem prefixo 55 forcado na tela.
  static String _telefoneInicialCliente(Cliente? cliente) {
    if (cliente == null || _clienteSemIdentificacaoParaWhatsapp(cliente)) {
      return '';
    }
    final w = cliente.whatsapp.trim();
    final t = cliente.telefone.trim();
    final bruto = w.isNotEmpty ? w : t;
    if (bruto.isEmpty) return '';
    return somenteDigitos(bruto);
  }

  static String _mensagemPadrao({
    required bool clienteGenerico,
    required String nomeCliente,
    required int numeroOrcamento,
    required String valorFormatado,
    required String nomeLoja,
  }) {
    final saudacao = clienteGenerico ? 'Olá!' : 'Olá *$nomeCliente*!';
    return '$saudacao Esse é o resumo do seu orçamento nº '
        '*$numeroOrcamento* no valor de *$valorFormatado* na *$nomeLoja*.\n\n'
        'Ficamos à disposição para qualquer dúvida ou para confirmar o pedido!';
  }

  @override
  void initState() {
    super.initState();
    _telefoneController = TextEditingController(
      text: _telefoneInicialCliente(widget.cliente),
    );
    _mensagemController = TextEditingController(
      text: _mensagemPadrao(
        clienteGenerico: _clienteMensagemGenerica,
        nomeCliente: _nomeClienteExibicao,
        numeroOrcamento: _numeroOrcamento,
        valorFormatado: OrcamentoPdfService.formatarMoeda(widget.valorTotal),
        nomeLoja: _nomeLojaExibicao,
      ),
    );
  }

  @override
  void dispose() {
    _telefoneFocusNode.dispose();
    _telefoneController.dispose();
    _mensagemController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      final telefone = _telefoneController.text;
      final mensagem = _mensagemController.text;
      final uri = OrcamentoWhatsappLauncher.montarUriWaMe(
        telefone: telefone,
        mensagem: mensagem,
      );
      if (uri == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Informe um WhatsApp válido (DDD + número, com código do país).',
            ),
          ),
        );
        return;
      }

      final abriu = await OrcamentoWhatsappLauncher.abrirConversa(
        telefone: telefone,
        mensagem: mensagem,
      );
      if (!mounted) return;
      if (!abriu) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir o WhatsApp. Verifique se o aplicativo '
              'está instalado ou tente novamente.',
            ),
          ),
        );
        return;
      }
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível abrir o WhatsApp. Tente novamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const whatsappGreen = Color(0xFF25D366);

    return AlertDialog(
      title: const Text('Enviar orçamento via WhatsApp'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _telefoneController,
                focusNode: _telefoneFocusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp / Telefone',
                  hintText: 'Ex: 71999998888 ou 5571999998888',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final tel = OrcamentoWhatsappLauncher.higienizarTelefone(
                    value ?? '',
                  );
                  if (tel.length < 12) {
                    return 'Informe DDD e número (10 ou 11 dígitos)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mensagemController,
                decoration: const InputDecoration(
                  labelText: 'Mensagem',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.multiline,
                minLines: 4,
                maxLines: 6,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Digite a mensagem';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: whatsappGreen,
              foregroundColor: Colors.white,
              padding: _acaoBotaoPadding,
              minimumSize: _acaoBotaoMinSize,
            ),
            onPressed: _enviando ? null : _enviar,
            icon: _enviando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.chat),
            label: const Text('Enviar'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: _acaoBotaoPadding,
              minimumSize: _acaoBotaoMinSize,
            ),
            onPressed: _enviando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ),
      ],
    );
  }
}
