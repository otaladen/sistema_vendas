import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api/funcionario_api_repository.dart';
import '../domain/perfil_usuario_preset.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import 'theme/app_semantic_helper.dart';
import 'usuarios/usuario_form_state.dart';
import 'widgets/lan_api_feedback.dart';
import 'usuarios/usuarios_permissoes_panel.dart';
import 'usuarios/usuarios_resumo_panel.dart';
import 'widgets/usuario/usuario_cadastro_header.dart';
import 'widgets/usuario/usuario_cadastro_rodape.dart';

enum _FiltroAtivoLista { todos, ativos, inativos }

class _UsuarioSalvarIntent extends Intent {
  const _UsuarioSalvarIntent();
}

class _UsuarioNovoIntent extends Intent {
  const _UsuarioNovoIntent();
}

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({
    super.key,
    required this.usuarioRepository,
    required this.motoristaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.usuarioLogado,
  });

  final dynamic usuarioRepository;
  final dynamic motoristaRepository;
  final dynamic vendedorRepository;
  final dynamic funcionarioRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage>
    with SingleTickerProviderStateMixin {
  static const _pageBg = Color(0xFFF8FAFC);
  static const _padCampo = EdgeInsets.symmetric(horizontal: 10, vertical: 10);
  static const _iconCampo = BoxConstraints(
    minWidth: 28,
    minHeight: 28,
    maxWidth: 32,
    maxHeight: 32,
  );

  final _nomeController = TextEditingController();
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();
  final _descontoMaxController = TextEditingController();
  final _buscaController = TextEditingController();
  final _scrollFormulario = ScrollController();
  final _scrollLista = ScrollController();

  late TabController _tabController;
  UsuarioFormState _form = UsuarioFormState.novo();
  List<UsuarioSistema> _usuarios = [];
  String _busca = '';
  _FiltroAtivoLista _filtroAtivo = _FiltroAtivoLista.todos;
  String? _filtroPerfilId;
  bool _senhaVisivel = false;
  String _status = '';

  bool get _podeGerenciarUsuarios =>
      UsuarioPermissaoHelper.tem(
        widget.usuarioLogado,
        PermissaoUsuario.gerenciarUsuarios,
      );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nomeController.dispose();
    _loginController.dispose();
    _senhaController.dispose();
    _descontoMaxController.dispose();
    _buscaController.dispose();
    _scrollFormulario.dispose();
    _scrollLista.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final dynamic repo = widget.usuarioRepository;
      Object? raw;
      try {
        raw = await repo.listarTodos(forcar: true);
      } catch (_) {
        raw = await repo.listarTodos();
      }
      final lista = <UsuarioSistema>[];
      if (raw is Iterable) {
        for (final item in raw) {
          if (item is UsuarioSistema) {
            lista.add(item);
          }
        }
      }
      lista.sort(
        (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
      );
      if (!mounted) return;
      setState(() => _usuarios = lista);
    } catch (e) {
      if (!mounted) return;
      setState(() => _usuarios = []);
      _mostrarSnack('Falha ao carregar usuarios: $e', erro: true);
    }
  }

  List<UsuarioSistema> get _usuariosFiltrados {
    var lista = List<UsuarioSistema>.from(_usuarios);
    switch (_filtroAtivo) {
      case _FiltroAtivoLista.ativos:
        lista = lista.where((u) => u.ativo).toList();
      case _FiltroAtivoLista.inativos:
        lista = lista.where((u) => !u.ativo).toList();
      case _FiltroAtivoLista.todos:
        break;
    }
    if (_filtroPerfilId != null && _filtroPerfilId!.isNotEmpty) {
      lista = lista.where((u) => u.perfil == _filtroPerfilId).toList();
    }
    final t = _busca.trim().toLowerCase();
    if (t.isNotEmpty) {
      lista = lista.where((u) {
        return u.nome.toLowerCase().contains(t) ||
            u.login.toLowerCase().contains(t) ||
            u.perfil.toLowerCase().contains(t);
      }).toList();
    }
    return lista;
  }

  void _mostrarSnack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Theme.of(context).colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _motoristaVinculadoValido() {
    final nome = _form.motoristaEntregaNome.trim();
    if (nome.isEmpty) return '';
    final ativos = widget.motoristaRepository
        .listarAtivos()
        .map((m) => m.nome)
        .toList();
    return ativos.contains(nome) ? nome : '';
  }

  int _vendedorVinculadoValido() {
    final id = _form.vendedorId;
    if (id <= 0) return 0;
    final v = widget.vendedorRepository.obterPorId(id);
    if (v == null || !v.ativo) return 0;
    return id;
  }

  bool get _mostrarVinculoVendedorPdv =>
      !_form.admin &&
      (_form.lerPermissao(PermissaoUsuario.acessarPdv) ||
          _form.perfilSelecionado == PerfilUsuarioPreset.vendedor);

  void _sincronizarControllers() {
    _nomeController.text = _form.nome;
    _loginController.text = _form.login;
    _senhaController.text = '';
    _descontoMaxController.text = _form.descontoMaximoTexto;
  }

  void _novoUsuario() {
    setState(() {
      _form.limpar();
      _sincronizarControllers();
      _status = '';
      _tabController.index = 1;
    });
  }

  void _editar(UsuarioSistema u) {
    setState(() {
      _form.carregar(u);
      _aplicarVendedorDoFuncionarioVinculado(u.id);
      _sincronizarControllers();
      _status = 'Editando: ${u.nome}';
      _tabController.index = 1;
    });
  }

  /// Se o RH ja vinculou este login a um funcionario com vendedor, preenche o dropdown.
  void _aplicarVendedorDoFuncionarioVinculado(String usuarioId) {
    final f = widget.funcionarioRepository.obterPorUsuarioSistemaId(usuarioId);
    if (f == null || f.vendedorId <= 0) return;
    final v = widget.vendedorRepository.obterPorId(f.vendedorId);
    if (v == null || !v.ativo) return;
    _form.definirVendedorId(f.vendedorId);
  }

  Future<void> _alinharFuncionarioComVendedor(
    String usuarioId,
    int vendedorId,
  ) async {
    final f = widget.funcionarioRepository.obterPorUsuarioSistemaId(usuarioId);
    if (f == null) return;
    if (vendedorId <= 0) return;
    if (f.vendedorId == vendedorId) return;
    f.vendedorId = vendedorId;
    try {
      if (widget.funcionarioRepository is FuncionarioApiRepository) {
        await widget.funcionarioRepository.salvarRemoto(f);
      } else {
        widget.funcionarioRepository.salvar(f);
      }
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Nao foi possivel vincular vendedor ao funcionario',
      );
    }
  }

  Future<void> _salvar() async {
    final nome = _nomeController.text.trim();
    final login = _loginController.text.trim();
    final senha = _senhaController.text;
    if (nome.isEmpty || login.isEmpty) {
      _mostrarSnack('Preencha nome e login.', erro: true);
      return;
    }
    final erroLogin = PoliticaSenhaUsuario.validarLogin(login);
    if (erroLogin != null) {
      _mostrarSnack(erroLogin, erro: true);
      return;
    }
    final criacao = _form.editandoId == null;
    final erroSenha = PoliticaSenhaUsuario.validarParaSalvar(
      criacao: criacao,
      senhaDigitada: senha,
    );
    if (erroSenha != null) {
      _mostrarSnack(erroSenha, erro: true);
      return;
    }

    _form.definirNome(nome);
    _form.definirLogin(login);
    _form.definirDescontoMaximoTexto(_descontoMaxController.text);

    final existe = await widget.usuarioRepository.loginJaExiste(
      login,
      ignorarId: _form.editandoId,
    );
    if (existe) {
      _mostrarSnack('Ja existe um usuario com este login.', erro: true);
      return;
    }

    final id = _form.editandoId ??
        DateTime.now().millisecondsSinceEpoch.toString();
    UsuarioSistema? anterior;
    if (_form.editandoId != null) {
      for (final u in _usuarios) {
        if (u.id == _form.editandoId) {
          anterior = u;
          break;
        }
      }
    }
    var usuario = _form.montarParaSalvar(id);
    if (!criacao && senha.isEmpty && anterior != null) {
      usuario = usuario.copyWith(senha: anterior.senha);
    }

    try {
      await widget.usuarioRepository.salvar(
        usuario,
        alteradoPor: widget.usuarioLogado,
        anterior: anterior,
        senhaPlainNova: senha.isEmpty ? null : senha,
      );
      await _alinharFuncionarioComVendedor(usuario.id, usuario.vendedorId);
    } catch (e) {
      _mostrarSnack(e.toString(), erro: true);
      return;
    }

    await _carregar();
    setState(() {
      _form.limpar();
      _sincronizarControllers();
      _status = 'Usuario salvo com sucesso.';
      _tabController.index = 0;
    });
  }

  Future<void> _alternarAtivo(UsuarioSistema u) async {
    final novo = !u.ativo;
    try {
      await widget.usuarioRepository.salvar(
        u.copyWith(ativo: novo),
        alteradoPor: widget.usuarioLogado,
        anterior: u,
      );
    } catch (e) {
      _mostrarSnack(e.toString(), erro: true);
      return;
    }
    await _carregar();
    _mostrarSnack(novo ? '${u.nome} ativado.' : '${u.nome} desativado.');
  }

  String _gerarSenhaTemporaria() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _redefinirSenha(UsuarioSistema u) async {
    if (!_podeGerenciarUsuarios) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redefinir senha'),
        content: Text(
          'Gerar uma nova senha temporaria para "${u.nome}" (${u.login})? '
          'O usuario devera usar essa senha no proximo login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gerar senha'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final nova = _gerarSenhaTemporaria();
    try {
      await widget.usuarioRepository.salvar(
        u,
        alteradoPor: widget.usuarioLogado,
        anterior: u,
        senhaPlainNova: nova,
        resumoExtra: 'Senha redefinida',
      );
    } catch (e) {
      _mostrarSnack(e.toString(), erro: true);
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Senha temporaria'),
        content: SelectableText(
          'Nova senha para ${u.login}:\n\n$nova\n\n'
          'Anote e entregue ao usuario. Ela nao sera exibida novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: nova));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Senha copiada.')),
              );
            },
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    _mostrarSnack('Senha de ${u.nome} redefinida.');
  }

  Future<void> _migrarUsuariosLegado() async {
    final n = await widget.usuarioRepository.migrarTodosLegado(
      alteradoPor: widget.usuarioLogado,
    );
    await _carregar();
    _mostrarSnack('Migracao concluida: $n usuario(s) atualizado(s).');
  }

  void _duplicar(UsuarioSistema u) {
    setState(() {
      _form.carregar(
        u.copyWith(
          id: '',
          nome: '${u.nome} (copia)',
          login: '${u.login}_2',
          senha: '',
        ),
      );
      _form.editandoId = null;
      _sincronizarControllers();
      _status = 'Duplicando usuario — ajuste login e senha.';
      _tabController.index = 1;
    });
  }

  Future<void> _confirmarRemover(UsuarioSistema u) async {
    if (u.id == widget.usuarioLogado.id) {
      _mostrarSnack('Voce nao pode remover o proprio usuario.', erro: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover usuario'),
        content: Text('Remover "${u.nome}" (${u.login})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.usuarioRepository.remover(
      id: u.id,
      removidoPor: widget.usuarioLogado,
    );
    await _carregar();
    if (!mounted) return;
    if (_form.editandoId == u.id) {
      setState(() {
        _form.limpar();
        _sincronizarControllers();
      });
    }
    _mostrarSnack('Usuario removido: ${u.nome}');
  }

  ThemeData _cadastroDenseTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return theme.copyWith(
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final denseTheme = _cadastroDenseTheme(theme);
    final editando = _form.editandoId != null;
    final perfilRotulo = _form.admin
        ? PerfilUsuarioPreset.dono.rotulo
        : _form.perfilSelecionado.rotulo;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f5): _UsuarioSalvarIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _UsuarioNovoIntent(),
      },
      child: Actions(
        actions: {
          _UsuarioSalvarIntent: CallbackAction(onInvoke: (_) {
            unawaited(_salvar());
            return null;
          }),
          _UsuarioNovoIntent: CallbackAction(onInvoke: (_) {
            _novoUsuario();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: _pageBg,
            appBar: AppBar(
              title: const Text('Cadastro de Usuarios'),
              actions: [
                if (_podeGerenciarUsuarios)
                  IconButton(
                    tooltip: 'Migrar usuarios antigos (perfil + senha)',
                    icon: const Icon(Icons.upgrade_outlined),
                    onPressed: _migrarUsuariosLegado,
                  ),
              ],
              bottom: MediaQuery.sizeOf(context).width >= 960
                  ? null
                  : TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(
                          text: 'Usuarios',
                          icon: Icon(Icons.people_outline),
                        ),
                        Tab(
                          text: 'Dados e permissoes',
                          icon: Icon(Icons.tune_outlined),
                        ),
                      ],
                    ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final largo = constraints.maxWidth >= 960;
                if (largo) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 400,
                        child: _buildLista(denseTheme),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _buildFormulario(
                          denseTheme,
                          editando,
                          perfilRotulo,
                        ),
                      ),
                    ],
                  );
                }
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLista(denseTheme),
                    _buildFormulario(
                      denseTheme,
                      editando,
                      perfilRotulo,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltrosLista() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<_FiltroAtivoLista>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(value: _FiltroAtivoLista.todos, label: Text('Todos')),
              ButtonSegment(value: _FiltroAtivoLista.ativos, label: Text('Ativos')),
              ButtonSegment(
                value: _FiltroAtivoLista.inativos,
                label: Text('Inativos'),
              ),
            ],
            selected: {_filtroAtivo},
            onSelectionChanged: (s) => setState(() => _filtroAtivo = s.first),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              // ignore: deprecated_member_use
              value: _filtroPerfilId,
              decoration: const InputDecoration(
                labelText: 'Perfil',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos perfis')),
                ...PerfilUsuarioPreset.values
                    .where((p) => p != PerfilUsuarioPreset.customizado)
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.rotulo),
                      ),
                    ),
                const DropdownMenuItem(
                  value: 'customizado',
                  child: Text('Personalizado'),
                ),
              ],
              onChanged: (v) => setState(() => _filtroPerfilId = v),
            ),
          ),
          Text(
            '${_usuariosFiltrados.length} usuario(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildLista(ThemeData denseTheme) {
    final lista = _usuariosFiltrados;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: _pageBg,
      child: Theme(
        data: denseTheme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: OutlinedButton.icon(
                onPressed: _novoUsuario,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Novo usuario'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _buscaController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                  labelText: 'Buscar por nome ou login',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
            _buildFiltrosLista(),
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum usuario encontrado.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    )
                  : RawScrollbar(
                      controller: _scrollLista,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 10,
                      radius: const Radius.circular(8),
                      child: ListView.builder(
                        controller: _scrollLista,
                        primary: false,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: lista.length,
                        itemBuilder: (context, i) {
                        final u = lista[i];
                        final chips = UsuarioPermissaoHelper.resumoChips(u);
                        final selecionado = _form.editandoId == u.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: selecionado
                                ? scheme.primaryContainer
                                    .withValues(alpha: 0.35)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: selecionado
                                    ? scheme.primary.withValues(alpha: 0.5)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              onTap: () => _editar(u),
                              title: Text(
                                '${u.nome} (${u.login})',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${u.ativo ? 'Ativo' : 'Inativo'} · '
                                    '${perfilUsuarioFromId(u.perfil).rotulo}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  if (chips.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: chips
                                          .map(
                                            (c) => Chip(
                                              label: Text(
                                                c,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding: EdgeInsets.zero,
                                              labelPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                              isThreeLine: chips.isNotEmpty,
                              trailing: SizedBox(
                                width: 148,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Transform.scale(
                                      scale: 0.85,
                                      child: Switch(
                                        value: u.ativo,
                                        onChanged: (_) => _alternarAtivo(u),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 20),
                                      onSelected: (v) {
                                        switch (v) {
                                          case 'editar':
                                            _editar(u);
                                          case 'senha':
                                            _redefinirSenha(u);
                                          case 'dup':
                                            _duplicar(u);
                                          case 'del':
                                            unawaited(_confirmarRemover(u));
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'editar',
                                          child: Text('Editar'),
                                        ),
                                        if (_podeGerenciarUsuarios)
                                          const PopupMenuItem(
                                            value: 'senha',
                                            child: Text('Redefinir senha'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'dup',
                                          child: Text('Duplicar'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'del',
                                          child: Text('Remover'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulario(
    ThemeData denseTheme,
    bool editando,
    String perfilRotulo,
  ) {
    final theme = Theme.of(context);
    UsuarioSistema? usuarioEmEdicao;
    if (editando) {
      for (final x in _usuarios) {
        if (x.id == _form.editandoId) {
          usuarioEmEdicao = x;
          break;
        }
      }
    }
    final podeExcluir =
        editando && _form.editandoId != widget.usuarioLogado.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UsuarioCadastroHeader(
          emEdicao: editando,
          nome: _form.nome,
          login: _form.login,
          ativo: _form.ativo,
          perfilRotulo: perfilRotulo,
          admin: _form.admin,
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildStatusBanner(context, _status),
          ),
        ],
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
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionCard(
                        title: 'Dados do usuario',
                        icon: Icons.person_outline,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Usuario e o login do sistema (permissoes e uma senha so). '
                                  'Para vender no PDV com este login, vincule o vendedor em Vinculos. '
                                  'Funcionario (RH) e Vendedor (comissao) sao cadastros separados.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _nomeController,
                            decoration: const InputDecoration(
                              labelText: 'Nome completo',
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _form.definirNome(v)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _loginController,
                            decoration: const InputDecoration(
                              labelText: 'Login',
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _form.definirLogin(v)),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _senhaController,
                            obscureText: !_senhaVisivel,
                            decoration: InputDecoration(
                              labelText: editando ? 'Nova senha' : 'Senha',
                              helperText: editando
                                  ? 'Deixe em branco para manter a senha atual.'
                                  : 'Minimo ${PoliticaSenhaUsuario.tamanhoMinimo} caracteres.',
                              isDense: true,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _senhaVisivel
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                ),
                                onPressed: () => setState(
                                  () => _senhaVisivel = !_senhaVisivel,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descontoMaxController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Teto de desconto no PDV (%)',
                              helperText:
                                  'Vazio = usa o limite das configuracoes da empresa. '
                                  'Gerente/dono com desconto manual ignora o teto.',
                              isDense: true,
                              suffixText: '%',
                            ),
                            onChanged: (v) {
                              _form.definirDescontoMaximoTexto(v);
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 4),
                          SwitchListTile(
                            value: _form.ativo,
                            onChanged: (v) =>
                                setState(() => _form.definirAtivo(v)),
                            title: const Text('Usuario ativo'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildSectionCard(
                        title: 'Perfil',
                        icon: Icons.badge_outlined,
                        children: [
                          Text(
                            'Escolha um perfil pronto e ajuste as permissoes abaixo se precisar.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in PerfilUsuarioPreset.values)
                                if (p != PerfilUsuarioPreset.customizado)
                                  ChoiceChip(
                                    label: Text(p.rotulo),
                                    visualDensity: VisualDensity.compact,
                                    selected: _form.perfilSelecionado == p,
                                    onSelected: _form.admin &&
                                            p != PerfilUsuarioPreset.dono
                                        ? null
                                        : (_) => setState(() {
                                              _form.aplicarPerfil(p);
                                              _descontoMaxController.text =
                                                  _form.descontoMaximoTexto;
                                            }),
                                  ),
                              ChoiceChip(
                                label: const Text('Personalizado'),
                                visualDensity: VisualDensity.compact,
                                selected: _form.perfilSelecionado ==
                                    PerfilUsuarioPreset.customizado,
                                onSelected: _form.admin
                                    ? null
                                    : (_) => setState(
                                          () => _form.aplicarPerfil(
                                            PerfilUsuarioPreset.customizado,
                                          ),
                                        ),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            value: _form.admin,
                            onChanged: (v) =>
                                setState(() => _form.definirAdmin(v)),
                            title: const Text(
                              'Acesso total (Dono / Administrador)',
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          SwitchListTile(
                            value: _form.podeModoMotorista,
                            onChanged: _form.admin
                                ? null
                                : (v) => setState(
                                      () => _form.definirPodeModoMotorista(v),
                                    ),
                            title: const Text(
                              'Modo motorista (entregas no celular)',
                            ),
                            subtitle: const Text(
                              'Permite abrir o painel simplificado de entregas e registrar POD.',
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildSectionCard(
                        title: 'Vinculos',
                        icon: Icons.link_outlined,
                        children: [
                          if (_form.podeModoMotorista && !_form.admin) ...[
                            DropdownButtonFormField<String>(
                              // ignore: deprecated_member_use
                              value: _motoristaVinculadoValido(),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Motorista vinculado',
                                helperText:
                                    'Nome do cadastro de motoristas; filtra as entregas deste usuario.',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text(
                                    '(Nenhum — usa o nome do usuario)',
                                  ),
                                ),
                                for (final m
                                    in widget.motoristaRepository.listarAtivos())
                                  DropdownMenuItem(
                                    value: m.nome,
                                    child: Text(m.nome),
                                  ),
                              ],
                              onChanged: (v) => setState(
                                () => _form.definirMotoristaEntregaNome(v),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_mostrarVinculoVendedorPdv) ...[
                            DropdownButtonFormField<int>(
                              // ignore: deprecated_member_use
                              value: _vendedorVinculadoValido(),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Vendedor vinculado (PDV)',
                                helperText:
                                    'Permite desbloquear o PDV com o login e a senha deste usuario. '
                                    'Se o RH ja vinculou um funcionario, o vendedor e preenchido automaticamente.',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 0,
                                  child: Text('(Nenhum)'),
                                ),
                                for (final v
                                    in widget.vendedorRepository.listarAtivos())
                                  DropdownMenuItem(
                                    value: v.id,
                                    child: Text(
                                      v.apelido.trim().isNotEmpty
                                          ? v.apelido.trim()
                                          : v.nomeCompleto,
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(
                                () => _form.definirVendedorId(v),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          UsuariosResumoPanel(form: _form),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildSectionCard(
                        title: 'Permissoes',
                        icon: Icons.admin_panel_settings_outlined,
                        children: [
                          UsuariosPermissoesPanel(
                            form: _form,
                            onChanged: () => setState(() {}),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        UsuarioCadastroRodape(
          emEdicao: editando,
          onSalvar: () => unawaited(_salvar()),
          onNovo: _novoUsuario,
          podeExcluir: podeExcluir,
          onExcluir: usuarioEmEdicao != null
              ? () => unawaited(_confirmarRemover(usuarioEmEdicao!))
              : null,
          extraActions: [
            if (_podeGerenciarUsuarios && editando && usuarioEmEdicao != null)
              OutlinedButton.icon(
                onPressed: () => unawaited(_redefinirSenha(usuarioEmEdicao!)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.lock_reset_outlined, size: 18),
                label: const Text('Redefinir senha'),
              ),
          ],
        ),
      ],
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
        m.contains('editando') ||
        m.contains('duplicando');
    final erro = m.contains('falha') ||
        m.contains('erro') ||
        m.contains('obrigat') ||
        m.contains('nao encontrado') ||
        m.contains('não encontrado');
    final ok = sucesso && !erro;
    final bg = ok ? semantic.successBg : semantic.errorBg;
    final border = ok ? semantic.successBorder : semantic.errorBorder;
    final fg = ok ? semantic.successFg : semantic.errorFg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}
