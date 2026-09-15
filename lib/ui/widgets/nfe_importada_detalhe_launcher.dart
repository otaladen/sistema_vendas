import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/api/nfe_importada_api_repository.dart';
import '../../data/api/produto_api_repository.dart';
import '../../data/nfe_entrada_repository.dart';
import '../../model/historico_entrada.dart';
import '../../model/nfe_importada_registro.dart';
import '../fiscal/nfe_devolucao_fornecedor_page.dart';
import '../shell/main_menu_deps.dart';
import 'lan_api_feedback.dart';

/// Abre o mesmo detalhe da tela "NF-e importadas" (bottom sheet).
abstract final class NfeImportadaDetalheLauncher {
  static final _nfData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _nfDataS = DateFormat('dd/MM/yyyy', 'pt_BR');

  static bool _terminalLeve(dynamic produtoRepository) =>
      produtoRepository is ProdutoApiRepository;

  static NfeImportadaApiRepository? _repoRemoto(dynamic nfeImportadaRepository) {
    final r = nfeImportadaRepository;
    return r is NfeImportadaApiRepository ? r : null;
  }

  /// A partir de uma linha do historico de compras do produto.
  static Future<void> abrirPorHistoricoEntrada(
    BuildContext context, {
    required HistoricoEntrada entrada,
    required dynamic produtoRepository,
    dynamic nfeImportadaRepository,
    VoidCallback? onImportacaoAlterada,
  }) async {
    final chave = entrada.chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chave da NF-e invalida ou ausente neste registro.'),
        ),
      );
      return;
    }

    final registro = await _resolverRegistro(
      chave: chave,
      entrada: entrada,
      produtoRepository: produtoRepository,
      nfeImportadaRepository: nfeImportadaRepository,
    );
    if (!context.mounted) return;

    await abrirRegistro(
      context,
      registro: registro,
      produtoRepository: produtoRepository,
      nfeImportadaRepository: nfeImportadaRepository,
      onImportacaoAlterada: onImportacaoAlterada,
    );
  }

  static Future<void> abrirRegistro(
    BuildContext context, {
    required NfeImportadaRegistro registro,
    required dynamic produtoRepository,
    dynamic nfeImportadaRepository,
    VoidCallback? onImportacaoAlterada,
  }) async {
    final terminalLeve = _terminalLeve(produtoRepository);
    List<NfeImportadaDetalheLinha> linhas = const [];
    var temXml = false;
    var carregandoItens = terminalLeve && registro.id > 0;

    if (!terminalLeve) {
      try {
        final ob = produtoRepository.objectBox;
        if (ob != null) {
          final repo = NfeEntradaRepository(ob);
          final historico = repo.listarHistoricoPorChaveNfe(registro.chaveAcesso);
          linhas = historico.map(NfeImportadaDetalheLinha.deHistorico).toList();
          temXml = repo.lerXmlImportacao(registro.chaveAcesso) != null;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return NfeImportadaDetalheSheet(
          registro: registro,
          linhasIniciais: linhas,
          temXmlInicial: temXml,
          carregandoInicial: carregandoItens,
          terminalLeve: terminalLeve,
          nfData: _nfData,
          nfDataS: _nfDataS,
          onCopiar: (label, valor) => _copiar(context, label, valor),
          onDevolver: () {
            Navigator.pop(ctx);
            _abrirDevolucaoFornecedor(
              context,
              registro: registro,
              produtoRepository: produtoRepository,
              nfeImportadaRepository: nfeImportadaRepository,
            );
          },
          onEstornar: () => _confirmarEstornoImportacao(
            ctx,
            context,
            registro: registro,
            produtoRepository: produtoRepository,
            nfeImportadaRepository: nfeImportadaRepository,
            onImportacaoAlterada: onImportacaoAlterada,
          ),
          onBaixarXml: () => _baixarXml(
            context,
            registro: registro,
            produtoRepository: produtoRepository,
            nfeImportadaRepository: nfeImportadaRepository,
          ),
          carregarRemoto: carregandoItens
              ? () async {
                  final repo = _repoRemoto(nfeImportadaRepository);
                  if (repo == null) {
                    throw StateError('Repositorio remoto indisponivel.');
                  }
                  final d = await repo.obterDetalhesRemoto(registro.id);
                  return (
                    linhas: d.itens
                        .map(NfeImportadaDetalheLinha.deRemoto)
                        .toList(growable: false),
                    temXml: d.temXml,
                  );
                }
              : null,
        );
      },
    );
  }

  static Future<NfeImportadaRegistro> _resolverRegistro({
    required String chave,
    required HistoricoEntrada entrada,
    required dynamic produtoRepository,
    dynamic nfeImportadaRepository,
  }) async {
    if (_terminalLeve(produtoRepository)) {
      final repo = _repoRemoto(nfeImportadaRepository);
      if (repo != null) {
        try {
          final listagem = await repo.listarImportadasRemoto(q: chave);
          for (final r in listagem.items) {
            if (r.chaveAcesso.replaceAll(RegExp(r'\D'), '') == chave) {
              return r;
            }
          }
        } catch (_) {}
      }
    } else {
      try {
        final ob = produtoRepository.objectBox;
        if (ob != null) {
          final local = NfeEntradaRepository(ob);
          final reg = local.obterImportacaoPorChave(chave);
          if (reg != null) return reg;
        }
      } catch (_) {}
    }

    return NfeImportadaRegistro(
      chaveAcesso: chave,
      numeroNota: entrada.numeroNota,
      dataEmissao: entrada.dataEmissao,
      nomeFornecedor: entrada.nomeFornecedor,
      cnpjFornecedor: entrada.cnpjFornecedor,
      dataHoraImportacao: entrada.dataEmissao,
      quantidadeItens: 1,
    );
  }

  static void _copiar(BuildContext context, String label, String valor) {
    if (valor.isEmpty) return;
    Clipboard.setData(ClipboardData(text: valor));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado.')),
    );
  }

  static void _abrirDevolucaoFornecedor(
    BuildContext context, {
    required NfeImportadaRegistro registro,
    required dynamic produtoRepository,
    dynamic nfeImportadaRepository,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NfeDevolucaoFornecedorPage(
          produtoRepository: produtoRepository,
          nfeImportadaRepository: nfeImportadaRepository ??
              MainMenuDeps.maybeOf(context)?.nfeImportadaRepository,
          chaveNotaInicial: registro.chaveAcesso,
        ),
      ),
    );
  }

  static Future<void> _baixarXml(
    BuildContext context, {
    required NfeImportadaRegistro registro,
    required dynamic produtoRepository,
    dynamic nfeImportadaRepository,
  }) async {
    try {
      if (_terminalLeve(produtoRepository)) {
        final repo = _repoRemoto(nfeImportadaRepository);
        if (repo == null) {
          throw StateError('Repositorio remoto indisponivel.');
        }
        final arquivo = await repo.baixarXmlRemoto(registro.id);
        final selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar XML da NF-e',
          fileName: arquivo.filename,
          type: FileType.custom,
          allowedExtensions: const ['xml'],
        );
        if (selectedPath == null) return;
        final path = selectedPath.toLowerCase().endsWith('.xml')
            ? selectedPath
            : '$selectedPath.xml';
        await File(path).writeAsBytes(arquivo.bytes, flush: true);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('XML salvo: $path')),
        );
        return;
      }
      final ob = produtoRepository.objectBox;
      if (ob == null) {
        throw StateError('ObjectBox indisponivel.');
      }
      final local = NfeEntradaRepository(ob);
      final xml = local.lerXmlImportacao(registro.chaveAcesso);
      if (xml == null || xml.trim().isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('XML nao encontrado no disco local.')),
        );
        return;
      }
      final chave = registro.chaveAcesso.replaceAll(RegExp(r'\D'), '');
      final selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar XML da NF-e',
        fileName: 'nfe_$chave.xml',
        type: FileType.custom,
        allowedExtensions: const ['xml'],
      );
      if (selectedPath == null) return;
      final path = selectedPath.toLowerCase().endsWith('.xml')
          ? selectedPath
          : '$selectedPath.xml';
      await File(path).writeAsString(xml, flush: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML salvo: $path')),
      );
    } catch (e) {
      if (!context.mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao baixar XML');
    }
  }

  static Future<void> _confirmarEstornoImportacao(
    BuildContext sheetContext,
    BuildContext pageContext, {
    required NfeImportadaRegistro registro,
    required dynamic produtoRepository,
    dynamic nfeImportadaRepository,
    VoidCallback? onImportacaoAlterada,
  }) async {
    final r = registro;
    final nfLabel = r.numeroNota > 0 ? 'NF #${r.numeroNota}' : 'esta NF-e';
    final fornecedor = r.nomeFornecedor.trim().isEmpty
        ? 'fornecedor nao informado'
        : r.nomeFornecedor;

    ValidacaoEstornoNfe validacao;
    var qtdContasPagar = 0;
    final terminalLeve = _terminalLeve(produtoRepository);

    if (terminalLeve) {
      final api = _repoRemoto(nfeImportadaRepository);
      if (api == null) {
        if (!pageContext.mounted) return;
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text('Repositorio remoto de NF-e indisponivel.'),
          ),
        );
        return;
      }
      try {
        final preview = await api.validarEstornoRemoto(r.id);
        validacao = preview.validacao;
        qtdContasPagar = preview.qtdContasPagar;
      } catch (e) {
        if (!pageContext.mounted) return;
        LanApiFeedback.snackErro(
          pageContext,
          e,
          prefixo: 'Falha ao validar estorno',
        );
        return;
      }
    } else {
      final ob = produtoRepository.objectBox;
      if (ob == null) {
        if (!pageContext.mounted) return;
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(content: Text('Banco local indisponivel.')),
        );
        return;
      }
      final repo = NfeEntradaRepository(ob);
      validacao = repo.validarEstornoImportacao(r.id);
      qtdContasPagar = repo.listarContasPagarPorChaveNfe(r.chaveAcesso).length;
    }

    if (!pageContext.mounted) return;

    final confirmou = await showDialog<bool>(
      context: pageContext,
      builder: (ctx) {
        final erro = Theme.of(ctx).colorScheme.error;
        return AlertDialog(
          title: const Text('Estornar importacao?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$nfLabel ($fornecedor) sera desfeita.\n\n'
                  'O estoque e o custo medio das entradas abaixo voltam atras'
                  '${qtdContasPagar > 0 ? ', $qtdContasPagar titulo(s) no '
                      'Contas a Pagar serao removidos' : ''} '
                  'e a chave fica livre para importar o XML de novo.',
                ),
                if (!validacao.podeEstornar) ...[
                  const SizedBox(height: 12),
                  Text(
                    validacao.motivoBloqueio ?? 'Estorno bloqueado.',
                    style: TextStyle(color: erro, fontWeight: FontWeight.w600),
                  ),
                ] else if (validacao.linhas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Reversao de estoque:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ...validacao.linhas.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${l.nomeProduto}: −${l.rotuloEstorno} '
                        '(fisico atual ${l.rotuloEstoqueAtual})',
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Nao ha lancamentos de historico; apenas o registro da '
                    'importacao sera removido.',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: erro,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: validacao.podeEstornar
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Estornar entrada'),
            ),
          ],
        );
      },
    );

    if (confirmou != true || !pageContext.mounted) return;

    try {
      if (terminalLeve) {
        final api = _repoRemoto(nfeImportadaRepository);
        if (api == null) {
          throw StateError('Repositorio remoto de NF-e indisponivel.');
        }
        final m = await api.estornarEntradaRemoto(r.id);
        try {
          final idsRaw = m['produtoIds'];
          final ids = idsRaw is List
              ? idsRaw
                  .map((e) => (e as num?)?.toInt() ?? 0)
                  .where((id) => id > 0)
                  .toList()
              : <int>[];
          final prodRepo = produtoRepository;
          if (prodRepo is ProdutoApiRepository) {
            if (ids.isNotEmpty) {
              await prodRepo.atualizarEstoquePorIds(ids);
            } else {
              prodRepo.invalidarCacheBusca();
            }
          } else {
            prodRepo.invalidarCacheBusca();
          }
        } catch (_) {}
        if (sheetContext.mounted) Navigator.pop(sheetContext);
        onImportacaoAlterada?.call();
        if (!pageContext.mounted) return;
        final msg = (m['mensagem'] ?? '').toString().trim();
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              msg.isNotEmpty
                  ? msg
                  : 'Importacao estornada. Estoque revertido; a nota pode '
                      'ser importada de novo.',
            ),
          ),
        );
      } else {
        final ob = produtoRepository.objectBox;
        if (ob == null) throw StateError('ObjectBox indisponivel.');
        final repo = NfeEntradaRepository(ob);
        repo.estornarImportacaoNfe(r.id);
        produtoRepository.invalidarCacheBusca();
        if (sheetContext.mounted) Navigator.pop(sheetContext);
        onImportacaoAlterada?.call();
        if (!pageContext.mounted) return;
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(
              qtdContasPagar > 0
                  ? 'Importacao estornada. Estoque revertido e '
                      '$qtdContasPagar titulo(s) a pagar removido(s).'
                  : 'Importacao estornada. Estoque revertido; a nota pode '
                      'ser importada de novo.',
            ),
          ),
        );
      }
    } on StateError catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!pageContext.mounted) return;
      LanApiFeedback.snackErro(
        pageContext,
        e,
        prefixo: 'Falha ao estornar importacao',
      );
    }
  }
}

class NfeImportadaDetalheLinha {
  const NfeImportadaDetalheLinha({
    required this.produtoNome,
    required this.quantidadeFornecedor,
    required this.unidadeFornecedor,
    required this.quantidadeEntradaEstoque,
    required this.fatorConversaoUtilizado,
    this.produtoCodigoInterno = '',
  });

  final String produtoNome;
  final String produtoCodigoInterno;
  final double quantidadeFornecedor;
  final String unidadeFornecedor;
  final double quantidadeEntradaEstoque;
  final double fatorConversaoUtilizado;

  factory NfeImportadaDetalheLinha.deHistorico(HistoricoEntrada h) {
    final prod = h.produto.target;
    final nome = prod?.nome.trim().isNotEmpty == true
        ? prod!.nome
        : (prod?.descricao ?? 'Produto');
    return NfeImportadaDetalheLinha(
      produtoNome: nome,
      produtoCodigoInterno: prod?.codigoInterno ?? '',
      quantidadeFornecedor: h.quantidadeFornecedor,
      unidadeFornecedor: h.unidadeFornecedor,
      quantidadeEntradaEstoque: h.quantidadeEntradaEstoque.toDouble(),
      fatorConversaoUtilizado: h.fatorConversaoUtilizado,
    );
  }

  factory NfeImportadaDetalheLinha.deRemoto(NfeImportadaLinhaRemota l) =>
      NfeImportadaDetalheLinha(
        produtoNome: l.produtoNome,
        produtoCodigoInterno: l.produtoCodigoInterno,
        quantidadeFornecedor: l.quantidadeFornecedor,
        unidadeFornecedor: l.unidadeFornecedor,
        quantidadeEntradaEstoque: l.quantidadeEntradaEstoque,
        fatorConversaoUtilizado: l.fatorConversaoUtilizado,
      );
}

class NfeImportadaDetalheSheet extends StatefulWidget {
  const NfeImportadaDetalheSheet({
    super.key,
    required this.registro,
    required this.linhasIniciais,
    required this.temXmlInicial,
    required this.carregandoInicial,
    required this.terminalLeve,
    required this.nfData,
    required this.nfDataS,
    required this.onCopiar,
    required this.onDevolver,
    required this.onEstornar,
    required this.onBaixarXml,
    this.carregarRemoto,
  });

  final NfeImportadaRegistro registro;
  final List<NfeImportadaDetalheLinha> linhasIniciais;
  final bool temXmlInicial;
  final bool carregandoInicial;
  final bool terminalLeve;
  final DateFormat nfData;
  final DateFormat nfDataS;
  final void Function(String label, String valor) onCopiar;
  final VoidCallback onDevolver;
  final VoidCallback onEstornar;
  final VoidCallback onBaixarXml;
  final Future<({List<NfeImportadaDetalheLinha> linhas, bool temXml})> Function()?
      carregarRemoto;

  @override
  State<NfeImportadaDetalheSheet> createState() =>
      _NfeImportadaDetalheSheetState();
}

class _NfeImportadaDetalheSheetState extends State<NfeImportadaDetalheSheet> {
  late List<NfeImportadaDetalheLinha> _linhas = widget.linhasIniciais;
  late bool _temXml = widget.temXmlInicial;
  late bool _carregando = widget.carregandoInicial;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.carregarRemoto != null) {
      unawaited(_carregar());
    }
  }

  Future<void> _carregar() async {
    try {
      final r = await widget.carregarRemoto!();
      if (!mounted) return;
      setState(() {
        _linhas = r.linhas;
        _temXml = r.temXml;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.registro;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.nomeFornecedor.trim().isEmpty
                  ? 'Fornecedor nao informado'
                  : r.nomeFornecedor,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'NF ${r.numeroNota > 0 ? "#${r.numeroNota}" : "—"} · '
              'Emissao ${widget.nfDataS.format(r.dataEmissao.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Importado em ${widget.nfData.format(r.dataHoraImportacao.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => widget.onCopiar('Chave', r.chaveAcesso),
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Copiar chave'),
                ),
                FilledButton.tonalIcon(
                  onPressed: r.cnpjFornecedor.trim().isEmpty
                      ? null
                      : () => widget.onCopiar('CNPJ', r.cnpjFornecedor.trim()),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Copiar CNPJ'),
                ),
                FilledButton.tonalIcon(
                  onPressed: (!_carregando && _erro == null && _temXml)
                      ? widget.onBaixarXml
                      : null,
                  icon: const Icon(Icons.code_outlined, size: 18),
                  label: const Text('Baixar XML'),
                ),
                FilledButton.icon(
                  onPressed: widget.onDevolver,
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Devolver ao fornecedor'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onEstornar,
              icon: Icon(
                Icons.undo_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              label: Text(
                'Estornar importacao (desfazer entrada)',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Itens no estoque (historico por chave)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator())
                  : _erro != null
                      ? Center(
                          child: Text(
                            _erro!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                      : _linhas.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum lancamento de historico para esta chave.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _linhas.length,
                              separatorBuilder: (context, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final h = _linhas[i];
                                return _TileHistoricoImportada(linha: h);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileHistoricoImportada extends StatelessWidget {
  const _TileHistoricoImportada({required this.linha});

  final NfeImportadaDetalheLinha linha;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        linha.produtoCodigoInterno.trim().isEmpty
            ? linha.produtoNome
            : '${linha.produtoCodigoInterno} · ${linha.produtoNome}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Qtd nota ${linha.quantidadeFornecedor} ${linha.unidadeFornecedor} · '
        'Entrada ${linha.quantidadeEntradaEstoque} un. · '
        'Fator ${linha.fatorConversaoUtilizado}',
        style: tema.textTheme.bodySmall,
      ),
    );
  }
}
