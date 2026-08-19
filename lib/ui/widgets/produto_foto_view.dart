import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/produto_imagem_lan_service.dart';

/// Como a foto tenta obter o arquivo.
enum ProdutoFotoModo {
  /// Local se existir; senao baixa da LAN (padrao no PC).
  automatico,

  /// So arquivo local. Se faltar, mostra placeholder (listas / miniaturas).
  somenteLocal,

  /// Local se existir; se faltar, mostra "Toque para baixar" e so baixa no toque.
  sobDemanda,
}

/// Exibe foto de produto resolvendo caminho local ou baixando do servidor LAN.
class ProdutoFotoView extends StatefulWidget {
  const ProdutoFotoView({
    super.key,
    required this.fotoPath,
    required this.imagesDirectoryPath,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.borderRadius,
    this.placeholderLabel = 'Sem foto',
    this.errorLabel = 'Foto indisponivel',
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = true,
    /// Se null: celular = [ProdutoFotoModo.sobDemanda], PC = [ProdutoFotoModo.automatico].
    this.modo,
  });

  final String fotoPath;
  final String imagesDirectoryPath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final String placeholderLabel;
  final String errorLabel;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final ProdutoFotoModo? modo;

  static bool get _ehCelular =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  ProdutoFotoModo get _modoEfetivo =>
      modo ??
      (_ehCelular ? ProdutoFotoModo.sobDemanda : ProdutoFotoModo.automatico);

  @override
  State<ProdutoFotoView> createState() => _ProdutoFotoViewState();
}

class _ProdutoFotoViewState extends State<ProdutoFotoView> {
  Future<String?>? _future;
  bool _pediuDownload = false;
  String? _erroDownload;

  @override
  void initState() {
    super.initState();
    _reiniciar();
  }

  @override
  void didUpdateWidget(covariant ProdutoFotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoPath != widget.fotoPath ||
        oldWidget.imagesDirectoryPath != widget.imagesDirectoryPath ||
        oldWidget.modo != widget.modo) {
      _pediuDownload = false;
      _erroDownload = null;
      _reiniciar();
    }
  }

  void _reiniciar() {
    final modo = widget._modoEfetivo;
    final lan = ProdutoImagemLanService(
      imagesDirectoryPath: widget.imagesDirectoryPath,
    );
    final local = lan.resolverSomenteLocal(widget.fotoPath);
    if (local != null) {
      _future = Future<String?>.value(local);
      _erroDownload = null;
      return;
    }
    if (modo == ProdutoFotoModo.somenteLocal) {
      _future = Future<String?>.value(null);
      return;
    }
    if (modo == ProdutoFotoModo.sobDemanda && !_pediuDownload) {
      _future = null;
      return;
    }
    _future = lan.resolverOuBaixar(widget.fotoPath, baixarSeFaltar: true);
  }

  Future<void> _baixarAgora() async {
    setState(() {
      _pediuDownload = true;
      _erroDownload = null;
      _future = null;
    });
    final r = await ProdutoImagemLanService(
      imagesDirectoryPath: widget.imagesDirectoryPath,
    ).baixarComMotivo(widget.fotoPath);
    if (!mounted) return;
    setState(() {
      _erroDownload = r.erro;
      _future = Future<String?>.value(r.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final raw = widget.fotoPath.trim();
    if (raw.isEmpty) {
      return _caixa(
        scheme,
        child: widget.placeholderLabel.isEmpty
            ? Icon(
                Icons.image_outlined,
                size: 20,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
              )
            : Text(widget.placeholderLabel),
      );
    }

    final modo = widget._modoEfetivo;
    if (_future == null &&
        modo == ProdutoFotoModo.sobDemanda &&
        !_pediuDownload) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _baixarAgora,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          child: _caixa(
            scheme,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  size: 22,
                  color: scheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  'Toque para ver foto',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_future == null && _pediuDownload) {
      return _caixa(
        scheme,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _caixa(
            scheme,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final path = snap.data?.trim() ?? '';
        if (path.isEmpty || !File(path).existsSync()) {
          // Miniaturas compactas / modo local: icone simples, sem texto longo.
          final compacto = (widget.width ?? 0) > 0 && (widget.width ?? 0) <= 56;
          if (modo == ProdutoFotoModo.somenteLocal || compacto) {
            return _caixa(
              scheme,
              child: Icon(
                Icons.image_outlined,
                size: compacto ? 18 : 20,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            );
          }
          final msg = (_erroDownload ?? widget.errorLabel).trim();
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _baixarAgora,
              borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
              child: _caixa(
                scheme,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 20,
                        color: scheme.error,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg.isEmpty ? widget.errorLabel : msg,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toque para tentar de novo',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        Widget image = Image.file(
          File(path),
          key: ValueKey(path),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          filterQuality: widget.filterQuality,
          gaplessPlayback: widget.gaplessPlayback,
          errorBuilder: (context, error, stackTrace) =>
              _caixa(scheme, child: Text(widget.errorLabel)),
        );
        final radius = widget.borderRadius;
        if (radius != null) {
          image = ClipRRect(borderRadius: radius, child: image);
        }
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: image,
        );
      },
    );
  }

  Widget _caixa(ColorScheme scheme, {required Widget child}) {
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ) ??
            TextStyle(color: scheme.onSurfaceVariant),
        child: child,
      ),
    );
  }
}
