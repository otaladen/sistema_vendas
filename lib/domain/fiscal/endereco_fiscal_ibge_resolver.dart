import '../../model/cliente.dart';
import '../../services/brasil_api_cep_service.dart';

/// Resolve codigo IBGE (7 digitos) para emissao de NF-e a partir do cadastro do cliente.
class EnderecoFiscalIbgeResolver {
  /// Retorna IBGE ja salvo ou busca na BrasilAPI pelo CEP do endereco de entrega.
  static Future<EnderecoIbgeResolvido> resolverParaCliente(
    Cliente cliente, {
    EnderecoCliente? enderecoPreferido,
  }) async {
    final end = enderecoPreferido ?? cliente.enderecoPadraoEntrega();
    if (end == null) {
      return const EnderecoIbgeResolvido(
        sucesso: false,
        mensagem: 'Cliente sem endereco cadastrado para NF-e.',
      );
    }

    final ibgeSalvo = end.codigoIbge.replaceAll(RegExp(r'\D'), '');
    if (ibgeSalvo.length == 7) {
      return EnderecoIbgeResolvido(
        sucesso: true,
        codigoIbge: ibgeSalvo,
        endereco: end,
        origem: 'cadastro',
      );
    }

    final cep = end.cep.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      return const EnderecoIbgeResolvido(
        sucesso: false,
        mensagem: 'Informe um CEP valido no cadastro do cliente.',
      );
    }

    try {
      final dados = await BrasilApiCepService.consultarComIbge(cep);
      if (dados == null) {
        return const EnderecoIbgeResolvido(
          sucesso: false,
          mensagem: 'CEP nao encontrado na BrasilAPI.',
        );
      }
      final ibge = dados.codigoIbge.replaceAll(RegExp(r'\D'), '');
      if (ibge.length != 7) {
        return const EnderecoIbgeResolvido(
          sucesso: false,
          mensagem:
              'BrasilAPI nao retornou codigo IBGE para este CEP. '
              'Atualize o cadastro manualmente.',
        );
      }

      final enderecoAtualizado = EnderecoCliente(
        tipo: end.tipo,
        rotulo: end.rotulo,
        nomeObra: end.nomeObra,
        padraoCarreto: end.padraoCarreto,
        cep: end.cep.trim().isNotEmpty ? end.cep : dados.cep,
        endereco: end.endereco.trim().isNotEmpty ? end.endereco : dados.logradouro,
        numero: end.numero,
        bairro: end.bairro.trim().isNotEmpty ? end.bairro : dados.bairro,
        cidade: end.cidade.trim().isNotEmpty ? end.cidade : dados.cidade,
        uf: end.uf.trim().isNotEmpty ? end.uf : dados.uf,
        referencia: end.referencia,
        codigoIbge: ibge,
      );

      return EnderecoIbgeResolvido(
        sucesso: true,
        codigoIbge: ibge,
        endereco: enderecoAtualizado,
        origem: 'brasilapi_cep',
      );
    } catch (e) {
      return EnderecoIbgeResolvido(
        sucesso: false,
        mensagem: 'Falha ao consultar CEP na BrasilAPI: $e',
      );
    }
  }

  /// Persiste o IBGE no JSON de enderecos do cliente (nao altera estoque).
  static Cliente aplicarIbgeNoCliente(
    Cliente cliente,
    EnderecoCliente enderecoComIbge,
  ) {
    final lista = cliente.listarEnderecos();
    if (lista.isEmpty) {
      cliente.cep = enderecoComIbge.cep;
      cliente.endereco = enderecoComIbge.endereco;
      cliente.numero = enderecoComIbge.numero;
      cliente.bairro = enderecoComIbge.bairro;
      cliente.cidade = enderecoComIbge.cidade;
      cliente.uf = enderecoComIbge.uf;
      cliente.referencia = enderecoComIbge.referencia;
      return cliente;
    }

    final atualizados = lista.map((e) {
      final mesmo = e.tipo == enderecoComIbge.tipo &&
          e.cep.replaceAll(RegExp(r'\D'), '') ==
              enderecoComIbge.cep.replaceAll(RegExp(r'\D'), '') &&
          e.endereco.trim() == enderecoComIbge.endereco.trim();
      if (mesmo) return enderecoComIbge;
      return e;
    }).toList();

    cliente.definirEnderecos(atualizados);
    return cliente;
  }
}

class EnderecoIbgeResolvido {
  const EnderecoIbgeResolvido({
    required this.sucesso,
    this.codigoIbge = '',
    this.endereco,
    this.mensagem = '',
    this.origem = '',
  });

  final bool sucesso;
  final String codigoIbge;
  final EnderecoCliente? endereco;
  final String mensagem;
  final String origem;
}
