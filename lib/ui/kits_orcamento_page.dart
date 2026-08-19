import 'package:flutter/material.dart';

import '../data/api/kit_promocao_api_repository.dart';
import '../data/api/produto_api_repository.dart';
import '../model/kit_orcamento.dart';
import '../model/produto.dart';
import 'produtos/produto_pesquisa_dialog.dart';
import 'widgets/lan_api_feedback.dart';

/// Lista e edicao de kits para orcamento (cadastro).
class KitsOrcamentoPage extends StatefulWidget {
  const KitsOrcamentoPage({
    super.key,
    required this.kitOrcamentoRepository,
    required this.produtoRepository,
  });

  final dynamic kitOrcamentoRepository;
  final dynamic produtoRepository;

  @override
  State<KitsOrcamentoPage> createState() => _KitsOrcamentoPageState();
}

class _KitsOrcamentoPageState extends State<KitsOrcamentoPage> {
  @override
  void initState() {
    super.initState();
    final repo = widget.kitOrcamentoRepository;
    if (repo is KitOrcamentoApiRepository) {
      repo.addListener(_onKitApiChanged);
    }
  }

  @override
  void dispose() {
    final repo = widget.kitOrcamentoRepository;
    if (repo is KitOrcamentoApiRepository) {
      repo.removeListener(_onKitApiChanged);
    }
    super.dispose();
  }

  void _onKitApiChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lista = widget.kitOrcamentoRepository.listarPorNome();
    return Scaffold(
      appBar: AppBar(title: const Text('Kits de orcamento')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => KitOrcamentoEditPage(
                kitOrcamentoRepository: widget.kitOrcamentoRepository,
                produtoRepository: widget.produtoRepository,
              ),
            ),
          );
          if (mounted) setState(() {});
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo kit'),
      ),
      body: lista.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nenhum kit cadastrado.\n'
                  'Monte grupos de produtos (ex.: kit banheiro) para inserir de uma vez no PDV.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: lista.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final k = lista[i];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      k.ativo
                          ? Icons.inventory_2_outlined
                          : Icons.inventory_outlined,
                      color: k.ativo
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    title: Text(k.nome),
                    subtitle: Text(
                      k.ativo ? 'Ativo' : 'Inativo',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => KitOrcamentoEditPage(
                            kitId: k.id,
                            kitOrcamentoRepository:
                                widget.kitOrcamentoRepository,
                            produtoRepository: widget.produtoRepository,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _LinhaDraftKit {
  _LinhaDraftKit({required this.produto, required this.quantidadeController});

  final Produto produto;
  final TextEditingController quantidadeController;

  void dispose() => quantidadeController.dispose();
}

/// Criar ou editar um kit e suas linhas de produto.
class KitOrcamentoEditPage extends StatefulWidget {
  const KitOrcamentoEditPage({
    super.key,
    this.kitId,
    required this.kitOrcamentoRepository,
    required this.produtoRepository,
  });

  final int? kitId;
  final dynamic kitOrcamentoRepository;
  final dynamic produtoRepository;

  @override
  State<KitOrcamentoEditPage> createState() => _KitOrcamentoEditPageState();
}

class _KitOrcamentoEditPageState extends State<KitOrcamentoEditPage> {
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _ativo = true;
  final List<_LinhaDraftKit> _linhas = [];
  bool _salvando = false;
  late int? _kitId;

  @override
  void initState() {
    super.initState();
    _kitId = widget.kitId;
    final id = _kitId;
    if (id != null) {
      final k = widget.kitOrcamentoRepository.obterPorId(id);
      if (k != null) {
        _preencherFormulario(k);
        if (widget.produtoRepository is ProdutoApiRepository) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completarProdutosRemotos(k);
          });
        }
      }
    }
  }

  void _preencherFormulario(KitOrcamento k) {
    _nomeCtrl.text = k.nome;
    _descCtrl.text = k.descricao;
    _ativo = k.ativo;
    for (final l in _linhas) {
      l.dispose();
    }
    _linhas.clear();
    final itens = _itensDoKit(k)..sort((a, b) => a.ordem.compareTo(b.ordem));
    for (final it in itens) {
      final pid = it.produto.targetId;
      final p = pid != 0
          ? widget.produtoRepository.obterPorId(pid) as Produto?
          : null;
      if (p != null) {
        _linhas.add(
          _LinhaDraftKit(
            produto: p,
            quantidadeController: TextEditingController(
              text: '${it.quantidade}',
            ),
          ),
        );
      }
    }
  }

  List<KitOrcamentoItem> _itensDoKit(KitOrcamento k) {
    final repo = widget.kitOrcamentoRepository;
    if (repo is KitOrcamentoApiRepository) {
      return List<KitOrcamentoItem>.from(repo.itensDoKit(k));
    }
    try {
      return List<KitOrcamentoItem>.from(k.itens);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _completarProdutosRemotos(KitOrcamento k) async {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoApiRepository) return;
    final faltando = <int>{};
    for (final it in _itensDoKit(k)) {
      final pid = it.produto.targetId;
      if (pid > 0 && repo.obterPorId(pid) == null) {
        faltando.add(pid);
      }
    }
    if (faltando.isEmpty) return;
    try {
      await repo.atualizarEstoquePorIds(faltando.toList());
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _preencherFormulario(k));
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _adicionarProduto() async {
    final p = await showProdutoPesquisaDialog(
      context: context,
      produtoRepository: widget.produtoRepository,
    );
    if (p == null || !mounted) return;
    setState(() {
      _linhas.add(
        _LinhaDraftKit(
          produto: p,
          quantidadeController: TextEditingController(text: '1'),
        ),
      );
    });
  }

  Future<void> _salvar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe o nome do kit.')));
      return;
    }
    if (_linhas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um produto ao kit.')),
      );
      return;
    }

    final itens = <KitOrcamentoItem>[];
    for (final l in _linhas) {
      final q = int.tryParse(l.quantidadeController.text.trim()) ?? 0;
      if (q <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quantidade invalida para ${l.produto.nome}.'),
          ),
        );
        return;
      }
      final item = KitOrcamentoItem(quantidade: q);
      item.produto.targetId = l.produto.id;
      itens.add(item);
    }

    final KitOrcamento kit;
    final idAtual = _kitId;
    if (idAtual != null) {
      final ex = widget.kitOrcamentoRepository.obterPorId(idAtual);
      if (ex == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kit nao encontrado ou foi excluido.')),
        );
        Navigator.of(context).pop();
        return;
      }
      kit = ex;
    } else {
      kit = KitOrcamento(nome: nome);
    }
    kit.nome = nome;
    kit.descricao = _descCtrl.text.trim();
    kit.ativo = _ativo;

    setState(() => _salvando = true);
    try {
      if (widget.kitOrcamentoRepository is KitOrcamentoApiRepository) {
        final idSalvo =
            await widget.kitOrcamentoRepository.salvarRemoto(kit, itens) as int;
        if (!mounted) return;
        // Evita criar kit duplicado em salvamentos seguintes.
        if (idSalvo > 0) {
          setState(() => _kitId = idSalvo);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kit salvo com sucesso.')),
        );
      } else {
        widget.kitOrcamentoRepository.salvar(kit, itens);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kit salvo com sucesso.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Erro ao salvar kit');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluir() async {
    final id = _kitId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir kit'),
        content: const Text(
          'Deseja excluir este kit? Os produtos no cadastro nao serao apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (widget.kitOrcamentoRepository is KitOrcamentoApiRepository) {
        await widget.kitOrcamentoRepository.removerRemoto(id);
      } else {
        widget.kitOrcamentoRepository.remover(id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kit excluido.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Erro ao excluir kit');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_kitId == null ? 'Novo kit' : 'Editar kit'),
        actions: [
          if (_kitId != null)
            IconButton(
              tooltip: 'Excluir kit',
              icon: const Icon(Icons.delete_outline),
              onPressed: _salvando ? null : _excluir,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nomeCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome do kit',
              hintText: 'Ex.: Kit banheiro basico',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descricao (opcional)',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Kit ativo no PDV'),
            subtitle: const Text(
              'Kits inativos nao aparecem na insercao rapida.',
            ),
            value: _ativo,
            onChanged: _salvando
                ? null
                : (v) {
                    setState(() => _ativo = v);
                  },
          ),
          const Divider(),
          Row(
            children: [
              Text(
                'Produtos do kit',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _salvando ? null : _adicionarProduto,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_linhas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nenhum produto. Use Adicionar para montar o kit.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (final l in _linhas)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.produto.nome,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l.produto.codigoInterno,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: l.quantidadeController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Qtd',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover linha',
                        onPressed: _salvando
                            ? null
                            : () {
                                setState(() {
                                  l.dispose();
                                  _linhas.remove(l);
                                });
                              },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_salvando ? 'Salvando...' : 'Salvar kit'),
          ),
        ],
      ),
    );
  }
}
