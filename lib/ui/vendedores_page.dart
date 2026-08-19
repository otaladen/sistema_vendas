import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api/vendedor_api_repository.dart';
import '../domain/usuario_senha_codec.dart';
import '../model/usuario_sistema.dart';
import '../model/vendedor.dart';
import 'layout/app_layout.dart';
import 'theme/app_semantic_helper.dart';
import 'widgets/consulta_lista_vazia.dart';
import 'widgets/lan_api_feedback.dart';
import 'widgets/vendedor/vendedor_cadastro_header.dart';
import 'widgets/vendedor/vendedor_cadastro_rodape.dart';

/// Cadastro de **vendedores** (balcao, comissoes, contato com cliente).
/// Separado de **Funcionarios** (RH) e **Usuarios** (login do sistema).
class VendedoresPage extends StatefulWidget {
  const VendedoresPage({
    super.key,
    required this.vendedorRepository,
    required this.usuarioRepository,
    this.vendaRepository,
  });

  final dynamic vendedorRepository;
  final dynamic usuarioRepository;
  /// Usado para bloquear exclusao quando ha vendas (servidor e terminal).
  final dynamic vendaRepository;

  @override
  State<VendedoresPage> createState() => _VendedoresPageState();
}

class _VendedoresPageState extends State<VendedoresPage> {
  final _formKey = GlobalKey<FormState>();

  static const double _wCodigo = 132;
  static const double _wFone = 184;
  static const double _wPct = 168;
  static const double _wMeta = 188;
  static const double _limiarDuasColunas = 700.0;
  static const _padCampo = EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const _iconCampo = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
    maxWidth: 32,
    maxHeight: 32,
  );
  static const Color _pageBg = Color(0xFFF8FAFC);

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
  final _scrollFormulario = ScrollController();

  int? _vendedorEmEdicaoId;
  bool _ativo = true;
  bool _ocultarSenhaPdv = true;
  bool _carregandoLista = false;
  bool _temPinAtual = false;
  String _status = '';
  UsuarioSistema? _usuarioVinculadoAoVendedor;

  late final _telefoneFormatter = _DigitosMaxFormatter(11);
  late final _emailFormatter = _EmailLowercaseFormatter();

  bool get _terminal => widget.vendedorRepository is VendedorApiRepository;

  @override
  void initState() {
    super.initState();
    _codigoController.text =
        '${widget.vendedorRepository.proximoCodigoInternoSequencial()}';
    final repo = widget.vendedorRepository;
    if (repo is VendedorApiRepository) {
      repo.addListener(_onVendedorApiChanged);
      unawaited(_hidratarTerminal());
    }
  }

  void _onVendedorApiChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _hidratarTerminal() async {
    final repo = widget.vendedorRepository;
    if (repo is! VendedorApiRepository) return;
    setState(() => _carregandoLista = true);
    try {
      await repo.hidratar();
      if (!mounted) return;
      setState(() {
        _carregandoLista = false;
        if (_vendedorEmEdicaoId == null) {
          _codigoController.text = '${repo.proximoCodigoInternoSequencial()}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoLista = false);
      LanApiFeedback.snackAviso(context, e, prefixo: 'Vendedores');
    }
  }

  @override
  void dispose() {
    final repo = widget.vendedorRepository;
    if (repo is VendedorApiRepository) {
      repo.removeListener(_onVendedorApiChanged);
    }
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
    _scrollFormulario.dispose();
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
      _temPinAtual = false;
      _vendedorEmEdicaoId = null;
      _usuarioVinculadoAoVendedor = null;
      _status = '';
    });
  }

  Future<void> _carregarUsuarioVinculado(int vendedorId) async {
    final u = await widget.usuarioRepository.obterAtivoPorVendedorId(vendedorId);
    if (!mounted) return;
    setState(() => _usuarioVinculadoAoVendedor = u);
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
      _temPinAtual = widget.vendedorRepository.temSenhaPdvConfigurada(v) == true;
      _usuarioVinculadoAoVendedor = null;
      _status = 'Editando: ${v.nomeCompleto}';
    });
    unawaited(_carregarUsuarioVinculado(v.id));
  }

  int _contarVendasDoVendedor(int vendedorId) {
    final repo = widget.vendaRepository;
    if (repo == null || vendedorId <= 0) return 0;
    try {
      return (repo.contarVendasFinalizadasPorVendedor(vendedorId) as num)
          .toInt();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _confirmarRemover(Vendedor v) async {
    final vendasPdv = _contarVendasDoVendedor(v.id);
    if (vendasPdv > 0) {
      setState(
        () => _status =
            'Nao e possivel remover: vendedor tem $vendasPdv venda(s) finalizada(s). '
            'Desative o cadastro em vez de apagar.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_status)),
        );
      }
      return;
    }

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
    final repo = widget.vendedorRepository;
    try {
      if (repo is VendedorApiRepository) {
        final removido = await repo.removerRemoto(v.id);
        if (!removido) {
          if (!mounted) return;
          LanApiFeedback.snackAviso(
            context,
            'Nao foi possivel remover o vendedor.',
          );
          return;
        }
      } else {
        repo.remover(v.id);
      }
      if (!mounted) return;
      if (_vendedorEmEdicaoId == v.id) {
        _limparFormulario();
      }
      setState(() {
        _status = 'Remocao concluida com sucesso.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vendedor removido com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel remover');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  void _salvar() {
    unawaited(_salvarAsync());
  }

  Future<void> _salvarAsync() async {
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

    try {
      final idSalvo = widget.vendedorRepository is VendedorApiRepository
          ? await widget.vendedorRepository.salvarRemoto(v)
          : widget.vendedorRepository.salvar(v);
      if (!mounted) return;
      final salvo = widget.vendedorRepository.obterPorId(idSalvo) as Vendedor?;
      setState(() {
        _status = 'Vendedor salvo com sucesso.';
        _vendedorEmEdicaoId = idSalvo;
        _senhaPdvController.clear();
        _temPinAtual = salvo != null &&
            widget.vendedorRepository.temSenhaPdvConfigurada(salvo) == true;
      });
      unawaited(_carregarUsuarioVinculado(idSalvo));
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel salvar');
      setState(() => _status = LanApiFeedback.mensagem(e));
    }
  }

  List<Vendedor> _vendedoresOrdenados() {
    final lista = widget.vendedorRepository.listarTodos() as List<Vendedor>;
    final copia = List<Vendedor>.from(lista);
    copia.sort((a, b) {
      final ca = a.codigoInterno.compareTo(b.codigoInterno);
      if (ca != 0) return ca;
      return a.id.compareTo(b.id);
    });
    return copia;
  }

  int _indiceVendedorAtual(List<Vendedor> lista) {
    if (_vendedorEmEdicaoId == null) return -1;
    return lista.indexWhere((v) => v.id == _vendedorEmEdicaoId);
  }

  void _abrirVendedorPorIndice(int indice) {
    final lista = _vendedoresOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha vendedores cadastrados para navegar.',
      );
      return;
    }
    _editar(lista[indice.clamp(0, lista.length - 1)]);
  }

  void _irParaPrimeiro() => _abrirVendedorPorIndice(0);

  void _irParaUltimo() {
    final lista = _vendedoresOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha vendedores cadastrados para navegar.',
      );
      return;
    }
    _abrirVendedorPorIndice(lista.length - 1);
  }

  void _irParaAnterior() {
    final lista = _vendedoresOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha vendedores cadastrados para navegar.',
      );
      return;
    }
    final atual = _indiceVendedorAtual(lista);
    _abrirVendedorPorIndice(atual <= 0 ? 0 : atual - 1);
  }

  void _irParaProximo() {
    final lista = _vendedoresOrdenados();
    if (lista.isEmpty) {
      setState(
        () => _status = 'Nao ha vendedores cadastrados para navegar.',
      );
      return;
    }
    final atual = _indiceVendedorAtual(lista);
    if (atual < 0 || atual >= lista.length - 1) {
      _abrirVendedorPorIndice(lista.length - 1);
      return;
    }
    _abrirVendedorPorIndice(atual + 1);
  }

  Future<void> _excluirAtual() async {
    final id = _vendedorEmEdicaoId;
    if (id == null) return;
    final v = widget.vendedorRepository.obterPorId(id) as Vendedor?;
    if (v == null) return;
    await _confirmarRemover(v);
  }

  Future<void> _abrirPesquisa() async {
    final ctrl = TextEditingController(text: _pesquisaListaController.text);
    final escolhido = await showDialog<Vendedor>(
      context: context,
      builder: (ctx) {
        var resultados = widget.vendedorRepository.pesquisar(ctrl.text)
            as List<Vendedor>;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Pesquisar vendedor'),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nome, codigo, apelido, e-mail...',
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) {
                        setLocal(() {
                          resultados = widget.vendedorRepository.pesquisar(v)
                              as List<Vendedor>;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum vendedor.'))
                          : ListView.builder(
                              itemCount: resultados.length,
                              itemBuilder: (_, i) {
                                final v = resultados[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    v.codigoInterno.isEmpty
                                        ? v.nomeCompleto
                                        : '${v.codigoInterno} · ${v.nomeCompleto}',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (v.apelido.isNotEmpty) v.apelido,
                                      if (v.email.isNotEmpty) v.email,
                                      if (!v.ativo) 'inativo',
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                  ),
                                  onTap: () => Navigator.pop(ctx, v),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (escolhido != null && mounted) _editar(escolhido);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final emEdicao = _vendedorEmEdicaoId != null;
    final listados = widget.vendedorRepository.pesquisar(
          _pesquisaListaController.text,
        )
        as List<Vendedor>;
    final comissaoHdr = _comissaoController.text.trim();
    final denseTheme = theme.copyWith(
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: _pageBg,
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: _padCampo,
        prefixIconConstraints: _iconCampo,
        suffixIconConstraints: _iconCampo,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
        hintStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      textTheme: theme.textTheme.copyWith(
        bodyLarge: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
        titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 12.5),
        labelLarge: theme.textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f5): _SalvarIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _LimparIntent(),
      },
      child: Actions(
        actions: {
          _SalvarIntent: CallbackAction(onInvoke: (_) {
            _salvar();
            return null;
          }),
          _LimparIntent: CallbackAction(onInvoke: (_) {
            _limparFormulario();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Cadastro de vendedores'),
              actions: [
                if (_terminal)
                  IconButton(
                    tooltip: 'Atualizar do servidor',
                    onPressed: _carregandoLista
                        ? null
                        : () => unawaited(_hidratarTerminal()),
                    icon: _carregandoLista
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_outlined),
                  ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBarraFerramentas(),
                        const SizedBox(height: 4),
                        VendedorCadastroHeader(
                          emEdicao: emEdicao,
                          vendedorId: _vendedorEmEdicaoId,
                          nome: _nomeCompletoController.text,
                          codigoInterno: _codigoController.text,
                          ativo: _ativo,
                          apelido: _apelidoController.text,
                          comissaoTexto:
                              comissaoHdr.isEmpty ? null : comissaoHdr,
                        ),
                        if (_status.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          _buildStatusBanner(context, _status),
                        ],
                        const SizedBox(height: 2),
                        Expanded(
                          child: Theme(
                            data: denseTheme,
                            child: ColoredBox(
                              color: _pageBg,
                              child: RawScrollbar(
                                controller: _scrollFormulario,
                                thumbVisibility: true,
                                trackVisibility: true,
                                thickness: 10,
                                radius: const Radius.circular(8),
                                child: SingleChildScrollView(
                                  controller: _scrollFormulario,
                                  primary: false,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 8, 8, 16),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildSectionCard(
                                          title: 'Identificacao',
                                          icon: Icons.badge_outlined,
                                          children: [
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: SizedBox(
                                                width: _wCodigo,
                                                child: TextField(
                                                  controller:
                                                      _codigoController,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'Codigo interno',
                                                    hintText: 'Auto (1, 2, 3…)',
                                                    isDense: true,
                                                  ),
                                                  keyboardType:
                                                      TextInputType.number,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            TextFormField(
                                              controller:
                                                  _nomeCompletoController,
                                              decoration:
                                                  const InputDecoration(
                                                labelText: 'Nome completo',
                                                isDense: true,
                                              ),
                                              validator: (v) {
                                                if (v == null ||
                                                    v.trim().isEmpty) {
                                                  return 'Informe o nome completo.';
                                                }
                                                return null;
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: _apelidoController,
                                              decoration:
                                                  const InputDecoration(
                                                labelText:
                                                    'Apelido na loja (opcional)',
                                                hintText: 'Telas e cupom',
                                                isDense: true,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title: 'Status',
                                          icon: Icons.toggle_on_outlined,
                                          children: [
                                            _buildMiniCardStatus(theme),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final cardContato =
                                                _buildSectionCard(
                                              title: 'Contato com cliente',
                                              icon: Icons.phone_outlined,
                                              children: [
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Wrap(
                                                    spacing: 10,
                                                    runSpacing: 8,
                                                    children: [
                                                      SizedBox(
                                                        width: _wFone,
                                                        child: TextField(
                                                          controller:
                                                              _telefoneController,
                                                          decoration:
                                                              const InputDecoration(
                                                            labelText:
                                                                'Telefone / loja',
                                                            isDense: true,
                                                          ),
                                                          keyboardType:
                                                              TextInputType
                                                                  .phone,
                                                          inputFormatters: [
                                                            _telefoneFormatter,
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: _wFone,
                                                        child: TextField(
                                                          controller:
                                                              _whatsappController,
                                                          decoration:
                                                              const InputDecoration(
                                                            labelText:
                                                                'WhatsApp',
                                                            isDense: true,
                                                          ),
                                                          keyboardType:
                                                              TextInputType
                                                                  .phone,
                                                          inputFormatters: [
                                                            _telefoneFormatter,
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                TextField(
                                                  controller:
                                                      _emailController,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText:
                                                        'E-mail (orcamentos)',
                                                    isDense: true,
                                                  ),
                                                  keyboardType: TextInputType
                                                      .emailAddress,
                                                  inputFormatters: [
                                                    _emailFormatter,
                                                  ],
                                                ),
                                              ],
                                            );
                                            final cardComercial =
                                                _buildSectionCard(
                                              title: 'Comercial',
                                              icon: Icons.trending_up,
                                              children: [
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Wrap(
                                                    spacing: 10,
                                                    runSpacing: 8,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment.end,
                                                    children: [
                                                      SizedBox(
                                                        width: _wPct,
                                                        child: TextFormField(
                                                          controller:
                                                              _comissaoController,
                                                          keyboardType:
                                                              const TextInputType
                                                                  .numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                          decoration:
                                                              const InputDecoration(
                                                            labelText:
                                                                'Comissao (%)',
                                                            hintText: '0 a 100',
                                                            isDense: true,
                                                          ),
                                                          validator: (v) {
                                                            final n =
                                                                _parseBrDecimal(
                                                              v ?? '',
                                                            );
                                                            if (n < 0 ||
                                                                n > 100) {
                                                              return 'Entre 0 e 100%.';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: _wMeta,
                                                        child: TextFormField(
                                                          controller:
                                                              _metaMensalController,
                                                          keyboardType:
                                                              const TextInputType
                                                                  .numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                          decoration:
                                                              const InputDecoration(
                                                            labelText:
                                                                'Meta mensal (R\$)',
                                                            hintText:
                                                                'Opcional',
                                                            isDense: true,
                                                          ),
                                                          validator: (v) {
                                                            if (v == null ||
                                                                v.trim()
                                                                    .isEmpty) {
                                                              return null;
                                                            }
                                                            if (_parseBrDecimal(
                                                                    v) <
                                                                0) {
                                                              return 'Nao pode ser negativa.';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Meta em reais (referencia); detalhes nos relatorios.',
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                ),
                                              ],
                                            );

                                            final usarDuasColunas =
                                                constraints.hasBoundedWidth &&
                                                    constraints.maxWidth >=
                                                        _limiarDuasColunas;
                                            if (!usarDuasColunas) {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  cardContato,
                                                  const SizedBox(height: 10),
                                                  cardComercial,
                                                ],
                                              );
                                            }
                                            return Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(child: cardContato),
                                                const SizedBox(width: 10),
                                                Expanded(child: cardComercial),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title: 'Observacoes comerciais',
                                          icon: Icons.notes_outlined,
                                          children: [
                                            TextField(
                                              controller:
                                                  _observacoesController,
                                              maxLines: 3,
                                              decoration:
                                                  const InputDecoration(
                                                labelText:
                                                    'Atuacao, setor da loja, tipos de cliente...',
                                                alignLabelWithHint: true,
                                                isDense: true,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title: 'PIN do PDV (opcional)',
                                          icon: Icons.lock_outline,
                                          children: [
                                            if (_usuarioVinculadoAoVendedor !=
                                                null) ...[
                                              Material(
                                                color: scheme
                                                    .secondaryContainer
                                                    .withValues(alpha: 0.45),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(10),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Icon(
                                                        Icons.person_outline,
                                                        size: 18,
                                                        color: scheme.primary,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'Ja existe usuario vinculado: '
                                                          '${_usuarioVinculadoAoVendedor!.nome} '
                                                          '(${_usuarioVinculadoAoVendedor!.login}). '
                                                          'No PDV, prefira a senha do sistema; o PIN abaixo '
                                                          'fica so para balcao rapido (legado).',
                                                          style: theme.textTheme
                                                              .bodySmall,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                            TextFormField(
                                              controller: _senhaPdvController,
                                              obscureText: _ocultarSenhaPdv,
                                              decoration: InputDecoration(
                                                labelText: emEdicao
                                                    ? 'Novo PIN do balcao (opcional)'
                                                    : 'PIN do balcao (opcional)',
                                                helperText:
                                                    _usuarioVinculadoAoVendedor !=
                                                            null
                                                        ? 'Deixe em branco se for usar so o login do sistema no PDV.'
                                                        : emEdicao
                                                            ? (_temPinAtual
                                                                ? 'PIN ja cadastrado. Deixe em branco para manter. '
                                                                    'Use so se a pessoa nao tiver login no sistema.'
                                                                : 'Deixe em branco para manter sem PIN. '
                                                                    'Use so se a pessoa nao tiver login no sistema.')
                                                            : 'So necessario se a pessoa nao usar login do sistema no PDV.',
                                                isDense: true,
                                                suffixIcon: IconButton(
                                                  tooltip: _ocultarSenhaPdv
                                                      ? 'Mostrar senha'
                                                      : 'Ocultar senha',
                                                  onPressed: () => setState(
                                                    () => _ocultarSenhaPdv =
                                                        !_ocultarSenhaPdv,
                                                  ),
                                                  icon: Icon(
                                                    _ocultarSenhaPdv
                                                        ? Icons
                                                            .visibility_outlined
                                                        : Icons
                                                            .visibility_off_outlined,
                                                  ),
                                                ),
                                              ),
                                              validator: (v) {
                                                final s = v?.trim() ?? '';
                                                if (s.isNotEmpty &&
                                                    s.length < 4) {
                                                  return 'Minimo 4 caracteres.';
                                                }
                                                return null;
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSectionCard(
                                          title:
                                              'Vendedores cadastrados (${listados.length})',
                                          icon: Icons.list_alt_outlined,
                                          children: [
                                            TextField(
                                              controller:
                                                  _pesquisaListaController,
                                              onChanged: (_) => setState(() {}),
                                              decoration:
                                                  const InputDecoration(
                                                labelText: 'Pesquisar na lista',
                                                isDense: true,
                                                prefixIcon: Icon(
                                                  Icons.search,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (_carregandoLista)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 16,
                                                ),
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              )
                                            else if (listados.isEmpty)
                                              const ConsultaListaVazia(
                                                mensagem:
                                                    'Nenhum vendedor listado.',
                                                dica:
                                                    'Preencha o formulario acima e salve.',
                                                icone: Icons
                                                    .point_of_sale_outlined,
                                              )
                                            else
                                              ...listados.map((v) {
                                                return ListTile(
                                                  dense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: Text(
                                                    v.nomeCompleto,
                                                    style: const TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    '${v.codigoInterno} · comissao ${v.percentualComissao.toStringAsFixed(1).replaceAll('.', ',')}%'
                                                    '${v.apelido.isNotEmpty ? " · ${v.apelido}" : ""}'
                                                    '${v.ativo ? "" : " · inativo"}'
                                                    '${widget.vendedorRepository.temSenhaPdvConfigurada(v) == true ? " · PIN" : ""}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  isThreeLine: true,
                                                  onTap: () => _editar(v),
                                                  trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        tooltip: 'Editar',
                                                        onPressed: () =>
                                                            _editar(v),
                                                        icon: const Icon(
                                                          Icons.edit_outlined,
                                                          size: 20,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Remover',
                                                        onPressed: () =>
                                                            unawaited(
                                                          _confirmarRemover(v),
                                                        ),
                                                        icon: Icon(
                                                          Icons
                                                              .delete_outline,
                                                          size: 20,
                                                          color: scheme.error,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                VendedorCadastroRodape(
                  emEdicao: emEdicao,
                  onSalvar: _salvar,
                  onNovo: _limparFormulario,
                  podeExcluir: emEdicao,
                  onExcluir: () => unawaited(_excluirAtual()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarraFerramentas() {
    final pesquisaBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: () => unawaited(_abrirPesquisa()),
      icon: const Icon(Icons.search, size: 20),
      label: const Text('Pesquisar vendedor'),
    );
    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Primeiro',
          onPressed: _irParaPrimeiro,
          icon: const Icon(Icons.first_page_outlined),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: _irParaAnterior,
          icon: const Icon(Icons.navigate_before_outlined),
        ),
        IconButton(
          tooltip: 'Proximo',
          onPressed: _irParaProximo,
          icon: const Icon(Icons.navigate_next_outlined),
        ),
        IconButton(
          tooltip: 'Ultimo',
          onPressed: _irParaUltimo,
          icon: const Icon(Icons.last_page_outlined),
        ),
      ],
    );
    if (context.isCompactLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pesquisaBtn,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [nav],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: pesquisaBtn),
        nav,
      ],
    );
  }

  Widget _buildMiniCardStatus(ThemeData theme) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              title: const Text(
                'Ativo para vendas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                'Desligue em ferias ou desligamento do balcao.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.1,
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
    final semantic = context.semanticColors;
    final m = message.toLowerCase();
    final sucesso = m.contains('sucesso') ||
        m.contains('salvo') ||
        m.contains('concluida');
    final erro = m.contains('falha') ||
        m.contains('erro') ||
        m.contains('invalido') ||
        m.contains('inválido') ||
        m.contains('ja existe') ||
        m.contains('já existe') ||
        m.contains('nao e possivel') ||
        m.contains('não e possivel') ||
        m.contains('nao ha') ||
        m.contains('não ha');
    final ok = sucesso && !erro;
    final bg = ok ? semantic.successBg : semantic.errorBg;
    final border = ok ? semantic.successBorder : semantic.errorBorder;
    final fg = ok ? semantic.successFg : semantic.errorFg;
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
            ok ? Icons.check_circle_outline : Icons.info_outline,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _SalvarIntent extends Intent {
  const _SalvarIntent();
}

class _LimparIntent extends Intent {
  const _LimparIntent();
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
