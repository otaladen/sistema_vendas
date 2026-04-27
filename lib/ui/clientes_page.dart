import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../data/cliente_repository.dart';
import '../model/cliente.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key, required this.clienteRepository});

  final ClienteRepository clienteRepository;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _nomeRazaoController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();
  final _documentoController = TextEditingController();
  final _inscricaoController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _cepController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _limiteController = TextEditingController();
  final _observacoesController = TextEditingController();

  int? _clienteEmEdicaoId;
  String _tipoPessoa = 'fisica';
  bool _ativo = true;
  String _status = '';
  late final _cpfCnpjFormatter = _CpfCnpjInputFormatter();
  late final _telefoneFormatter = _TelefoneInputFormatter();
  late final _cepFormatter = _CepInputFormatter();
  late final _emailFormatter = _EmailInputFormatter();
  late final _limiteCreditoFormatter = _MoedaInputFormatter();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nomeRazaoController.dispose();
    _nomeFantasiaController.dispose();
    _documentoController.dispose();
    _inscricaoController.dispose();
    _telefoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _cepController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    _referenciaController.dispose();
    _limiteController.dispose();
    _observacoesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _abrirPesquisaCliente() async {
    final clientesBase = widget.clienteRepository.listarTodos();
    final pesquisaController = TextEditingController();
    List<Cliente> resultados = clientesBase;

    final clienteSelecionado = await showDialog<Cliente>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pesquisar cliente'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nome, documento, telefone, cidade...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim().toLowerCase();
                        setDialogState(() {
                          resultados = clientesBase.where((cliente) {
                            final campos = [
                              cliente.nomeRazao,
                              cliente.nomeFantasia,
                              cliente.documento,
                              cliente.telefone,
                              cliente.whatsapp,
                              cliente.email,
                              cliente.cidade,
                            ].map((e) => e.toLowerCase());
                            return campos.any((campo) => campo.contains(termo));
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum cliente encontrado.'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final cliente = resultados[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(cliente.nomeRazao),
                                  subtitle: Text(
                                    '${cliente.tipoPessoa == 'fisica' ? 'CPF' : 'CNPJ'}: '
                                    '${cliente.documento.isEmpty ? '-' : cliente.documento} | '
                                    'Cidade: ${cliente.cidade.isEmpty ? '-' : cliente.cidade}',
                                  ),
                                  onTap: () => Navigator.pop(context, cliente),
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
          },
        );
      },
    );

    pesquisaController.dispose();

    if (clienteSelecionado != null) {
      _editarCliente(clienteSelecionado);
    }
  }

  void _limparFormulario() {
    setState(() {
      _nomeRazaoController.clear();
      _nomeFantasiaController.clear();
      _documentoController.clear();
      _inscricaoController.clear();
      _telefoneController.clear();
      _whatsappController.clear();
      _emailController.clear();
      _cepController.clear();
      _enderecoController.clear();
      _numeroController.clear();
      _bairroController.clear();
      _cidadeController.clear();
      _ufController.clear();
      _referenciaController.clear();
      _limiteController.clear();
      _observacoesController.clear();
      _tipoPessoa = 'fisica';
      _ativo = true;
      _clienteEmEdicaoId = null;
    });
  }

  void _salvarCliente() {
    final nomeRazao = _nomeRazaoController.text.trim();
    if (nomeRazao.isEmpty) {
      setState(() {
        _status = 'Nome/Razao social e obrigatorio.';
      });
      return;
    }
    final limiteCredito = double.tryParse(
          _limiteController.text.trim().replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0;
    final existente = _clienteEmEdicaoId == null
        ? null
        : widget.clienteRepository.obterPorId(_clienteEmEdicaoId!);

    final cliente = Cliente(
      id: existente?.id ?? 0,
      tipoPessoa: _tipoPessoa,
      nomeRazao: nomeRazao,
      nomeFantasia: _nomeFantasiaController.text.trim(),
      documento: _documentoController.text.trim(),
      inscricaoEstadual: _tipoPessoa == 'juridica' ? _inscricaoController.text.trim() : '',
      telefone: _telefoneController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      cep: _cepController.text.trim(),
      endereco: _enderecoController.text.trim(),
      numero: _numeroController.text.trim(),
      bairro: _bairroController.text.trim(),
      cidade: _cidadeController.text.trim(),
      uf: _ufController.text.trim().toUpperCase(),
      referencia: _referenciaController.text.trim(),
      limiteCredito: limiteCredito,
      observacoes: _observacoesController.text.trim(),
      ativo: _ativo,
      criadoEm: existente?.criadoEm,
    );
    widget.clienteRepository.salvar(cliente);
    _limparFormulario();
    setState(() {
      _status = 'Cliente salvo com sucesso.';
    });
  }

  void _editarCliente(Cliente c) {
    setState(() {
      _clienteEmEdicaoId = c.id;
      _tipoPessoa = c.tipoPessoa;
      _nomeRazaoController.text = c.nomeRazao;
      _nomeFantasiaController.text = c.nomeFantasia;
      _documentoController.text = c.documento;
      _inscricaoController.text = c.inscricaoEstadual;
      _telefoneController.text = c.telefone;
      _whatsappController.text = c.whatsapp;
      _emailController.text = c.email;
      _cepController.text = c.cep;
      _enderecoController.text = c.endereco;
      _numeroController.text = c.numero;
      _bairroController.text = c.bairro;
      _cidadeController.text = c.cidade;
      _ufController.text = c.uf;
      _referenciaController.text = c.referencia;
      _limiteController.text = c.limiteCredito.toStringAsFixed(2).replaceAll('.', ',');
      _observacoesController.text = c.observacoes;
      _ativo = c.ativo;
      _status = 'Editando cliente: ${c.nomeRazao}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emEdicao = _clienteEmEdicaoId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de Clientes')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: RawScrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 10,
          radius: const Radius.circular(8),
          crossAxisMargin: 2,
          mainAxisMargin: 4,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(right: 10),
            children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 30,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cadastro de Clientes',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          emEdicao
                              ? 'Modo edicao ativo: revise os dados e salve.'
                              : 'Preencha os dados para registrar um novo cliente.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _abrirPesquisaCliente,
                icon: const Icon(Icons.search),
                label: const Text('Pesquisar cliente'),
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              context: context,
              title: 'Dados principais',
              icon: Icons.person_outline,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _tipoPessoa,
                  decoration: const InputDecoration(labelText: 'Tipo de pessoa'),
                  items: const [
                    DropdownMenuItem(value: 'fisica', child: Text('Fisica')),
                    DropdownMenuItem(value: 'juridica', child: Text('Juridica')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _tipoPessoa = v;
                        _documentoController.clear();
                        if (_tipoPessoa == 'fisica') {
                          _inscricaoController.clear();
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nomeRazaoController,
                  decoration: const InputDecoration(labelText: 'Nome / Razao social'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nomeFantasiaController,
                  decoration: const InputDecoration(labelText: 'Nome fantasia (opcional)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _documentoController,
                        decoration: InputDecoration(
                          labelText: _tipoPessoa == 'fisica' ? 'CPF' : 'CNPJ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [_cpfCnpjFormatter],
                      ),
                    ),
                    if (_tipoPessoa == 'juridica') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inscricaoController,
                          decoration: const InputDecoration(labelText: 'Inscricao Estadual'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSectionCard(
              context: context,
              title: 'Contato',
              icon: Icons.phone_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _telefoneController,
                        decoration: const InputDecoration(labelText: 'Telefone'),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_telefoneFormatter],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _whatsappController,
                        decoration: const InputDecoration(labelText: 'WhatsApp'),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_telefoneFormatter],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [_emailFormatter],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSectionCard(
              context: context,
              title: 'Endereco',
              icon: Icons.location_on_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cepController,
                        decoration: const InputDecoration(labelText: 'CEP'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [_cepFormatter],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _enderecoController,
                        decoration: const InputDecoration(labelText: 'Endereco'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _numeroController,
                        decoration: const InputDecoration(labelText: 'Numero'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bairroController,
                        decoration: const InputDecoration(labelText: 'Bairro'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _cidadeController,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _ufController,
                        decoration: const InputDecoration(labelText: 'UF'),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                          LengthLimitingTextInputFormatter(2),
                          UpperCaseTextFormatter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSectionCard(
              context: context,
              title: 'Comercial',
              icon: Icons.payments_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _referenciaController,
                        decoration: const InputDecoration(labelText: 'Referencia'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _limiteController,
                        decoration: const InputDecoration(labelText: 'Limite de credito'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [_limiteCreditoFormatter],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _observacoesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Observacoes'),
                ),
                SwitchListTile(
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cliente ativo'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _salvarCliente,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(emEdicao ? 'Salvar edicao' : 'Salvar cliente'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _limparFormulario,
                    icon: Icon(emEdicao ? Icons.close : Icons.cleaning_services_outlined),
                    label: Text(emEdicao ? 'Cancelar edicao' : 'Limpar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_status.isNotEmpty) _buildStatusBanner(context, _status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, String message) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>();
    final sucesso = message.toLowerCase().contains('sucesso');
    final bg = sucesso ? semantic?.successBg ?? const Color(0xFFEAF8EF) : semantic?.errorBg ?? const Color(0xFFFDECEC);
    final border = sucesso
        ? semantic?.successBorder ?? const Color(0xFF8FD1A8)
        : semantic?.errorBorder ?? const Color(0xFFF1A3A3);
    final fg = sucesso
        ? semantic?.successFg ?? const Color(0xFF166534)
        : semantic?.errorFg ?? const Color(0xFF9B1C1C);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(sucesso ? Icons.check_circle_outline : Icons.error_outline, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 14 ? digits.substring(0, 14) : digits;
    final masked = truncated.length <= 11 ? _maskCpf(truncated) : _maskCnpj(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  String _maskCpf(String value) {
    if (value.length <= 3) return value;
    if (value.length <= 6) return '${value.substring(0, 3)}.${value.substring(3)}';
    if (value.length <= 9) {
      return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6)}';
    }
    return '${value.substring(0, 3)}.${value.substring(3, 6)}.${value.substring(6, 9)}-${value.substring(9)}';
  }

  String _maskCnpj(String value) {
    if (value.length <= 2) return value;
    if (value.length <= 5) return '${value.substring(0, 2)}.${value.substring(2)}';
    if (value.length <= 8) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5)}';
    }
    if (value.length <= 12) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5, 8)}/${value.substring(8)}';
    }
    return '${value.substring(0, 2)}.${value.substring(2, 5)}.${value.substring(5, 8)}/${value.substring(8, 12)}-${value.substring(12)}';
  }
}

class _TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 11 ? digits.substring(0, 11) : digits;
    final masked = _maskTelefone(truncated);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }

  String _maskTelefone(String value) {
    if (value.isEmpty) return '';
    if (value.length <= 2) return '($value';
    if (value.length <= 6) return '(${value.substring(0, 2)}) ${value.substring(2)}';
    if (value.length <= 10) {
      return '(${value.substring(0, 2)}) ${value.substring(2, 6)}-${value.substring(6)}';
    }
    return '(${value.substring(0, 2)}) ${value.substring(2, 7)}-${value.substring(7)}';
  }
}

class _CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > 8 ? digits.substring(0, 8) : digits;
    final masked = truncated.length <= 5
        ? truncated
        : '${truncated.substring(0, 5)}-${truncated.substring(5)}';
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

class _EmailInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = newValue.text.replaceAll(' ', '').toLowerCase();
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
  }
}

class _MoedaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final valor = double.parse(digits) / 100;
    final partes = valor.toStringAsFixed(2).split('.');
    final inteiro = partes[0];
    final decimal = partes[1];
    final buffer = StringBuffer();
    for (var i = 0; i < inteiro.length; i++) {
      final pos = inteiro.length - i;
      buffer.write(inteiro[i]);
      if (pos > 1 && pos % 3 == 1) {
        buffer.write('.');
      }
    }
    final formatado = '${buffer.toString()},$decimal';
    return TextEditingValue(
      text: formatado,
      selection: TextSelection.collapsed(offset: formatado.length),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
