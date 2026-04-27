import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

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

  Future<String?> processarESalvarImagemProduto({
    required String sourceImagePath,
    required String productIdentifier,
    int maxWidth = 1280,
    int jpegQuality = 80,
  }) async {
    final arquivoOrigem = File(sourceImagePath);
    if (!arquivoOrigem.existsSync()) {
      return null;
    }

    final bytesOriginais = await arquivoOrigem.readAsBytes();
    final imagemDecodificada = img.decodeImage(bytesOriginais);
    if (imagemDecodificada == null) {
      return null;
    }

    final imagemFinal = imagemDecodificada.width > maxWidth
        ? img.copyResize(imagemDecodificada, width: maxWidth)
        : imagemDecodificada;

    final bytesJpeg = Uint8List.fromList(img.encodeJpg(imagemFinal, quality: jpegQuality));
    final safeId = _sanitizeFileName(productIdentifier);
    final fileName = 'produto_$safeId.jpg';
    final destinoPath = p.join(imagesDirectoryPath, fileName);
    final arquivoDestino = File(destinoPath);
    await arquivoDestino.writeAsBytes(bytesJpeg, flush: true);
    return destinoPath;
  }

  Future<void> removerImagemProduto(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) {
      return;
    }
    final arquivo = File(imagePath);
    if (arquivo.existsSync()) {
      await arquivo.delete();
    }
  }

  String _sanitizeFileName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  }
}
