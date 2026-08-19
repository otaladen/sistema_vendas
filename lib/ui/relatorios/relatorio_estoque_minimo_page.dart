import 'package:flutter/material.dart';

import '../../domain/produto_embalagem.dart';
import '../../model/produto.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioEstoqueMinimoPage extends StatefulWidget {
  const RelatorioEstoqueMinimoPage({super.key, required this.produtoRepository});

  final dynamic produtoRepository;

  @override
  State<RelatorioEstoqueMinimoPage> createState() =>
      _RelatorioEstoqueMinimoPageState();
}

class _RelatorioEstoqueMinimoPageState extends State<RelatorioEstoqueMinimoPage> {
  List<Produto> _lista = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    final todos =
        (widget.produtoRepository.listarTodos() as List).cast<Produto>();
    final critico = todos
        .where((p) => p.estoqueExibicao < p.quantidadeMinima)
        .toList()
      ..sort((a, b) {
        final da = a.quantidadeMinima - a.estoqueExibicao;
        final db = b.quantidadeMinima - b.estoqueExibicao;
        return db.compareTo(da);
      });
    setState(() => _lista = critico);
  }

  List<List<String>> _linhasCsv() => [
        [
          'Codigo',
          'Produto',
          'Categoria',
          'Minimo',
          'Estoque',
          'Falta',
          'Unidade',
        ],
        ..._lista.map(
          (p) {
            final estoqueTxt = ProdutoEmbalagem.formatarEstoque(
              p,
              p.estoqueReal,
              comUnidade: true,
            );
            final falta = (p.quantidadeMinima - p.estoqueExibicao)
                .clamp(0.0, double.infinity);
            final faltaTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
              p,
              falta,
            );
            return [
              p.codigoInterno,
              p.nome,
              p.categoria,
              '${p.quantidadeMinima}',
              estoqueTxt,
              '$faltaTxt ${p.unidade}',
              p.unidade,
            ];
          },
        ),
      ];

  List<String> _paginasPdf() {
    return relatorioMontarPaginasTabela(
      titulo: 'ESTOQUE ABAIXO DO MINIMO',
      subtitulo: '${_lista.length} produto(s)',
      cabecalho: ['Codigo', 'Produto', 'Min', 'Atual', 'Falta'],
      linhas: _lista
          .map(
            (p) {
              final estoqueTxt = ProdutoEmbalagem.formatarEstoque(
                p,
                p.estoqueReal,
              );
              final falta =
                  (p.quantidadeMinima - p.estoqueExibicao).clamp(0.0, double.infinity);
              final faltaTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
                p,
                falta,
              );
              return [
                p.codigoInterno,
                p.nome,
                '${p.quantidadeMinima}',
                estoqueTxt,
                faltaTxt,
              ];
            },
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque abaixo do minimo'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'estoque_abaixo_minimo',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _lista.isEmpty
          ? const Center(child: Text('Nenhum produto abaixo do minimo.'))
          : ListView.builder(
              itemCount: _lista.length,
              itemBuilder: (context, i) {
                final p = _lista[i];
                final falta =
                    (p.quantidadeMinima - p.estoqueExibicao).clamp(0.0, double.infinity);
                final estoqueTxt = ProdutoEmbalagem.formatarEstoque(
                  p,
                  p.estoqueReal,
                  comUnidade: true,
                );
                final faltaTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
                  p,
                  falta,
                );
                final critico = falta >= p.quantidadeMinima * 0.5;
                return ListTile(
                  title: Text(p.nome),
                  subtitle: Text(
                    '${p.categoria.isNotEmpty ? '${p.categoria} · ' : ''}'
                    'Min: ${p.quantidadeMinima} ${p.unidade} · '
                    'Atual: $estoqueTxt · '
                    'Falta: $faltaTxt ${p.unidade}',
                  ),
                  trailing: critico
                      ? Icon(
                          Icons.warning_amber,
                          color: Theme.of(context).colorScheme.error,
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => abrirProdutoRelatorio(
                    context,
                    produtoRepository: widget.produtoRepository,
                    produtoId: p.id,
                  ),
                );
              },
            ),
    );
  }
}
