import '../../model/cliente.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';

/// Serializacao para sync LAN (JSON).
class SyncEntityCodec {
  static Map<String, dynamic> produtoParaMap(Produto p) {
    return {
      'id': p.id,
      'codigoInterno': p.codigoInterno,
      'nome': p.nome,
      'descricao': p.descricao,
      'unidade': p.unidade,
      'categoria': p.categoria,
      'subcategoria': p.subcategoria,
      'marca': p.marca,
      'fornecedor': p.fornecedor,
      'fabricante': p.fabricante,
      'codigoBarras': p.codigoBarras,
      'fotoPath': p.fotoPath,
      'localizacao': p.localizacao,
      'ncm': p.ncm,
      'estoqueReal': p.estoqueReal,
      'estoqueReservado': p.estoqueReservado,
      'quantidadeMinima': p.quantidadeMinima,
      'precoCusto': p.precoCusto,
      'custoMedio': p.custoMedio,
      'preco1': p.preco1,
      'preco2': p.preco2,
      'preco3': p.preco3,
      'precoVenda': p.precoVenda,
      'criadoEm': p.criadoEm.toUtc().toIso8601String(),
      'ativo': p.ativo,
    };
  }

  static Produto produtoDeMap(Map<String, dynamic> m) {
    return Produto(
      id: (m['id'] as num?)?.toInt() ?? 0,
      codigoInterno: (m['codigoInterno'] ?? '').toString(),
      nome: (m['nome'] ?? '').toString(),
      descricao: (m['descricao'] ?? '').toString(),
      unidade: (m['unidade'] ?? 'UN').toString(),
      categoria: (m['categoria'] ?? '').toString(),
      subcategoria: (m['subcategoria'] ?? '').toString(),
      marca: (m['marca'] ?? '').toString(),
      fornecedor: (m['fornecedor'] ?? '').toString(),
      fabricante: (m['fabricante'] ?? '').toString(),
      codigoBarras: (m['codigoBarras'] ?? '').toString(),
      fotoPath: (m['fotoPath'] ?? '').toString(),
      localizacao: (m['localizacao'] ?? '').toString(),
      ncm: (m['ncm'] ?? '').toString(),
      estoqueReal: (m['estoqueReal'] as num?)?.toInt() ?? 0,
      estoqueReservado: (m['estoqueReservado'] as num?)?.toInt() ?? 0,
      quantidadeMinima: (m['quantidadeMinima'] as num?)?.toInt() ?? 0,
      precoCusto: (m['precoCusto'] as num?)?.toDouble() ?? 0,
      custoMedio: (m['custoMedio'] as num?)?.toDouble() ?? 0,
      preco1: (m['preco1'] as num?)?.toDouble() ?? 0,
      preco2: (m['preco2'] as num?)?.toDouble() ?? 0,
      preco3: (m['preco3'] as num?)?.toDouble() ?? 0,
      precoVenda: (m['precoVenda'] as num?)?.toDouble() ?? 0,
      criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
      ativo: m['ativo'] != false,
    );
  }

  static Map<String, dynamic> clienteParaMap(Cliente c) {
    return {
      'id': c.id,
      'tipoPessoa': c.tipoPessoa,
      'nomeRazao': c.nomeRazao,
      'nomeFantasia': c.nomeFantasia,
      'documento': c.documento,
      'inscricaoEstadual': c.inscricaoEstadual,
      'telefone': c.telefone,
      'whatsapp': c.whatsapp,
      'email': c.email,
      'cep': c.cep,
      'endereco': c.endereco,
      'numero': c.numero,
      'bairro': c.bairro,
      'cidade': c.cidade,
      'uf': c.uf,
      'referencia': c.referencia,
      'enderecosJson': c.enderecosJson,
      'limiteCredito': c.limiteCredito,
      'observacoes': c.observacoes,
      'ativo': c.ativo,
      'criadoEm': c.criadoEm.toUtc().toIso8601String(),
    };
  }

  static Cliente clienteDeMap(Map<String, dynamic> m) {
    return Cliente(
      id: (m['id'] as num?)?.toInt() ?? 0,
      tipoPessoa: (m['tipoPessoa'] ?? 'fisica').toString(),
      nomeRazao: (m['nomeRazao'] ?? '').toString(),
      nomeFantasia: (m['nomeFantasia'] ?? '').toString(),
      documento: (m['documento'] ?? '').toString(),
      inscricaoEstadual: (m['inscricaoEstadual'] ?? '').toString(),
      telefone: (m['telefone'] ?? '').toString(),
      whatsapp: (m['whatsapp'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
      cep: (m['cep'] ?? '').toString(),
      endereco: (m['endereco'] ?? '').toString(),
      numero: (m['numero'] ?? '').toString(),
      bairro: (m['bairro'] ?? '').toString(),
      cidade: (m['cidade'] ?? '').toString(),
      uf: (m['uf'] ?? '').toString(),
      referencia: (m['referencia'] ?? '').toString(),
      enderecosJson: (m['enderecosJson'] ?? '').toString(),
      limiteCredito: (m['limiteCredito'] as num?)?.toDouble() ?? 0,
      observacoes: (m['observacoes'] ?? '').toString(),
      ativo: m['ativo'] == true,
      criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
    );
  }

  static Map<String, dynamic> vendedorParaMap(Vendedor v) {
    return {
      'id': v.id,
      'codigoInterno': v.codigoInterno,
      'nomeCompleto': v.nomeCompleto,
      'apelido': v.apelido,
      'telefone': v.telefone,
      'whatsapp': v.whatsapp,
      'email': v.email,
      'percentualComissao': v.percentualComissao,
      'metaMensalValor': v.metaMensalValor,
      'observacoesComerciais': v.observacoesComerciais,
      'ativo': v.ativo,
      'criadoEm': v.criadoEm.toUtc().toIso8601String(),
    };
  }

  static Vendedor vendedorDeMap(Map<String, dynamic> m) {
    return Vendedor(
      id: (m['id'] as num?)?.toInt() ?? 0,
      codigoInterno: (m['codigoInterno'] ?? '').toString(),
      nomeCompleto: (m['nomeCompleto'] ?? '').toString(),
      apelido: (m['apelido'] ?? '').toString(),
      telefone: (m['telefone'] ?? '').toString(),
      whatsapp: (m['whatsapp'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
      percentualComissao: (m['percentualComissao'] as num?)?.toDouble() ?? 0,
      metaMensalValor: (m['metaMensalValor'] as num?)?.toDouble() ?? 0,
      observacoesComerciais: (m['observacoesComerciais'] ?? '').toString(),
      ativo: m['ativo'] != false,
      criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
    );
  }

  static Map<String, dynamic> vendaParaMap(Venda v) {
    final itens = <Map<String, dynamic>>[];
    for (final i in v.itens) {
      itens.add({
        'nomeProduto': i.nomeProduto,
        'quantidade': i.quantidade,
        'quantidadeJaRetirada': i.quantidadeJaRetirada,
        'quantidadeNoCarreto': i.quantidadeNoCarreto,
        'quantidadeDevolvida': i.quantidadeDevolvida,
        'precoTipo': i.precoTipo,
        'precoUnitario': i.precoUnitario,
        'precoCustoUnitario': i.precoCustoUnitario,
        'produtoId': i.produto.targetId,
      });
    }
    return {
      'id': v.id,
      'data': v.data.toUtc().toIso8601String(),
      'total': v.total,
      'custoTotal': v.custoTotal,
      'lucroTotal': v.lucroTotal,
      'status': v.status,
      'numeroOrcamento': v.numeroOrcamento,
      'formaPagamento': v.formaPagamento,
      'quantidadeParcelas': v.quantidadeParcelas,
      'pagamentosJson': v.pagamentosJson,
      'tipoEntrega': v.tipoEntrega,
      'valorFrete': v.valorFrete,
      'enderecoEntrega': v.enderecoEntrega,
      'observacaoEntrega': v.observacaoEntrega,
      'statusEntrega': v.statusEntrega,
      'prioridadeEntrega': v.prioridadeEntrega,
      'janelaEntrega': v.janelaEntrega,
      'dataEntregaMarcada': v.dataEntregaMarcada?.toUtc().toIso8601String(),
      'cargaSeparada': v.cargaSeparada,
      'cargaCarregada': v.cargaCarregada,
      'cargaSaiu': v.cargaSaiu,
      'entregaPendente': v.entregaPendente,
      'cancelada': v.cancelada,
      'motivoCancelamento': v.motivoCancelamento,
      'canceladaPor': v.canceladaPor,
      'canceladaEm': v.canceladaEm?.toUtc().toIso8601String(),
      'idOrcamentoFreteRetiradaAberto': v.idOrcamentoFreteRetiradaAberto,
      'vendaOrigemFreteRetiradaId': v.vendaOrigemFreteRetiradaId,
      'grupoEntregaFreteId': v.grupoEntregaFreteId,
      'complementoEntregaJson': v.complementoEntregaJson,
      'clienteId': v.cliente.targetId,
      'vendedorId': v.vendedor.targetId,
      'itens': itens,
    };
  }

  static Venda vendaCabecaDeMap(Map<String, dynamic> m) {
    return Venda(
      id: (m['id'] as num?)?.toInt() ?? 0,
      data: DateTime.tryParse((m['data'] ?? '').toString())?.toUtc(),
      total: (m['total'] as num?)?.toDouble() ?? 0,
      custoTotal: (m['custoTotal'] as num?)?.toDouble() ?? 0,
      lucroTotal: (m['lucroTotal'] as num?)?.toDouble() ?? 0,
      status: (m['status'] ?? 'orcamento').toString(),
      numeroOrcamento: (m['numeroOrcamento'] as num?)?.toInt() ?? 0,
      formaPagamento: (m['formaPagamento'] ?? 'dinheiro').toString(),
      quantidadeParcelas: (m['quantidadeParcelas'] as num?)?.toInt() ?? 1,
      pagamentosJson: (m['pagamentosJson'] ?? '').toString(),
      tipoEntrega: (m['tipoEntrega'] ?? 'retirada').toString(),
      valorFrete: (m['valorFrete'] as num?)?.toDouble() ?? 0,
      enderecoEntrega: (m['enderecoEntrega'] ?? '').toString(),
      observacaoEntrega: (m['observacaoEntrega'] ?? '').toString(),
      statusEntrega: (m['statusEntrega'] ?? 'nao_aplicavel').toString(),
      prioridadeEntrega: (m['prioridadeEntrega'] ?? 'normal').toString(),
      janelaEntrega: (m['janelaEntrega'] ?? 'nao_definida').toString(),
      dataEntregaMarcada: DateTime.tryParse(
        (m['dataEntregaMarcada'] ?? '').toString(),
      )?.toUtc(),
      cargaSeparada: m['cargaSeparada'] == true,
      cargaCarregada: m['cargaCarregada'] == true,
      cargaSaiu: m['cargaSaiu'] == true,
      entregaPendente: m['entregaPendente'] == true,
      cancelada: m['cancelada'] == true,
      motivoCancelamento: (m['motivoCancelamento'] ?? '').toString(),
      canceladaPor: (m['canceladaPor'] ?? '').toString(),
      canceladaEm: DateTime.tryParse(
        (m['canceladaEm'] ?? '').toString(),
      )?.toUtc(),
      idOrcamentoFreteRetiradaAberto:
          (m['idOrcamentoFreteRetiradaAberto'] as num?)?.toInt() ?? 0,
      vendaOrigemFreteRetiradaId:
          (m['vendaOrigemFreteRetiradaId'] as num?)?.toInt() ?? 0,
      grupoEntregaFreteId: (m['grupoEntregaFreteId'] as num?)?.toInt() ?? 0,
      complementoEntregaJson: (m['complementoEntregaJson'] ?? '').toString(),
    );
  }

  static ItemVenda itemDeMap(Map<String, dynamic> m) {
    return ItemVenda(
      id: 0,
      nomeProduto: (m['nomeProduto'] ?? '').toString(),
      quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
      quantidadeJaRetirada: (m['quantidadeJaRetirada'] as num?)?.toInt() ?? 0,
      quantidadeNoCarreto: (m['quantidadeNoCarreto'] as num?)?.toInt() ?? 0,
      quantidadeDevolvida: (m['quantidadeDevolvida'] as num?)?.toInt() ?? 0,
      precoTipo: (m['precoTipo'] ?? 'preco1').toString(),
      precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
      precoCustoUnitario: (m['precoCustoUnitario'] as num?)?.toDouble() ?? 0,
    );
  }
}
