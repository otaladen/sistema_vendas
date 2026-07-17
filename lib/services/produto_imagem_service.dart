import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Fotos de produto com reuso: mesma imagem = um arquivo, varios produtos.
class ProdutoImagemService {
  ProdutoImagemService({required this.imagesDirectoryPath});

  final String imagesDirectoryPath;

  Future<String?> selecionarImagemLocal() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
    );
    if (resultado == null || resultado.files.isEmpty) {
      return null;
    }
    return resultado.files.first.path;
  }

  /// Processa e grava como `shared_<sha1>.jpg`.
  ///
  /// Decodifica com o codec nativo do Flutter (Skia) para preservar cores
  /// de WebP/JPEG progressivo etc.; o pacote `image` sozinho corrompe algumas.
  /// Se a origem ja esta na pasta de imagens do app, reutiliza o mesmo arquivo.
  Future<String?> processarESalvarImagemProduto({
    required String sourceImagePath,
    String productIdentifier = '',
    int maxWidth = 1280,
    int jpegQuality = 80,
  }) async {
    final arquivoOrigem = File(sourceImagePath);
    if (!arquivoOrigem.existsSync()) {
      return null;
    }

    final origemAbs = p.normalize(arquivoOrigem.absolute.path);
    final pastaAbs = p.normalize(Directory(imagesDirectoryPath).absolute.path);
    if (p.isWithin(pastaAbs, origemAbs) ||
        p.equals(pastaAbs, p.dirname(origemAbs))) {
      return origemAbs;
    }

    final bytesOriginais = await arquivoOrigem.readAsBytes();
    if (bytesOriginais.isEmpty) return null;

    // JPEG ja no tamanho: copia sem reencodar (qualidade e cores intactas).
    if (_ehJpeg(bytesOriginais) &&
        await _larguraJpegOuZero(bytesOriginais) <= maxWidth) {
      return _gravarBytesCompartilhados(bytesOriginais);
    }

    final rgb = await _decodificarParaRgb(bytesOriginais, maxWidth: maxWidth);
    if (rgb == null) return null;

    final bytesJpeg = Uint8List.fromList(
      img.encodeJpg(rgb, quality: jpegQuality),
    );
    return _gravarBytesCompartilhados(bytesJpeg);
  }

  Future<String> _gravarBytesCompartilhados(Uint8List bytesJpeg) async {
    final hash = sha1.convert(bytesJpeg).toString();
    final destinoPath = p.join(imagesDirectoryPath, 'shared_$hash.jpg');
    final arquivoDestino = File(destinoPath);
    if (!arquivoDestino.existsSync()) {
      await Directory(imagesDirectoryPath).create(recursive: true);
      await arquivoDestino.writeAsBytes(bytesJpeg, flush: true);
    }
    return p.normalize(arquivoDestino.absolute.path);
  }

  /// Skia (Flutter) para decode → RGB uint8 limpo para o encodeJpg.
  /// Transparencia (PNG/WebP) e composta sobre fundo branco — JPEG nao tem alpha
  /// e, sem isso, areas transparentes viram pretas.
  static Future<img.Image?> _decodificarParaRgb(
    Uint8List bytes, {
    required int maxWidth,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxWidth,
      );
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final w = uiImage.width;
      final h = uiImage.height;
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      uiImage.dispose();
      if (byteData == null) return null;

      final rgba = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: byteData.buffer,
        bytesOffset: byteData.offsetInBytes,
        rowStride: w * 4,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return _achatarSobreFundoBranco(rgba);
    } catch (_) {
      // Fallback: pacote image (importacao local etc.).
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      var working = _achatarSobreFundoBranco(decoded);
      if (working.width > maxWidth) {
        working = img.copyResize(
          working,
          width: maxWidth,
          interpolation: img.Interpolation.average,
        );
      }
      return working;
    }
  }

  /// JPEG nao tem canal alpha: fundo transparente vira preto se so remover o A.
  static img.Image _achatarSobreFundoBranco(img.Image origem) {
    final fundo = img.Image(
      width: origem.width,
      height: origem.height,
      numChannels: 3,
    );
    img.fill(fundo, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(fundo, origem);
    return fundo;
  }

  static bool _ehJpeg(Uint8List bytes) {
    return bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  /// 0 = desconhecido / falha → forca reencode pelo caminho seguro.
  static Future<int> _larguraJpegOuZero(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      frame.image.dispose();
      return w;
    } catch (_) {
      return 0;
    }
  }

  /// Apaga so se [contarReferencias] for 0 (nenhum produto aponta para o arquivo).
  Future<void> removerImagemProdutoSeOrfao(
    String? imagePath, {
    required int Function(String absolutePath) contarReferencias,
  }) async {
    if (imagePath == null || imagePath.trim().isEmpty) {
      return;
    }
    final path = p.normalize(File(imagePath).absolute.path);
    if (contarReferencias(path) > 0) {
      return;
    }
    final arquivo = File(path);
    if (arquivo.existsSync()) {
      await arquivo.delete();
    }
  }

  /// Compatibilidade: apaga sem checar referencias (evitar em fluxos de cadastro).
  Future<void> removerImagemProduto(String? imagePath) async {
    await removerImagemProdutoSeOrfao(
      imagePath,
      contarReferencias: (_) => 0,
    );
  }

  /// Une arquivos com o mesmo conteudo em `shared_<hash>.jpg` e devolve
  /// mapa idProduto → novo path (apenas onde muda).
  Future<({Map<int, String> novosPaths, int arquivosRemovidos})>
      consolidarImagensDuplicadas(
    List<({int id, String fotoPath})> produtos,
  ) async {
    await Directory(imagesDirectoryPath).create(recursive: true);

    final hashCanonico = <String, String>{};
    final novosPaths = <int, String>{};
    final candidatosRemocao = <String>{};

    for (final item in produtos) {
      final pathRaw = item.fotoPath.trim();
      if (pathRaw.isEmpty) continue;
      final pathAtual = p.normalize(File(pathRaw).absolute.path);
      final arquivo = File(pathAtual);
      if (!arquivo.existsSync()) continue;

      Uint8List bytes;
      try {
        bytes = await arquivo.readAsBytes();
      } catch (_) {
        continue;
      }
      if (bytes.isEmpty) continue;

      final hash = sha1.convert(bytes).toString();
      var canonico = hashCanonico[hash];
      if (canonico == null) {
        final sharedPath = p.normalize(
          File(
            p.join(imagesDirectoryPath, 'shared_$hash.jpg'),
          ).absolute.path,
        );
        final shared = File(sharedPath);
        if (!shared.existsSync()) {
          if (p.equals(pathAtual, sharedPath)) {
            // ja e o nome canônico
          } else {
            await shared.writeAsBytes(bytes, flush: true);
            candidatosRemocao.add(pathAtual);
          }
        } else if (!p.equals(pathAtual, sharedPath)) {
          candidatosRemocao.add(pathAtual);
        }
        canonico = sharedPath;
        hashCanonico[hash] = canonico;
      } else if (!p.equals(pathAtual, canonico)) {
        candidatosRemocao.add(pathAtual);
      }

      if (!p.equals(pathAtual, canonico)) {
        novosPaths[item.id] = canonico;
      }
    }

    final emUso = hashCanonico.values.toSet();
    var removidos = 0;
    for (final antigo in candidatosRemocao) {
      if (emUso.contains(antigo)) continue;
      final aindaPrecisa = produtos.any((pr) {
        final fp = p.normalize(File(pr.fotoPath.trim()).absolute.path);
        if (fp != antigo) return false;
        final novo = novosPaths[pr.id];
        return novo == null || p.normalize(novo) == antigo;
      });
      if (aindaPrecisa) continue;
      try {
        final f = File(antigo);
        if (f.existsSync()) {
          await f.delete();
          removidos++;
        }
      } catch (_) {}
    }

    return (novosPaths: novosPaths, arquivosRemovidos: removidos);
  }
}
