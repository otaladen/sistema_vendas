import 'package:flutter/material.dart';

import '../../domain/entregas/loja_origem_mercadoria.dart';

/// Caixa compacta: loja atual ou outra loja (sem digitar nome).
class OrigemMaterialCaixa extends StatelessWidget {
  const OrigemMaterialCaixa({
    super.key,
    required this.valor,
    required this.onChanged,
    this.enabled = true,
  });

  final String valor;
  final ValueChanged<String> onChanged;
  final bool enabled;

  static const _kLocal = '__local__';

  @override
  Widget build(BuildContext context) {
    final atual = LojaOrigemMercadoria.normalizar(valor);
    final String valorDrop;
    if (LojaOrigemMercadoria.ehMisto(atual)) {
      valorDrop = LojaOrigemMercadoria.misto;
    } else if (LojaOrigemMercadoria.ehLocal(atual)) {
      valorDrop = _kLocal;
    } else {
      valorDrop = LojaOrigemMercadoria.outraLoja;
    }
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 188,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          border: const OutlineInputBorder(),
          enabled: enabled,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isDense: true,
            isExpanded: true,
            value: valorDrop,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: enabled
                      ? scheme.onSurface
                      : scheme.onSurface.withValues(alpha: 0.55),
                ),
            items: [
              const DropdownMenuItem(
                value: LojaOrigemMercadoria.outraLoja,
                child: Text(LojaOrigemMercadoria.outraLoja),
              ),
              const DropdownMenuItem(
                value: _kLocal,
                child: Text(
                  LojaOrigemMercadoria.saidaLojaAtual,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (LojaOrigemMercadoria.ehMisto(atual))
                const DropdownMenuItem(
                  value: LojaOrigemMercadoria.misto,
                  enabled: false,
                  child: Text(LojaOrigemMercadoria.misto),
                ),
            ],
            onChanged: enabled
                ? (v) {
                    if (v == null || v == LojaOrigemMercadoria.misto) return;
                    onChanged(
                      v == _kLocal
                          ? LojaOrigemMercadoria.local
                          : LojaOrigemMercadoria.outraLoja,
                    );
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
