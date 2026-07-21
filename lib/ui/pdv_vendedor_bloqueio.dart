import 'dart:async';

import 'package:flutter/material.dart';

import '../services/cupom_nao_fiscal_venda_pdf.dart';
import '../data/usuario_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/vendedor.dart';

enum _ModoIdentificacaoVendedorPdv { senhaVendedor, usuarioSistema }

/// Identifica o vendedor no terminal PDV (senha do cadastro ou login do sistema).
Future<Vendedor?> solicitarIdentificacaoVendedorPdv({
  required BuildContext context,
  required VendedorRepository vendedorRepository,
  required UsuarioRepository usuarioRepository,
  bool permitirCancelar = true,
  String titulo = 'Identificacao do vendedor',
  String mensagem =
      'Use a senha do sistema (login) se o vendedor tem usuario vinculado, '
      'ou o PIN do vendedor para desbloqueio rapido no balcao.',
  String rotuloConfirmar = 'Entrar',
}) async {
  final comSenha = vendedorRepository.contarAtivosComSenhaPdv();
  final comUsuario = await usuarioRepository.contarAtivosComVendedorVinculado();
  if (comSenha == 0 && comUsuario == 0) {
    if (!context.mounted) return null;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloqueio vendedor'),
        content: const Text(
          'Nenhum vendedor ativo tem PIN do PDV cadastrado e nenhum usuario '
          'tem vendedor vinculado.\n\n'
          'Configure em Cadastros → Usuarios (vendedor vinculado + senha do sistema) '
          'ou Cadastros → Vendedores (PIN do balcao), '
          'ou desative o bloqueio em Configuracoes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    return null;
  }

  return showDialog<Vendedor>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoBloqueioVendedorPdv(
      vendedorRepository: vendedorRepository,
      usuarioRepository: usuarioRepository,
      permitirCancelar: permitirCancelar,
      permiteSenhaVendedor: comSenha > 0,
      permiteUsuarioSistema: comUsuario > 0,
      titulo: titulo,
      mensagem: mensagem,
      rotuloConfirmar: rotuloConfirmar,
    ),
  );
}

/// Senha PDV ou login do sistema para registrar quem autorizou retirada na loja.
Future<String?> solicitarOperadorRetiradaNaLoja({
  required BuildContext context,
  required VendedorRepository vendedorRepository,
  required UsuarioRepository usuarioRepository,
}) async {
  final vendedor = await solicitarIdentificacaoVendedorPdv(
    context: context,
    vendedorRepository: vendedorRepository,
    usuarioRepository: usuarioRepository,
    titulo: 'Autorizar retirada',
    mensagem:
        'Informe a senha do sistema (login) ou o PIN do vendedor (balcao).',
    rotuloConfirmar: 'Confirmar',
  );
  if (vendedor == null) return null;
  return CupomNaoFiscalVendaPdf.rotuloVendedorUmLinha(vendedor);
}

class _DialogoBloqueioVendedorPdv extends StatefulWidget {
  const _DialogoBloqueioVendedorPdv({
    required this.vendedorRepository,
    required this.usuarioRepository,
    required this.permitirCancelar,
    required this.permiteSenhaVendedor,
    required this.permiteUsuarioSistema,
    required this.titulo,
    required this.mensagem,
    required this.rotuloConfirmar,
  });

  final VendedorRepository vendedorRepository;
  final UsuarioRepository usuarioRepository;
  final bool permitirCancelar;
  final bool permiteSenhaVendedor;
  final bool permiteUsuarioSistema;
  final String titulo;
  final String mensagem;
  final String rotuloConfirmar;

  @override
  State<_DialogoBloqueioVendedorPdv> createState() =>
      _DialogoBloqueioVendedorPdvState();
}

class _DialogoBloqueioVendedorPdvState extends State<_DialogoBloqueioVendedorPdv> {
  late final TextEditingController _senhaController;
  late final TextEditingController _loginController;
  late final TextEditingController _senhaUsuarioController;
  late _ModoIdentificacaoVendedorPdv _modo;
  final _senhaFocus = FocusNode();
  final _loginFocus = FocusNode();
  final _senhaUsuarioFocus = FocusNode();
  bool _ocultarSenha = true;
  bool _autenticando = false;
  String _erro = '';

  @override
  void initState() {
    super.initState();
    _senhaController = TextEditingController();
    _loginController = TextEditingController();
    _senhaUsuarioController = TextEditingController();
    // Prefere login do sistema quando disponivel (senha unica do ERP).
    if (widget.permiteUsuarioSistema) {
      _modo = _ModoIdentificacaoVendedorPdv.usuarioSistema;
    } else {
      _modo = _ModoIdentificacaoVendedorPdv.senhaVendedor;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _focarCampoAtual());
  }

  @override
  void dispose() {
    _senhaController.dispose();
    _loginController.dispose();
    _senhaUsuarioController.dispose();
    _senhaFocus.dispose();
    _loginFocus.dispose();
    _senhaUsuarioFocus.dispose();
    super.dispose();
  }

  void _focarCampoAtual() {
    if (!mounted) return;
    switch (_modo) {
      case _ModoIdentificacaoVendedorPdv.senhaVendedor:
        _senhaFocus.requestFocus();
      case _ModoIdentificacaoVendedorPdv.usuarioSistema:
        _loginFocus.requestFocus();
    }
  }

  void _definirModo(_ModoIdentificacaoVendedorPdv modo) {
    if (_modo == modo) return;
    setState(() {
      _modo = modo;
      _erro = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focarCampoAtual());
  }

  Future<void> _confirmar() async {
    if (_autenticando) return;

    setState(() {
      _autenticando = true;
      _erro = '';
    });

    Vendedor? vendedor;
    if (_modo == _ModoIdentificacaoVendedorPdv.senhaVendedor) {
      final senha = _senhaController.text.trim();
      if (senha.isEmpty) {
        setState(() {
          _autenticando = false;
          _erro = 'Informe o PIN do vendedor.';
        });
        return;
      }
      vendedor = widget.vendedorRepository.autenticarPorSenhaPdv(senha);
      if (vendedor == null && mounted) {
        setState(() {
          _autenticando = false;
          _erro = 'PIN invalido ou ambiguo. Verifique o cadastro do vendedor.';
        });
        return;
      }
    } else {
      final login = _loginController.text.trim();
      final senha = _senhaUsuarioController.text.trim();
      if (login.isEmpty || senha.isEmpty) {
        setState(() {
          _autenticando = false;
          _erro = 'Informe login e senha do sistema.';
        });
        return;
      }
      final usuario = await widget.usuarioRepository.autenticarComVendedorVinculado(
        login,
        senha,
        vendedorAtivo: (id) {
          final v = widget.vendedorRepository.obterPorId(id);
          return v != null && v.ativo;
        },
      );
      if (!mounted) return;
      if (usuario == null) {
        setState(() {
          _autenticando = false;
          _erro =
              'Login invalido, usuario inativo, sem vendedor vinculado '
              'ou vendedor inativo.';
        });
        return;
      }
      vendedor = widget.vendedorRepository.obterPorId(usuario.vendedorId);
    }

    if (!mounted || vendedor == null) return;
    Navigator.of(context).pop(vendedor);
  }

  @override
  Widget build(BuildContext context) {
    final mostrarSeletorModo =
        widget.permiteSenhaVendedor && widget.permiteUsuarioSistema;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.mensagem),
            if (widget.permiteUsuarioSistema) ...[
              const SizedBox(height: 8),
              Text(
                widget.permiteSenhaVendedor
                    ? 'Recomendado: senha do sistema (login). '
                        'O PIN do vendedor e so para balcao rapido.'
                    : 'Use a senha do sistema (mesma do login do app).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (mostrarSeletorModo) ...[
              const SizedBox(height: 12),
              SegmentedButton<_ModoIdentificacaoVendedorPdv>(
                segments: const [
                  ButtonSegment(
                    value: _ModoIdentificacaoVendedorPdv.usuarioSistema,
                    label: Text('Senha sistema'),
                    icon: Icon(Icons.person_outline, size: 18),
                  ),
                  ButtonSegment(
                    value: _ModoIdentificacaoVendedorPdv.senhaVendedor,
                    label: Text('PIN balcao'),
                    icon: Icon(Icons.pin_outlined, size: 18),
                  ),
                ],
                selected: {_modo},
                onSelectionChanged: (s) => _definirModo(s.first),
              ),
            ],
            const SizedBox(height: 12),
            if (_modo == _ModoIdentificacaoVendedorPdv.senhaVendedor) ...[
              TextField(
                controller: _senhaController,
                focusNode: _senhaFocus,
                obscureText: _ocultarSenha,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_confirmar()),
                decoration: InputDecoration(
                  labelText: 'PIN do vendedor (balcao)',
                  helperText: 'Cadastro em Vendedores — opcional se ja usa login.',
                  errorText: _erro.isEmpty ? null : _erro,
                  suffixIcon: IconButton(
                    tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: () =>
                        setState(() => _ocultarSenha = !_ocultarSenha),
                    icon: Icon(
                      _ocultarSenha
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _loginController,
                focusNode: _loginFocus,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Login do sistema',
                  errorText: _erro.isEmpty ? null : _erro,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _senhaUsuarioController,
                focusNode: _senhaUsuarioFocus,
                obscureText: _ocultarSenha,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_confirmar()),
                decoration: InputDecoration(
                  labelText: 'Senha do sistema',
                  helperText: 'Mesma senha usada para entrar no app.',
                  suffixIcon: IconButton(
                    tooltip: _ocultarSenha ? 'Mostrar senha' : 'Ocultar senha',
                    onPressed: () =>
                        setState(() => _ocultarSenha = !_ocultarSenha),
                    icon: Icon(
                      _ocultarSenha
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.permitirCancelar)
          TextButton(
            onPressed: _autenticando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        FilledButton(
          onPressed: _autenticando ? null : () => unawaited(_confirmar()),
          child: _autenticando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.rotuloConfirmar),
        ),
      ],
    );
  }
}
