import 'dart:typed_data';

import 'gaveta_raw_stub.dart'
    if (dart.library.ffi) 'gaveta_raw_win32.dart' as platform;

Future<void> enviarRawParaImpressora(String nomeImpressora, Uint8List dados) =>
    platform.enviarRawImpressoraWindows(nomeImpressora, dados);
