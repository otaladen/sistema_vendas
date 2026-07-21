import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'produto_imagem_service.dart';

/// Fotos de funcionario (mesmo pipeline de compressao dos produtos).
class FuncionarioImagemService {
  FuncionarioImagemService({required this.imagesDirectoryPath})
      : _produto = ProdutoImagemService(
          imagesDirectoryPath: imagesDirectoryPath,
        );

  final String imagesDirectoryPath;
  final ProdutoImagemService _produto;

  static bool get cameraDisponivel =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Caminho absoluto existente, ou relativo na pasta de imagens.
  String? resolverArquivoExistente(String? fotoPath) {
    final raw = (fotoPath ?? '').trim();
    if (raw.isEmpty) return null;
    final abs = File(p.normalize(raw));
    if (abs.existsSync()) return abs.path;
    final rel = File(p.join(imagesDirectoryPath, p.basename(raw)));
    if (rel.existsSync()) return p.normalize(rel.path);
    return null;
  }

  Future<String?> selecionarArquivoLocal() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
    );
    if (resultado == null || resultado.files.isEmpty) return null;
    return resultado.files.first.path;
  }

  Future<String?> capturarFotoCamera() async {
    if (!cameraDisponivel) return null;
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 88,
      maxWidth: 1600,
    );
    return x?.path;
  }

  Future<String?> selecionarDaGaleria() async {
    if (!cameraDisponivel) {
      return selecionarArquivoLocal();
    }
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    return x?.path;
  }

  Future<String?> processarESalvar({
    required String sourceImagePath,
    String funcionarioIdentifier = '',
  }) {
    return _produto.processarESalvarImagemProduto(
      sourceImagePath: sourceImagePath,
      productIdentifier: funcionarioIdentifier,
      maxWidth: 960,
      jpegQuality: 82,
    );
  }

  Future<void> removerSeOrfao(
    String? imagePath, {
    required int Function(String absolutePath) contarReferencias,
  }) {
    return _produto.removerImagemProdutoSeOrfao(
      imagePath,
      contarReferencias: contarReferencias,
    );
  }
}
