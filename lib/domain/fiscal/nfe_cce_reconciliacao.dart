import '../../data/nfe_saida_fiscal_store.dart';
import '../../services/focus_nfe_service.dart';
import 'nfe_cce_xml_local_service.dart';
import 'nfe_registro_focus_merge.dart';

/// Reconsulta CC-e pendentes na Focus e arquiva XML local quando disponivel.
Future<NfeSaidaFiscalRegistro> reconsultarCartasCorrecaoPendentes({
  required NfeSaidaFiscalRegistro registro,
  required FocusNfeService focusNfe,
  String? storeDirectoryPath,
}) async {
  if (registro.cartasCorrecaoProcessando <= 0) return registro;
  var atualizado = registro;
  for (final cce in registro.cartasCorrecao.where((c) => c.processando)) {
    final res = await focusNfe.consultarCartaCorrecaoNfe(
      registro.referenciaFocus,
      numeroSequencia: cce.numeroSequencia,
    );
    if (!res.sucesso) continue;
    atualizado = mesclarCartaCorrecaoComResultado(
      atualizado,
      res,
      textoCorrecao: cce.textoCorrecao,
    );
    final chave = atualizado.chaveNfe.replaceAll(RegExp(r'\D'), '');
    final url = res.urlXml.trim();
    if (storeDirectoryPath != null &&
        chave.length == 44 &&
        url.isNotEmpty &&
        !res.processando) {
      await NfeCceXmlLocalService.arquivarOuEnfileirar(
        storeDirectoryPath: storeDirectoryPath,
        chaveAcesso: chave,
        numeroSequencia: cce.numeroSequencia,
        urlXml: url,
      );
    }
  }
  return atualizado;
}
