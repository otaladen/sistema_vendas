import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/usuario_repository.dart';
import '../domain/perfil_usuario_preset.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import 'usuarios/usuario_form_state.dart';
import 'usuarios/usuarios_permissoes_panel.dart';
import 'usuarios/usuarios_resumo_panel.dart';

enum _FiltroAtivoLista { todos, ativos, inativos }

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({
    super.key,
    required this.usuarioRepository,
    required this.usuarioLogado,
  });

  final UsuarioRepository usuarioRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage>
    with SingleTickerProviderStateMixin {
  final _nomeController = TextEditingController();
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();
  final _descontoMaxController = TextEditingController();
  final _buscaController = TextEditingController();

  late TabController _tabController;
  UsuarioFormState _form = UsuarioFormState.novo();
  List<UsuarioSistema> _usuarios = [];
  String _busca = '';
  _FiltroAtivoLista _filtroAtivo = _FiltroAtivoLista.todos;
  String? _filtroPerfilId;
  bool _senhaVisivel = false;
  int? _abaAtual;

  bool get _podeGerenciarUsuarios =>
      UsuarioPermissaoHelper.tem(
        widget.usuarioLogado,
        PermissaoUsuario.gerenciarUsuarios,
      );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _abaAtual = _tabController.index);
      }
    });
    _abaAtual = 0;
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
    super.dispose();
  }

  Future<void> _carregar() async {
    final lista = await widget.usuarioRepository.listarTodos();
    if (!mounted) return;
    setState(() {
      _usuarios = lista..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    });
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
      _tabController.index = 1;
    });
  }

  void _editar(UsuarioSistema u) {
    setState(() {
      _form.carregar(u);
      _sincronizarControllers();
      _tabController.index = 1;
    });
    _mostrarSnack('Editando: ${u.nome}');
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
    } catch (e) {
      _mostrarSnack(e.toString(), erro: true);
      return;
    }

    await _carregar();
    setState(() {
      _form.limpar();
      _sincronizarControllers();
      _tabController.index = 0;
    });
    _mostrarSnack('Usuario salvo com sucesso.');
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
      _tabController.index = 1;
    });
    _mostrarSnack('Duplicando usuario — ajuste login e senha.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Tab(text: 'Usuarios', icon: Icon(Icons.people_outline)),
                  Tab(text: 'Dados e permissoes', icon: Icon(Icons.tune_outlined)),
                ],
              ),
      ),
      floatingActionButton: (_abaAtual == 0 || MediaQuery.sizeOf(context).width >= 960)
          ? FloatingActionButton.extended(
              onPressed: _novoUsuario,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Novo usuario'),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final largo = constraints.maxWidth >= 960;
          if (largo) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 400, child: _buildLista()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildFormulario()),
              ],
            );
          }
          return TabBarView(
            controller: _tabController,
            children: [
              _buildLista(),
              _buildFormulario(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFiltrosLista() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<_FiltroAtivoLista>(
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
              value: _filtroPerfilId,
              decoration: const InputDecoration(
                labelText: 'Perfil',
                border: OutlineInputBorder(),
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

  Widget _buildLista() {
    final lista = _usuariosFiltrados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _buscaController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar por nome ou login',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        _buildFiltrosLista(),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('Nenhum usuario encontrado.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lista.length,
                  itemBuilder: (context, i) {
                    final u = lista[i];
                    final chips = UsuarioPermissaoHelper.resumoChips(u);
                    final selecionado = _form.editandoId == u.id;
                    return Card(
                      color: selecionado
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.35)
                          : null,
                      child: ListTile(
                        onTap: () => _editar(u),
                        title: Text('${u.nome} (${u.login})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${u.ativo ? 'Ativo' : 'Inativo'} · '
                              '${perfilUsuarioFromId(u.perfil).rotulo}',
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: chips
                                  .map(
                                    (c) => Chip(
                                      label: Text(c),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: SizedBox(
                          width: 168,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Switch(
                                value: u.ativo,
                                onChanged: (_) => _alternarAtivo(u),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) {
                                  switch (v) {
                                    case 'editar':
                                      _editar(u);
                                    case 'senha':
                                      _redefinirSenha(u);
                                    case 'dup':
                                      _duplicar(u);
                                    case 'del':
                                      _confirmarRemover(u);
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
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFormulario() {
    final editando = _form.editandoId != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (editando)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Editando usuario',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_podeGerenciarUsuarios)
                  OutlinedButton.icon(
                    onPressed: () {
                      UsuarioSistema? alvo;
                      for (final x in _usuarios) {
                        if (x.id == _form.editandoId) {
                          alvo = x;
                          break;
                        }
                      }
                      if (alvo != null) _redefinirSenha(alvo);
                    },
                    icon: const Icon(Icons.lock_reset_outlined),
                    label: const Text('Redefinir senha'),
                  ),
              ],
            ),
          ),
        Text('Dados do usuario', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _nomeController,
          decoration: const InputDecoration(
            labelText: 'Nome completo',
            border: OutlineInputBorder(),
          ),
          onChanged: _form.definirNome,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _loginController,
          decoration: const InputDecoration(
            labelText: 'Login',
            border: OutlineInputBorder(),
          ),
          onChanged: _form.definirLogin,
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
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _senhaVisivel ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descontoMaxController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Teto de desconto no PDV (%)',
            helperText:
                'Vazio = usa o limite das configuracoes da empresa. '
                'Gerente/dono com desconto manual ignora o teto.',
            border: OutlineInputBorder(),
            suffixText: '%',
          ),
          onChanged: (v) {
            _form.definirDescontoMaximoTexto(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          value: _form.ativo,
          onChanged: (v) => setState(() => _form.definirAtivo(v)),
          title: const Text('Usuario ativo'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _form.admin,
          onChanged: (v) => setState(() => _form.definirAdmin(v)),
          title: const Text('Acesso total (Dono / Administrador)'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        Text('Perfil da loja', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Escolha um perfil pronto e ajuste as permissoes abaixo se precisar.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in PerfilUsuarioPreset.values)
              if (p != PerfilUsuarioPreset.customizado)
                ChoiceChip(
                  label: Text(p.rotulo),
                  selected: _form.perfilSelecionado == p,
                  onSelected: _form.admin && p != PerfilUsuarioPreset.dono
                      ? null
                      : (_) => setState(() {
                            _form.aplicarPerfil(p);
                            _descontoMaxController.text =
                                _form.descontoMaximoTexto;
                          }),
                ),
            ChoiceChip(
              label: const Text('Personalizado'),
              selected:
                  _form.perfilSelecionado == PerfilUsuarioPreset.customizado,
              onSelected: _form.admin
                  ? null
                  : (_) => setState(
                        () => _form.aplicarPerfil(PerfilUsuarioPreset.customizado),
                      ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        UsuariosResumoPanel(form: _form),
        const SizedBox(height: 16),
        Text('Permissoes', style: Theme.of(context).textTheme.titleMedium),
        UsuariosPermissoesPanel(
          form: _form,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.save_outlined),
                label: Text(editando ? 'Salvar edicao' : 'Salvar usuario'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _form.limpar();
                  _sincronizarControllers();
                }),
                icon: Icon(editando ? Icons.close : Icons.cleaning_services_outlined),
                label: Text(editando ? 'Cancelar edicao' : 'Limpar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
