import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_interno_hub.dart';

class ChatInternoCampoMensagem extends StatefulWidget {
  const ChatInternoCampoMensagem({
    super.key,
    required this.controller,
    required this.enviando,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final bool enviando;
  final VoidCallback onEnviar;

  @override
  State<ChatInternoCampoMensagem> createState() =>
      _ChatInternoCampoMensagemState();
}

class _ChatInternoCampoMensagemState extends State<ChatInternoCampoMensagem> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  int _sugestaoIndice = 0;
  List<({String token, String rotulo, String? subtitulo})> _sugestoes =
      const [];
  bool _mencaoAtiva = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTexto);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTexto);
    _fecharOverlay();
    super.dispose();
  }

  void _onTexto() {
    unawaited(_atualizarMencao());
  }

  Future<void> _atualizarMencao() async {
    final texto = widget.controller.text;
    final sel = widget.controller.selection.baseOffset;
    if (sel < 0) {
      _fecharOverlay();
      return;
    }
    final prefixo = texto.substring(0, sel);
    final at = prefixo.lastIndexOf('@');
    if (at < 0) {
      _fecharOverlay();
      return;
    }
    if (at > 0) {
      final antes = prefixo[at - 1];
      if (RegExp(r'[\w]').hasMatch(antes)) {
        _fecharOverlay();
        return;
      }
    }
    final frag = prefixo.substring(at + 1);
    if (frag.contains(' ') || frag.contains('\n')) {
      _fecharOverlay();
      return;
    }
    final lista = await ChatInternoHub.instance.listarSugestoesMencao(frag);
    if (!mounted) return;
    if (lista.isEmpty) {
      _fecharOverlay();
      return;
    }
    setState(() {
      _mencaoAtiva = true;
      _sugestoes = lista;
      _sugestaoIndice = 0;
    });
    _mostrarOverlay();
  }

  void _mostrarOverlay() {
    if (_overlay == null) {
      _overlay = OverlayEntry(
        builder: (ctx) {
          return Positioned(
            width: 280,
            child: CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -8),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _sugestoes.length,
                    itemBuilder: (context, i) {
                      final s = _sugestoes[i];
                      final sel = i == _sugestaoIndice;
                      return ListTile(
                        dense: true,
                        selected: sel,
                        title: Text('@${s.token}'),
                        subtitle: Text(
                          s.subtitulo ?? s.rotulo,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => _aplicarSugestao(s.token),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      );
      Overlay.maybeOf(context)?.insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _fecharOverlay() {
    if (!_mencaoAtiva && _overlay == null) return;
    _mencaoAtiva = false;
    _sugestoes = const [];
    _overlay?.remove();
    _overlay = null;
  }

  void _aplicarSugestao(String token) {
    final texto = widget.controller.text;
    final sel = widget.controller.selection.baseOffset;
    if (sel < 0) return;
    final prefixo = texto.substring(0, sel);
    final at = prefixo.lastIndexOf('@');
    if (at < 0) return;
    final suffix = texto.substring(sel);
    final inserir = '@$token ';
    widget.controller.text = '${texto.substring(0, at)}$inserir$suffix';
    widget.controller.selection = TextSelection.collapsed(
      offset: at + inserir.length,
    );
    _fecharOverlay();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_mencaoAtiva || _sugestoes.isEmpty) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _sugestaoIndice = (_sugestaoIndice + 1) % _sugestoes.length;
      });
      _overlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _sugestaoIndice =
            (_sugestaoIndice - 1 + _sugestoes.length) % _sugestoes.length;
      });
      _overlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _aplicarSugestao(_sugestoes[_sugestaoIndice].token);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _fecharOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        onKeyEvent: _onKey,
        child: TextField(
          controller: widget.controller,
          enabled: !widget.enviando,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) {
            if (_mencaoAtiva && _sugestoes.isNotEmpty) {
              _aplicarSugestao(_sugestoes[_sugestaoIndice].token);
              return;
            }
            if (!widget.enviando) widget.onEnviar();
          },
          decoration: const InputDecoration(
            hintText: '@caixa #1234 recado rapido...',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
