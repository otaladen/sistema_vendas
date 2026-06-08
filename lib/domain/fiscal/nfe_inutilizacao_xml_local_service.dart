import 'package:http/http.dart' as http;

import '../../data/nfe_inutilizacao_store.dart';
import '../../data/nfe_inutilizacao_xml_store.dart';
import '../../services/focus_nfe_service.dart';

/// Resultado ao tentar recuperar XML de inutilizacao.
class NfeInutilizacaoXmlRecuperacaoResultado {
  const NfeInutilizacaoXmlRecuperacaoResultado({
    required this.sucesso,
    required this.mensagem,
    this.jaExistia = false,
  });

  final bool sucesso;
  final String mensagem;
  final bool jaExistia;

  factory NfeInutilizacaoXmlRecuperacaoResultado.erro(String mensagem) {
    return NfeInutilizacaoXmlRecuperacaoResultado(
      sucesso: false,
      mensagem: mensagem,
    );
  }
}

/// Arquiva e recupera XML de inutilizacao NF-e (corpo ou download Focus).
abstract final class NfeInutilizacaoXmlLocalService {
  NfeInutilizacaoXmlLocalService._();

  static bool possuiXmlLocal({
    required String storeDirectoryPath,
    required String registroId,
  }) {
    return NfeInutilizacaoXmlStore(storeDirectoryPath).existe(registroId.trim());
  }

  static Future<void> arquivarSePossivel({
    required String storeDirectoryPath,
    required String registroId,
    required FocusNfeOperacaoSimplesResultado resultado,
    FocusNfeService? focusNfe,
    http.Client? httpClient,
  }) async {
    final id = registroId.trim();
    if (id.isEmpty || !resultado.sucesso) return;

    final store = NfeInutilizacaoXmlStore(storeDirectoryPath);
    if (store.existe(id)) return;

    final corpo = resultado.xmlCorpo.trim();
    if (corpo.startsWith('<')) {
      store.salvarXml(id, corpo);
      return;
    }

    final url = resultado.urlXml.trim();
    if (url.isEmpty) return;

    final xml = await _baixarXml(
      url: url,
      focusNfe: focusNfe,
      httpClient: httpClient,
    );
    if (xml != null) {
      store.salvarXml(id, xml);
    }
  }

  static Future<NfeInutilizacaoXmlRecuperacaoResultado> recuperarXml({
    required String storeDirectoryPath,
    required NfeInutilizacaoRegistro registro,
    FocusNfeService? focusNfe,
    http.Client? httpClient,
  }) async {
    if (!registro.sucesso) {
      return NfeInutilizacaoXmlRecuperacaoResultado.erro(
        'Inutilizacao nao foi homologada na SEFAZ.',
      );
    }

    final id = registro.id.trim();
    final store = NfeInutilizacaoXmlStore(storeDirectoryPath);
    if (store.existe(id)) {
      return const NfeInutilizacaoXmlRecuperacaoResultado(
        sucesso: true,
        jaExistia: true,
        mensagem: 'XML ja arquivado neste computador.',
      );
    }

    final url = registro.urlXml.trim();
    if (url.isEmpty) {
      final prot = registro.protocolo.trim();
      return NfeInutilizacaoXmlRecuperacaoResultado.erro(
        prot.isEmpty
            ? 'Este registro antigo nao guardou a URL do XML. '
                'Consulte o painel Focus NFe ou peca ao contador pelo protocolo.'
            : 'URL do XML nao salva neste registro. Protocolo SEFAZ: $prot. '
                'Tente localizar o XML no painel Focus NFe.',
      );
    }

    if (focusNfe != null) {
      try {
        focusNfe.validarConfiguracao();
      } catch (e) {
        return NfeInutilizacaoXmlRecuperacaoResultado.erro('$e');
      }
    }

    final xml = await _baixarXml(
      url: url,
      focusNfe: focusNfe,
      httpClient: httpClient,
    );
    if (xml == null || xml.trim().isEmpty) {
      return NfeInutilizacaoXmlRecuperacaoResultado.erro(
        'Nao foi possivel baixar o XML na Focus. Verifique internet, token '
        'e se o link ainda e valido.',
      );
    }

    store.salvarXml(id, xml);
    return const NfeInutilizacaoXmlRecuperacaoResultado(
      sucesso: true,
      mensagem: 'XML baixado e salvo com sucesso.',
    );
  }

  static Future<String?> _baixarXml({
    required String url,
    FocusNfeService? focusNfe,
    http.Client? httpClient,
  }) async {
    final focus = focusNfe;
    if (focus != null) {
      try {
        final autenticado = await focus.baixarDocumentoXml(url);
        if (autenticado != null && autenticado.trim().isNotEmpty) {
          return autenticado;
        }
      } catch (_) {}
    }

    final client = httpClient ?? http.Client();
    try {
      final response =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.trim().startsWith('<')) {
        return response.body;
      }
    } catch (_) {}
    return null;
  }
}
