import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/nfe_saida_xml_store.dart';
import '../../data/sync/nfe_xml_retry_outbox.dart';

/// Baixa e arquiva XML de NF-e de saida a partir da URL Focus.
class NfeXmlLocalService {
  NfeXmlLocalService(
    this._store, {
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final NfeSaidaXmlStore _store;
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
        await NfeXmlRetryOutbox.registrar(
          chaveAcesso: chave,
          urlXml: url,
          cancelada: cancelada,
        );
        return false;
      }
      final body = utf8.decode(response.bodyBytes);
      if (!body.contains('<')) {
        await NfeXmlRetryOutbox.registrar(
          chaveAcesso: chave,
          urlXml: url,
          cancelada: cancelada,
        );
        return false;
      }
      _store.salvarXml(chave, body, cancelada: cancelada);
      await NfeXmlRetryOutbox.remover(
        chaveAcesso: chave,
        cancelada: cancelada,
      );
      return true;
    } catch (_) {
      await NfeXmlRetryOutbox.registrar(
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
    final svc = NfeXmlLocalService(NfeSaidaXmlStore(storeDirectoryPath));
    await svc.tentarArquivar(
      chaveAcesso: chave,
      urlXml: url,
      cancelada: cancelada,
    );
  }

  static Future<int> processarFilaRetry(String storeDirectoryPath) async {
    final fila = await NfeXmlRetryOutbox.listar();
    if (fila.isEmpty) return 0;
    final svc = NfeXmlLocalService(NfeSaidaXmlStore(storeDirectoryPath));
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
