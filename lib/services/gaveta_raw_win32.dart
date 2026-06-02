import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Envia bytes ESC/POS em modo RAW para a fila da impressora (USB/driver Windows).
Future<void> enviarRawImpressoraWindows(
  String printerName,
  Uint8List data,
) async {
  if (data.isEmpty) return;
  final nome = printerName.trim();
  if (nome.isEmpty) {
    throw ArgumentError('Nome da impressora vazio.');
  }

  final namePtr = nome.toNativeUtf16();
  final hPrinterPtr = calloc<HANDLE>();
  var hPrinter = 0;
  Pointer<Utf16>? docNamePtr;
  Pointer<Utf16>? dataTypePtr;
  Pointer<DOC_INFO_1>? docInfoPtr;

  try {
    if (OpenPrinter(namePtr, hPrinterPtr, nullptr) == 0) {
      throw WindowsException(GetLastError());
    }
    hPrinter = hPrinterPtr.value;

    docNamePtr = 'Gaveta ESC/POS'.toNativeUtf16();
    dataTypePtr = 'RAW'.toNativeUtf16();
    docInfoPtr = calloc<DOC_INFO_1>();
    docInfoPtr.ref
      ..pDocName = docNamePtr
      ..pOutputFile = nullptr
      ..pDatatype = dataTypePtr;

    if (StartDocPrinter(hPrinter, 1, docInfoPtr.cast()) == 0) {
      throw WindowsException(GetLastError());
    }
    try {
      if (StartPagePrinter(hPrinter) == 0) {
        throw WindowsException(GetLastError());
      }
      try {
        final buffer = calloc<Uint8>(data.length);
        try {
          buffer.asTypedList(data.length).setAll(0, data);
          final written = calloc<DWORD>();
          try {
            if (WritePrinter(hPrinter, buffer, data.length, written) == 0) {
              throw WindowsException(GetLastError());
            }
          } finally {
            free(written);
          }
        } finally {
          free(buffer);
        }
      } finally {
        EndPagePrinter(hPrinter);
      }
    } finally {
      EndDocPrinter(hPrinter);
    }
  } finally {
    free(namePtr);
    free(hPrinterPtr);
    if (docInfoPtr != null) free(docInfoPtr);
    if (docNamePtr != null) free(docNamePtr);
    if (dataTypePtr != null) free(dataTypePtr);
    if (hPrinter != 0) {
      ClosePrinter(hPrinter);
    }
  }
}
