import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../data/produto_busca_util.dart';
import '../../data/produto_repository.dart';
import '../widgets/produto_busca_input.dart';
import '../../model/produto.dart';
import '../../services/pdf_tabela_produtos_texto.dart';
import 'relatorio_cores.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioTabelaPrecosPage extends StatefulWidget {
  const RelatorioTabelaPrecosPage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioTabelaPrecosPage> createState() =>
      _RelatorioTabelaPrecosPageState();
}

class _RelatorioTabelaPrecosPageState extends State<RelatorioTabelaPrecosPage> {
  bool _somenteAtivos = false;
  String _busca = '';
  List<Produto> _preview = [];

  @override
  void initState() {
    super.initState();
    _atualizarPreview();
  }

  double _precoAVista(Produto p) =>
      p.preco2 > 0 ? p.preco2 : p.precoVenda;

  List<Produto> _produtosFiltrados() {
    final termo = _busca.trim();
    if (termo.isNotEmpty) {
      return widget.produtoRepository.pesquisarPadraoPdv(
        termo,
        limite: 500,
        somenteAtivos: _somenteAtivos,
      );
    }
    final base = widget.produtoRepository.listarTodos();
    final filtrado = _somenteAtivos
        ? base.where((p) => p.ativo).toList()
        : List<Produto>.from(base);
    final lista = filtrado
        .where((p) => !produtoEhCadastroInternoSistema(p))
        .toList();
    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  void _atualizarPreview() {
    setState(() => _preview = _produtosFiltrados());
  }

  Future<void> _exportarPdfTabela({required bool incluirCustos}) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar o PDF',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    try {
      final produtos = _produtosFiltrados();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo =
          incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final sufixoAtivos = _somenteAtivos ? '_ativos_' : '_';
      final arquivo = File(
        p.join(
          pastaDestino,
          '${tipoArquivo}_relatorio$sufixoAtivos$timestamp.pdf',
        ),
      );
      final titulo = incluirCustos
          ? 'Tabela Preco+Custo (alfabetica)'
          : 'Tabela Precos (alfabetica)';

      final bytes = await gerarPdfTabelaProdutosTexto(
        produtos: produtos,
        incluirCustos: incluirCustos,
        titulo: titulo,
        incluirColunaEstoque: true,
      );
      await arquivo.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('PDF exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar PDF: $e'),
        ),
      );
    }
  }

  List<List<String>> _linhasCsv() {
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return [
      ['Codigo', 'Produto', 'Estoque', 'A prazo', 'A vista', 'Custo'],
      ..._preview.map(
        (p) => [
          p.codigoInterno,
          p.nome,
          '${p.estoqueReal}',
          moeda.format(p.precoVenda),
          moeda.format(_precoAVista(p)),
          moeda.format(p.precoCusto),
        ],
      ),
    ];
  }

  List<String> _paginasPdfResumo() {
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return relatorioMontarPaginasTabela(
      titulo: 'TABELA DE PRECOS (resumo)',
      subtitulo:
          '${_preview.length} produto(s)'
          '${_somenteAtivos ? ' · Somente ativos' : ''}',
      cabecalho: ['Codigo', 'Produto', 'Est', 'A prazo', 'A vista'],
      linhas: _preview
          .map(
            (p) => [
              p.codigoInterno,
              p.nome,
              '${p.estoqueReal}',
              moeda.format(p.precoVenda),
              moeda.format(_precoAVista(p)),
            ],
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabela de precos'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'tabela_precos_resumo',
            paginasPdf: _paginasPdfResumo,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_preview.length} produto(s) na lista. PDF completo (grade estoque) nos botoes abaixo.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: produtoBuscaInputDecoration(isDense: true),
                  onChanged: (v) {
                    _busca = v;
                    _atualizarPreview();
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _somenteAtivos,
                  onChanged: (v) {
                    setState(() => _somenteAtivos = v);
                    _atualizarPreview();
                  },
                  title: const Text('Somente produtos ativos'),
                  secondary: Icon(
                    Icons.inventory_2_outlined,
                    color: corRelTabelaPrecos,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exportarPdfTabela(incluirCustos: false),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF completo — precos'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exportarPdfTabela(incluirCustos: true),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('PDF — preco+custo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _preview.isEmpty
                ? const Center(child: Text('Nenhum produto encontrado.'))
                : ListView.builder(
                    itemCount: _preview.length,
                    itemBuilder: (context, i) {
                      final p = _preview[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.nome),
                        subtitle: Text(
                          '${p.codigoInterno} · Est: ${p.estoqueReal} ${p.unidade}',
                        ),
                        trailing: Text(
                          'R\$ ${moeda.format(p.precoVenda)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        onTap: () => abrirProdutoRelatorio(
                          context,
                          produtoRepository: widget.produtoRepository,
                          produtoId: p.id,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
