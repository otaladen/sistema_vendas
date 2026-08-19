import 'package:flutter/material.dart';

import '../../domain/obra_calculadora.dart';
import '../../domain/obra_calculadora_templates.dart';
import '../../model/produto.dart';
import '../widgets/produto_busca_input.dart';

/// Mapeamento de produtos padrao da calculadora de obra (Configuracoes > PDV).
class ObraCalculadoraConfigSection extends StatefulWidget {
  const ObraCalculadoraConfigSection({
    super.key,
    required this.produtoRepository,
    required this.tijoloProdutoId,
    required this.cimentoProdutoId,
    required this.areiaProdutoId,
    required this.pisoProdutoId,
    required this.britaProdutoId,
    required this.telhaProdutoId,
    required this.ferroProdutoId,
    required this.perdaPadraoPct,
    required this.perdaRebocoPct,
    required this.perdaPisoPct,
    required this.espessuraRebocoMm,
    required this.espessuraContrapisoMm,
    required this.m2PorCaixaPiso,
    required this.geminiParseAtivo,
    required this.templatesJson,
    required this.usarSubstitutoEstoqueZero,
    required this.onChanged,
  });

  final dynamic produtoRepository;
  final int tijoloProdutoId;
  final int cimentoProdutoId;
  final int areiaProdutoId;
  final int pisoProdutoId;
  final int britaProdutoId;
  final int telhaProdutoId;
  final int ferroProdutoId;
  final double perdaPadraoPct;
  final double perdaRebocoPct;
  final double perdaPisoPct;
  final double espessuraRebocoMm;
  final double espessuraContrapisoMm;
  final double m2PorCaixaPiso;
  final bool geminiParseAtivo;
  final String templatesJson;
  final bool usarSubstitutoEstoqueZero;
  final void Function({
    int? tijoloProdutoId,
    int? cimentoProdutoId,
    int? areiaProdutoId,
    int? pisoProdutoId,
    int? britaProdutoId,
    int? telhaProdutoId,
    int? ferroProdutoId,
    double? perdaPadraoPct,
    double? perdaRebocoPct,
    double? perdaPisoPct,
    double? espessuraRebocoMm,
    double? espessuraContrapisoMm,
    double? m2PorCaixaPiso,
    bool? geminiParseAtivo,
    String? templatesJson,
    bool? usarSubstitutoEstoqueZero,
  }) onChanged;

  @override
  State<ObraCalculadoraConfigSection> createState() =>
      _ObraCalculadoraConfigSectionState();
}

class _ObraCalculadoraConfigSectionState extends State<ObraCalculadoraConfigSection> {
  late final TextEditingController _perdaController;
  late final TextEditingController _perdaRebocoController;
  late final TextEditingController _perdaPisoController;
  late final TextEditingController _espRebocoController;
  late final TextEditingController _espContrapisoController;
  late final TextEditingController _m2CaixaController;

  @override
  void initState() {
    super.initState();
    _perdaController = TextEditingController(
      text: widget.perdaPadraoPct.toStringAsFixed(0),
    );
    _perdaRebocoController = TextEditingController(
      text: widget.perdaRebocoPct.toStringAsFixed(0),
    );
    _perdaPisoController = TextEditingController(
      text: widget.perdaPisoPct.toStringAsFixed(0),
    );
    _espRebocoController = TextEditingController(
      text: widget.espessuraRebocoMm.toStringAsFixed(0),
    );
    _espContrapisoController = TextEditingController(
      text: widget.espessuraContrapisoMm.toStringAsFixed(0),
    );
    _m2CaixaController = TextEditingController(
      text: widget.m2PorCaixaPiso.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _perdaController.dispose();
    _perdaRebocoController.dispose();
    _perdaPisoController.dispose();
    _espRebocoController.dispose();
    _espContrapisoController.dispose();
    _m2CaixaController.dispose();
    super.dispose();
  }

  String _rotuloProduto(int id) {
    if (id <= 0) return 'Nao selecionado';
    final p = widget.produtoRepository.obterPorId(id);
    if (p == null) return 'Produto #$id (nao encontrado)';
    return '${p.nome} (#${p.id})';
  }

  List<ObraCalculadoraTemplate> get _templates =>
      ObraCalculadoraTemplatesUtil.decode(widget.templatesJson);

  Future<void> _escolherProduto({
    required String titulo,
    required int atualId,
    required void Function(int id) onPick,
  }) async {
    final buscaCtrl = TextEditingController();
    var resultados = widget.produtoRepository.pesquisarPadraoPdv('');

    final escolhido = await showDialog<Produto>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialog) {
            void buscar(String t) {
              setDialog(() {
                resultados = widget.produtoRepository.pesquisarPadraoPdv(t);
              });
            }

            return AlertDialog(
              title: Text(titulo),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: buscaCtrl,
                      autofocus: true,
                      decoration: produtoBuscaInputDecoration(isDense: true),
                      onChanged: buscar,
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: resultados.isEmpty
                          ? const Text('Nenhum produto encontrado.')
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: resultados.length.clamp(0, 40),
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final p = resultados[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(p.nome),
                                  subtitle: Text(
                                    'SKU ${p.codigoInterno} · ${p.unidade}',
                                  ),
                                  selected: p.id == atualId,
                                  onTap: () => Navigator.pop(ctx, p),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (atualId > 0)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Limpar'),
                  ),
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

    if (escolhido == null && atualId > 0) {
      onPick(0);
    } else if (escolhido != null) {
      onPick(escolhido.id);
    }
  }

  Widget _linhaProduto({
    required String rotulo,
    required int produtoId,
    required void Function(int id) onPick,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(rotulo),
      subtitle: Text(_rotuloProduto(produtoId)),
      trailing: OutlinedButton(
        onPressed: () => _escolherProduto(
          titulo: rotulo,
          atualId: produtoId,
          onPick: onPick,
        ),
        child: const Text('Escolher'),
      ),
    );
  }

  void _salvarTemplates(List<ObraCalculadoraTemplate> lista) {
    widget.onChanged(
      templatesJson: ObraCalculadoraTemplatesUtil.encode(lista),
    );
  }

  Future<void> _importarPadroesLoja() async {
    final padroes = ObraCalculadoraTemplatesUtil.padroesLoja();
    final atuais = _templates;
    final ids = atuais.map((t) => t.id).toSet();
    final novos = [
      ...atuais,
      ...padroes.where((p) => !ids.contains(p.id)),
    ];
    _salvarTemplates(novos);
  }

  Future<void> _removerTemplate(ObraCalculadoraTemplate t) async {
    _salvarTemplates(_templates.where((x) => x.id != t.id).toList());
  }

  double? _parseBr(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final templates = _templates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Produtos e parametros usados no PDV (F12): parede, reboco, piso e contrapiso.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _linhaProduto(
          rotulo: 'Tijolo padrao',
          produtoId: widget.tijoloProdutoId,
          onPick: (id) => widget.onChanged(tijoloProdutoId: id),
        ),
        _linhaProduto(
          rotulo: 'Cimento (saco 50 kg)',
          produtoId: widget.cimentoProdutoId,
          onPick: (id) => widget.onChanged(cimentoProdutoId: id),
        ),
        _linhaProduto(
          rotulo: 'Areia (m³ · passo 0,50 · venda fracionada)',
          produtoId: widget.areiaProdutoId,
          onPick: (id) => widget.onChanged(areiaProdutoId: id),
        ),
        _linhaProduto(
          rotulo: 'Piso / porcelanato (caixa)',
          produtoId: widget.pisoProdutoId,
          onPick: (id) => widget.onChanged(pisoProdutoId: id),
        ),
        _linhaProduto(
          rotulo: 'Brita (m³ · passo 0,50 · venda fracionada)',
          produtoId: widget.britaProdutoId,
          onPick: (id) => widget.onChanged(britaProdutoId: id),
        ),
        _linhaProduto(
          rotulo: 'Telha',
          produtoId: widget.telhaProdutoId,
          onPick: (id) => widget.onChanged(telhaProdutoId: id),
        ),
        _linhaProduto(
          rotulo: 'Ferro (KG, opcional fundacao)',
          produtoId: widget.ferroProdutoId,
          onPick: (id) => widget.onChanged(ferroProdutoId: id),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _perdaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Perda parede (%)',
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = _parseBr(v);
                  if (n != null) widget.onChanged(perdaPadraoPct: n.clamp(0, 50));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _perdaRebocoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Perda reboco (%)',
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = _parseBr(v);
                  if (n != null) widget.onChanged(perdaRebocoPct: n.clamp(0, 50));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _perdaPisoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Perda piso (%)',
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = _parseBr(v);
                  if (n != null) widget.onChanged(perdaPisoPct: n.clamp(0, 50));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _m2CaixaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'm² por caixa (padrao)',
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = _parseBr(v);
                  if (n != null) {
                    widget.onChanged(m2PorCaixaPiso: n.clamp(0.1, 10));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _espRebocoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Espessura reboco (mm)',
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = _parseBr(v);
                  if (n != null) {
                    widget.onChanged(espessuraRebocoMm: n.clamp(5, 50));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _espContrapisoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Espessura contrapiso (mm)',
                  isDense: true,
                ),
                onChanged: (v) {
                  final n = _parseBr(v);
                  if (n != null) {
                    widget.onChanged(espessuraContrapisoMm: n.clamp(10, 80));
                  }
                },
              ),
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: widget.usarSubstitutoEstoqueZero,
          onChanged: (v) => widget.onChanged(usarSubstitutoEstoqueZero: v),
          title: const Text('Usar substituto se estoque zerado'),
          subtitle: const Text(
            'Troca automaticamente pelo substituto cadastrado no produto.',
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: widget.geminiParseAtivo,
          onChanged: (v) => widget.onChanged(geminiParseAtivo: v),
          title: const Text('Interpretar texto com Gemini (opcional)'),
          subtitle: const Text(
            'Quando o regex local nao entender, tenta Gemini so para extrair dimensoes.',
          ),
        ),
        const Divider(height: 24),
        Row(
          children: [
            Text(
              'Templates salvos',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _importarPadroesLoja,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Importar padroes'),
            ),
          ],
        ),
        if (templates.isEmpty)
          Text(
            'Nenhum template. Importe os padroes da loja ou salve no PDV.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...templates.map(
            (t) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t.nome),
              subtitle: Text('${t.tipo.rotulo} · ${_rotuloDimensao(t)}'),
              trailing: IconButton(
                tooltip: 'Remover template',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _removerTemplate(t),
              ),
            ),
          ),
      ],
    );
  }

  String _rotuloDimensao(ObraCalculadoraTemplate t) {
    if (t.areaM2 > 0) return '${t.areaM2.toStringAsFixed(0)} m²';
    return '${t.larguraM}×${t.alturaM} m';
  }
}
