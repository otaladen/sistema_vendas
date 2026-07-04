import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/vendedor_repository.dart';
import '../domain/usuario_senha_codec.dart';
import 'theme/app_semantic_helper.dart';
import '../model/vendedor.dart';

/// Cadastro de **vendedores** (balcao, comissoes, contato com cliente).
/// Nao substitui tela futura de **Funcionarios** (RH / contratacao).
class VendedoresPage extends StatefulWidget {
  const VendedoresPage({super.key, required this.vendedorRepository});

  final VendedorRepository vendedorRepository;

  @override
  State<VendedoresPage> createState() => _VendedoresPageState();
}

class _VendedoresPageState extends State<VendedoresPage> {
  final _formKey = GlobalKey<FormState>();
  static ButtonStyle get _estiloBotaoContornoCompacto => OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static ButtonStyle get _estiloBotaoPrimarioCompacto => FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static const double _wCodigo = 132;
  static const double _wFone = 184;
  static const double _wPct = 168;
  static const double _wMeta = 188;
  static const double _limiarDuasColunas = 700.0;

  final _codigoController = TextEditingController();
  final _nomeCompletoController = TextEditingController();
  final _apelidoController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _comissaoController = TextEditingController();
  final _metaMensalController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _senhaPdvController = TextEditingController();
  final _pesquisaListaController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  int? _vendedorEmEdicaoId;
  bool _ativo = true;
  bool _ocultarSenhaPdv = true;
  String _status = '';

  late final _telefoneFormatter = _DigitosMaxFormatter(11);
  late final _emailFormatter = _EmailLowercaseFormatter();

  @override
  void initState() {
    super.initState();
    _codigoController.text =
        '${widget.vendedorRepository.proximoCodigoInternoSequencial()}';
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _nomeCompletoController.dispose();
    _apelidoController.dispose();
    _telefoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _comissaoController.dispose();
    _metaMensalController.dispose();
    _observacoesController.dispose();
    _senhaPdvController.dispose();
    _pesquisaListaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  double _parseBrDecimal(String texto, {double fallback = 0}) {
    final t = texto.trim();
    if (t.isEmpty) {
      return fallback;
    }
    final v = double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
    return v ?? fallback;
  }

  void _limparFormulario() {
    final proximo = widget.vendedorRepository.proximoCodigoInternoSequencial();
    setState(() {
      _codigoController.text = '$proximo';
      _nomeCompletoController.clear();
      _apelidoController.clear();
      _telefoneController.clear();
      _whatsappController.clear();
      _emailController.clear();
      _comissaoController.clear();
      _metaMensalController.clear();
      _observacoesController.clear();
      _senhaPdvController.clear();
      _ativo = true;
      _vendedorEmEdicaoId = null;
      _status = '';
    });
  }

  void _editar(Vendedor v) {
    setState(() {
      _vendedorEmEdicaoId = v.id;
      _codigoController.text = v.codigoInterno;
      _nomeCompletoController.text = v.nomeCompleto;
      _apelidoController.text = v.apelido;
      _telefoneController.text = v.telefone;
      _whatsappController.text = v.whatsapp;
      _emailController.text = v.email;
      _comissaoController.text = v.percentualComissao == 0
          ? ''
          : v.percentualComissao.toStringAsFixed(2).replaceAll('.', ',');
      _metaMensalController.text = v.metaMensalValor == 0
          ? ''
          : v.metaMensalValor.toStringAsFixed(2).replaceAll('.', ',');
      _observacoesController.text = v.observacoesComerciais;
      _senhaPdvController.clear();
      _ativo = v.ativo;
      _status = 'Editando: ${v.nomeCompleto}';
    });
  }

  Future<void> _confirmarRemover(Vendedor v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover vendedor'),
        content: Text('Remover "${v.nomeCompleto}" da lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.vendedorRepository.remover(v.id);
    if (_vendedorEmEdicaoId == v.id) {
      _limparFormulario();
    }
    setState(() {
      _status = 'Remocao concluida com sucesso.';
    });
  }

  void _salvar() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    var codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      codigo = '${widget.vendedorRepository.proximoCodigoInternoSequencial()}';
      _codigoController.text = codigo;
    }
    final nome = _nomeCompletoController.text.trim();
    final idAtual = _vendedorEmEdicaoId ?? 0;
    if (widget.vendedorRepository.existeCodigoParaOutro(
      codigoNormalizado: codigo,
      ignorarId: idAtual,
    )) {
      setState(() => _status = 'Ja existe outro vendedor com este codigo.');
      return;
    }

    final comissao = _parseBrDecimal(_comissaoController.text);
    final meta = _parseBrDecimal(_metaMensalController.text);

    final existente = _vendedorEmEdicaoId == null
        ? null
        : widget.vendedorRepository.obterPorId(_vendedorEmEdicaoId!);

    final novaSenhaPdv = _senhaPdvController.text.trim();

    var senhaPdv = existente?.senhaPdv ?? '';
    if (novaSenhaPdv.isNotEmpty) {
      senhaPdv = UsuarioSenhaCodec.gerarHash(novaSenhaPdv);
    }

    final v = Vendedor(
      id: existente?.id ?? 0,
      codigoInterno: codigo,
      nomeCompleto: nome,
      apelido: _apelidoController.text.trim(),
      telefone: _telefoneController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
      email: _emailController.text.trim(),
      percentualComissao: comissao,
      metaMensalValor: meta,
      observacoesComerciais: _observacoesController.text.trim(),
      ativo: _ativo,
      senhaPdv: senhaPdv,
      criadoEm: existente?.criadoEm,
    );

    final idSalvo = widget.vendedorRepository.salvar(v);
    setState(() {
      _status = 'Vendedor salvo com sucesso.';
      _vendedorEmEdicaoId = idSalvo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emEdicao = _vendedorEmEdicaoId != null;
    final listados = widget.vendedorRepository.pesquisar(
      _pesquisaListaController.text,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de vendedores')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.point_of_sale_outlined,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Equipe de vendas',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Use este cadastro para quem atende no balcao, recebe comissao e aparece em '
                            'orcamentos e relatarios de venda. Um cadastro futuro de Funcionarios '
                            'tera dados de RH (contrato, cargo administrativo etc.).',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_status.isNotEmpty) ...[
                _buildStatusBanner(context, _status),
                const SizedBox(height: 8),
              ],
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              _buildSectionCard(
                context: context,
                title: 'Identificacao',
                icon: Icons.badge_outlined,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: _wCodigo,
                      child: TextField(
                        controller: _codigoController,
                        decoration: const InputDecoration(
                          labelText: 'Codigo interno',
                          hintText: 'Auto (1, 2, 3…)',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nomeCompletoController,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                      isDense: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Informe o nome completo.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _apelidoController,
                    decoration: const InputDecoration(
                      labelText: 'Apelido na loja (opcional)',
                      hintText: 'Telas e cupom',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo para vendas'),
                    subtitle: const Text(
                      'Desligue em ferias ou desligamento do balcao.',
                    ),
                    value: _ativo,
                    onChanged: (v) => setState(() => _ativo = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardContato = _buildSectionCard(
                    context: context,
                    title: 'Contato com cliente',
                    icon: Icons.phone_outlined,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: _wFone,
                              child: TextField(
                                controller: _telefoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Telefone / loja',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [_telefoneFormatter],
                              ),
                            ),
                            SizedBox(
                              width: _wFone,
                              child: TextField(
                                controller: _whatsappController,
                                decoration: const InputDecoration(
                                  labelText: 'WhatsApp',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [_telefoneFormatter],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'E-mail (orcamentos)',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [_emailFormatter],
                      ),
                    ],
                  );
                  final cardComercial = _buildSectionCard(
                    context: context,
                    title: 'Comercial',
                    icon: Icons.trending_up,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            SizedBox(
                              width: _wPct,
                              child: TextFormField(
                                controller: _comissaoController,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Comissao (%)',
                                  hintText: '0 a 100',
                                  isDense: true,
                                ),
                                validator: (v) {
                                  final n = _parseBrDecimal(v ?? '');
                                  if (n < 0 || n > 100) {
                                    return 'Entre 0 e 100%.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            SizedBox(
                              width: _wMeta,
                              child: TextFormField(
                                controller: _metaMensalController,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Meta mensal (R\$)',
                                  hintText: 'Opcional',
                                  isDense: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (_parseBrDecimal(v) < 0) {
                                    return 'Nao pode ser negativa.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Meta em reais (referencia); detalhes nos relatorios.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  );

                  final usarDuasColunas = constraints.hasBoundedWidth &&
                      constraints.maxWidth >= _limiarDuasColunas;
                  if (!usarDuasColunas) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cardContato,
                        const SizedBox(height: 8),
                        cardComercial,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cardContato),
                      const SizedBox(width: 10),
                      Expanded(child: cardComercial),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildSectionCard(
                context: context,
                title: 'Observacoes comerciais',
                icon: Icons.notes_outlined,
                children: [
                  TextField(
                    controller: _observacoesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Atuacao, setor da loja, tipos de cliente...',
                      alignLabelWithHint: true,
                      isDense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSectionCard(
                context: context,
                title: 'Senha do PDV',
                icon: Icons.lock_outline,
                children: [
                  TextFormField(
                    controller: _senhaPdvController,
                    obscureText: _ocultarSenhaPdv,
                    decoration: InputDecoration(
                      labelText: emEdicao
                          ? 'Nova senha do PDV (opcional)'
                          : 'Senha do PDV (opcional)',
                      helperText: emEdicao
                          ? 'Deixe em branco para manter a senha atual. '
                              'Necessaria quando o bloqueio vendedor esta ativo.'
                          : 'Usada no bloqueio vendedor do terminal PDV.',
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: _ocultarSenhaPdv
                            ? 'Mostrar senha'
                            : 'Ocultar senha',
                        onPressed: () => setState(
                          () => _ocultarSenhaPdv = !_ocultarSenhaPdv,
                        ),
                        icon: Icon(
                          _ocultarSenhaPdv
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isNotEmpty && s.length < 4) {
                        return 'Minimo 4 caracteres.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: _estiloBotaoPrimarioCompacto,
                      onPressed: _salvar,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: Text(emEdicao ? 'Atualizar' : 'Salvar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: _estiloBotaoContornoCompacto,
                    onPressed: _limparFormulario,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Novo'),
                  ),
                ],
              ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Vendedores cadastrados',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pesquisaListaController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Pesquisar na lista',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              if (listados.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text('Nenhum vendedor listado.')),
                )
              else
                ...listados.map(
                  (v) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(v.nomeCompleto),
                      subtitle: Text(
                        '${v.codigoInterno} · comissao ${v.percentualComissao.toStringAsFixed(1).replaceAll('.', ',')}%'
                        '${v.apelido.isNotEmpty ? " · ${v.apelido}" : ""}'
                        '${v.ativo ? "" : " · inativo"}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () => _editar(v),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Remover',
                            onPressed: () => _confirmarRemover(v),
                            icon: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _editar(v),
                    ),
                  ),
                ),
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, String message) {
    final semantic = context.semanticColors;
    final sucesso = message.toLowerCase().contains('sucesso');
    final bg = sucesso ? semantic.successBg : semantic.errorBg;
    final border = sucesso ? semantic.successBorder : semantic.errorBorder;
    final fg = sucesso ? semantic.successFg : semantic.errorFg;
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
          Icon(
            sucesso ? Icons.check_circle_outline : Icons.info_outline,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _DigitosMaxFormatter extends TextInputFormatter {
  _DigitosMaxFormatter(this.maxDigits);

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > maxDigits
        ? digits.substring(0, maxDigits)
        : digits;
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

class _EmailLowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.trim(),
      selection: newValue.selection,
    );
  }
}
