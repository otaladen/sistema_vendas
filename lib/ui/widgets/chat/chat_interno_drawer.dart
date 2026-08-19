import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/sync/entregas_foco_hub.dart';
import '../../../domain/chat_interno_parser.dart';
import '../../../domain/main_menu_destino.dart';
import '../../../domain/usuario_permissao_helper.dart';
import '../../../model/mensagem_interna.dart';
import '../../shell/app_shell_scope.dart';
import '../../shell/main_menu_deps.dart';
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
    final usuario = MainMenuDeps.maybeOf(context)?.usuarioLogado;
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
  const _ChatInternoPainel({this.onAbrirEntregas});

  final VoidCallback? onAbrirEntregas;

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

  void _abrirPedido(int numero) {
    EntregasFocoHub.instance.focarPedido(numero);
    Navigator.of(context).maybePop();
    widget.onAbrirEntregas?.call();
    if (widget.onAbrirEntregas == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Abra Entregas e busque o pedido #$numero.')),
      );
    }
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
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                _erro!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final a in ChatInternoParser.atalhosUi)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(a.rotulo, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _inserirAtalho(a.token),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
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
    );
  }

  Widget _bolha(MensagemInterna m, ThemeData theme) {
    final hora = _fmt.format(m.dataHora.toLocal());
    final paraMim = ChatInternoParser.mencionadaPara(
      ChatInternoHub.instance.perfilUsuario,
      m.mencoes,
    );
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: paraMim
              ? scheme.tertiaryContainer.withValues(alpha: 0.55)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: paraMim ? scheme.tertiary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.vendedor,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (m.pendenteLocal)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Enviando...',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  Text(
                    hora,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(m.texto, style: theme.textTheme.bodyMedium),
              if (m.mencoes.isNotEmpty || m.pedidoNumero > 0) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final id in m.mencoes)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          '@${ChatInternoParser.rotuloMencao(id)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    if (m.pedidoNumero > 0)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.local_shipping_outlined, size: 16),
                        label: Text(
                          'Pedido #${m.pedidoNumero}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _abrirPedido(m.pedidoNumero),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
