import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/sync/entregas_foco_hub.dart';
import '../../../domain/chat_interno_parser.dart';
import '../../../domain/main_menu_destino.dart';
import '../../../domain/usuario_permissao_helper.dart';
import '../../../model/mensagem_interna.dart';
import '../../../model/usuario_sistema.dart';
import '../../../model/venda.dart';
import '../../orcamento_pdv_navigation.dart';
import '../../shell/app_shell_scope.dart';
import '../../shell/main_menu_deps.dart';
import 'autorizacao_pdv_chat_card.dart';
import 'chat_interno_hub.dart';

/// Botao da TopBar com badge de recados novos.
class ChatInternoTopBarButton extends StatelessWidget {
  const ChatInternoTopBarButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChatInternoHub.instance,
      builder: (context, _) {
        final hub = ChatInternoHub.instance;
        final n = hub.naoLidos;
        final mencao = hub.temMencaoNaoLida;
        return IconButton(
          tooltip: n > 0
              ? (mencao
                  ? 'Chat interno ($n novos, mencao para voce)'
                  : 'Chat interno ($n novos)')
              : 'Chat interno',
          onPressed: onPressed ?? () => ChatInternoDrawer.abrir(context),
          icon: Badge(
            isLabelVisible: n > 0,
            backgroundColor: mencao
                ? Theme.of(context).colorScheme.error
                : null,
            label: Text(n > 99 ? '99+' : '$n'),
            child: const Text('💬', style: TextStyle(fontSize: 18)),
          ),
        );
      },
    );
  }
}

/// Gaveta lateral leve com lista + envio rapido.
class ChatInternoDrawer {
  static Future<void> abrir(BuildContext context) async {
    final hub = ChatInternoHub.instance;
    final abrirEntregas = AppShellScope.maybeOf(context)?.irPara;
    final usuario = MainMenuDeps.maybeOf(context)?.usuarioLogado ??
        ChatInternoHub.instance.usuarioLogado;
    await hub.carregarHistorico();
    hub.marcarPainelAberto(true);
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: 'Fechar chat',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secondary) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 12,
            color: Theme.of(ctx).colorScheme.surface,
            child: SizedBox(
              width: MediaQuery.sizeOf(ctx).width.clamp(320, 420),
              height: MediaQuery.sizeOf(ctx).height,
              child: _ChatInternoPainel(
                usuarioLogado: usuario,
                onAbrirEntregas: abrirEntregas == null
                    ? null
                    : () {
                        final destino = usuario != null &&
                                UsuarioPermissaoHelper.ehMotoristaCampoSomente(
                                  usuario,
                                )
                            ? MainMenuDestino.motorista
                            : MainMenuDestino.entregas;
                        abrirEntregas(destino);
                      },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
    hub.marcarPainelAberto(false);
  }
}

class _ChatInternoPainel extends StatefulWidget {
  const _ChatInternoPainel({this.onAbrirEntregas, this.usuarioLogado});

  final VoidCallback? onAbrirEntregas;
  final UsuarioSistema? usuarioLogado;

  @override
  State<_ChatInternoPainel> createState() => _ChatInternoPainelState();
}

class _ChatInternoPainelState extends State<_ChatInternoPainel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _fmt = DateFormat('HH:mm');
  bool _enviando = false;
  String? _erro;
  bool _grudadoNoFim = true;
  bool _scrollInicialFeito = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final noFim = pos.maxScrollExtent - pos.pixels < 64;
    _grudadoNoFim = noFim;
    if (noFim) {
      unawaited(ChatInternoHub.instance.marcarLidasAteFim());
    }
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ChatInternoHub.instance.enviar(texto);
      _ctrl.clear();
      _grudadoNoFim = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _irParaFim();
        unawaited(ChatInternoHub.instance.marcarLidasAteFim());
      });
    } catch (e) {
      setState(() => _erro = '$e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _irParaFim() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _agendarScrollInicial() {
    if (_scrollInicialFeito) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scrollInicialFeito = true;
      final idx = ChatInternoHub.instance.indicePrimeiraNaoLida();
      if (idx <= 0) {
        _irParaFim();
        return;
      }
      final offset = (idx * 72.0).clamp(0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(offset.toDouble());
      _grudadoNoFim = false;
    });
  }

  void _inserirAtalho(String token) {
    final t = _ctrl.text;
    final sep = t.isEmpty || t.endsWith(' ') ? '' : ' ';
    _ctrl.text = '$t$sep$token ';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  Future<void> _abrirPedido(int numero) async {
    if (numero <= 0 || !mounted) return;
    final nav = Navigator.of(context);
    final deps = MainMenuDeps.maybeOf(context);
    if (deps != null) {
      try {
        final repo = deps.vendaRepository;
        Venda? orcamento;
        try {
          orcamento = repo.buscarOrcamentoPendentePorNumero(numero) as Venda?;
        } catch (_) {}
        if (orcamento == null && deps.vendaApiRepository != null) {
          orcamento = await deps.vendaApiRepository!
              .buscarOrcamentoPendentePorNumeroRemoto(numero);
        }
        if (!mounted) return;
        if (orcamento != null) {
          nav.maybePop();
          await abrirPdvComOrcamento(
            context,
            orcamentoId: orcamento.id,
            produtoRepository: deps.produtoRepository,
            clienteRepository: deps.clienteRepository,
            vendaRepository: deps.vendaRepository,
            vendedorRepository: deps.vendedorRepository,
            configuracoesService: deps.configuracoesService,
            printService: deps.printService,
            usuarioLogado: deps.usuarioLogado,
          );
          return;
        }

        Venda? venda;
        try {
          venda = repo.buscarVendaFinalizadaPorNumeroOuId(numero) as Venda?;
        } catch (_) {}
        if (venda == null && deps.vendaApiRepository != null) {
          venda = await deps.vendaApiRepository!
              .buscarVendaFinalizadaPorNumeroOuIdRemoto(numero);
        }
        if (!mounted) return;
        if (venda != null) {
          nav.maybePop();
          AppShellScope.maybeOf(context)?.irPara(MainMenuDestino.vendas);
          final rotulo =
              venda.numeroControle > 0 ? venda.numeroControle : numero;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Venda #$rotulo — abra a lista de vendas.',
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    EntregasFocoHub.instance.focarPedido(numero);
    nav.maybePop();
    widget.onAbrirEntregas?.call();
    if (widget.onAbrirEntregas == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Abra Entregas e busque o pedido #$numero.')),
      );
    }
  }

  Future<void> _mostrarFrasesRapidas() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Mensagens rapidas',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (final frase in ChatInternoParser.frasesRapidas)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, size: 20),
                  title: Text(frase),
                  onTap: () => Navigator.pop(ctx, frase),
                ),
            ],
          ),
        );
      },
    );
    if (escolha == null || !mounted) return;
    _ctrl.text = escolha;
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  Widget _textoComPedidos(String texto, ThemeData theme) {
    final re = ChatInternoParser.pedidoNumeroPattern;
    final partes = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(texto)) {
      if (m.start > last) {
        partes.add(TextSpan(text: texto.substring(last, m.start)));
      }
      final n = int.tryParse(m.group(1) ?? '') ?? 0;
      partes.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              label: Text('#$n', style: const TextStyle(fontSize: 12)),
              onPressed: n > 0 ? () => unawaited(_abrirPedido(n)) : null,
            ),
          ),
        ),
      );
      last = m.end;
    }
    if (last < texto.length) {
      partes.add(TextSpan(text: texto.substring(last)));
    }
    if (partes.isEmpty) {
      return Text(texto, style: theme.textTheme.bodyMedium);
    }
    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodyMedium,
        children: partes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              leading: const Text('💬', style: TextStyle(fontSize: 22)),
              title: const Text(
                'Mural / Chat interno',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: ListenableBuilder(
                listenable: ChatInternoHub.instance,
                builder: (context, _) {
                  final hub = ChatInternoHub.instance;
                  if (hub.temPendentes) {
                    return const Text('Enviando recado pendente...');
                  }
                  return const Text('Recados leves entre terminais');
                },
              ),
              trailing: IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: ChatInternoHub.instance,
              builder: (context, _) {
                final msgs = ChatInternoHub.instance.mensagens;
                if (msgs.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum recado ainda.\nEnvie o primeiro aviso para a equipe.\nUse @caixa @patio @motorista e #1234.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                _agendarScrollInicial();
                if (_grudadoNoFim) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_grudadoNoFim) _irParaFim();
                  });
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _bolha(msgs[i], theme),
                );
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Text(
                    _erro!,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    for (final a in ChatInternoParser.atalhosUi)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            a.rotulo,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _inserirAtalho(a.token),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 8,
                  bottom: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Mensagens rapidas',
                      onPressed: _enviando ? null : () => unawaited(_mostrarFrasesRapidas()),
                      icon: const Icon(Icons.bolt_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => unawaited(_enviar()),
                        decoration: const InputDecoration(
                          hintText: '@caixa #1234 recado rapido...',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _enviando ? null : () => unawaited(_enviar()),
                      child: _enviando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bolha(MensagemInterna m, ThemeData theme) {
    final hora = _fmt.format(m.dataHora.toLocal());
    final paraMim = ChatInternoParser.mencionadaPara(
      ChatInternoHub.instance.perfilUsuario,
      m.mencoes,
    );
    final minha = ChatInternoHub.instance.ehMensagemDesteTerminal(m);
    final scheme = theme.colorScheme;
    const verdeSuave = Color(0xFFDCF8C6);
    final fundo = minha
        ? verdeSuave
        : (paraMim
            ? scheme.tertiaryContainer.withValues(alpha: 0.45)
            : scheme.surface);
    final borda = minha
        ? const Color(0xFFB8E0B0)
        : (paraMim ? scheme.tertiary : const Color(0xFFE2E8F0));
    final maxLargura = MediaQuery.sizeOf(context).width.clamp(320, 420) * 0.78;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLargura),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fundo,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(minha ? 12 : 4),
                bottomRight: Radius.circular(minha ? 4 : 12),
              ),
              border: Border.all(color: borda),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment:
                    minha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          m.vendedor.trim().isNotEmpty
                              ? m.vendedor.trim()
                              : 'Terminal',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (m.pendenteLocal) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Enviando...',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        hora,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (m.ehAutorizacaoPdv)
                    AutorizacaoPdvChatCard(
                      mensagem: m,
                      usuarioLogado: widget.usuarioLogado,
                    )
                  else
                    _textoComPedidos(m.texto, theme),
                  if (!m.ehAutorizacaoPdv && m.mencoes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment:
                          minha ? WrapAlignment.end : WrapAlignment.start,
                      children: [
                        for (final id in m.mencoes)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: Text(
                              '@${ChatInternoParser.rotuloMencao(id)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
