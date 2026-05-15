import 'package:flutter/material.dart';

import '../data/kit_orcamento_repository.dart';
import '../data/produto_repository.dart';
import '../model/kit_orcamento.dart';
import '../model/produto.dart';

/// Lista e edicao de kits para orcamento (cadastro).
class KitsOrcamentoPage extends StatefulWidget {
  const KitsOrcamentoPage({
    super.key,
    required this.kitOrcamentoRepository,
    required this.produtoRepository,
  });

  final KitOrcamentoRepository kitOrcamentoRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<KitsOrcamentoPage> createState() => _KitsOrcamentoPageState();
}

class _KitsOrcamentoPageState extends State<KitsOrcamentoPage> {
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
                      k.ativo ? Icons.inventory_2_outlined : Icons.inventory_outlined,
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
                            kitOrcamentoRepository: widget.kitOrcamentoRepository,
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
  _LinhaDraftKit({
    required this.produto,
    required this.quantidadeController,
  });

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
  final KitOrcamentoRepository kitOrcamentoRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<KitOrcamentoEditPage> createState() => _KitOrcamentoEditPageState();
}

class _KitOrcamentoEditPageState extends State<KitOrcamentoEditPage> {
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _ativo = true;
  final List<_LinhaDraftKit> _linhas = [];
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final id = widget.kitId;
    if (id != null) {
      final k = widget.kitOrcamentoRepository.obterPorId(id);
      if (k != null) {
        _nomeCtrl.text = k.nome;
        _descCtrl.text = k.descricao;
        _ativo = k.ativo;
        final itens = k.itens.toList()
          ..sort((a, b) => a.ordem.compareTo(b.ordem));
        for (final it in itens) {
          final pid = it.produto.targetId;
          final p =
              pid != 0 ? widget.produtoRepository.obterPorId(pid) : null;
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
    }
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
    final buscaCtrl = TextEditingController();
    List<Produto> resultados = widget.produtoRepository.pesquisar(
      '',
      limite: 50,
      somenteAtivos: false,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            void buscar(String t) {
              resultados = widget.produtoRepository.pesquisar(
                t,
                limite: 50,
                somenteAtivos: false,
              );
              setDlg(() {});
            }

            return AlertDialog(
              title: const Text('Incluir produto no kit'),
              content: SizedBox(
                width: 420,
                height: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: buscaCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Nome, SKU, codigo de barras...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: buscar,
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: resultados.isEmpty
                          ? const Center(child: Text('Nenhum produto encontrado.'))
                          : ListView.builder(
                              itemCount: resultados.length,
                              itemBuilder: (_, i) {
                                final p = resultados[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    p.nome,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(p.codigoInterno),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    setState(() {
                                      _linhas.add(
                                        _LinhaDraftKit(
                                          produto: p,
                                          quantidadeController:
                                              TextEditingController(text: '1'),
                                        ),
                                      );
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
    buscaCtrl.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do kit.')),
      );
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
            content: Text(
              'Quantidade invalida para ${l.produto.nome}.',
            ),
          ),
        );
        return;
      }
      final item = KitOrcamentoItem(quantidade: q);
      item.produto.targetId = l.produto.id;
      itens.add(item);
    }

    final KitOrcamento kit;
    if (widget.kitId != null) {
      final ex = widget.kitOrcamentoRepository.obterPorId(widget.kitId!);
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
      widget.kitOrcamentoRepository.salvar(kit, itens);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kit salvo com sucesso.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluir() async {
    final id = widget.kitId;
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
    widget.kitOrcamentoRepository.remover(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kit excluido.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kitId == null ? 'Novo kit' : 'Editar kit'),
        actions: [
          if (widget.kitId != null)
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
            subtitle: const Text('Kits inativos nao aparecem na insercao rapida.'),
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
          else
            ...[
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
                                style: const TextStyle(fontWeight: FontWeight.w600),
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
