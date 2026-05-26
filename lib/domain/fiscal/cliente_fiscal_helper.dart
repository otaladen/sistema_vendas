import '../../model/cliente.dart';

/// Regras de destinatario para NF-e modelo 55 no balcao.
abstract final class ClienteFiscalHelper {
  ClienteFiscalHelper._();

  static bool documentoEhCnpj(String documento) {
    final doc = documento.replaceAll(RegExp(r'\D'), '');
    return doc.length == 14;
  }

  static bool clienteExigeNfe55(Cliente? cliente) {
    if (cliente == null) return false;
    if (cliente.tipoPessoa.trim().toLowerCase() == 'juridica') {
      return true;
    }
    return documentoEhCnpj(cliente.documento);
  }
}
