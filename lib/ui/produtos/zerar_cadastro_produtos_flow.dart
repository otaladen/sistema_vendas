import 'package:flutter/material.dart';

import '../../data/produto_repository.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/produto_cadastro_zerar.dart';
import '../../services/auditoria_registrar.dart';

/// Fluxo compartilhado: zerar cadastro de produtos com confirmacao forte.
Future<ProdutoCadastroZerarResultado?> executarZerarCadastroProdutos({
  required BuildContext context,
  required ProdutoRepository produtoRepository,
  void Function(String mensagem, {bool erro})? onStatus,
}) async {
  final total = produtoRepository.listarTodos().length;
  if (total <= 0) {
    onStatus?.call('Nao ha produtos para zerar.', erro: false);
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cadastro ja vazio'),
          content: const Text('Nao ha produtos cadastrados.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return const ProdutoCadastroZerarResultado(
      produtosRemovidos: 0,
      movimentosRemovidos: 0,
      historicosEntradaRemovidos: 0,
      vinculosRemovidos: 0,
      kitsRemovidos: 0,
      kitItensRemovidos: 0,
      promocoesRemovidas: 0,
      promocaoItensRemovidos: 0,
      promocaoCombosRemovidos: 0,
      sugestoesRemovidas: 0,
      metricasSugestaoRemovidas: 0,
      itensListaCompraRemovidos: 0,
      imagensRemovidas: 0,
    );
  }

  if (!context.mounted) return null;
  final confirmar = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _ZerarCadastroConfirmDialog(totalProdutos: total);
    },
  );
  if (confirmar != true) return null;
  if (!context.mounted) return null;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Zerando cadastro de produtos…')),
          ],
        ),
      ),
    ),
  );

  try {
    final resultado = await produtoRepository.zerarCadastroCompleto();
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.estoque,
      acao: AuditoriaAcao.zerarCadastroProdutos,
      entidade: 'produto',
      resumo:
          'Cadastro de produtos zerado (${resultado.produtosRemovidos} itens)',
      detalhes: {
        'produtos': resultado.produtosRemovidos,
        'movimentos': resultado.movimentosRemovidos,
        'historicosEntrada': resultado.historicosEntradaRemovidos,
        'kits': resultado.kitsRemovidos,
        'promocoes': resultado.promocoesRemovidas,
        'imagens': resultado.imagensRemovidas,
      },
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cadastro zerado'),
          content: Text(
            '${resultado.produtosRemovidos} produto(s) removido(s).\n'
            'Pode importar o Chacal/CSV do zero.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    onStatus?.call(
      'Cadastro zerado: ${resultado.produtosRemovidos} produto(s).',
      erro: false,
    );
    return resultado;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Falha ao zerar'),
          content: Text('$e'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    onStatus?.call('Falha ao zerar cadastro: $e', erro: true);
    return null;
  }
}

class _ZerarCadastroConfirmDialog extends StatefulWidget {
  const _ZerarCadastroConfirmDialog({required this.totalProdutos});

  final int totalProdutos;

  @override
  State<_ZerarCadastroConfirmDialog> createState() =>
      _ZerarCadastroConfirmDialogState();
}

class _ZerarCadastroConfirmDialogState
    extends State<_ZerarCadastroConfirmDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = ProdutoCadastroZerarConfirmacao.confirma(_controller.text);
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Zerar cadastro de produtos'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Isto vai apagar os ${widget.totalProdutos} produto(s) do '
              'cadastro para permitir uma nova importacao do zero.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tambem serao removidos: movimentos de estoque, '
              'historico de entrada, kits, promocoes, sugestoes PDV, '
              'vinculos com fornecedor e itens da lista de compras.\n\n'
              'Vendas, clientes e usuarios serao mantidos.',
            ),
            const SizedBox(height: 12),
            Text(
              'Digite ${ProdutoCadastroZerarConfirmacao.frase} para confirmar:',
              style: TextStyle(color: error, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: ProdutoCadastroZerarConfirmacao.frase,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (ok) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: error),
          child: const Text('Zerar cadastro'),
        ),
      ],
    );
  }
}
