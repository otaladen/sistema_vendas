import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/produto_repository.dart';
import '../../domain/sugestao_venda_tipo.dart';
import '../../model/produto.dart';
import '../../model/produto_sugestao_venda.dart';

/// Rascunho de sugestao de venda no cadastro de produto.
class SugestaoVendaCadastroDraft {
  SugestaoVendaCadastroDraft({
    required this.produtoSugeridoId,
    this.tipo = SugestaoVendaTipo.complementar,
    this.quantidadeSugerida = 1,
    this.prioridade = 0,
    this.observacao = '',
    this.ativo = true,
  });

  factory SugestaoVendaCadastroDraft.fromEntity(ProdutoSugestaoVenda s) {
    return SugestaoVendaCadastroDraft(
      produtoSugeridoId: s.produtoSugeridoId,
      tipo: SugestaoVendaTipo.fromCodigo(s.tipo),
      quantidadeSugerida: s.quantidadeSugerida,
      prioridade: s.prioridade,
      observacao: s.observacao,
      ativo: s.ativo,
    );
  }

  int produtoSugeridoId;
  SugestaoVendaTipo tipo;
  int quantidadeSugerida;
  int prioridade;
  String observacao;
  bool ativo;
}

/// Card de sugestoes de venda (produtos agregados) no cadastro.
class ProdutosSugestoesVendaSection extends StatelessWidget {
  const ProdutosSugestoesVendaSection({
    super.key,
    required this.produtoRepository,
    required this.sugestoes,
    required this.onChanged,
    this.produtoEmEdicaoId,
  });

  final ProdutoRepository produtoRepository;
  final List<SugestaoVendaCadastroDraft> sugestoes;
  final ValueChanged<List<SugestaoVendaCadastroDraft>> onChanged;
  final int? produtoEmEdicaoId;

  Future<void> _adicionar(BuildContext context) async {
    final draft = await showDialog<SugestaoVendaCadastroDraft>(
      context: context,
      builder: (ctx) => _SugestaoVendaDialog(
        produtoRepository: produtoRepository,
        produtoEmEdicaoId: produtoEmEdicaoId,
        idsJaUsados: sugestoes.map((s) => s.produtoSugeridoId).toSet(),
      ),
    );
    if (draft == null) return;
    final prioridade = sugestoes.isEmpty ? 0 : sugestoes.length * 10;
    onChanged([
      ...sugestoes,
      SugestaoVendaCadastroDraft(
        produtoSugeridoId: draft.produtoSugeridoId,
        tipo: draft.tipo,
        quantidadeSugerida: draft.quantidadeSugerida,
        prioridade: prioridade,
        observacao: draft.observacao,
        ativo: draft.ativo,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sugestoes para o vendedor',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Aparecem na consulta PDV em "Ofereca tambem" (badge Sugestao).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (sugestoes.isEmpty)
          Text(
            'Nenhuma sugestao cadastrada.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < sugestoes.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _SugestaoLinha(
                  nome: produtoRepository
                          .obterPorId(sugestoes[i].produtoSugeridoId)
                          ?.nome ??
                      '#${sugestoes[i].produtoSugeridoId}',
                  draft: sugestoes[i],
                  onRemover: () {
                    final copia = List<SugestaoVendaCadastroDraft>.from(sugestoes);
                    copia.removeAt(i);
                    onChanged(copia);
                  },
                ),
              ],
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _adicionar(context),
            icon: const Icon(Icons.playlist_add_outlined),
            label: const Text('Adicionar sugestao'),
          ),
        ),
      ],
    );
  }
}

class _SugestaoLinha extends StatelessWidget {
  const _SugestaoLinha({
    required this.nome,
    required this.draft,
    required this.onRemover,
  });

  final String nome;
  final SugestaoVendaCadastroDraft draft;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${draft.tipo.rotulo} · ${draft.quantidadeSugerida} un.'
                    '${draft.observacao.trim().isNotEmpty ? ' · ${draft.observacao.trim()}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remover',
              onPressed: onRemover,
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _SugestaoVendaDialog extends StatefulWidget {
  const _SugestaoVendaDialog({
    required this.produtoRepository,
    required this.produtoEmEdicaoId,
    required this.idsJaUsados,
  });

  final ProdutoRepository produtoRepository;
  final int? produtoEmEdicaoId;
  final Set<int> idsJaUsados;

  @override
  State<_SugestaoVendaDialog> createState() => _SugestaoVendaDialogState();
}

class _SugestaoVendaDialogState extends State<_SugestaoVendaDialog> {
  final _buscaCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _obsCtrl = TextEditingController();
  SugestaoVendaTipo _tipo = SugestaoVendaTipo.complementar;
  List<Produto> _resultados = const [];
  Produto? _selecionado;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _qtyCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  void _buscar() {
    final termo = _buscaCtrl.text.trim();
    if (termo.length < 2) {
      setState(() => _resultados = const []);
      return;
    }
    final todos = widget.produtoRepository
        .pesquisarPadraoPdv(termo)
        .where((p) => p.ativo)
        .take(40)
        .toList();
    setState(() => _resultados = todos);
  }

  void _confirmar() {
    final p = _selecionado;
    if (p == null) return;
    if (p.id == widget.produtoEmEdicaoId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O produto nao pode sugerir a si mesmo.'),
        ),
      );
      return;
    }
    if (widget.idsJaUsados.contains(p.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto ja esta na lista.')),
      );
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade sugerida invalida.')),
      );
      return;
    }
    Navigator.pop(
      context,
      SugestaoVendaCadastroDraft(
        produtoSugeridoId: p.id,
        tipo: _tipo,
        quantidadeSugerida: qty,
        observacao: _obsCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sugestao de venda'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _buscaCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar produto',
                suffixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _buscar(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _buscar,
                child: const Text('Buscar'),
              ),
            ),
            SizedBox(
              height: 160,
              child: _resultados.isEmpty
                  ? const Center(child: Text('Digite e busque um produto.'))
                  : ListView.builder(
                      itemCount: _resultados.length,
                      itemBuilder: (_, i) {
                        final p = _resultados[i];
                        final sel = _selecionado?.id == p.id;
                        return ListTile(
                          dense: true,
                          selected: sel,
                          title: Text(p.nome, maxLines: 1),
                          subtitle: Text(
                            p.codigoInterno.trim().isNotEmpty
                                ? 'SKU ${p.codigoInterno}'
                                : 'Sem SKU',
                          ),
                          onTap: () => setState(() => _selecionado = p),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SugestaoVendaTipo>(
              value: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: SugestaoVendaTipo.values
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.rotulo),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tipo = v);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantidade sugerida',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observacao (opcional)',
                hintText: 'Ex.: levar junto com a tinta',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selecionado == null ? null : _confirmar,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
