import 'package:flutter/material.dart';

/// Estado de um chip de resumo no topo de um cartao de configuracao.
enum ConfigResumoTom { ativo, inativo, alerta }

class ConfigResumoItem {
  const ConfigResumoItem(this.texto, {this.tom = ConfigResumoTom.ativo});

  const ConfigResumoItem.ativo(this.texto) : tom = ConfigResumoTom.ativo;
  const ConfigResumoItem.inativo(this.texto) : tom = ConfigResumoTom.inativo;
  const ConfigResumoItem.alerta(this.texto) : tom = ConfigResumoTom.alerta;

  final String texto;
  final ConfigResumoTom tom;
}

/// Faixa de chips que resume, em uma olhada, como o cartao esta configurado.
class ConfigResumoChips extends StatelessWidget {
  const ConfigResumoChips({super.key, required this.itens});

  final List<ConfigResumoItem> itens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in itens)
          _Chip(
            texto: item.texto,
            fundo: switch (item.tom) {
              ConfigResumoTom.ativo =>
                scheme.primaryContainer.withValues(alpha: 0.55),
              ConfigResumoTom.inativo =>
                scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              ConfigResumoTom.alerta =>
                scheme.errorContainer.withValues(alpha: 0.6),
            },
            cor: switch (item.tom) {
              ConfigResumoTom.ativo => scheme.onPrimaryContainer,
              ConfigResumoTom.inativo => scheme.onSurfaceVariant,
              ConfigResumoTom.alerta => scheme.onErrorContainer,
            },
            estilo: theme.textTheme.labelSmall,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.texto,
    required this.fundo,
    required this.cor,
    required this.estilo,
  });

  final String texto;
  final Color fundo;
  final Color cor;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          texto,
          style: estilo?.copyWith(color: cor, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Switch compacto: o subtitulo fica em uma linha e a explicacao longa vai para
/// o tooltip do (i), o que evita cartoes com mais texto do que controle.
class ConfigSwitchTile extends StatelessWidget {
  const ConfigSwitchTile({
    super.key,
    required this.titulo,
    required this.resumo,
    required this.valor,
    required this.onChanged,
    this.detalhe,
    this.motivoDesabilitado,
  });

  final String titulo;

  /// Uma linha, no imperativo do efeito ("Obriga informar quem vendeu").
  final String resumo;

  /// Texto completo, exibido no tooltip do icone de informacao.
  final String? detalhe;

  final bool valor;
  final ValueChanged<bool>? onChanged;

  /// Quando [onChanged] e nulo, explica por que o controle esta indisponivel.
  final String? motivoDesabilitado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desabilitado = onChanged == null;
    final legenda = desabilitado ? (motivoDesabilitado ?? resumo) : resumo;

    return InkWell(
      onTap: desabilitado ? null : () => onChanged!(!valor),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titulo,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: desabilitado ? theme.disabledColor : null,
                          ),
                        ),
                      ),
                      if (detalhe != null) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: detalhe!,
                          triggerMode: TooltipTriggerMode.tap,
                          showDuration: const Duration(seconds: 12),
                          child: Icon(
                            Icons.info_outline,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    legenda,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: desabilitado
                          ? theme.disabledColor
                          : scheme.onSurfaceVariant,
                      fontStyle: desabilitado ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(value: valor, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Bloco de opcoes que so existem quando a opcao pai esta ligada. Aparece e
/// desaparece com o pai, em vez de ficar cinza sem explicar o motivo.
class ConfigSubGrupo extends StatelessWidget {
  const ConfigSubGrupo({
    super.key,
    required this.visivel,
    required this.children,
  });

  final bool visivel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visivel
          ? Container(
              margin: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scheme.primary.withValues(alpha: 0.4), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Faixa de feedback sob um campo numerico (simulacao de desconto, aviso).
class ConfigLinhaSimulacao extends StatelessWidget {
  const ConfigLinhaSimulacao({
    super.key,
    required this.texto,
    this.alerta = false,
  });

  final String texto;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cor = alerta ? scheme.error : scheme.primary;
    final fundo = alerta
        ? scheme.errorContainer.withValues(alpha: 0.45)
        : scheme.primaryContainer.withValues(alpha: 0.38);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              alerta ? Icons.error_outline : Icons.calculate_outlined,
              size: 18,
              color: cor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: alerta ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtitulo de grupo dentro de um cartao.
class ConfigGrupoTitulo extends StatelessWidget {
  const ConfigGrupoTitulo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        texto.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
