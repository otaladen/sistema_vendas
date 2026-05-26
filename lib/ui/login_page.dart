import 'package:flutter/material.dart';

import '../data/usuario_repository.dart';
import '../domain/auditoria_catalogo.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';
import 'layout/app_layout.dart';

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
  static const _nomeMarca = 'Sistema de Vendas';
  static const _sloganMarca = 'Gestao inteligente para vendas e entregas';

  final _nomeController = TextEditingController();
  final _loginController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  final _loginFocus = FocusNode();
  final _senhaFocus = FocusNode();
  final _confirmarSenhaFocus = FocusNode();

  bool _primeiroAcesso = false;
  bool _carregando = true;
  bool _autenticando = false;
  bool _ocultarSenha = true;
  bool _ocultarConfirmarSenha = true;
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
    _loginFocus.dispose();
    _senhaFocus.dispose();
    _confirmarSenhaFocus.dispose();
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
    if (_autenticando) return;
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
    setState(() {
      _autenticando = true;
      _erro = '';
    });
    try {
      final existe = await widget.usuarioRepository.loginJaExiste(login);
      if (existe) {
        if (!mounted) return;
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
        perfil: 'dono',
        podeCadastros: true,
        podeEstoque: true,
        podeVendas: true,
        podeCaixa: true,
        podeAcessarPdv: true,
        podeAcessarCaixa: true,
        podeAcessarRelatorios: true,
        podeLeituraParcialCaixa: true,
        podeManutencaoAuditoriaCaixa: true,
        podeEntregas: true,
        podeVisualizarEntregas: true,
        podeGerenciarEntregas: true,
        podeFinanceiro: true,
        podeConfiguracoes: true,
        podeCancelarVendas: true,
        podeAutorizarSegundaViaCupom: true,
        podeAutorizarMargemVenda: true,
        podeReajustePrecoLote: true,
        podeAutorizarReajustePreco: true,
        podeAlterarPrecoPdv: true,
        podeVenderFiado: true,
        podeVerCustoMargem: true,
        podeGerenciarUsuarios: true,
        podeEmitirNfeSaida: true,
        podeCancelarNfeSaida: true,
      );
      await widget.usuarioRepository.salvar(admin, senhaPlainNova: senha);
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.autenticacao,
        acao: AuditoriaAcao.adminCriado,
        usuarioLogin: login,
        resumo: 'Primeiro administrador criado: $nome',
        detalhes: {'login': login},
      );
      if (!mounted) return;
      widget.onLoginSuccess(admin);
    } finally {
      if (mounted) {
        setState(() {
          _autenticando = false;
        });
      }
    }
  }

  Future<void> _entrar() async {
    if (_autenticando) return;
    final login = _loginController.text.trim();
    final senha = _senhaController.text.trim();
    if (login.isEmpty || senha.isEmpty) {
      setState(() => _erro = 'Informe usuario e senha.');
      return;
    }
    setState(() {
      _autenticando = true;
      _erro = '';
    });
    try {
      final usuario = await widget.usuarioRepository.autenticar(login, senha);
      if (usuario == null) {
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.autenticacao,
          acao: AuditoriaAcao.loginFalha,
          usuarioLogin: login,
          resumo: 'Tentativa de login falhou: $login',
        );
        if (!mounted) return;
        setState(() => _erro = 'Usuario ou senha invalidos.');
        return;
      }
      if (!usuario.ativo) {
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.autenticacao,
          acao: AuditoriaAcao.loginFalha,
          usuarioLogin: login,
          resumo: 'Login bloqueado (usuario inativo): $login',
        );
        if (!mounted) return;
        setState(() => _erro = 'Usuario inativo. Procure o administrador.');
        return;
      }
      if (!mounted) return;
      widget.onLoginSuccess(usuario);
    } finally {
      if (mounted) {
        setState(() {
          _autenticando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;
    final acaoLogin = _primeiroAcesso ? _criarAdministrador : _entrar;

    final corMarca = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.22),
      scheme.surface,
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              corMarca,
              scheme.surface,
              scheme.tertiary.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Card(
                margin: EdgeInsets.all(
                  context.isCompactLayout ? 12 : 24,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final formulario = Padding(
                            padding: EdgeInsets.all(
                              context.isCompactLayout ? 16 : 28,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: context.isCompactLayout
                                        ? constraints.maxWidth
                                        : 430,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                        child: Container(
                                          width: 250,
                                          height: 88,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: scheme.outlineVariant.withValues(alpha: 0.75),
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.07),
                                                blurRadius: 18,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            child: Image.asset(
                                              'assets/images/logo.jpg',
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.storefront_outlined,
                                                      color: scheme.primary,
                                                      size: 24,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _nomeMarca,
                                                      style: TextStyle(
                                                        color: scheme.primary,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        _nomeMarca,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _sloganMarca,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        _primeiroAcesso
                                            ? 'Primeiro acesso'
                                            : 'Bem-vindo',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _primeiroAcesso
                                            ? 'Cadastre o administrador inicial com acesso total.'
                                            : 'Informe usuario e senha para entrar no sistema.',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 18),
                                      if (_primeiroAcesso) ...[
                                        TextField(
                                          controller: _nomeController,
                                          decoration: const InputDecoration(
                                            labelText: 'Nome do administrador',
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      TextField(
                                        controller: _loginController,
                                        decoration: const InputDecoration(
                                          labelText: 'Usuario',
                                        ),
                                        focusNode: _loginFocus,
                                        textInputAction: TextInputAction.next,
                                        onSubmitted: (_) => FocusScope.of(context)
                                            .requestFocus(_senhaFocus),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _senhaController,
                                        obscureText: _ocultarSenha,
                                        decoration: InputDecoration(
                                          labelText: 'Senha',
                                          suffixIcon: IconButton(
                                            tooltip: _ocultarSenha
                                                ? 'Mostrar senha'
                                                : 'Ocultar senha',
                                            onPressed: () => setState(
                                              () => _ocultarSenha = !_ocultarSenha,
                                            ),
                                            icon: Icon(
                                              _ocultarSenha
                                                  ? Icons.visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                            ),
                                          ),
                                        ),
                                        focusNode: _senhaFocus,
                                        textInputAction: _primeiroAcesso
                                            ? TextInputAction.next
                                            : TextInputAction.done,
                                        onSubmitted: (_) {
                                          if (_primeiroAcesso) {
                                            FocusScope.of(context)
                                                .requestFocus(_confirmarSenhaFocus);
                                            return;
                                          }
                                          acaoLogin();
                                        },
                                      ),
                                      if (_primeiroAcesso) ...[
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: _confirmarSenhaController,
                                          obscureText: _ocultarConfirmarSenha,
                                          decoration: InputDecoration(
                                            labelText: 'Confirmar senha',
                                            suffixIcon: IconButton(
                                              tooltip: _ocultarConfirmarSenha
                                                  ? 'Mostrar senha'
                                                  : 'Ocultar senha',
                                              onPressed: () => setState(
                                                () => _ocultarConfirmarSenha =
                                                    !_ocultarConfirmarSenha,
                                              ),
                                              icon: Icon(
                                                _ocultarConfirmarSenha
                                                    ? Icons.visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                              ),
                                            ),
                                          ),
                                          focusNode: _confirmarSenhaFocus,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => acaoLogin(),
                                        ),
                                      ],
                                      if (_erro.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: scheme.errorContainer.withValues(alpha: 0.7),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: scheme.error.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Text(
                                            _erro,
                                            style: TextStyle(
                                              color: scheme.onErrorContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      ElevatedButton.icon(
                                        onPressed: _autenticando ? null : acaoLogin,
                                        icon: _autenticando
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.2,
                                                ),
                                              )
                                            : Icon(
                                                _primeiroAcesso
                                                    ? Icons.admin_panel_settings_outlined
                                                    : Icons.login,
                                              ),
                                        label: Text(
                                          _autenticando
                                              ? 'Aguarde...'
                                              : _primeiroAcesso
                                                  ? 'Criar administrador e entrar'
                                                  : 'Entrar',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Dica: Enter no usuario vai para senha e Enter na senha entra.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Versao 1.0.0',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                    if (context.isDesktopLayout) {
                      return Row(
                        children: [
                          Expanded(child: formulario),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: formulario,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
