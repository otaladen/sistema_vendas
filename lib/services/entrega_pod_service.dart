import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'entrega_pod_paths.dart';

/// Salva JPEG de prova de entrega (POD) no disco local.
class EntregaPodService {
  EntregaPodService({Directory? diretorioLocal})
      : _dir = diretorioLocal;

  final Directory? _dir;

  Future<Directory> _resolverDir() async {
    final local = _dir;
    if (local != null) return local;
    return EntregaPodPaths.diretorioLocal();
  }

  static bool get cameraDisponivel =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<String?> selecionarFoto() => selecionarFotoGaleria();

  Future<String?> capturarFotoCamera() async {
    if (!cameraDisponivel) return null;
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: EntregaPodPaths.pickerQuality,
      maxWidth: EntregaPodPaths.pickerMaxWidth.toDouble(),
      maxHeight: EntregaPodPaths.pickerMaxWidth.toDouble(),
    );
    return x?.path;
  }

  Future<String?> selecionarFotoGaleria() async {
    if (cameraDisponivel) {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: EntregaPodPaths.pickerQuality,
        maxWidth: EntregaPodPaths.pickerMaxWidth.toDouble(),
        maxHeight: EntregaPodPaths.pickerMaxWidth.toDouble(),
      );
      return x?.path;
    }
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
    );
    if (resultado == null || resultado.files.isEmpty) return null;
    return resultado.files.first.path;
  }

  Future<String?> processarESalvarFotoPod({
    required int vendaId,
    required String sourceImagePath,
    int maxWidth = EntregaPodPaths.jpegMaxWidth,
    int jpegQuality = EntregaPodPaths.jpegQuality,
  }) async {
    final arquivoOrigem = File(sourceImagePath);
    if (!arquivoOrigem.existsSync()) return null;

    final bytesOriginais = await arquivoOrigem.readAsBytes();
    final imagemDecodificada = img.decodeImage(bytesOriginais);
    if (imagemDecodificada == null) return null;

    img.Image imagemFinal = imagemDecodificada;
    if (imagemDecodificada.width > maxWidth) {
      imagemFinal = img.copyResize(imagemDecodificada, width: maxWidth);
    } else if (imagemDecodificada.height > maxWidth) {
      imagemFinal = img.copyResize(imagemDecodificada, height: maxWidth);
    }

    final bytesJpeg = Uint8List.fromList(
      img.encodeJpg(imagemFinal, quality: jpegQuality),
    );

    final dir = await _resolverDir();
    final nome = EntregaPodPaths.nomeArquivoVenda(vendaId);
    final destinoPath = p.join(dir.path, nome);
    await File(destinoPath).writeAsBytes(bytesJpeg, flush: true);

    // Fase 2: copia para pasta do servidor quando este PC hospeda o sync.
    final dirServidor = EntregaPodPaths.diretorioServidorSeExistir();
    if (dirServidor != null) {
      try {
        await File(p.join(dirServidor.path, nome)).writeAsBytes(
          bytesJpeg,
          flush: true,
        );
      } catch (_) {}
    }

    return destinoPath;
  }

  /// Caminho relativo gravado na venda para abrir no servidor (`pod_entrega/arquivo.jpg`).
  String? caminhoRelativoServidorDe(String caminhoLocalCompleto) {
    final nome = p.basename(caminhoLocalCompleto);
    if (nome.isEmpty) return null;
    return '${EntregaPodPaths.subpastaServidor}/$nome';
  }
}
