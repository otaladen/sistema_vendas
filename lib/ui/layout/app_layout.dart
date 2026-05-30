import 'package:flutter/material.dart';

/// Quebras de layout: desktop mantem o leiaute atual do ERP (PC).
abstract final class AppBreakpoints {
  /// Abaixo disso: celular / leiaute compacto.
  static const double compact = 600;

  /// A partir daqui: mesmo comportamento visual do PC.
  static const double desktop = 900;
}

/// Acesso rapido ao modo de tela.
extension AppLayoutContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  bool get isCompactLayout => screenWidth < AppBreakpoints.compact;

  bool get isMobileLayout => screenWidth < AppBreakpoints.desktop;

  /// Leiaute PC completo (inalterado em relacao ao desenvolvimento original).
  bool get isDesktopLayout => screenWidth >= AppBreakpoints.desktop;
}

/// Corpo de pagina com rolagem e margens seguras no celular.
class AdaptivePageBody extends StatelessWidget {
  const AdaptivePageBody({
    super.key,
    required this.child,
    this.padding,
    this.desktopPadding,
    this.alwaysScroll = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? desktopPadding;
  final bool alwaysScroll;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompactLayout;
    final resolvedPadding = compact
        ? (padding ?? const EdgeInsets.all(12))
        : (desktopPadding ?? padding ?? const EdgeInsets.all(16));

    final content = Padding(padding: resolvedPadding, child: child);

    if (compact || alwaysScroll) {
      return SafeArea(
        child: SingleChildScrollView(
          child: content,
        ),
      );
    }
    return SafeArea(child: content);
  }
}

/// Corpo do menu principal com largura maxima e rolagem.
class MainMenuBody extends StatelessWidget {
  const MainMenuBody({
    super.key,
    required this.child,
    this.maxContentWidth = 1080,
  });

  final Widget child;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final padding = context.isCompactLayout
        ? const EdgeInsets.fromLTRB(12, 12, 12, 20)
        : const EdgeInsets.fromLTRB(20, 16, 20, 28);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Grade responsiva para tiles do menu (1, 2 ou 3 colunas).
class MainMenuTileGrid extends StatelessWidget {
  const MainMenuTileGrid({
    super.key,
    required this.tiles,
    this.spacing = 12,
  });

  final List<Widget> tiles;
  final double spacing;

  int _colunas(double largura) {
    if (largura >= AppBreakpoints.desktop) return 3;
    if (largura >= AppBreakpoints.compact) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _colunas(constraints.maxWidth);
        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                tiles[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += cols) {
          final slice = tiles.sublist(
            i,
            i + cols > tiles.length ? tiles.length : i + cols,
          );
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < cols; j++)
                  Expanded(
                    child: j < slice.length
                        ? Padding(
                            padding: EdgeInsets.only(
                              right: j < cols - 1 ? spacing / 2 : 0,
                              left: j > 0 ? spacing / 2 : 0,
                            ),
                            child: slice[j],
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          );
          if (i + cols < tiles.length) {
            rows.add(SizedBox(height: spacing));
          }
        }
        return Column(children: rows);
      },
    );
  }
}

/// Lista de hub (menu, cadastros): coluna com rolagem quando a altura nao cabe.
class AdaptiveHubBody extends StatelessWidget {
  const AdaptiveHubBody({
    super.key,
    required this.children,
    this.spacing = 12,
    this.maxContentWidth = 520,
  });

  final List<Widget> children;
  final double spacing;

  /// Largura maxima dos botoes no menu (centralizado em telas largas).
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );

    final padding = context.isCompactLayout
        ? const EdgeInsets.fromLTRB(12, 12, 12, 20)
        : const EdgeInsets.fromLTRB(16, 16, 16, 24);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final larguraMax = context.isDesktopLayout
              ? constraints.maxWidth
              : maxContentWidth;
          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: larguraMax),
                  child: column,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Largura maxima de dialogos: no PC usa [desktopWidth]; no celular quase tela cheia.
double adaptiveDialogWidth(
  BuildContext context, {
  required double desktopWidth,
  double horizontalMargin = 24,
}) {
  if (context.isDesktopLayout) {
    return desktopWidth;
  }
  final w = context.screenWidth - horizontalMargin * 2;
  return w.clamp(280, desktopWidth);
}

/// Conteudo de dialogo com largura adaptativa.
class AdaptiveDialogContent extends StatelessWidget {
  const AdaptiveDialogContent({
    super.key,
    required this.desktopWidth,
    required this.child,
    this.horizontalMargin = 24,
  });

  final double desktopWidth;
  final Widget child;
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: adaptiveDialogWidth(
        context,
        desktopWidth: desktopWidth,
        horizontalMargin: horizontalMargin,
      ),
      child: child,
    );
  }
}

/// Painel de dialogo com largura e altura opcional (listas / checkout).
class AdaptiveDialogPane extends StatelessWidget {
  const AdaptiveDialogPane({
    super.key,
    required this.desktopWidth,
    required this.child,
    this.desktopHeight,
    this.mobileHeightFactor = 0.72,
    this.horizontalMargin = 24,
  });

  final double desktopWidth;
  final Widget child;
  final double? desktopHeight;
  final double mobileHeightFactor;
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = adaptiveDialogWidth(
      context,
      desktopWidth: desktopWidth,
      horizontalMargin: horizontalMargin,
    );
    double? height = desktopHeight;
    if (height != null && !context.isDesktopLayout) {
      height = screen.height * mobileHeightFactor;
    }
    return SizedBox(width: width, height: height, child: child);
  }
}

/// Altura maxima de listas dentro de dialogos.
double adaptiveDialogListMaxHeight(
  BuildContext context, {
  double desktopFactor = 0.58,
  double mobileFactor = 0.42,
}) {
  final h = MediaQuery.sizeOf(context).height;
  return h *
      (context.isDesktopLayout ? desktopFactor : mobileFactor);
}

/// Row no desktop, Column no celular (ex.: login, formularios largos).
class AdaptiveRowColumn extends StatelessWidget {
  const AdaptiveRowColumn({
    super.key,
    required this.children,
    this.breakpoint = AppBreakpoints.desktop,
    this.spacing = 16,
    this.rowCrossAxisAlignment = CrossAxisAlignment.start,
    this.columnCrossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;
  final CrossAxisAlignment rowCrossAxisAlignment;
  final CrossAxisAlignment columnCrossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final useRow = context.screenWidth >= breakpoint;
    if (useRow) {
      return Row(
        crossAxisAlignment: rowCrossAxisAlignment,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: children[i]),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: columnCrossAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );
  }
}

/// Barra inferior de acoes (assistente): empilha botoes no celular.
class AdaptiveBottomActions extends StatelessWidget {
  const AdaptiveBottomActions({
    super.key,
    required this.leading,
    required this.primary,
    this.secondary,
  });

  final Widget leading;
  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopLayout) {
      return Row(
        children: [
          leading,
          const Spacer(),
          if (secondary != null) ...[
            secondary!,
            const SizedBox(width: 8),
          ],
          primary,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        leading,
        const SizedBox(height: 8),
        if (secondary != null) ...[
          secondary!,
          const SizedBox(height: 8),
        ],
        primary,
      ],
    );
  }
}

/// Ajusta tema (densidade e dialogos) sem alterar o PC.
Widget buildAdaptiveAppShell(BuildContext context, Widget? child) {
  final desktop = context.isDesktopLayout;
  final theme = Theme.of(context);
  final inset = desktop
      ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24)
      : const EdgeInsets.symmetric(horizontal: 16, vertical: 20);

  return Theme(
    data: theme.copyWith(
      visualDensity:
          desktop ? VisualDensity.standard : VisualDensity.compact,
      dialogTheme: theme.dialogTheme.copyWith(insetPadding: inset),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}
