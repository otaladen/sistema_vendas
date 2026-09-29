import 'package:flutter/material.dart';

import '../../domain/produto_categorias_catalogo.dart';
import 'search_text_field.dart';

class SelecaoCategoriaProduto {
  const SelecaoCategoriaProduto({
    required this.categoria,
    this.subcategoria,
  });

  final String categoria;
  final String? subcategoria;
}

Future<SelecaoCategoriaProduto?> showSeletorCategoriaProduto(
  BuildContext context, {
  String? categoriaAtual,
  String? subcategoriaAtual,
}) {
  return showDialog<SelecaoCategoriaProduto>(
    context: context,
    builder: (ctx) => SeletorCategoriaProdutoDialog(
      categoriaAtual: categoriaAtual,
      subcategoriaAtual: subcategoriaAtual,
    ),
  );
}

class SeletorCategoriaProdutoDialog extends StatefulWidget {
  const SeletorCategoriaProdutoDialog({
    super.key,
    this.categoriaAtual,
    this.subcategoriaAtual,
  });

  final String? categoriaAtual;
  final String? subcategoriaAtual;

  @override
  State<SeletorCategoriaProdutoDialog> createState() =>
      _SeletorCategoriaProdutoDialogState();
}

class _SeletorCategoriaProdutoDialogState
    extends State<SeletorCategoriaProdutoDialog> {
  final _busca = TextEditingController();
  final _chavesCategoria = <String, GlobalKey>{};
  late String? _categoria;
  late String? _subcategoria;
  var _mostrandoSubcategorias = false;

  @override
  void initState() {
    super.initState();
    _categoria = widget.categoriaAtual;
    _subcategoria = widget.subcategoriaAtual;
    if (_categoria != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _chavesCategoria[_categoria]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.3);
        }
      });
    }
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  GlobalKey _chaveDe(String categoria) =>
      _chavesCategoria.putIfAbsent(categoria, GlobalKey.new);

  void _confirmar() {
    final categoria = _categoria;
    if (categoria == null) return;
    if (categoria != ProdutoCategoriasCatalogo.outros &&
        (_subcategoria == null || _subcategoria!.trim().isEmpty)) {
      return;
    }
    Navigator.pop(
      context,
      SelecaoCategoriaProduto(
        categoria: categoria,
        subcategoria: categoria == ProdutoCategoriasCatalogo.outros
            ? null
            : _subcategoria,
      ),
    );
  }

  void _escolherSubcategoria(String subcategoria) {
    final categoria = _categoria;
    if (categoria == null) return;
    Navigator.pop(
      context,
      SelecaoCategoriaProduto(
        categoria: categoria,
        subcategoria: subcategoria,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consulta = _busca.text.trim();
    final podeConfirmar = _categoria != null &&
        (_categoria == ProdutoCategoriasCatalogo.outros ||
            (_subcategoria != null && _subcategoria!.trim().isNotEmpty));
    final tela = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: (tela.width - 48).clamp(320, 880).toDouble(),
        height: (tela.height - 48).clamp(360, 640).toDouble(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Classificacao',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'Setores da loja, com categoria e subcategoria. '
                'Busque pelo nome ou navegue a lista.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SearchTextField(
                controller: _busca,
                hintText: 'Buscar categoria ou subcategoria',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: consulta.isEmpty
                    ? _painelNavegacao(context)
                    : _painelBusca(context, consulta),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _rotuloSelecao(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: podeConfirmar ? _confirmar : null,
                    child: const Text('Confirmar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _rotuloSelecao() {
    final categoria = _categoria;
    if (categoria == null) return 'Nenhuma categoria selecionada';
    final setor = ProdutoCategoriasCatalogo.setorDe(categoria);
    final prefixo = setor == null ? categoria : '$setor · $categoria';
    if (categoria == ProdutoCategoriasCatalogo.outros) {
      return '$prefixo · texto livre';
    }
    final sub = _subcategoria;
    if (sub == null || sub.trim().isEmpty) {
      return '$prefixo · escolha a subcategoria';
    }
    return '$prefixo · $sub';
  }

  Widget _painelNavegacao(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ladoALado = constraints.maxWidth >= 640;
        final categorias = _listaCategorias(context);
        final subcategorias = _listaSubcategorias(context);
        if (!ladoALado) {
          if (_mostrandoSubcategorias && _categoria != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _mostrandoSubcategorias = false),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Categorias'),
                  ),
                ),
                Expanded(child: subcategorias),
              ],
            );
          }
          return categorias;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 300, child: categorias),
            const VerticalDivider(width: 24),
            Expanded(child: subcategorias),
          ],
        );
      },
    );
  }

  Widget _listaCategorias(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        for (final setor in ProdutoCategoriasCatalogo.setores) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Text(
              setor.nome.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final categoria in setor.categorias)
            ListTile(
              key: _chaveDe(categoria),
              dense: true,
              selected: categoria == _categoria,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(categoria),
              subtitle: Text(
                _resumoSubcategorias(categoria),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                setState(() {
                  _categoria = categoria;
                  final subs =
                      ProdutoCategoriasCatalogo.subcategoriasDe(categoria);
                  if (!subs.contains(_subcategoria)) {
                    _subcategoria = null;
                  }
                  _mostrandoSubcategorias = true;
                });
              },
            ),
        ],
      ],
    );
  }

  String _resumoSubcategorias(String categoria) {
    if (categoria == ProdutoCategoriasCatalogo.outros) {
      return 'Subcategoria digitada no cadastro';
    }
    final subs = ProdutoCategoriasCatalogo.subcategoriasDe(categoria);
    if (subs.isEmpty) return 'Sem subcategorias';
    return subs.take(3).join(', ');
  }

  Widget _listaSubcategorias(BuildContext context) {
    final theme = Theme.of(context);
    final categoria = _categoria;
    if (categoria == null) {
      return Center(
        child: Text(
          'Escolha uma categoria para ver as subcategorias.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (categoria == ProdutoCategoriasCatalogo.outros) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Outros usa uma subcategoria livre, digitada no formulario '
            'depois de confirmar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final subs = ProdutoCategoriasCatalogo.subcategoriasDe(categoria);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(categoria, style: theme.textTheme.titleSmall),
        Text(
          ProdutoCategoriasCatalogo.setorDe(categoria) ?? '',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: subs.length,
            itemBuilder: (context, index) {
              final sub = subs[index];
              final selecionada = sub == _subcategoria;
              return ListTile(
                dense: true,
                selected: selecionada,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Text(sub),
                trailing: selecionada
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => _escolherSubcategoria(sub),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _painelBusca(BuildContext context, String consulta) {
    final theme = Theme.of(context);
    final q = ProdutoCategoriasCatalogo.normalizar(consulta);
    final itens = <_ResultadoBusca>[];

    for (final setor in ProdutoCategoriasCatalogo.setores) {
      final setorNorm = ProdutoCategoriasCatalogo.normalizar(setor.nome);
      for (final categoria in setor.categorias) {
        final catNorm = ProdutoCategoriasCatalogo.normalizar(categoria);
        final categoriaCasa = catNorm.contains(q) || setorNorm.contains(q);
        if (categoria == ProdutoCategoriasCatalogo.outros) {
          if (categoriaCasa || catNorm.contains(q)) {
            itens.add(
              _ResultadoBusca(
                setor: setor.nome,
                categoria: categoria,
              ),
            );
          }
          continue;
        }
        final subs = ProdutoCategoriasCatalogo.subcategoriasDe(categoria);
        for (final sub in subs) {
          final subNorm = ProdutoCategoriasCatalogo.normalizar(sub);
          if (categoriaCasa || subNorm.contains(q)) {
            itens.add(
              _ResultadoBusca(
                setor: setor.nome,
                categoria: categoria,
                subcategoria: sub,
              ),
            );
          }
        }
      }
    }

    if (itens.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma categoria ou subcategoria encontrada.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: itens.length,
      itemBuilder: (context, index) {
        final item = itens[index];
        final sub = item.subcategoria;
        return ListTile(
          dense: true,
          title: Text(sub ?? item.categoria),
          subtitle: Text(
            sub == null
                ? '${item.setor} · texto livre'
                : '${item.setor} · ${item.categoria}',
          ),
          onTap: () {
            Navigator.pop(
              context,
              SelecaoCategoriaProduto(
                categoria: item.categoria,
                subcategoria: sub,
              ),
            );
          },
        );
      },
    );
  }
}

class _ResultadoBusca {
  const _ResultadoBusca({
    required this.setor,
    required this.categoria,
    this.subcategoria,
  });

  final String setor;
  final String categoria;
  final String? subcategoria;
}
