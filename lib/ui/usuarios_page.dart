import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';
import '../model/usuario_sistema.dart';

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key, required this.usuarioRepository});

  final UsuarioRepository usuarioRepository;

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  final _nomeController = TextEditingController();
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();

  List<UsuarioSistema> _usuarios = [];
  String? _editandoId;
  bool _ativo = true;
  bool _admin = false;
  bool _podeCadastros = false;
  bool _podeEstoque = false;
  bool _podeVendas = false;
  bool _podeCaixa = false;
  bool _podeLeituraParcialCaixa = false;
  bool _podeManutencaoAuditoriaCaixa = false;
  bool _podeEntregas = false;
  bool _podeFinanceiro = false;
  bool _podeConfiguracoes = false;
  bool _podeAutorizarSegundaViaCupom = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _loginController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final lista = await widget.usuarioRepository.listarTodos();
    if (!mounted) return;
    setState(() {
      _usuarios = lista;
    });
  }

  void _limparFormulario() {
    setState(() {
      _editandoId = null;
      _nomeController.clear();
      _loginController.clear();
      _senhaController.clear();
      _ativo = true;
      _admin = false;
      _podeCadastros = false;
      _podeEstoque = false;
      _podeVendas = false;
      _podeCaixa = false;
      _podeLeituraParcialCaixa = false;
      _podeManutencaoAuditoriaCaixa = false;
      _podeEntregas = false;
      _podeFinanceiro = false;
      _podeConfiguracoes = false;
      _podeAutorizarSegundaViaCupom = false;
    });
  }

  void _aplicarAdmin(bool valor) {
    _admin = valor;
    if (valor) {
      _podeCadastros = true;
      _podeEstoque = true;
      _podeVendas = true;
      _podeCaixa = true;
      _podeLeituraParcialCaixa = true;
      _podeManutencaoAuditoriaCaixa = true;
      _podeEntregas = true;
      _podeFinanceiro = true;
      _podeConfiguracoes = true;
      _podeAutorizarSegundaViaCupom = true;
    }
  }

  Future<void> _salvar() async {
    final nome = _nomeController.text.trim();
    final login = _loginController.text.trim();
    final senha = _senhaController.text.trim();
    if (nome.isEmpty || login.isEmpty || senha.isEmpty) {
      setState(() => _status = 'Preencha nome, login e senha.');
      return;
    }
    final existe = await widget.usuarioRepository.loginJaExiste(
      login,
      ignorarId: _editandoId,
    );
    if (existe) {
      setState(() => _status = 'Ja existe um usuario com este login.');
      return;
    }

    final id = _editandoId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final usuario = UsuarioSistema(
      id: id,
      nome: nome,
      login: login,
      senha: senha,
      ativo: _ativo,
      admin: _admin,
      podeCadastros: _podeCadastros,
      podeEstoque: _podeEstoque,
      podeVendas: _podeVendas,
      podeCaixa: _podeCaixa,
      podeLeituraParcialCaixa: _podeLeituraParcialCaixa,
      podeManutencaoAuditoriaCaixa: _podeManutencaoAuditoriaCaixa,
      podeEntregas: _podeEntregas,
      podeFinanceiro: _podeFinanceiro,
      podeConfiguracoes: _podeConfiguracoes,
      podeAutorizarSegundaViaCupom: _podeAutorizarSegundaViaCupom,
    );
    await widget.usuarioRepository.salvar(usuario);
    await _carregar();
    _limparFormulario();
    setState(() => _status = 'Usuario salvo com sucesso.');
  }

  void _editar(UsuarioSistema u) {
    setState(() {
      _editandoId = u.id;
      _nomeController.text = u.nome;
      _loginController.text = u.login;
      _senhaController.text = u.senha;
      _ativo = u.ativo;
      _admin = u.admin;
      _podeCadastros = u.podeCadastros;
      _podeEstoque = u.podeEstoque;
      _podeVendas = u.podeVendas;
      _podeCaixa = u.podeCaixa;
      _podeLeituraParcialCaixa = u.podeLeituraParcialCaixa;
      _podeManutencaoAuditoriaCaixa = u.podeManutencaoAuditoriaCaixa;
      _podeEntregas = u.podeEntregas;
      _podeFinanceiro = u.podeFinanceiro;
      _podeConfiguracoes = u.podeConfiguracoes;
      _podeAutorizarSegundaViaCupom = u.podeAutorizarSegundaViaCupom;
      _status = 'Editando usuario: ${u.nome}';
    });
  }

  Future<void> _remover(UsuarioSistema u) async {
    await widget.usuarioRepository.remover(u.id);
    await _carregar();
    if (!mounted) return;
    setState(() => _status = 'Usuario removido: ${u.nome}');
    if (_editandoId == u.id) {
      _limparFormulario();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de Usuarios')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nomeController,
            decoration: const InputDecoration(labelText: 'Nome do usuario'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _loginController,
            decoration: const InputDecoration(labelText: 'Login'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _senhaController,
            decoration: const InputDecoration(labelText: 'Senha'),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _ativo,
            onChanged: (v) => setState(() => _ativo = v),
            title: const Text('Usuario ativo'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _admin,
            onChanged: (v) => setState(() => _aplicarAdmin(v)),
            title: const Text('Administrador (acesso total)'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Text('Permissoes de acesso', style: Theme.of(context).textTheme.titleMedium),
          CheckboxListTile(
            value: _podeCadastros,
            onChanged: _admin ? null : (v) => setState(() => _podeCadastros = v ?? false),
            title: const Text('Cadastros'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeEstoque,
            onChanged: _admin ? null : (v) => setState(() => _podeEstoque = v ?? false),
            title: const Text('Estoque'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeVendas,
            onChanged: _admin ? null : (v) => setState(() => _podeVendas = v ?? false),
            title: const Text('Vendas'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeCaixa,
            onChanged: _admin ? null : (v) => setState(() => _podeCaixa = v ?? false),
            title: const Text('Caixa'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeLeituraParcialCaixa,
            onChanged: _admin
                ? null
                : (v) => setState(() => _podeLeituraParcialCaixa = v ?? false),
            title: const Text('Leitura parcial do caixa'),
            subtitle: const Text(
              'Ver totais por forma de pagamento e vendas sem fechar o caixa',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeManutencaoAuditoriaCaixa,
            onChanged: _admin
                ? null
                : (v) => setState(() => _podeManutencaoAuditoriaCaixa = v ?? false),
            title: const Text('Manutencao da auditoria do caixa'),
            subtitle: const Text('Pode limpar registros antigos/filtrados da auditoria'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeEntregas,
            onChanged: _admin ? null : (v) => setState(() => _podeEntregas = v ?? false),
            title: const Text('Entregas'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeFinanceiro,
            onChanged: _admin ? null : (v) => setState(() => _podeFinanceiro = v ?? false),
            title: const Text('Financeiro'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeConfiguracoes,
            onChanged: _admin ? null : (v) => setState(() => _podeConfiguracoes = v ?? false),
            title: const Text('Configuracoes'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _podeAutorizarSegundaViaCupom,
            onChanged: _admin
                ? null
                : (v) => setState(() => _podeAutorizarSegundaViaCupom = v ?? false),
            title: const Text('Autorizar segunda via do cupom'),
            subtitle: const Text(
              'Pode informar login e senha para reimprimir cupom na listagem de vendas ou no caixa.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _salvar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_editandoId == null ? 'Salvar usuario' : 'Salvar edicao'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _limparFormulario,
                  icon: Icon(_editandoId == null ? Icons.cleaning_services_outlined : Icons.close),
                  label: Text(_editandoId == null ? 'Limpar' : 'Cancelar edicao'),
                ),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status),
          ],
          const SizedBox(height: 12),
          Text('Usuarios cadastrados', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_usuarios.isEmpty) const Text('Nenhum usuario cadastrado.')
          else
            ..._usuarios.map(
              (u) => Card(
                child: ListTile(
                  title: Text('${u.nome} (${u.login})'),
                  subtitle: Text(
                    '${u.admin ? 'Admin' : 'Perfil customizado'} | ${u.ativo ? 'Ativo' : 'Inativo'}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        onPressed: () => _editar(u),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: () => _remover(u),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
