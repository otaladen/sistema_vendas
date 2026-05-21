import 'package:flutter/material.dart';

import '../relatorio_export_util.dart';
import '../relatorio_pdf_acoes.dart';

/// Menu padrao de exportacao (PDF imprimir, PDF salvar, CSV) para AppBar.
class RelatorioExportacoesMenu extends StatelessWidget {
  const RelatorioExportacoesMenu({
    super.key,
    required this.nomeArquivo,
    required this.paginasPdf,
    required this.linhasCsv,
    this.mensagemSeVazio = 'Nada para exportar.',
  });

  final String nomeArquivo;
  final List<String> Function() paginasPdf;
  final List<List<String>> Function() linhasCsv;
  final String mensagemSeVazio;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Exportar',
      icon: const Icon(Icons.more_vert),
      onSelected: (acao) async {
        switch (acao) {
          case 'pdf_print':
            await RelatorioPdfAcoes.imprimirPaginas(
              context,
              paginas: paginasPdf(),
              mensagemSeVazio: mensagemSeVazio,
            );
          case 'pdf_save':
            await RelatorioPdfAcoes.salvarPaginas(
              context,
              paginas: paginasPdf(),
              nomeArquivoSemExtensao: nomeArquivo,
              mensagemSeVazio: mensagemSeVazio,
            );
          case 'csv':
            await relatorioSalvarCsv(
              context,
              nomeArquivoSemExtensao: nomeArquivo,
              linhas: linhasCsv(),
              mensagemSeVazio: mensagemSeVazio,
            );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'pdf_print',
          child: ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text('Imprimir PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'pdf_save',
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Salvar PDF'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'csv',
          child: ListTile(
            leading: Icon(Icons.table_rows_outlined),
            title: Text('Exportar CSV'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
