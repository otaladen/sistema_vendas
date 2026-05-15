import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/nfe_entrada_repository.dart';
import '../data/produto_repository.dart';
import '../model/item_nota_temporario.dart';
import '../model/produto.dart';

/// Conferencia de itens da NF-e antes de gravar estoque e vinculos.
class ConferenciaXmlScreen extends StatefulWidget {
  const ConferenciaXmlScreen({
    super.key,
    required this.nfe,
    required this.nfeRepository,
    required this.produtoRepository,
  });

  final NfeXmlParseResult nfe;
  final NfeEntradaRepository nfeRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<ConferenciaXmlScreen> createState() => _ConferenciaXmlScreenState();
}

class _LinhaEdicao {
  _LinhaEdicao({
    required this.sugestao,
    required this.fatorCtrl,
    required this.unidade,
  });

  final SugestaoLinhaConferencia sugestao;
  final TextEditingController fatorCtrl;
  String unidade;

  /// Quando preenchido, substitui a sugestao automatica (ex.: vincular item "novo" a um cadastro).
  int? vinculoManualProdutoId;
  String? vinculoManualProdutoNome;

  int? produtoDestinoId() {
    if (vinculoManualProdutoId != null) {
      return vinculoManualProdutoId;
    }
    if (!sugestao.produtoNovo) {
      return sugestao.produtoExistenteId;
    }
    return null;
  }
}

class _ConferenciaXmlScreenState extends State<ConferenciaXmlScreen> {
  List<_LinhaEdicao> _linhas = [];
  String? _initError;
  bool _confirmando = false;

  static final NumberFormat _nfQtd = NumberFormat('#,##0.###', 'pt_BR');

  @override
  void initState() {
    super.initState();
    try {
      final sugestoes =
          widget.nfeRepository.prepararSugestoesConferencia(widget.nfe);
      _linhas = sugestoes.map((s) {
        final c = TextEditingController(text: _formatarFator(s.fatorInicial));
        c.addListener(() {
          if (mounted) setState(() {});
        });
        return _LinhaEdicao(
          sugestao: s,
          fatorCtrl: c,
          unidade: s.unidadeInternaInicial,
        );
      }).toList();
    } catch (e, st) {
      _initError = e is FormatException || e is StateError
          ? e.toString()
          : 'Nao foi possivel montar a conferencia da nota.';
      assert(() {
        debugPrint('ConferenciaXmlScreen initState: $e\n$st');
        return true;
      }());
    }
  }

  static String _formatarFator(double v) {
    if (v == v.roundToDouble()) {
      return v.round().toString();
    }
    return v
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static double _lerFator(String texto) {
    final v = double.tryParse(texto.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite) {
      return 0;
    }
    return v;
  }

  double _quantidadeCalculada(_LinhaEdicao linha) {
    final f = _lerFator(linha.fatorCtrl.text);
    if (f <= 0) return 0;
    final q = linha.sugestao.item.quantidadeComercial;
    if (!q.isFinite || q < 0) return 0;
    final prod = q * f;
    if (!prod.isFinite) return 0;
    return prod;
  }

  String? _rotuloProdutoVinculado(_LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) return null;
    if (linha.vinculoManualProdutoNome != null) {
      return linha.vinculoManualProdutoNome;
    }
    final p = widget.produtoRepository.obterPorId(id);
    if (p == null) {
      return 'Produto #$id';
    }
    return '${p.codigoInterno} · ${p.nome}';
  }

  Future<void> _abrirDialogVincularProduto(_LinhaEdicao linha) async {
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
              title: const Text('Vincular a produto cadastrado'),
              content: SizedBox(
                width: 420,
                height: 420,
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
                          ? const Center(
                              child: Text('Nenhum produto encontrado.'),
                            )
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
                                  subtitle: Text(
                                    '${p.codigoInterno} · EAN ${p.codigoBarras.isEmpty ? "—" : p.codigoBarras} · Fisico ${p.estoqueReal}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    final u = p.unidade.trim().toUpperCase();
                                    setState(() {
                                      linha.vinculoManualProdutoId = p.id;
                                      linha.vinculoManualProdutoNome =
                                          '${p.codigoInterno} · ${p.nome}';
                                      if (NfeEntradaRepository
                                          .unidadesInternasValidas
                                          .contains(u)) {
                                        linha.unidade = u;
                                      }
                                    });
                                    Navigator.pop(ctx);
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

  @override
  void dispose() {
    for (final l in _linhas) {
      l.fatorCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmar() async {
    final confirmacoes = <ConferenciaNfeLinhaConfirmacao>[];
    for (final linha in _linhas) {
      final f = _lerFator(linha.fatorCtrl.text);
      if (f <= 0) {
        final d = linha.sugestao.item.descricao;
        final curto = d.length > 48 ? '${d.substring(0, 48)}…' : d;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fator invalido no item: $curto')),
        );
        return;
      }
      final qCom = linha.sugestao.item.quantidadeComercial;
      if (!qCom.isFinite || qCom < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Quantidade da nota invalida em um dos itens. Verifique o XML.',
            ),
          ),
        );
        return;
      }
      final qtdCalc = qCom * f;
      if (!qtdCalc.isFinite) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Quantidade para estoque invalida (nao finita). Ajuste o fator.',
            ),
          ),
        );
        return;
      }
      if (qtdCalc > 2147483647) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Quantidade para estoque acima do limite suportado. Reduza o fator ou corrija a nota.',
            ),
          ),
        );
        return;
      }
      if (!NfeEntradaRepository.unidadesInternasValidas.contains(linha.unidade)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unidade invalida: ${linha.unidade}')),
        );
        return;
      }
      confirmacoes.add(
        ConferenciaNfeLinhaConfirmacao(
          item: linha.sugestao.item,
          fatorConversao: f,
          unidadeInterna: linha.unidade,
          produtoExistenteId: linha.produtoDestinoId(),
        ),
      );
    }

    setState(() => _confirmando = true);
    try {
      widget.nfeRepository.confirmarEntrada(
        nfe: widget.nfe,
        linhas: confirmacoes,
      );
      widget.produtoRepository.invalidarCacheBusca();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrada da NF-e registrada com sucesso.')),
      );
      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao confirmar: $e')),
      );
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conferencia NF-e (XML)')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                _initError!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    final emit = widget.nfe.emitente;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferencia NF-e (XML)'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    emit.razaoSocial,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'CNPJ ${emit.cnpj} · Chave ${widget.nfe.chaveAcesso}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _confirmando ? null : _confirmar,
            icon: _confirmando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_confirmando ? 'Gravando...' : 'Confirmar entrada'),
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _linhas.length,
        itemBuilder: (context, index) {
          final linha = _linhas[index];
          final s = linha.sugestao;
          final item = s.item;
          final qCalc = _quantidadeCalculada(linha);
          final destinoId = linha.produtoDestinoId();
          final rotuloVinculo = _rotuloProdutoVinculado(linha);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.descricao,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (destinoId == null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Chip(
                            label: const Text('Novo produto'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                Theme.of(context).colorScheme.tertiaryContainer,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rotuloVinculo != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            'Cadastrado: $rotuloVinculo',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _abrirDialogVincularProduto(linha),
                        icon: const Icon(Icons.link, size: 18),
                        label: Text(
                          destinoId == null
                              ? 'Vincular a produto existente'
                              : 'Trocar vinculo',
                        ),
                      ),
                      if (linha.vinculoManualProdutoId != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              linha.vinculoManualProdutoId = null;
                              linha.vinculoManualProdutoNome = null;
                            });
                          },
                          child: const Text('Desfazer vinculo manual'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fornecedor: ${item.unidadeComercial} · Qtd original: ${_nfQtd.format(item.quantidadeComercial)} · Cod. ${item.codigo}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (item.codigoBarras.isNotEmpty)
                    Text(
                      'EAN: ${item.codigoBarras}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('${index}_${linha.unidade}'),
                          decoration: const InputDecoration(
                            labelText: 'Unidade interna',
                            isDense: true,
                          ),
                          initialValue: linha.unidade,
                          items: NfeEntradaRepository.unidadesInternasValidas
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => linha.unidade = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: linha.fatorCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Fator conversao',
                            hintText: 'Ex.: 12',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quantidade para o estoque: ${_nfQtd.format(qCalc)} ${linha.unidade}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
