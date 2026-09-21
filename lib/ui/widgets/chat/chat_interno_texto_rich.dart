import 'package:flutter/material.dart';

import '../../../domain/chat_interno_parser.dart';

/// Texto do mural com #pedido clicavel e @mencoes destacadas.
class ChatInternoTextoRich extends StatelessWidget {
  const ChatInternoTextoRich({
    super.key,
    required this.texto,
    required this.theme,
    this.onPedido,
  });

  final String texto;
  final ThemeData theme;
  final void Function(int numero)? onPedido;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final pedidoRe = ChatInternoParser.pedidoNumeroPattern;
    final mencaoRe = ChatInternoParser.mencaoNoTextoPattern;
    final eventos = <_Trecho>[];
    for (final m in pedidoRe.allMatches(texto)) {
      eventos.add(_Trecho(m.start, m.end, _TrechoTipo.pedido, m.group(0) ?? ''));
    }
    for (final m in mencaoRe.allMatches(texto)) {
      eventos.add(_Trecho(m.start, m.end, _TrechoTipo.mencao, m.group(0) ?? ''));
    }
    eventos.sort((a, b) => a.inicio.compareTo(b.inicio));
    final partes = <InlineSpan>[];
    var cursor = 0;
    for (final ev in eventos) {
      if (ev.inicio < cursor) continue;
      if (ev.inicio > cursor) {
        partes.add(TextSpan(text: texto.substring(cursor, ev.inicio)));
      }
      if (ev.tipo == _TrechoTipo.mencao) {
        partes.add(
          TextSpan(
            text: ev.valor,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              backgroundColor: scheme.primaryContainer.withValues(alpha: 0.55),
            ),
          ),
        );
      } else {
        final n = int.tryParse(
              RegExp(r'#(\d+)').firstMatch(ev.valor)?.group(1) ?? '',
            ) ??
            0;
        partes.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(ev.valor, style: const TextStyle(fontSize: 12)),
                onPressed:
                    n > 0 && onPedido != null ? () => onPedido!(n) : null,
              ),
            ),
          ),
        );
      }
      cursor = ev.fim;
    }
    if (cursor < texto.length) {
      partes.add(TextSpan(text: texto.substring(cursor)));
    }
    if (partes.isEmpty) {
      return Text(texto, style: theme.textTheme.bodyMedium);
    }
    return Text.rich(
      TextSpan(style: theme.textTheme.bodyMedium, children: partes),
    );
  }
}

enum _TrechoTipo { pedido, mencao }

class _Trecho {
  _Trecho(this.inicio, this.fim, this.tipo, this.valor);

  final int inicio;
  final int fim;
  final _TrechoTipo tipo;
  final String valor;
}
