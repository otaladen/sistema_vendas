import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/nfe_entrada_repository.dart';
import '../data/produto_repository.dart';
import '../domain/produto_embalagem.dart';
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
  static final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');

  static const Color _custoAumentoFg = Color(0xFFB91C1C);
  static const Color _custoQuedaFg = Color(0xFF15803D);
  static const Color _chipEanBg = Color(0xFFE8F5E9);
  static const Color _chipEanFg = Color(0xFF1B5E20);
  static const Color _chipFornBg = Color(0xFFE3F2FD);
  static const Color _chipFornFg = Color(0xFF0D47A1);
  static const Color _chipNovoBg = Color(0xFFFFF3E0);
  static const Color _chipNovoFg = Color(0xFFE65100);
  static const Color _chipManualBg = Color(0xFFE8EAF6);
  static const Color _chipManualFg = Color(0xFF283593);

  /// Mesmos gaps usados em telas ERP (ex.: produtos_page).
  static const double _erpGap8 = 8;
  static const double _erpGap16 = 16;

  /// Largura minima para dispor "Custo atual" e bloco XML em duas colunas.
  static const double _custoPainelBreakpoint2Col = 640;

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
    var multiplica = true;
    final id = linha.produtoDestinoId();
    if (id != null) {
      final p = widget.produtoRepository.obterPorId(id);
      if (p != null) multiplica = p.embalagemMultiplica;
    }
    return ProdutoEmbalagem.quantidadeNotaParaEstoque(
      quantidadeComercial: q,
      fator: f,
      embalagemMultiplica: multiplica,
    ).toDouble();
  }

  /// Custo unitario na [unidade interna] do cadastro (mesma formula de [NfeEntradaRepository.confirmarEntrada]).
  double? _custoUnitarioXmlConvertidoInterno(_LinhaEdicao linha) {
    final f = _lerFator(linha.fatorCtrl.text);
    final vUn = linha.sugestao.item.valorUnitarioComercial;
    if (f <= 0 || !vUn.isFinite || vUn < 0) {
      return null;
    }
    var multiplica = true;
    final id = linha.produtoDestinoId();
    if (id != null) {
      final p = widget.produtoRepository.obterPorId(id);
      if (p != null) multiplica = p.embalagemMultiplica;
    }
    final unit = multiplica ? vUn / f : vUn * f;
    if (!unit.isFinite || unit < 0) {
      return null;
    }
    return unit;
  }

  static String _formatarReais(double v) => 'R\$ ${_nfMoeda.format(v)}';

  /// Painel custo cadastro vs XML; so quando ja existe produto destino.
  Widget _buildComparativoCustoPainel(BuildContext context, _LinhaEdicao linha) {
    final id = linha.produtoDestinoId();
    if (id == null) {
      return const SizedBox.shrink();
    }
    final p = widget.produtoRepository.obterPorId(id);
    if (p == null) {
      return const SizedBox.shrink();
    }
    final custoXml = _custoUnitarioXmlConvertidoInterno(linha);
    final atual = p.precoCusto;
    final uInt = linha.unidade.trim();

    if (custoXml == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Informe um fator valido para comparar o custo unitario do XML com o cadastro.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final textoCustoCadastro = Text(
      'Custo cadastro (precoCusto): ${_formatarReais(atual)} / $uInt',
      style: Theme.of(context).textTheme.bodySmall,
      softWrap: true,
    );

    final bm = Theme.of(context).textTheme.bodyMedium;
    final xmlPrecoRich = Text.rich(
      TextSpan(
        style: bm?.copyWith(fontWeight: FontWeight.w700),
        children: [
          const TextSpan(text: 'XML convertido: '),
          TextSpan(
            text: _formatarReais(custoXml),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: ' / $uInt',
            style: bm?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    Widget? indicadorVariacao;
    const eps = 1e-9;
    if (atual > eps) {
      final pct = (custoXml - atual) / atual * 100;
      if (pct > 5 + 1e-9) {
        final pctTxt =
            pct >= 10 ? pct.round().toString() : pct.toStringAsFixed(1);
        indicadorVariacao = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '⚠️',
              style: TextStyle(
                color: _custoAumentoFg,
                fontSize: 18,
                height: 1,
              ),
            ),
            Text(
              '+$pctTxt% de aumento',
              style: const TextStyle(
                color: _custoAumentoFg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              softWrap: true,
            ),
          ],
        );
      } else if (custoXml < atual - eps) {
        final pctAbs = ((atual - custoXml) / atual * 100).abs();
        final pctTxt = pctAbs >= 10
            ? pctAbs.round().toString()
            : pctAbs.toStringAsFixed(1);
        indicadorVariacao = Text(
          '$pctTxt% menor que o cadastro',
          style: const TextStyle(
            color: _custoQuedaFg,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          softWrap: true,
        );
      }
    } else if (custoXml > eps) {
      indicadorVariacao = Text(
        'Custo cadastro era zero; apos confirmar sera ${_formatarReais(custoXml)} / $uInt',
        style: TextStyle(
          color: cs.tertiary,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        softWrap: true,
      );
    }

    Widget blocoXmlEIndicador(double larguraMaxBloco) {
      return Wrap(
        spacing: _erpGap8,
        runSpacing: _erpGap8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: larguraMaxBloco),
            child: xmlPrecoRich,
          ),
          if (indicadorVariacao != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: larguraMaxBloco),
              child: indicadorVariacao,
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: LayoutBuilder(
            builder: (context, c) {
              final maxW = c.maxWidth;
              final titulo = Text(
                'Custo vs cadastro',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
              );

              if (maxW >= _custoPainelBreakpoint2Col) {
                final colW = (maxW - _erpGap16) / 2;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titulo,
                    const SizedBox(height: _erpGap8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: colW,
                          child: textoCustoCadastro,
                        ),
                        const SizedBox(width: _erpGap16),
                        SizedBox(
                          width: colW,
                          child: blocoXmlEIndicador(colW),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titulo,
                  const SizedBox(height: _erpGap8),
                  textoCustoCadastro,
                  const SizedBox(height: _erpGap8),
                  blocoXmlEIndicador(maxW),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _mensagemFatorConversao(_LinhaEdicao linha) {
    final item = linha.sugestao.item;
    final uCom = item.unidadeComercial.trim();
    final uInt = linha.unidade.trim();
    final q = item.quantidadeComercial;
    final f = _lerFator(linha.fatorCtrl.text);
    final uComLabel = uCom.isEmpty ? '(unid. na nota)' : uCom;
    final uIntLabel = uInt.isEmpty ? '?' : uInt;
    if (f <= 0) {
      return 'Informe um fator maior que zero. Ex.: se a nota usa CX e voce controla '
          'em UN, digite quantas UN existem em 1 CX.';
    }
    if (!q.isFinite || q < 0) {
      return 'Quantidade da nota invalida; confira o XML.';
    }
    var multiplica = true;
    final id = linha.produtoDestinoId();
    if (id != null) {
      final p = widget.produtoRepository.obterPorId(id);
      if (p != null) multiplica = p.embalagemMultiplica;
    }
    final qtd = ProdutoEmbalagem.quantidadeNotaParaEstoque(
      quantidadeComercial: q,
      fator: f,
      embalagemMultiplica: multiplica,
    );
    final qFmt = _nfQtd.format(q);
    final modo = multiplica ? 'multiplica' : 'divide';
    return 'Na nota: $qFmt $uComLabel. Fator $f ($modo) -> '
        '$qtd $uIntLabel no estoque.';
  }

  ({Color bg, Color fg, String label}) _coresStatusChip(_LinhaEdicao linha) {
    final manual = linha.vinculoManualProdutoId != null;
    final tipo = linha.sugestao.tipoMatch;
    if (manual && tipo == ConferenciaNfeMatchTipo.produtoNovo) {
      return (
        bg: _chipManualBg,
        fg: _chipManualFg,
        label: 'Vinculo manual - produto cadastrado',
      );
    }
    switch (tipo) {
      case ConferenciaNfeMatchTipo.vinculadoPorEan:
        return (
          bg: _chipEanBg,
          fg: _chipEanFg,
          label: 'Produto vinculado por EAN',
        );
      case ConferenciaNfeMatchTipo.vinculoFornecedor:
        return (
          bg: _chipFornBg,
          fg: _chipFornFg,
          label: 'Vinculo por fornecedor encontrado',
        );
      case ConferenciaNfeMatchTipo.produtoNovo:
        return (
          bg: _chipNovoBg,
          fg: _chipNovoFg,
          label: 'Novo produto (sera cadastrado)',
        );
    }
  }

  Widget _buildStatusChip(_LinhaEdicao linha) {
    final s = _coresStatusChip(linha);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.fg.withValues(alpha: 0.38)),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          color: s.fg,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildLinhaCard(BuildContext context, int index) {
    final linha = _linhas[index];
    final s = linha.sugestao;
    final item = s.item;
    final qCalc = _quantidadeCalculada(linha);
    final destinoId = linha.produtoDestinoId();
    final rotuloVinculo = _rotuloProdutoVinculado(linha);
    final cs = Theme.of(context).colorScheme;
    final avisoConversao = _mensagemFatorConversao(linha);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: _buildStatusChip(linha)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.descricao,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (rotuloVinculo != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      'Destino: $rotuloVinculo',
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
              'XML: ${item.unidadeComercial} · Qtd na nota: ${_nfQtd.format(item.quantidadeComercial)} · cProd ${item.codigo}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (item.codigoBarras.isNotEmpty)
              Text(
                'EAN: ${item.codigoBarras}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            _buildComparativoCustoPainel(context, linha),
            const SizedBox(height: 12),
            Material(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.straighten, size: 22, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Fator de conversao',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Evite erro: a unidade da nota e a unidade do cadastro podem ser diferentes.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.75),
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('${index}_${linha.unidade}'),
                            decoration: InputDecoration(
                              labelText: 'Unidade no cadastro',
                              isDense: true,
                              filled: true,
                              fillColor: cs.surface,
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
                          flex: 2,
                          child: TextFormField(
                            controller: linha.fatorCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Fator (destaque)',
                              hintText: 'Ex.: 12',
                              isDense: true,
                              filled: true,
                              fillColor: cs.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: cs.primary,
                                  width: 1.8,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: cs.primary.withValues(alpha: 0.55),
                                  width: 1.4,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: cs.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Text(
                          avisoConversao,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total no estoque apos confirmar: ${_nfQtd.format(qCalc)} ${linha.unidade}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        itemBuilder: (context, index) => _buildLinhaCard(context, index),
      ),
    );
  }
}
