import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';
import '../model/usuario_sistema.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.usuarioRepository,
    required this.onLoginSuccess,
  });

  final UsuarioRepository usuarioRepository;
  final ValueChanged<UsuarioSistema> onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nomeController = TextEditingController();
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  bool _primeiroAcesso = false;
  bool _carregando = true;
  String _erro = '';

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _loginController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    final usuarios = await widget.usuarioRepository.listarTodos();
    if (!mounted) return;
    setState(() {
      _primeiroAcesso = usuarios.isEmpty;
      _carregando = false;
    });
  }

  Future<void> _criarAdministrador() async {
    final nome = _nomeController.text.trim();
    final login = _loginController.text.trim();
    final senha = _senhaController.text.trim();
    final confirmar = _confirmarSenhaController.text.trim();
    if (nome.isEmpty || login.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Preencha nome, usuario e senha.');
      return;
    }
    if (senha != confirmar) {
      setState(() => _erro = 'As senhas nao conferem.');
      return;
    }
    final existe = await widget.usuarioRepository.loginJaExiste(login);
    if (existe) {
      setState(() => _erro = 'Ja existe um usuario com esse login.');
      return;
    }

    final admin = UsuarioSistema(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      nome: nome,
      login: login,
      senha: senha,
      ativo: true,
      admin: true,
      podeCadastros: true,
      podeEstoque: true,
      podeVendas: true,
      podeCaixa: true,
      podeEntregas: true,
      podeFinanceiro: true,
      podeConfiguracoes: true,
    );
    await widget.usuarioRepository.salvar(admin);
    widget.onLoginSuccess(admin);
  }

  Future<void> _entrar() async {
    final login = _loginController.text.trim();
    final senha = _senhaController.text.trim();
    if (login.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Informe usuario e senha.');
      return;
    }
    final usuario = await widget.usuarioRepository.autenticar(login, senha);
    if (usuario == null) {
      setState(() => _erro = 'Usuario ou senha invalidos.');
      return;
    }
    if (!usuario.ativo) {
      setState(() => _erro = 'Usuario inativo. Procure o administrador.');
      return;
    }
    widget.onLoginSuccess(usuario);
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_primeiroAcesso ? 'Primeiro acesso' : 'Login do sistema'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _primeiroAcesso
                        ? 'Cadastre o administrador inicial com acesso total.'
                        : 'Informe seu usuario e senha para acessar o sistema.',
                  ),
                  const SizedBox(height: 12),
                  if (_primeiroAcesso) ...[
                    TextField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do administrador',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _loginController,
                    decoration: const InputDecoration(labelText: 'Usuario'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                  ),
                  if (_primeiroAcesso) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmarSenhaController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar senha',
                      ),
                    ),
                  ],
                  if (_erro.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _erro,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _primeiroAcesso ? _criarAdministrador : _entrar,
                    icon: Icon(
                      _primeiroAcesso
                          ? Icons.admin_panel_settings_outlined
                          : Icons.login,
                    ),
                    label: Text(
                      _primeiroAcesso
                          ? 'Criar administrador e entrar'
                          : 'Entrar',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
