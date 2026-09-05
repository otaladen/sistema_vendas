import 'package:flutter/material.dart';

typedef _PdvAtalhoItem = ({String tecla, String descricao, bool destaque});

/// Tecla + descricao para leitura rapida no PDV.
class PdvAtalhoLinha extends StatelessWidget {
  const PdvAtalhoLinha({
    super.key,
    required this.tecla,
    required this.descricao,
    this.destaque = false,
    this.compacto = false,
  });

  final String tecla;
  final String descricao;
  final bool destaque;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final chip = _TeclaChip(tecla: tecla, destaque: destaque, compacto: compacto);
    final texto = Text(
      descricao,
      maxLines: compacto ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: (compacto ? theme.textTheme.labelSmall : theme.textTheme.bodySmall)
          ?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );

    if (compacto) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          const SizedBox(width: 5),
          texto,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        const SizedBox(height: 5),
        texto,
      ],
    );
  }
}

class _TeclaChip extends StatelessWidget {
  const _TeclaChip({
    required this.tecla,
    required this.destaque,
    required this.compacto,
  });

  final String tecla;
  final bool destaque;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fundo = destaque
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerHighest;
    final texto = destaque ? scheme.onTertiaryContainer : scheme.onSurface;
    final borda = destaque
        ? scheme.tertiary.withValues(alpha: 0.55)
        : scheme.outline.withValues(alpha: 0.35);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 6 : 8,
        vertical: compacto ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        tecla,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
          color: texto,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _PdvAtalhosGrupoCard extends StatelessWidget {
  const _PdvAtalhosGrupoCard({
    required this.titulo,
    required this.itens,
    required this.colunas,
  });

  final String titulo;
  final List<_PdvAtalhoItem> itens;
  final int colunas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    titulo,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final gap = 10.0;
                final itemW =
                    (constraints.maxWidth - gap * (colunas - 1)) / colunas;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in itens)
                      SizedBox(
                        width: itemW,
                        child: PdvAtalhoLinha(
                          tecla: item.tecla,
                          descricao: item.descricao,
                          destaque: item.destaque,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Atalhos gerais abaixo da barra de pesquisa do PDV.
class PdvAtalhosAjudaPesquisa extends StatelessWidget {
  const PdvAtalhosAjudaPesquisa({super.key});

  static const _navegacao = <_PdvAtalhoItem>[
    (tecla: 'Tab', descricao: 'vendedor → entrega → cliente', destaque: false),
    (tecla: 'F6', descricao: 'foco no carrinho', destaque: false),
    (tecla: 'F8', descricao: 'foco na busca', destaque: false),
    (tecla: '↓', descricao: 'busca entra no carrinho', destaque: false),
    (tecla: '↑', descricao: '1º item volta à busca', destaque: false),
  ];

  static const _precoCliente = <_PdvAtalhoItem>[
    (tecla: 'F1–F3', descricao: 'tabela da linha no carrinho', destaque: false),
    (tecla: 'Shift+F2', descricao: 'foco no cliente', destaque: false),
    (tecla: 'Ctrl+N', descricao: 'novo cliente', destaque: false),
    (tecla: 'Shift+F4', descricao: 'lista de clientes', destaque: false),
    (tecla: 'Ctrl+F1–F3', descricao: 'entrega no carrinho', destaque: false),
  ];

  static const _consulta = <_PdvAtalhoItem>[
    (tecla: 'F4', descricao: 'consulta de produtos', destaque: true),
    (tecla: 'Enter', descricao: 'abre consulta', destaque: false),
    (tecla: 'F5', descricao: 'recarrega cadastros', destaque: false),
    (tecla: 'Ctrl+K', descricao: 'limpa busca', destaque: false),
  ];

  static const _carrinho = <_PdvAtalhoItem>[
    (tecla: 'E', descricao: 'entrega da linha', destaque: false),
    (tecla: 'T', descricao: 'tabela da linha', destaque: false),
    (tecla: 'Ctrl+D', descricao: 'divide item', destaque: false),
    (tecla: 'Ctrl+P', descricao: 'altera preço (gerente)', destaque: true),
    (tecla: '+ / −', descricao: 'quantidade', destaque: false),
    (tecla: 'Del', descricao: 'remove linha', destaque: false),
  ];

  static const _fechamento = <_PdvAtalhoItem>[
    (tecla: 'F10', descricao: 'salvar / checkout', destaque: true),
    (tecla: 'F11', descricao: 'calculadora', destaque: true),
    (tecla: 'F12', descricao: 'calculadora de obra', destaque: true),
    (tecla: 'Ctrl+S', descricao: 'salvar orçamento', destaque: false),
    (tecla: 'Ctrl+O', descricao: 'ler orçamento', destaque: false),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final duasColunas = constraints.maxWidth >= 640;
        final colItens = constraints.maxWidth >= 900 ? 3 : 2;

        final colunaEsquerda = <Widget>[
          _PdvAtalhosGrupoCard(
            titulo: 'NAVEGAÇÃO',
            itens: _navegacao,
            colunas: colItens,
          ),
          const SizedBox(height: 8),
          _PdvAtalhosGrupoCard(
            titulo: 'BUSCA',
            itens: _consulta,
            colunas: colItens,
          ),
        ];

        final colunaDireita = <Widget>[
          _PdvAtalhosGrupoCard(
            titulo: 'PREÇO E CLIENTE',
            itens: _precoCliente,
            colunas: colItens,
          ),
          const SizedBox(height: 8),
          _PdvAtalhosGrupoCard(
            titulo: 'CARRINHO',
            itens: _carrinho,
            colunas: colItens,
          ),
          const SizedBox(height: 8),
          _PdvAtalhosGrupoCard(
            titulo: 'FECHAMENTO',
            itens: _fechamento,
            colunas: colItens,
          ),
        ];

        if (!duasColunas) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...colunaEsquerda,
              const SizedBox(height: 8),
              ...colunaDireita,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: colunaEsquerda,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: colunaDireita,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Dica compacta na consulta de produtos do PDV.
class PdvAtalhosAjudaConsulta extends StatelessWidget {
  const PdvAtalhosAjudaConsulta({super.key});

  static const _itens = <_PdvAtalhoItem>[
    (tecla: 'F1–F3', descricao: 'tabela para adicionar', destaque: false),
    (tecla: '+ / −', descricao: 'quantidade no painel', destaque: false),
    (tecla: 'Enter', descricao: 'adiciona selecionado', destaque: true),
    (tecla: 'F7', descricao: 'painel / drawer', destaque: false),
    (tecla: 'F9', descricao: 'detalhes', destaque: false),
    (tecla: 'F8', descricao: 'busca', destaque: false),
    (tecla: '↑↓', descricao: 'lista', destaque: false),
    (tecla: 'Esc', descricao: 'voltar', destaque: false),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _itens.length; i++) ...[
              if (i > 0)
                Text(
                  '·',
                  style: TextStyle(
                    color: scheme.outline,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              PdvAtalhoLinha(
                tecla: _itens[i].tecla,
                descricao: _itens[i].descricao,
                destaque: _itens[i].destaque,
                compacto: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dica compacta acima da lista do carrinho.
class PdvAtalhosAjudaCarrinho extends StatelessWidget {
  const PdvAtalhosAjudaCarrinho({super.key});

  static const _itens = <_PdvAtalhoItem>[
    (tecla: 'Clique', descricao: 'detalhes à direita', destaque: false),
    (tecla: '↑↓', descricao: 'troca item', destaque: false),
    (tecla: '+ / −', descricao: 'quantidade', destaque: false),
    (tecla: 'E', descricao: 'entrega', destaque: false),
    (tecla: 'T', descricao: 'tabela', destaque: false),
    (tecla: 'Ctrl+D', descricao: 'dividir', destaque: false),
    (tecla: 'Ctrl+P', descricao: 'preço', destaque: true),
    (tecla: 'Del', descricao: 'remove', destaque: false),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _itens.length; i++) ...[
              if (i > 0)
                Text(
                  '·',
                  style: TextStyle(
                    color: scheme.outline,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              PdvAtalhoLinha(
                tecla: _itens[i].tecla,
                descricao: _itens[i].descricao,
                destaque: _itens[i].destaque,
                compacto: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
