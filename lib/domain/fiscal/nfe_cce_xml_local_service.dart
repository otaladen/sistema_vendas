import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/nfe_cce_xml_store.dart';
import '../../data/sync/nfe_cce_xml_retry_outbox.dart';

/// Baixa e arquiva XML de CC-e a partir da URL Focus.
class NfeCceXmlLocalService {
  NfeCceXmlLocalService(
    this._store, {
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final NfeCceXmlStore _store;
  final http.Client _http;

  Future<bool> tentarArquivar({
    required String chaveAcesso,
    required int numeroSequencia,
    required String urlXml,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final url = urlXml.trim();
    if (chave.length != 44 || numeroSequencia <= 0 || url.isEmpty) {
      return false;
    }
    if (_store.existe(chave, numeroSequencia)) return true;

    try {
      final response =
          await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await NfeCceXmlRetryOutbox.registrar(
          chaveAcesso: chave,
          numeroSequencia: numeroSequencia,
          urlXml: url,
        );
        return false;
      }
      final body = utf8.decode(response.bodyBytes);
      if (!body.contains('<')) {
        await NfeCceXmlRetryOutbox.registrar(
          chaveAcesso: chave,
          numeroSequencia: numeroSequencia,
          urlXml: url,
        );
        return false;
      }
      _store.salvarXml(chave, numeroSequencia, body);
      await NfeCceXmlRetryOutbox.remover(
        chaveAcesso: chave,
        numeroSequencia: numeroSequencia,
      );
      return true;
    } catch (_) {
      await NfeCceXmlRetryOutbox.registrar(
        chaveAcesso: chave,
        numeroSequencia: numeroSequencia,
        urlXml: url,
      );
      return false;
    }
  }

  static Future<void> arquivarOuEnfileirar({
    required String storeDirectoryPath,
    required String chaveAcesso,
    required int numeroSequencia,
    required String urlXml,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final url = urlXml.trim();
    if (chave.length != 44 || numeroSequencia <= 0 || url.isEmpty) return;
    final svc = NfeCceXmlLocalService(NfeCceXmlStore(storeDirectoryPath));
    await svc.tentarArquivar(
      chaveAcesso: chave,
      numeroSequencia: numeroSequencia,
      urlXml: url,
    );
  }

  static Future<int> processarFilaRetry(String storeDirectoryPath) async {
    final fila = await NfeCceXmlRetryOutbox.listar();
    if (fila.isEmpty) return 0;
    final svc = NfeCceXmlLocalService(NfeCceXmlStore(storeDirectoryPath));
    var ok = 0;
    for (final item in fila) {
      final arquivou = await svc.tentarArquivar(
        chaveAcesso: item.chaveAcesso,
        numeroSequencia: item.numeroSequencia,
        urlXml: item.urlXml,
      );
      if (arquivou) ok++;
    }
    return ok;
  }
}
