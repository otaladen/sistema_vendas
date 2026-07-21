import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/promocao_info_vigente.dart';
import '../model/produto.dart';
import '../services/produto_imagem_lan_service.dart';
import 'theme/app_modulo_cores.dart';
import 'widgets/produto_foto_view.dart';

/// Modal compacto com foto e descricao (PDV e demais telas de venda).
Future<void> mostrarModalDetalheProdutoVenda(
  BuildContext context, {
  required Produto produto,
  List<PromocaoInfoVigente> campanhasVigentes = const [],
  String imagesDirectoryPath = '',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final alturaMax = MediaQuery.sizeOf(dialogContext).height * 0.72;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: alturaMax.clamp(320.0, 640.0),
          ),
          child: ProdutoDetalheVendaConteudo(
            produto: produto,
            campanhasVigentes: campanhasVigentes,
            imagesDirectoryPath: imagesDirectoryPath,
          ),
        ),
      );
    },
  );
}

/// Conteudo do modal de detalhe do produto na venda.
class ProdutoDetalheVendaConteudo extends StatelessWidget {
  const ProdutoDetalheVendaConteudo({
    super.key,
    required this.produto,
    this.campanhasVigentes = const [],
    this.imagesDirectoryPath = '',
  });

  final Produto produto;
  final List<PromocaoInfoVigente> campanhasVigentes;
  final String imagesDirectoryPath;

  Future<void> _abrirZoomFoto(BuildContext context) async {
    if (produto.fotoPath.trim().isEmpty) return;
    final path = await ProdutoImagemLanService(
      imagesDirectoryPath: imagesDirectoryPath,
    ).resolverOuBaixar(produto.fotoPath);
    if (!context.mounted) return;
    if (path == null || path.isEmpty || !File(path).existsSync()) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(ctx).width * 0.85,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFoto(BuildContext context, {required double altura}) {
    final scheme = Theme.of(context).colorScheme;
    final semFoto = produto.fotoPath.trim().isEmpty;
    final foto = ProdutoFotoView(
      fotoPath: produto.fotoPath,
      imagesDirectoryPath: imagesDirectoryPath,
      height: altura,
      width: double.infinity,
      fit: BoxFit.contain,
      borderRadius: BorderRadius.circular(8),
      placeholderLabel: 'Sem foto',
      errorLabel: 'Foto indisponivel',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: semFoto ? null : () => _abrirZoomFoto(context),
            borderRadius: BorderRadius.circular(8),
            child: foto,
          ),
        ),
        if (!semFoto)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Toque na foto para ampliar',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildDescricao(BuildContext context) {
    return ProdutoDescricaoTecnicaInline(
      produto: produto,
      expandir: true,
    );
  }

  Widget _buildBannerCampanhas(BuildContext context) {
    if (campanhasVigentes.isEmpty) return const SizedBox.shrink();
    final fmtData = DateFormat('dd/MM/yyyy');
    final scheme = Theme.of(context).colorScheme;
    final corPromo = AppModuloCores.modulo(context, AppModuloId.promocoes);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: corPromo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: corPromo.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer, color: corPromo, size: 20),
              const SizedBox(width: 6),
              Text(
                'Campanha promocional ativa',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: corPromo,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final c in campanhasVigentes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.nome,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${c.rotuloTipoCampanha} · ${c.resumoRegra} · '
                    'ate ${fmtData.format(c.dataFim.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    c.textoPrecoParaVendedor,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: corPromo,
                        ),
                  ),
                  if (c.textoPrecoComplementar != null)
                    Text(
                      c.textoPrecoComplementar!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  if (c.quantidadeMaximaPorVenda > 0)
                    Text(
                      'Max. ${c.quantidadeMaximaPorVenda} un. por venda',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (c.quantidadeRestanteGlobal > 0)
                    Text(
                      'Restam ${c.quantidadeRestanteGlobal} un. na campanha',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (c.margemMinimaPercentual > 0)
                    Text(
                      'Margem minima: ${c.margemMinimaPercentual.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'SKU: ${produto.codigoInterno}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (campanhasVigentes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _buildBannerCampanhas(context),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ladoALado = constraints.maxWidth >= 420;
                if (ladoALado) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 200,
                        child: _buildFoto(context, altura: 200),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: _buildDescricao(context)),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFoto(context, altura: 160),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _buildDescricao(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bloco de descricao tecnica (painel PDV ou modal).
class ProdutoDescricaoTecnicaInline extends StatelessWidget {
  const ProdutoDescricaoTecnicaInline({
    super.key,
    required this.produto,
    this.alturaMaxima = 160,
    this.expandir = false,
    this.compacto = false,
  });

  final Produto produto;
  final double alturaMaxima;
  final bool expandir;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final desc = produto.descricao.trim().isEmpty
        ? 'Sem descricao tecnica cadastrada.'
        : produto.descricao.trim();

    final caixa = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          desc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );

    final conteudo = expandir
        ? Expanded(child: caixa)
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: alturaMaxima),
            child: caixa,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: expandir ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Text(
          'Descricao tecnica',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: compacto ? 13 : null,
              ),
        ),
        const SizedBox(height: 6),
        conteudo,
      ],
    );
  }
}

/// Pagina cheia legada; prefira [mostrarModalDetalheProdutoVenda].
@Deprecated('Use mostrarModalDetalheProdutoVenda para nao ocupar a tela inteira.')
class ProdutoDetalheVendaPage extends StatelessWidget {
  const ProdutoDetalheVendaPage({super.key, required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do Produto')),
      body: ProdutoDetalheVendaConteudo(produto: produto),
    );
  }
}
