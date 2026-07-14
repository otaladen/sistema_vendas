import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/auditoria_catalogo.dart';
import '../data/usuario_repository.dart';
import '../domain/permissao_usuario.dart';
import '../domain/produto_limite_desconto_pdv.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/produto.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';
import 'pdv_desconto_autorizacao.dart';

class AlteracaoPrecoUnitarioPdvResult {
  const AlteracaoPrecoUnitarioPdvResult({
    required this.novoPreco,
    required this.manual,
    required this.autorizadoPor,
  });

  final double novoPreco;
  final bool manual;
  final String autorizadoPor;
}

class _CredenciaisAutorizacao {
  const _CredenciaisAutorizacao({required this.login, required this.senha});

  final String login;
  final String senha;
}

bool usuarioPodeAutorizarAlterarPrecoUnitarioPdv(UsuarioSistema u) {
  return UsuarioPermissaoHelper.tem(
    u,
    PermissaoUsuario.alterarPrecoUnitarioPdv,
  );
}

/// Login/senha de gerente + valor desejado para preco unitario no carrinho.
Future<AlteracaoPrecoUnitarioPdvResult?> solicitarAlteracaoPrecoUnitarioPdv(
  BuildContext context,
  UsuarioRepository usuarioRepository, {
  required UsuarioSistema usuarioLogado,
  required Produto produto,
  required String precoTipo,
  required double tetoDescontoPercentualEmpresa,
  required double quantidadeLinha,
  required String nomeProduto,
  required double precoAtual,
  required double precoTabela,
  required String rotuloTabela,
  required String Function(double) formatarMoeda,
}) async {
  String autorizadoPor = usuarioLogado.login;

  if (!usuarioPodeAutorizarAlterarPrecoUnitarioPdv(usuarioLogado)) {
    final cred = await showDialog<_CredenciaisAutorizacao>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => _DialogoAutorizacaoPrecoPdv(nomeProduto: nomeProduto),
    );
    if (cred == null || !context.mounted) return null;
    if (cred.login.isEmpty || cred.senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha login e senha.')),
      );
      return null;
    }
    final usuario = await usuarioRepository.autenticar(cred.login, cred.senha);
    if (!context.mounted) return null;
    if (usuario == null || !usuarioPodeAutorizarAlterarPrecoUnitarioPdv(usuario)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem permissao. Ative "Alterar preco unitario no PDV" no cadastro '
            'de usuarios ou use um administrador.',
          ),
        ),
      );
      return null;
    }
    autorizadoPor = usuario.login;
  }

  if (!context.mounted) return null;

  final valor = await showDialog<_ResultadoPrecoDialogo>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _DialogoNovoPrecoPdv(
      nomeProduto: nomeProduto,
      precoAtual: precoAtual,
      precoTabela: precoTabela,
      rotuloTabela: rotuloTabela,
      formatarMoeda: formatarMoeda,
      produto: produto,
      precoTipo: precoTipo,
      tetoDescontoPercentualEmpresa: tetoDescontoPercentualEmpresa,
    ),
  );
  if (valor == null || !context.mounted) return null;

  if (valor.manual) {
    final descontoExtraUnitario = ProdutoLimiteDescontoPdv.descontoUnitarioAcimaDoTeto(
      novoPrecoUnitario: valor.preco,
      precoTabelaReferencia: precoTabela,
      produto: produto,
      precoTipo: precoTipo,
      tetoEmpresaOuUsuario: tetoDescontoPercentualEmpresa,
    );
    if (descontoExtraUnitario > 1e-6) {
      final maximoPermitido = ProdutoLimiteDescontoPdv.descontoMaximoReaisNaLinha(
        precoTabelaReferencia: precoTabela,
        quantidade: quantidadeLinha,
        produto: produto,
        precoTipo: precoTipo,
        tetoEmpresaOuUsuario: tetoDescontoPercentualEmpresa,
      );
      final descontoSolicitado = (precoTabela - valor.preco) * quantidadeLinha;
      final authDesconto = await solicitarAutorizacaoDescontoAcimaTetoPdv(
        context,
        usuarioRepository,
        usuarioLogado: usuarioLogado,
        maximoPermitidoReais: maximoPermitido,
        descontoSolicitadoReais: descontoSolicitado,
        formatarMoeda: formatarMoeda,
      );
      if (!context.mounted) return null;
      if (authDesconto == null) return null;
      autorizadoPor = authDesconto;
    }
  }

  AuditoriaRegistrar.registrar(
    modulo: AuditoriaModulo.orcamento,
    acao: AuditoriaAcao.alterarPrecoUnitarioPdv,
    usuarioLogin: usuarioLogado.login,
    resumo: 'Preco unitario PDV: $nomeProduto',
    detalhes: {
      'produto': nomeProduto,
      'precoAnterior': precoAtual,
      'precoNovo': valor.preco,
      'precoTabela': precoTabela,
      'manual': valor.manual,
      'autorizadoPor': autorizadoPor,
    },
  );

  return AlteracaoPrecoUnitarioPdvResult(
    novoPreco: valor.preco,
    manual: valor.manual,
    autorizadoPor: autorizadoPor,
  );
}

class _ResultadoPrecoDialogo {
  const _ResultadoPrecoDialogo({
    required this.preco,
    required this.manual,
  });

  final double preco;
  final bool manual;
}

class _DialogoAutorizacaoPrecoPdv extends StatefulWidget {
  const _DialogoAutorizacaoPrecoPdv({required this.nomeProduto});

  final String nomeProduto;

  @override
  State<_DialogoAutorizacaoPrecoPdv> createState() =>
      _DialogoAutorizacaoPrecoPdvState();
}

class _DialogoAutorizacaoPrecoPdvState
    extends State<_DialogoAutorizacaoPrecoPdv> {
  final _login = TextEditingController();
  final _senha = TextEditingController();

  @override
  void dispose() {
    _login.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _ok() {
    Navigator.pop(
      context,
      _CredenciaisAutorizacao(
        login: _login.text.trim(),
        senha: _senha.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Autorizacao de gerente'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alterar preco unitario de:\n${widget.nomeProduto}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _login,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Login'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _senha,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha'),
              onSubmitted: (_) => _ok(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Autorizar')),
      ],
    );
  }
}

class _DialogoNovoPrecoPdv extends StatefulWidget {
  const _DialogoNovoPrecoPdv({
    required this.nomeProduto,
    required this.precoAtual,
    required this.precoTabela,
    required this.rotuloTabela,
    required this.formatarMoeda,
    required this.produto,
    required this.precoTipo,
    required this.tetoDescontoPercentualEmpresa,
  });

  final String nomeProduto;
  final double precoAtual;
  final double precoTabela;
  final String rotuloTabela;
  final String Function(double) formatarMoeda;
  final Produto produto;
  final String precoTipo;
  final double tetoDescontoPercentualEmpresa;

  @override
  State<_DialogoNovoPrecoPdv> createState() => _DialogoNovoPrecoPdvState();
}

class _DialogoNovoPrecoPdvState extends State<_DialogoNovoPrecoPdv> {
  late final TextEditingController _precoController;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _precoController = TextEditingController(
      text: _formatarEntrada(widget.precoAtual),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _precoController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _precoController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _precoController.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _formatarEntrada(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');

  double? _lerPreco() {
    final t = _precoController.text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v < 0) return null;
    return v;
  }

  void _confirmar({required bool manual}) {
    final v = _lerPreco();
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um preco valido (>= 0).')),
      );
      return;
    }
    Navigator.pop(
      context,
      _ResultadoPrecoDialogo(preco: v, manual: manual),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct = ProdutoLimiteDescontoPdv.percentualEfetivo(
      produto: widget.produto,
      precoTipo: widget.precoTipo,
      tetoEmpresaOuUsuario: widget.tetoDescontoPercentualEmpresa,
    );
    final precoMinimo = ProdutoLimiteDescontoPdv.precoMinimoUnitario(
      precoTabelaReferencia: widget.precoTabela,
      produto: widget.produto,
      precoTipo: widget.precoTipo,
      tetoEmpresaOuUsuario: widget.tetoDescontoPercentualEmpresa,
    );
    return AlertDialog(
      title: const Text('Preco unitario'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.nomeProduto,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Atual: ${widget.formatarMoeda(widget.precoAtual)} · '
              '${widget.rotuloTabela}: ${widget.formatarMoeda(widget.precoTabela)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.precoTabela > 0 && pct > 0.004) ...[
              const SizedBox(height: 4),
              Text(
                'Minimo sem autorizacao: ${widget.formatarMoeda(precoMinimo)} '
                '(desconto max. ${pct.toStringAsFixed(1)}%)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _precoController,
              focusNode: _focus,
              decoration: const InputDecoration(
                labelText: 'Novo preco unitario',
                prefixText: 'R\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirmar(manual: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => _confirmar(manual: false),
          child: Text('Usar ${widget.rotuloTabela}'),
        ),
        FilledButton(
          onPressed: () => _confirmar(manual: true),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
