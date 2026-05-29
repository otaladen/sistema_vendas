import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/nfce_saida_xml_store.dart';
import '../../data/sync/nfce_xml_retry_outbox.dart';

/// Baixa e arquiva XML de NFC-e a partir da URL Focus (F4/F5).
class NfceXmlLocalService {
  NfceXmlLocalService(
    this._store, {
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final NfceSaidaXmlStore _store;
  final http.Client _http;

  Future<bool> tentarArquivar({
    required String chaveAcesso,
    required String urlXml,
    bool cancelada = false,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final url = urlXml.trim();
    if (chave.length != 44 || url.isEmpty) return false;
    if (_store.existe(chave, cancelada: cancelada)) return true;

    try {
      final response =
          await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await NfceXmlRetryOutbox.registrar(
          chaveAcesso: chave,
          urlXml: url,
          cancelada: cancelada,
        );
        return false;
      }
      final body = utf8.decode(response.bodyBytes);
      if (!body.contains('<')) {
        await NfceXmlRetryOutbox.registrar(
          chaveAcesso: chave,
          urlXml: url,
          cancelada: cancelada,
        );
        return false;
      }
      _store.salvarXml(chave, body, cancelada: cancelada);
      await NfceXmlRetryOutbox.remover(chaveAcesso: chave, cancelada: cancelada);
      return true;
    } catch (_) {
      await NfceXmlRetryOutbox.registrar(
        chaveAcesso: chave,
        urlXml: url,
        cancelada: cancelada,
      );
      return false;
    }
  }

  static Future<void> arquivarOuEnfileirar({
    required String storeDirectoryPath,
    required String chaveAcesso,
    required String urlXml,
    bool cancelada = false,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final url = urlXml.trim();
    if (chave.length != 44 || url.isEmpty) return;
    final svc = NfceXmlLocalService(NfceSaidaXmlStore(storeDirectoryPath));
    await svc.tentarArquivar(
      chaveAcesso: chave,
      urlXml: url,
      cancelada: cancelada,
    );
  }

  static Future<int> processarFilaRetry(String storeDirectoryPath) async {
    final fila = await NfceXmlRetryOutbox.listar();
    if (fila.isEmpty) return 0;
    final svc = NfceXmlLocalService(NfceSaidaXmlStore(storeDirectoryPath));
    var ok = 0;
    for (final item in fila) {
      final arquivou = await svc.tentarArquivar(
        chaveAcesso: item.chaveAcesso,
        urlXml: item.urlXml,
        cancelada: item.cancelada,
      );
      if (arquivou) ok++;
    }
    return ok;
  }
}
