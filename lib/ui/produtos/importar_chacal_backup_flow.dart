import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/chacal_backup_import_service.dart';
import '../../data/produto_busca_util.dart';
import '../../data/produto_legado_import_service.dart';
import '../../data/produto_repository.dart';

/// Fluxo compartilhado: escolher backup Chacal (.s3db, .sql, .txt/.json).
Future<void> executarImportacaoChacalBackup({
  required BuildContext context,
  required ProdutoRepository produtoRepository,
  void Function(String mensagem, {bool erro})? onStatus,
}) async {
  final pick = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['s3db', 'sql', 'txt', 'json'],
    dialogTitle: 'Importar backup Chacal (.s3db / .sql / .txt)',
  );
  if (!context.mounted) return;
  if (pick == null || pick.files.isEmpty) return;

  final arquivo = pick.files.single;
  final caminho = arquivo.path;
  if (caminho == null || caminho.trim().isEmpty) {
    await _mostrarErroDialog(
      context,
      'Nao foi possivel ler o caminho do arquivo selecionado.',
    );
    onStatus?.call('Nao foi possivel ler o caminho do arquivo.', erro: true);
    return;
  }

  final tamanhoBytes = await File(caminho).length();
  final tamanhoMb = tamanhoBytes / (1024 * 1024);
  final lower = caminho.toLowerCase();
  final ehSql = lower.endsWith('.sql');
  final ehJsonTxt = lower.endsWith('.txt') || lower.endsWith('.json');

  if (!context.mounted) return;
  final seguir = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirmar importacao Chacal'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Arquivo: ${arquivo.name}'),
              Text('Tamanho: ${tamanhoMb.toStringAsFixed(1)} MB'),
              const SizedBox(height: 12),
              const Text(
                'Isso importa somente o cadastro de produtos do Chacal '
                '(precos, NCM, categorias).\n\n'
                'Nao e uma restauracao completa do sistema. '
                'Vendas, clientes e usuarios atuais serao mantidos.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (ehJsonTxt) ...[
                const SizedBox(height: 12),
                Text(
                  'Exportacao JSON (PRODUTOS.txt): nao inclui saldo de estoque. '
                  'Produtos ja cadastrados mantem o estoque atual; '
                  'produtos novos entram com estoque 0.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (ehSql && tamanhoMb >= 50) ...[
                const SizedBox(height: 12),
                Text(
                  'Arquivo .sql grande: a leitura pode levar 1 a 3 minutos. '
                  'Nao feche o programa — a tela de carregamento ficara visivel.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      );
    },
  );
  if (seguir != true || !context.mounted) return;

  var incluirInativos = false;
  var atualizarExistentes = true;

  ChacalBackupLeituraResumo? leitura;
  try {
    leitura = await _comDialogoCarregando(
      context: context,
      mensagem: ehSql
          ? 'Lendo dump MySQL do Chacal...\nAguarde (arquivo grande).'
          : ehJsonTxt
              ? 'Lendo exportacao JSON do Chacal (PRODUTOS.txt)...'
              : 'Lendo backup Chacal...',
      acao: () => ChacalBackupImportService.lerArquivo(
            caminhoArquivo: caminho,
            incluirInativos: incluirInativos,
          ),
    );
  } catch (e) {
    if (!context.mounted) return;
    await _mostrarErroDialog(
      context,
      'Erro ao ler o backup Chacal:\n\n$e',
    );
    onStatus?.call('Erro ao ler backup Chacal: $e', erro: true);
    return;
  }

  if (!context.mounted) return;
  if (leitura == null || leitura.linhas.isEmpty) {
    await _mostrarErroDialog(
      context,
      'Nenhum produto encontrado no arquivo.\n'
      'Confira se e o backup completo do Chacal (.sql, .s3db ou PRODUTOS.txt).',
    );
    onStatus?.call(
      'Nenhum produto encontrado no backup. Verifique se e o arquivo completo do Chacal.',
      erro: true,
    );
    return;
  }

  final confirmar = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setSt) {
          return AlertDialog(
            title: const Text('Importar produtos Chacal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Arquivo: ${arquivo.name}'),
                  Text('Produtos encontrados: ${leitura!.linhas.length}'),
                  if (leitura!.pulados > 0)
                    Text('Ignorados na leitura: ${leitura!.pulados}'),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Atualizar produto se o codigo ja existir',
                    ),
                    value: atualizarExistentes,
                    onChanged: (v) {
                      setSt(() => atualizarExistentes = v ?? true);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Incluir produtos inativos no Chacal'),
                    value: incluirInativos,
                    onChanged: (v) async {
                      final novo = v ?? false;
                      setSt(() => incluirInativos = novo);
                      try {
                        final relida = await _comDialogoCarregando(
                          context: context,
                          mensagem: 'Relendo backup...',
                          acao: () => ChacalBackupImportService.lerArquivo(
                                caminhoArquivo: caminho,
                                incluirInativos: novo,
                              ),
                        );
                        leitura = relida;
                        setSt(() {});
                      } catch (e) {
                        if (context.mounted) {
                          await _mostrarErroDialog(
                            context,
                            'Erro ao reler backup:\n\n$e',
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'SKU: quando o Chacal nao tiver codigo interno, o sistema '
                    'gera 1, 2, 3... e guarda o GTIN no codigo de barras.\n'
                    'Fotos nao sao importadas. '
                    'No PRODUTOS.txt o estoque existente e preservado.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Importar'),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmar != true || !context.mounted || leitura == null) return;

  late final ProdutoLegadoImportResumo resumo;
  try {
    resumo = await _importarComProgresso(
      context: context,
      total: leitura!.linhas.length,
      acao: (onProgresso) {
        return ProdutoLegadoImportService.importarAsync(
          produtoRepository: produtoRepository,
          linhas: leitura!.linhas,
          atualizarExistentes: atualizarExistentes,
          onProgresso: onProgresso,
        );
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    await _mostrarErroDialog(
      context,
      'Falha ao gravar os produtos:\n\n$e',
    );
    onStatus?.call('Erro na importacao Chacal: $e', erro: true);
    return;
  }

  if (!context.mounted) return;

  final buf = StringBuffer()
    ..write(
      'Importacao concluida.\n\n'
      'Novos: ${resumo.inseridos}\n'
      'Atualizados: ${resumo.atualizados}',
    );
  if (resumo.ignorados > 0) {
    buf.write('\nIgnorados: ${resumo.ignorados}');
  }
  if (resumo.erros.isNotEmpty) {
    buf.write('\nErros: ${resumo.erros.length}');
  }

  final snack = StringBuffer()
    ..write(
      'Importacao Chacal: ${resumo.inseridos} novos, ${resumo.atualizados} atualizados',
    );
  if (resumo.ignorados > 0) {
    snack.write(', ${resumo.ignorados} ignorados');
  }
  if (resumo.erros.isNotEmpty) {
    snack.write('. ${resumo.erros.length} erro(s).');
  }
  onStatus?.call(snack.toString(), erro: resumo.erros.isNotEmpty);

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          resumo.erros.isEmpty
              ? 'Importacao concluida'
              : 'Importacao concluida com avisos',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(buf.toString()),
              if (resumo.erros.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Primeiros erros:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  resumo.erros.length > 25
                      ? '${resumo.erros.take(25).join('\n')}\n... e mais ${resumo.erros.length - 25} linha(s).'
                      : resumo.erros.join('\n'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return;
  await _oferecerRenumerarSkusGrandes(
    context: context,
    produtoRepository: produtoRepository,
    onStatus: onStatus,
  );
}

Future<void> _oferecerRenumerarSkusGrandes({
  required BuildContext context,
  required ProdutoRepository produtoRepository,
  void Function(String mensagem, {bool erro})? onStatus,
}) async {
  final pendentes = produtoRepository
      .listarTodos()
      .where(
        (p) =>
            !produtoEhCadastroInternoSistema(p) &&
            skuPareceCodigoBarrasGtin(p.codigoInterno),
      )
      .length;
  if (pendentes <= 0 || !context.mounted) return;

  final confirmar = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Corrigir SKUs grandes'),
        content: Text(
          'Ha $pendentes produto(s) com SKU no formato de codigo de barras '
          '(numeros longos).\n\n'
          'Deseja renumerar para SKUs curtos (1, 2, 3...), '
          'mantendo o GTIN no campo codigo de barras?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Agora nao'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Renumerar'),
          ),
        ],
      );
    },
  );
  if (confirmar != true || !context.mounted) return;

  late final int feitos;
  try {
    feitos = await _importarComProgresso(
      context: context,
      total: pendentes,
      acao: (onProgresso) {
        return ProdutoLegadoImportService.renumerarSkusBarrasParaSequenciais(
          produtoRepository: produtoRepository,
          onProgresso: onProgresso,
        );
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    await _mostrarErroDialog(context, 'Falha ao renumerar SKUs:\n\n$e');
    onStatus?.call('Erro ao renumerar SKUs: $e', erro: true);
    return;
  }

  if (!context.mounted) return;
  onStatus?.call('SKUs renumerados: $feitos produto(s).');
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('SKUs corrigidos'),
        content: Text(
          '$feitos produto(s) receberam SKU sequencial curto.\n'
          'O codigo de barras (GTIN) foi preservado.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

Future<T> _comDialogoCarregando<T>({
  required BuildContext context,
  required String mensagem,
  required Future<T> Function() acao,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  mensagem,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  try {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return await acao();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

Future<T> _importarComProgresso<T>({
  required BuildContext context,
  required int total,
  required Future<T> Function(void Function(int atual, int total) onProgresso)
      acao,
}) async {
  final progresso = ValueNotifier<(int, int)>((0, total));

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Importando produtos'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progresso,
            builder: (context, value, _) {
              final atual = value.$1;
              final tot = value.$2 <= 0 ? 1 : value.$2;
              final frac = (atual / tot).clamp(0.0, 1.0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Gravando $atual de $tot...\nNao feche o programa.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: frac),
                  const SizedBox(height: 8),
                  Text('${(frac * 100).toStringAsFixed(0)}%'),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  try {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return await acao((atual, tot) {
      progresso.value = (atual, tot);
    });
  } finally {
    progresso.dispose();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

Future<void> _mostrarErroDialog(BuildContext context, String mensagem) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Erro na importacao'),
        content: SingleChildScrollView(
          child: SelectableText(mensagem),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
