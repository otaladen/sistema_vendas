import '../../model/fornecedor_nfe.dart';
import '../../model/fechamento_rh_funcionario.dart';
import '../../model/funcionario.dart';
import '../../model/lancamento_funcionario.dart';
import '../../model/historico_entrada.dart';
import '../../model/conferencia_carga_romaneio.dart';
import '../../model/historico_entrega.dart';
import '../../model/kit_orcamento.dart';
import '../../model/promocao.dart';
import '../../model/linha_devolucao_entrada.dart';
import '../../model/linha_troca_saida.dart';
import '../../model/motorista.dart';
import '../../model/recebimento_fiado.dart';
import '../../model/titulo_receber.dart';
import '../../model/nfe_importada_registro.dart';
import '../../model/registro_devolucao.dart';
import '../../model/uso_vale_credito.dart';
import '../../model/vale_credito.dart';
import '../../model/usuario_sistema.dart';
import '../../model/vinculo_fornecedor_produto.dart';
import '../../domain/auditoria_retencao.dart';
import '../../domain/backup_retencao.dart';
import '../../domain/pod_foto_retencao.dart';
import '../app_config_repository.dart';

/// Codecs adicionais para sync LAN (entidades alem de produto/cliente/venda/vendedor).
class SyncEntityCodecExtras {
  static String? _dt(DateTime? d) => d?.toUtc().toIso8601String();
  static DateTime? _parseDt(String? s) =>
      s == null || s.isEmpty ? null : DateTime.tryParse(s)?.toUtc();

  // --- Funcionario ---
  static Map<String, dynamic> funcionarioParaMap(Funcionario f) => {
        'id': f.id,
        'codigoInterno': f.codigoInterno,
        'nomeCompleto': f.nomeCompleto,
        'cargo': f.cargo,
        'setor': f.setor,
        'funcao': f.funcao,
        'funcaoOutro': f.funcaoOutro,
        'cpf': f.cpf,
        'rg': f.rg,
        'pis': f.pis,
        'telefone': f.telefone,
        'whatsapp': f.whatsapp,
        'email': f.email,
        'contatoEmergenciaNome': f.contatoEmergenciaNome,
        'contatoEmergenciaTelefone': f.contatoEmergenciaTelefone,
        'endereco': f.endereco,
        'numero': f.numero,
        'bairro': f.bairro,
        'cidade': f.cidade,
        'uf': f.uf,
        'cep': f.cep,
        'observacoes': f.observacoes,
        'salario': f.salario,
        'descontoAtual': f.descontoAtual,
        'adiantamentoAtual': f.adiantamentoAtual,
        'historicoFinanceiro': f.historicoFinanceiro,
        'valesJson': f.valesJson,
        'diaPagamento': f.diaPagamento,
        'ativo': f.ativo,
        'motivoDemissao': f.motivoDemissao,
        'motivoDemissaoOutro': f.motivoDemissaoOutro,
        'dataNascimento': _dt(f.dataNascimento),
        'dataAdmissao': _dt(f.dataAdmissao),
        'dataDemissao': _dt(f.dataDemissao),
        'vendedorId': f.vendedorId,
        'motoristaId': f.motoristaId,
        'usuarioSistemaId': f.usuarioSistemaId,
        'tipoVinculo': f.tipoVinculo,
        'cnhNumero': f.cnhNumero,
        'cnhCategoria': f.cnhCategoria,
        'cnhValidade': _dt(f.cnhValidade),
        'asoData': _dt(f.asoData),
        'asoValidade': _dt(f.asoValidade),
        'tamanhoUniforme': f.tamanhoUniforme,
        'epiObservacoes': f.epiObservacoes,
        'podeOperarEmpilhadeira': f.podeOperarEmpilhadeira,
        'podeOperarTranspalete': f.podeOperarTranspalete,
        'fotoPath': f.fotoPath,
        'criadoEm': _dt(f.criadoEm),
      };

  static Funcionario funcionarioDeMap(Map<String, dynamic> m) => Funcionario(
        id: (m['id'] as num?)?.toInt() ?? 0,
        codigoInterno: (m['codigoInterno'] ?? '').toString(),
        nomeCompleto: (m['nomeCompleto'] ?? '').toString(),
        cargo: (m['cargo'] ?? '').toString(),
        setor: (m['setor'] ?? '').toString(),
        funcao: (m['funcao'] ?? '').toString(),
        funcaoOutro: (m['funcaoOutro'] ?? '').toString(),
        cpf: (m['cpf'] ?? '').toString(),
        rg: (m['rg'] ?? '').toString(),
        pis: (m['pis'] ?? '').toString(),
        telefone: (m['telefone'] ?? '').toString(),
        whatsapp: (m['whatsapp'] ?? '').toString(),
        email: (m['email'] ?? '').toString(),
        contatoEmergenciaNome: (m['contatoEmergenciaNome'] ?? '').toString(),
        contatoEmergenciaTelefone:
            (m['contatoEmergenciaTelefone'] ?? '').toString(),
        endereco: (m['endereco'] ?? '').toString(),
        numero: (m['numero'] ?? '').toString(),
        bairro: (m['bairro'] ?? '').toString(),
        cidade: (m['cidade'] ?? '').toString(),
        uf: (m['uf'] ?? '').toString(),
        cep: (m['cep'] ?? '').toString(),
        observacoes: (m['observacoes'] ?? '').toString(),
        salario: (m['salario'] as num?)?.toDouble() ?? 0,
        descontoAtual: (m['descontoAtual'] as num?)?.toDouble() ?? 0,
        adiantamentoAtual: (m['adiantamentoAtual'] as num?)?.toDouble() ?? 0,
        historicoFinanceiro: (m['historicoFinanceiro'] ?? '').toString(),
        valesJson: (m['valesJson'] ?? '[]').toString(),
        diaPagamento: (m['diaPagamento'] as num?)?.toInt() ?? 5,
        ativo: m['ativo'] != false,
        motivoDemissao: (m['motivoDemissao'] ?? '').toString(),
        motivoDemissaoOutro: (m['motivoDemissaoOutro'] ?? '').toString(),
        dataNascimento: _parseDt((m['dataNascimento'] ?? '').toString()),
        dataAdmissao: _parseDt((m['dataAdmissao'] ?? '').toString()),
        dataDemissao: _parseDt((m['dataDemissao'] ?? '').toString()),
        vendedorId: (m['vendedorId'] as num?)?.toInt() ?? 0,
        motoristaId: (m['motoristaId'] as num?)?.toInt() ?? 0,
        usuarioSistemaId: (m['usuarioSistemaId'] ?? '').toString(),
        tipoVinculo: (m['tipoVinculo'] ?? 'clt').toString(),
        cnhNumero: (m['cnhNumero'] ?? '').toString(),
        cnhCategoria: (m['cnhCategoria'] ?? '').toString(),
        cnhValidade: _parseDt((m['cnhValidade'] ?? '').toString()),
        asoData: _parseDt((m['asoData'] ?? '').toString()),
        asoValidade: _parseDt((m['asoValidade'] ?? '').toString()),
        tamanhoUniforme: (m['tamanhoUniforme'] ?? '').toString(),
        epiObservacoes: (m['epiObservacoes'] ?? '').toString(),
        podeOperarEmpilhadeira: m['podeOperarEmpilhadeira'] == true,
        podeOperarTranspalete: m['podeOperarTranspalete'] == true,
        fotoPath: (m['fotoPath'] ?? '').toString(),
        criadoEm: _parseDt((m['criadoEm'] ?? '').toString()),
      );

  // --- LancamentoFuncionario ---
  static Map<String, dynamic> lancamentoFuncionarioParaMap(
    LancamentoFuncionario l,
  ) =>
      {
        'id': l.id,
        'tipo': l.tipo,
        'valor': l.valor,
        'observacao': l.observacao,
        'estornado': l.estornado,
        'data': _dt(l.data),
        'criadoEm': _dt(l.criadoEm),
        'funcionarioId': l.funcionario.targetId,
      };

  static LancamentoFuncionario lancamentoFuncionarioDeMap(
    Map<String, dynamic> m,
  ) {
    final l = LancamentoFuncionario(
      id: (m['id'] as num?)?.toInt() ?? 0,
      tipo: (m['tipo'] ?? 'vale').toString(),
      valor: (m['valor'] as num?)?.toDouble() ?? 0,
      observacao: (m['observacao'] ?? '').toString(),
      estornado: m['estornado'] == true,
      data: _parseDt((m['data'] ?? '').toString()),
      criadoEm: _parseDt((m['criadoEm'] ?? '').toString()),
    );
    final fid = (m['funcionarioId'] as num?)?.toInt() ?? 0;
    if (fid > 0) {
      l.funcionario.targetId = fid;
    }
    return l;
  }

  // --- FechamentoRhFuncionario ---
  static Map<String, dynamic> fechamentoRhParaMap(FechamentoRhFuncionario f) =>
      {
        'id': f.id,
        'funcionarioId': f.funcionarioId,
        'mesReferencia': _dt(f.mesReferencia),
        'salarioBase': f.salarioBase,
        'descontoFixo': f.descontoFixo,
        'totalVales': f.totalVales,
        'totalDescontosLancados': f.totalDescontosLancados,
        'totalBonus': f.totalBonus,
        'liquidoApagar': f.liquidoApagar,
        'qtdVales': f.qtdVales,
        'contaPagarId': f.contaPagarId,
        'fechadoPorLogin': f.fechadoPorLogin,
        'fechadoEm': _dt(f.fechadoEm),
      };

  static FechamentoRhFuncionario fechamentoRhDeMap(Map<String, dynamic> m) =>
      FechamentoRhFuncionario(
        id: (m['id'] as num?)?.toInt() ?? 0,
        funcionarioId: (m['funcionarioId'] as num?)?.toInt() ?? 0,
        mesReferencia:
            _parseDt((m['mesReferencia'] ?? '').toString()) ?? DateTime.now(),
        salarioBase: (m['salarioBase'] as num?)?.toDouble() ?? 0,
        descontoFixo: (m['descontoFixo'] as num?)?.toDouble() ?? 0,
        totalVales: (m['totalVales'] as num?)?.toDouble() ?? 0,
        totalDescontosLancados:
            (m['totalDescontosLancados'] as num?)?.toDouble() ?? 0,
        totalBonus: (m['totalBonus'] as num?)?.toDouble() ?? 0,
        liquidoApagar: (m['liquidoApagar'] as num?)?.toDouble() ?? 0,
        qtdVales: (m['qtdVales'] as num?)?.toInt() ?? 0,
        contaPagarId: (m['contaPagarId'] as num?)?.toInt() ?? 0,
        fechadoPorLogin: (m['fechadoPorLogin'] ?? '').toString(),
        fechadoEm: _parseDt((m['fechadoEm'] ?? '').toString()),
      );

  // --- Motorista ---
  static Map<String, dynamic> motoristaParaMap(Motorista m) => {
        'id': m.id,
        'codigoInterno': m.codigoInterno,
        'nome': m.nome,
        'telefone': m.telefone,
        'cpf': m.cpf,
        'cnhNumero': m.cnhNumero,
        'cnhCategoria': m.cnhCategoria,
        'cnhValidade': _dt(m.cnhValidade),
        'ativo': m.ativo,
        'criadoEm': _dt(m.criadoEm),
      };

  static Motorista motoristaDeMap(Map<String, dynamic> m) => Motorista(
        id: (m['id'] as num?)?.toInt() ?? 0,
        codigoInterno: (m['codigoInterno'] ?? '').toString(),
        nome: (m['nome'] ?? '').toString(),
        telefone: (m['telefone'] ?? '').toString(),
        cpf: (m['cpf'] ?? '').toString(),
        cnhNumero: (m['cnhNumero'] ?? '').toString(),
        cnhCategoria: (m['cnhCategoria'] ?? '').toString(),
        cnhValidade: _parseDt((m['cnhValidade'] ?? '').toString()),
        ativo: m['ativo'] != false,
        criadoEm: _parseDt((m['criadoEm'] ?? '').toString()) ?? DateTime.now(),
      );

  // --- Fornecedor NF-e ---
  static Map<String, dynamic> fornecedorNfeParaMap(FornecedorNfe f) => {
        'id': f.id,
        'cnpj': f.cnpj,
        'razaoSocial': f.razaoSocial,
        'nomeFantasia': f.nomeFantasia,
        'inscricaoEstadual': f.inscricaoEstadual,
        'telefone': f.telefone,
        'whatsapp': f.whatsapp,
        'email': f.email,
        'cep': f.cep,
        'endereco': f.endereco,
        'numero': f.numero,
        'bairro': f.bairro,
        'cidade': f.cidade,
        'uf': f.uf,
        'observacoes': f.observacoes,
        'ativo': f.ativo,
        'atualizadoEm': f.atualizadoEm.toUtc().toIso8601String(),
      };

  static FornecedorNfe fornecedorNfeDeMap(Map<String, dynamic> m) =>
      FornecedorNfe(
        id: (m['id'] as num?)?.toInt() ?? 0,
        cnpj: (m['cnpj'] ?? '').toString(),
        razaoSocial: (m['razaoSocial'] ?? '').toString(),
        nomeFantasia: (m['nomeFantasia'] ?? '').toString(),
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
        observacoes: (m['observacoes'] ?? '').toString(),
        ativo: m['ativo'] != false,
        atualizadoEm: _parseDt((m['atualizadoEm'] ?? '').toString()),
      );

  // --- Vinculo ---
  static Map<String, dynamic> vinculoParaMap(VinculoFornecedorProduto v) => {
        'id': v.id,
        'codigoProdutoFornecedor': v.codigoProdutoFornecedor,
        'fatorConversao': v.fatorConversao,
        'fornecedorId': v.fornecedor.targetId,
        'produtoId': v.produto.targetId,
      };

  static VinculoFornecedorProduto vinculoDeMap(Map<String, dynamic> m) =>
      VinculoFornecedorProduto(
        id: (m['id'] as num?)?.toInt() ?? 0,
        codigoProdutoFornecedor: (m['codigoProdutoFornecedor'] ?? '').toString(),
        fatorConversao: (m['fatorConversao'] as num?)?.toDouble() ?? 1,
      );

  // --- Historico entrada ---
  static Map<String, dynamic> historicoEntradaParaMap(HistoricoEntrada h) => {
        'id': h.id,
        'numeroNota': h.numeroNota,
        'chaveAcesso': h.chaveAcesso,
        'dataEmissao': _dt(h.dataEmissao),
        'nomeFornecedor': h.nomeFornecedor,
        'cnpjFornecedor': h.cnpjFornecedor,
        'unidadeFornecedor': h.unidadeFornecedor,
        'quantidadeFornecedor': h.quantidadeFornecedor,
        'fatorConversaoUtilizado': h.fatorConversaoUtilizado,
        'quantidadeEntradaEstoque': h.quantidadeEntradaEstoque,
        'precoCustoUnitarioNota': h.precoCustoUnitarioNota,
        'produtoId': h.produto.targetId,
      };

  static HistoricoEntrada historicoEntradaDeMap(Map<String, dynamic> m) {
    final h = HistoricoEntrada(
      id: (m['id'] as num?)?.toInt() ?? 0,
      numeroNota: (m['numeroNota'] as num?)?.toInt() ?? 0,
      chaveAcesso: (m['chaveAcesso'] ?? '').toString(),
      dataEmissao: _parseDt((m['dataEmissao'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      nomeFornecedor: (m['nomeFornecedor'] ?? '').toString(),
      cnpjFornecedor: (m['cnpjFornecedor'] ?? '').toString(),
      unidadeFornecedor: (m['unidadeFornecedor'] ?? '').toString(),
      quantidadeFornecedor:
          (m['quantidadeFornecedor'] as num?)?.toDouble() ?? 0,
      fatorConversaoUtilizado:
          (m['fatorConversaoUtilizado'] as num?)?.toDouble() ?? 1,
      quantidadeEntradaEstoque:
          (m['quantidadeEntradaEstoque'] as num?)?.toInt() ?? 0,
      precoCustoUnitarioNota:
          (m['precoCustoUnitarioNota'] as num?)?.toDouble() ?? 0,
    );
    final pid = (m['produtoId'] as num?)?.toInt() ?? 0;
    if (pid > 0) {
      try {
        h.produto.targetId = pid;
      } catch (_) {}
    }
    return h;
  }

  // --- NF-e importada ---
  static Map<String, dynamic> nfeImportadaParaMap(NfeImportadaRegistro r) => {
        'id': r.id,
        'chaveAcesso': r.chaveAcesso,
        'numeroNota': r.numeroNota,
        'dataEmissao': _dt(r.dataEmissao),
        'nomeFornecedor': r.nomeFornecedor,
        'cnpjFornecedor': r.cnpjFornecedor,
        'dataHoraImportacao': _dt(r.dataHoraImportacao),
        'quantidadeItens': r.quantidadeItens,
      };

  static NfeImportadaRegistro nfeImportadaDeMap(Map<String, dynamic> m) =>
      NfeImportadaRegistro(
        id: (m['id'] as num?)?.toInt() ?? 0,
        chaveAcesso: (m['chaveAcesso'] ?? '').toString(),
        numeroNota: (m['numeroNota'] as num?)?.toInt() ?? 0,
        dataEmissao: _parseDt((m['dataEmissao'] ?? '').toString()) ??
            DateTime.now().toUtc(),
        nomeFornecedor: (m['nomeFornecedor'] ?? '').toString(),
        cnpjFornecedor: (m['cnpjFornecedor'] ?? '').toString(),
        dataHoraImportacao: _parseDt((m['dataHoraImportacao'] ?? '').toString()) ??
            DateTime.now().toUtc(),
        quantidadeItens: (m['quantidadeItens'] as num?)?.toInt() ?? 0,
      );

  // --- Kit (com itens embutidos) ---
  static Map<String, dynamic> kitParaMap(KitOrcamento k) {
    final itens = <Map<String, dynamic>>[];
    for (final it in k.itens) {
      itens.add({
        'id': it.id,
        'quantidade': it.quantidade,
        'ordem': it.ordem,
        'produtoId': it.produto.targetId,
      });
    }
    return {
      'id': k.id,
      'nome': k.nome,
      'descricao': k.descricao,
      'ativo': k.ativo,
      'criadoEm': _dt(k.criadoEm),
      'itens': itens,
    };
  }

  // --- Promocao (com itens embutidos) ---
  static Map<String, dynamic> promocaoParaMap(Promocao p) {
    final itens = <Map<String, dynamic>>[];
    for (final it in p.itens) {
      itens.add({
        'id': it.id,
        'produtoAlvoId': it.produtoAlvoId,
        'categoria': it.categoria,
        'subcategoria': it.subcategoria,
        'quantidadeMinima': it.quantidadeMinima,
        'quantidadeMaximaPromo': it.quantidadeMaximaPromo,
        'ordem': it.ordem,
      });
    }
    final comboItens = <Map<String, dynamic>>[];
    for (final c in p.comboItens) {
      comboItens.add({
        'id': c.id,
        'produtoAlvoId': c.produtoAlvoId,
        'quantidade': c.quantidade,
        'ordem': c.ordem,
      });
    }
    return {
      'id': p.id,
      'nome': p.nome,
      'descricao': p.descricao,
      'dataInicio': _dt(p.dataInicio),
      'dataFim': _dt(p.dataFim),
      'ativa': p.ativa,
      'prioridade': p.prioridade,
      'tipoRegra': p.tipoRegra,
      'valorRegra': p.valorRegra,
      'segmentoCliente': p.segmentoCliente,
      'tipoCampanha': p.tipoCampanha,
      'margemMinimaPercentual': p.margemMinimaPercentual,
      'limiteQuantidadeTotal': p.limiteQuantidadeTotal,
      'quantidadeVendidaPromo': p.quantidadeVendidaPromo,
      'leveQuantidade': p.leveQuantidade,
      'pagueQuantidade': p.pagueQuantidade,
      'precoCombo': p.precoCombo,
      'criadoEm': _dt(p.criadoEm),
      'itens': itens,
      'comboItens': comboItens,
    };
  }

  // --- Conferencia carga romaneio (montagem / patio) ---
  static Map<String, dynamic> conferenciaCargaRomaneioParaMap(
    ConferenciaCargaRomaneio c,
  ) =>
      {
        'id': c.id,
        'escopoViagem': c.escopoViagem,
        'chaveProduto': c.chaveProduto,
        'conferido': c.conferido,
        'usuarioLogin': c.usuarioLogin,
        'atualizadoEm': _dt(c.atualizadoEm),
      };

  static ConferenciaCargaRomaneio conferenciaCargaRomaneioDeMap(
    Map<String, dynamic> m,
  ) =>
      ConferenciaCargaRomaneio(
        id: (m['id'] as num?)?.toInt() ?? 0,
        escopoViagem: (m['escopoViagem'] ?? '').toString(),
        chaveProduto: (m['chaveProduto'] ?? '').toString(),
        conferido: m['conferido'] == true,
        usuarioLogin: (m['usuarioLogin'] ?? '').toString(),
        atualizadoEm: _parseDt((m['atualizadoEm'] ?? '').toString()),
      );

  // --- Historico entrega ---
  static Map<String, dynamic> historicoEntregaParaMap(HistoricoEntrega h) => {
        'id': h.id,
        'statusAnterior': h.statusAnterior,
        'statusNovo': h.statusNovo,
        'usuario': h.usuario,
        'dataHora': _dt(h.dataHora),
        'vendaId': h.venda.targetId,
      };

  static HistoricoEntrega historicoEntregaDeMap(Map<String, dynamic> m) =>
      HistoricoEntrega(
        id: (m['id'] as num?)?.toInt() ?? 0,
        statusAnterior: (m['statusAnterior'] ?? '').toString(),
        statusNovo: (m['statusNovo'] ?? '').toString(),
        usuario: (m['usuario'] ?? '').toString(),
        dataHora: _parseDt((m['dataHora'] ?? '').toString()),
      );

  // --- Registro devolucao (linhas embutidas) ---
  static Map<String, dynamic> registroDevolucaoParaMap(RegistroDevolucao r) {
    final ent = <Map<String, dynamic>>[];
    for (final l in r.linhasEntrada) {
      ent.add({
        'id': l.id,
        'itemVendaId': l.itemVendaId,
        'quantidade': l.quantidade,
        'precoUnitarioReferencia': l.precoUnitarioReferencia,
        'nomeProdutoSnapshot': l.nomeProdutoSnapshot,
        'produtoId': l.produto.targetId,
      });
    }
    final sai = <Map<String, dynamic>>[];
    for (final l in r.linhasSaidaTroca) {
      sai.add({
        'id': l.id,
        'quantidade': l.quantidade,
        'precoUnitario': l.precoUnitario,
        'precoCustoUnitario': l.precoCustoUnitario,
        'precoTipo': l.precoTipo,
        'nomeProdutoSnapshot': l.nomeProdutoSnapshot,
        'produtoId': l.produto.targetId,
      });
    }
    return {
      'id': r.id,
      'tipo': r.tipo,
      'motivo': r.motivo,
      'observacaoFinanceira': r.observacaoFinanceira,
      'registradoPor': r.registradoPor,
      'data': _dt(r.data),
      'vendaOrigemId': r.vendaOrigem.targetId,
      'linhasEntrada': ent,
      'linhasSaidaTroca': sai,
    };
  }

  static RegistroDevolucao registroDevolucaoDeMap(Map<String, dynamic> m) =>
      RegistroDevolucao(
        id: (m['id'] as num?)?.toInt() ?? 0,
        tipo: (m['tipo'] ?? 'devolucao').toString(),
        motivo: (m['motivo'] ?? '').toString(),
        observacaoFinanceira: (m['observacaoFinanceira'] ?? '').toString(),
        registradoPor: (m['registradoPor'] ?? '').toString(),
        data: _parseDt((m['data'] ?? '').toString()),
      );

  static LinhaDevolucaoEntrada linhaDevolucaoDeMap(Map<String, dynamic> m) =>
      LinhaDevolucaoEntrada(
        id: (m['id'] as num?)?.toInt() ?? 0,
        itemVendaId: (m['itemVendaId'] as num?)?.toInt() ?? 0,
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitarioReferencia:
            (m['precoUnitarioReferencia'] as num?)?.toDouble() ?? 0,
        nomeProdutoSnapshot: (m['nomeProdutoSnapshot'] ?? '').toString(),
      );

  static LinhaTrocaSaida linhaTrocaDeMap(Map<String, dynamic> m) =>
      LinhaTrocaSaida(
        id: (m['id'] as num?)?.toInt() ?? 0,
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitario: (m['precoUnitario'] as num?)?.toDouble() ?? 0,
        precoCustoUnitario: (m['precoCustoUnitario'] as num?)?.toDouble() ?? 0,
        precoTipo: (m['precoTipo'] ?? 'preco1').toString(),
        nomeProdutoSnapshot: (m['nomeProdutoSnapshot'] ?? '').toString(),
      );

  // --- Vale de credito (usos embutidos) ---
  static Map<String, dynamic> valeCreditoParaMap(ValeCredito v) {
    final usos = <Map<String, dynamic>>[];
    for (final u in v.usos) {
      usos.add({
        'id': u.id,
        'valor': u.valor,
        'registradoPor': u.registradoPor,
        'numeroVenda': u.numeroVenda,
        'data': _dt(u.data),
        'vendaId': u.venda.targetId,
      });
    }
    return {
      'id': v.id,
      'codigo': v.codigo,
      'valorOriginal': v.valorOriginal,
      'valorUtilizado': v.valorUtilizado,
      'cancelado': v.cancelado,
      'motivoCancelamento': v.motivoCancelamento,
      'canceladoPor': v.canceladoPor,
      'emitidoPor': v.emitidoPor,
      'observacao': v.observacao,
      'numeroVendaOrigem': v.numeroVendaOrigem,
      'dataEmissao': _dt(v.dataEmissao),
      'dataValidade': _dt(v.dataValidade),
      'dataCancelamento': _dt(v.dataCancelamento),
      'clienteId': v.cliente.targetId,
      'vendaOrigemId': v.vendaOrigem.targetId,
      'registroDevolucaoId': v.registroDevolucao.targetId,
      'usos': usos,
    };
  }

  static ValeCredito valeCreditoDeMap(Map<String, dynamic> m) => ValeCredito(
        id: (m['id'] as num?)?.toInt() ?? 0,
        codigo: (m['codigo'] ?? '').toString(),
        valorOriginal: (m['valorOriginal'] as num?)?.toDouble() ?? 0,
        valorUtilizado: (m['valorUtilizado'] as num?)?.toDouble() ?? 0,
        cancelado: m['cancelado'] == true,
        motivoCancelamento: (m['motivoCancelamento'] ?? '').toString(),
        canceladoPor: (m['canceladoPor'] ?? '').toString(),
        emitidoPor: (m['emitidoPor'] ?? '').toString(),
        observacao: (m['observacao'] ?? '').toString(),
        numeroVendaOrigem: (m['numeroVendaOrigem'] as num?)?.toInt() ?? 0,
        dataEmissao: _parseDt((m['dataEmissao'] ?? '').toString()),
        dataValidade: _parseDt((m['dataValidade'] ?? '').toString()),
        dataCancelamento: _parseDt((m['dataCancelamento'] ?? '').toString()),
      );

  static UsoValeCredito usoValeCreditoDeMap(Map<String, dynamic> m) =>
      UsoValeCredito(
        id: (m['id'] as num?)?.toInt() ?? 0,
        valor: (m['valor'] as num?)?.toDouble() ?? 0,
        registradoPor: (m['registradoPor'] ?? '').toString(),
        numeroVenda: (m['numeroVenda'] as num?)?.toInt() ?? 0,
        data: _parseDt((m['data'] ?? '').toString()),
      );

  // --- Config empresa (registro unico id=1) ---
  /// Campos locais por PC — nao entram no payload de sync (S7).
  // ignore: unused_field
  static const _empresaConfigCamposLocais = {
    'pastaPadraoPdf',
    'impressoraPadrao',
    'logoPath',
    'redeSincronizacaoAtiva',
    'redeModoServidor',
    'redePortaServidor',
    'redeServidorUrl',
    'redeSyncToken',
    'backupAutomaticoPasta',
    'ultimoBackupAutomaticoMs',
    'backupSegundoDestinoPasta',
    'abrirGavetaAutomatica',
    'gavetaPino',
    'modoImpressaoBalcao',
    'escPosLargura',
    'escPosDestino',
    'escPosHost',
    'escPosPortaTcp',
    'escPosPortaCom',
    'pdvAutoImpressaoAoFinalizarVenda',
  };

  static Map<String, dynamic> empresaConfigParaMap(EmpresaConfig c) => {
        'nomeLoja': c.nomeLoja,
        'telefone': c.telefone,
        'endereco': c.endereco,
        'modeloPdf': c.modeloPdf,
        'rodapeNota': c.rodapeNota,
        'rodapeOrcamento': c.rodapeOrcamento,
        'limiteDivergenciaCaixa': c.limiteDivergenciaCaixa,
        'mostrarCampoDescontoCaixa': c.mostrarCampoDescontoCaixa,
        'exigirAutorizacaoSegundaViaCupom': c.exigirAutorizacaoSegundaViaCupom,
        'maxDescontoPercentualPdv': c.maxDescontoPercentualPdv,
        'permitirVendaSemEstoque': c.permitirVendaSemEstoque,
        'pdvBalcaoRapido': c.pdvBalcaoRapido,
        'pdvCheckoutDireto': c.pdvCheckoutDireto,
        'pdvPularDialogOrcamentoSalvo': c.pdvPularDialogOrcamentoSalvo,
        'pdvExigirVendedor': c.pdvExigirVendedor,
        'pdvBloqueioVendedor': c.pdvBloqueioVendedor,
        'pdvBloqueioVendedorInatividadeMinutos':
            c.pdvBloqueioVendedorInatividadeMinutos,
        'pdvBloqueioVendedorAposOrcamento': c.pdvBloqueioVendedorAposOrcamento,
        'pdvExigirClienteRetiradaFutura': c.pdvExigirClienteRetiradaFutura,
        'caixaFiscalNaoBloqueante': c.caixaFiscalNaoBloqueante,
        'caixaLimiteOrcamentosPendentes': c.caixaLimiteOrcamentosPendentes,
        'backupAutomaticoAtivo': c.backupAutomaticoAtivo,
        'backupAutomaticoIntervaloMinutos': c.backupAutomaticoIntervaloMinutos,
        'backupRetencaoMaxCopias': c.backupRetencaoMaxCopias,
        'backupSegundoDestinoAtivo': c.backupSegundoDestinoAtivo,
        'layoutImpressaoJson': c.layoutImpressaoJson,
        'auditoriaRetencaoDias': c.auditoriaRetencaoDias,
        'podFotoRetencaoDias': c.podFotoRetencaoDias,
        'margemMinimaPercentualPadrao': c.margemMinimaPercentualPadrao,
        'umCaixaAbertoPorLoja': c.umCaixaAbertoPorLoja,
        'regimeTributarioEmitente': c.regimeTributarioEmitente,
        'obraCalcTijoloProdutoId': c.obraCalcTijoloProdutoId,
        'obraCalcCimentoProdutoId': c.obraCalcCimentoProdutoId,
        'obraCalcAreiaProdutoId': c.obraCalcAreiaProdutoId,
        'obraCalcPisoProdutoId': c.obraCalcPisoProdutoId,
        'obraCalcPerdaPadraoPct': c.obraCalcPerdaPadraoPct,
        'obraCalcPerdaRebocoPct': c.obraCalcPerdaRebocoPct,
        'obraCalcPerdaPisoPct': c.obraCalcPerdaPisoPct,
        'obraCalcEspessuraRebocoMm': c.obraCalcEspessuraRebocoMm,
        'obraCalcEspessuraContrapisoMm': c.obraCalcEspessuraContrapisoMm,
        'obraCalcM2PorCaixaPiso': c.obraCalcM2PorCaixaPiso,
        'obraCalcGeminiParseAtivo': c.obraCalcGeminiParseAtivo,
        'obraCalcTemplatesJson': c.obraCalcTemplatesJson,
        'obraCalcBritaProdutoId': c.obraCalcBritaProdutoId,
        'obraCalcTelhaProdutoId': c.obraCalcTelhaProdutoId,
        'obraCalcFerroProdutoId': c.obraCalcFerroProdutoId,
        'obraCalcEspessuraLajeMm': c.obraCalcEspessuraLajeMm,
        'obraCalcPerdaLajePct': c.obraCalcPerdaLajePct,
        'obraCalcPerdaFundacaoPct': c.obraCalcPerdaFundacaoPct,
        'obraCalcPerdaTelhadoPct': c.obraCalcPerdaTelhadoPct,
        'obraCalcTelhasPorM2': c.obraCalcTelhasPorM2,
        'obraCalcInclinacaoTelhadoPct': c.obraCalcInclinacaoTelhadoPct,
        'obraCalcUsarSubstitutoEstoqueZero': c.obraCalcUsarSubstitutoEstoqueZero,
      };

  static EmpresaConfig empresaConfigDeMap(
    EmpresaConfig base,
    Map<String, dynamic> m,
  ) {
    return base.copyWith(
      nomeLoja: (m['nomeLoja'] ?? base.nomeLoja).toString(),
      telefone: (m['telefone'] ?? base.telefone).toString(),
      endereco: (m['endereco'] ?? base.endereco).toString(),
      modeloPdf: (m['modeloPdf'] ?? base.modeloPdf).toString(),
      rodapeNota: (m['rodapeNota'] ?? base.rodapeNota).toString(),
      rodapeOrcamento: (m['rodapeOrcamento'] ?? base.rodapeOrcamento).toString(),
      limiteDivergenciaCaixa:
          (m['limiteDivergenciaCaixa'] as num?)?.toDouble() ??
              base.limiteDivergenciaCaixa,
      mostrarCampoDescontoCaixa:
          m['mostrarCampoDescontoCaixa'] as bool? ?? base.mostrarCampoDescontoCaixa,
      exigirAutorizacaoSegundaViaCupom:
          m['exigirAutorizacaoSegundaViaCupom'] as bool? ??
              base.exigirAutorizacaoSegundaViaCupom,
      maxDescontoPercentualPdv:
          (m['maxDescontoPercentualPdv'] as num?)?.toDouble() ??
              base.maxDescontoPercentualPdv,
      permitirVendaSemEstoque:
          m['permitirVendaSemEstoque'] as bool? ?? base.permitirVendaSemEstoque,
      pdvBalcaoRapido:
          m['pdvBalcaoRapido'] as bool? ?? base.pdvBalcaoRapido,
      pdvCheckoutDireto:
          m['pdvCheckoutDireto'] as bool? ?? base.pdvCheckoutDireto,
      pdvPularDialogOrcamentoSalvo:
          m['pdvPularDialogOrcamentoSalvo'] as bool? ??
              base.pdvPularDialogOrcamentoSalvo,
      pdvExigirVendedor:
          m['pdvExigirVendedor'] as bool? ?? base.pdvExigirVendedor,
      pdvBloqueioVendedor:
          m['pdvBloqueioVendedor'] as bool? ?? base.pdvBloqueioVendedor,
      pdvBloqueioVendedorInatividadeMinutos: () {
        final v =
            (m['pdvBloqueioVendedorInatividadeMinutos'] as num?)?.toInt();
        if (v == null) return base.pdvBloqueioVendedorInatividadeMinutos;
        return v.clamp(0, 480);
      }(),
      pdvBloqueioVendedorAposOrcamento:
          m['pdvBloqueioVendedorAposOrcamento'] as bool? ??
              base.pdvBloqueioVendedorAposOrcamento,
      pdvExigirClienteRetiradaFutura:
          m['pdvExigirClienteRetiradaFutura'] as bool? ??
              base.pdvExigirClienteRetiradaFutura,
      caixaFiscalNaoBloqueante:
          m['caixaFiscalNaoBloqueante'] as bool? ??
              base.caixaFiscalNaoBloqueante,
      caixaLimiteOrcamentosPendentes: () {
        final v = (m['caixaLimiteOrcamentosPendentes'] as num?)?.toInt();
        if (v == null) return base.caixaLimiteOrcamentosPendentes;
        return v.clamp(20, 500);
      }(),
      backupAutomaticoAtivo:
          m['backupAutomaticoAtivo'] as bool? ?? base.backupAutomaticoAtivo,
      backupAutomaticoIntervaloMinutos:
          (m['backupAutomaticoIntervaloMinutos'] as num?)?.toInt() ??
              base.backupAutomaticoIntervaloMinutos,
      backupRetencaoMaxCopias: BackupRetencaoOpcoes.normalizar(
        (m['backupRetencaoMaxCopias'] as num?)?.toInt() ??
            base.backupRetencaoMaxCopias,
      ),
      backupSegundoDestinoAtivo:
          m['backupSegundoDestinoAtivo'] as bool? ??
              base.backupSegundoDestinoAtivo,
      // backupSegundoDestinoPasta: local por PC (S7) — preserva [base].
      layoutImpressaoJson:
          (m['layoutImpressaoJson'] ?? base.layoutImpressaoJson).toString(),
      auditoriaRetencaoDias: AuditoriaRetencaoOpcoes.normalizar(
        (m['auditoriaRetencaoDias'] as num?)?.toInt() ??
            base.auditoriaRetencaoDias,
      ),
      podFotoRetencaoDias: PodFotoRetencaoOpcoes.normalizar(
        (m['podFotoRetencaoDias'] as num?)?.toInt() ??
            base.podFotoRetencaoDias,
      ),
      margemMinimaPercentualPadrao: () {
        final v = (m['margemMinimaPercentualPadrao'] as num?)?.toDouble();
        if (v == null) return base.margemMinimaPercentualPadrao;
        return v.clamp(0, 99).toDouble();
      }(),
      umCaixaAbertoPorLoja:
          m['umCaixaAbertoPorLoja'] as bool? ?? base.umCaixaAbertoPorLoja,
      regimeTributarioEmitente: () {
        final v = (m['regimeTributarioEmitente'] as num?)?.toInt();
        if (v == null || v < 1 || v > 3) {
          return base.regimeTributarioEmitente;
        }
        return v;
      }(),
      obraCalcTijoloProdutoId:
          (m['obraCalcTijoloProdutoId'] as num?)?.toInt() ??
              base.obraCalcTijoloProdutoId,
      obraCalcCimentoProdutoId:
          (m['obraCalcCimentoProdutoId'] as num?)?.toInt() ??
              base.obraCalcCimentoProdutoId,
      obraCalcAreiaProdutoId:
          (m['obraCalcAreiaProdutoId'] as num?)?.toInt() ??
              base.obraCalcAreiaProdutoId,
      obraCalcPerdaPadraoPct: () {
        final v = (m['obraCalcPerdaPadraoPct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcPerdaPadraoPct;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPisoProdutoId:
          (m['obraCalcPisoProdutoId'] as num?)?.toInt() ??
              base.obraCalcPisoProdutoId,
      obraCalcPerdaRebocoPct: () {
        final v = (m['obraCalcPerdaRebocoPct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcPerdaRebocoPct;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaPisoPct: () {
        final v = (m['obraCalcPerdaPisoPct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcPerdaPisoPct;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcEspessuraRebocoMm: () {
        final v = (m['obraCalcEspessuraRebocoMm'] as num?)?.toDouble();
        if (v == null) return base.obraCalcEspessuraRebocoMm;
        return v.clamp(5, 50).toDouble();
      }(),
      obraCalcEspessuraContrapisoMm: () {
        final v = (m['obraCalcEspessuraContrapisoMm'] as num?)?.toDouble();
        if (v == null) return base.obraCalcEspessuraContrapisoMm;
        return v.clamp(10, 80).toDouble();
      }(),
      obraCalcM2PorCaixaPiso: () {
        final v = (m['obraCalcM2PorCaixaPiso'] as num?)?.toDouble();
        if (v == null) return base.obraCalcM2PorCaixaPiso;
        return v.clamp(0.1, 10).toDouble();
      }(),
      obraCalcGeminiParseAtivo:
          m['obraCalcGeminiParseAtivo'] as bool? ?? base.obraCalcGeminiParseAtivo,
      obraCalcTemplatesJson:
          (m['obraCalcTemplatesJson'] ?? base.obraCalcTemplatesJson).toString(),
      obraCalcBritaProdutoId:
          (m['obraCalcBritaProdutoId'] as num?)?.toInt() ??
              base.obraCalcBritaProdutoId,
      obraCalcTelhaProdutoId:
          (m['obraCalcTelhaProdutoId'] as num?)?.toInt() ??
              base.obraCalcTelhaProdutoId,
      obraCalcFerroProdutoId:
          (m['obraCalcFerroProdutoId'] as num?)?.toInt() ??
              base.obraCalcFerroProdutoId,
      obraCalcEspessuraLajeMm: () {
        final v = (m['obraCalcEspessuraLajeMm'] as num?)?.toDouble();
        if (v == null) return base.obraCalcEspessuraLajeMm;
        return v.clamp(50, 200).toDouble();
      }(),
      obraCalcPerdaLajePct: () {
        final v = (m['obraCalcPerdaLajePct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcPerdaLajePct;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaFundacaoPct: () {
        final v = (m['obraCalcPerdaFundacaoPct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcPerdaFundacaoPct;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaTelhadoPct: () {
        final v = (m['obraCalcPerdaTelhadoPct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcPerdaTelhadoPct;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcTelhasPorM2: () {
        final v = (m['obraCalcTelhasPorM2'] as num?)?.toDouble();
        if (v == null) return base.obraCalcTelhasPorM2;
        return v.clamp(8, 40).toDouble();
      }(),
      obraCalcInclinacaoTelhadoPct: () {
        final v = (m['obraCalcInclinacaoTelhadoPct'] as num?)?.toDouble();
        if (v == null) return base.obraCalcInclinacaoTelhadoPct;
        return v.clamp(0, 60).toDouble();
      }(),
      obraCalcUsarSubstitutoEstoqueZero:
          m['obraCalcUsarSubstitutoEstoqueZero'] as bool? ??
              base.obraCalcUsarSubstitutoEstoqueZero,
    );
  }

  static Map<String, dynamic> usuariosParaMap(List<UsuarioSistema> lista) =>
      {'usuarios': lista.map((u) => u.toMapParaSync()).toList()};

  /// Mescla usuarios vindos da rede preservando hash de senha local.
  static List<UsuarioSistema> mesclarUsuariosAposSync({
    required List<UsuarioSistema> locais,
    required List<UsuarioSistema> remotos,
  }) {
    final porId = {for (final u in locais) u.id: u};
    final out = <UsuarioSistema>[];
    final vistos = <String>{};

    for (final rem in remotos) {
      if (rem.id.isEmpty) continue;
      vistos.add(rem.id);
      final local = porId[rem.id];
      if (local == null) {
        out.add(rem);
        continue;
      }
      out.add(rem.copyWith(senha: local.senha));
    }

    for (final loc in locais) {
      if (!vistos.contains(loc.id)) {
        out.add(loc);
      }
    }
    return out;
  }

  static List<UsuarioSistema> usuariosDeMap(Map<String, dynamic> m) {
    final raw = m['usuarios'] ?? m['items'] ?? m['data'];
    final list = raw is List
        ? raw
        : (raw is Map && raw['usuarios'] is List)
            ? raw['usuarios'] as List
            : null;
    if (list == null) return [];
    final out = <UsuarioSistema>[];
    for (final e in list) {
      if (e is! Map) continue;
      try {
        final map = Map<String, dynamic>.from(e);
        map.putIfAbsent('senha', () => '');
        out.add(UsuarioSistema.fromMap(map));
      } catch (_) {}
    }
    return out;
  }

  // --- TituloReceber ---
  static Map<String, dynamic> tituloReceberParaMap(TituloReceber t) => {
        'id': t.id,
        'numeroParcela': t.numeroParcela,
        'totalParcelas': t.totalParcelas,
        'valorOriginal': t.valorOriginal,
        'saldo': t.saldo,
        'status': t.status,
        'vencimento': _dt(t.vencimento),
        'dataQuitacao': _dt(t.dataQuitacao),
        'criadoEm': _dt(t.criadoEm),
        'clienteId': t.cliente.targetId,
        'vendaId': t.venda.targetId,
      };

  static TituloReceber tituloReceberDeMap(Map<String, dynamic> m) {
    final t = TituloReceber(
      id: (m['id'] as num?)?.toInt() ?? 0,
      numeroParcela: (m['numeroParcela'] as num?)?.toInt() ?? 1,
      totalParcelas: (m['totalParcelas'] as num?)?.toInt() ?? 1,
      valorOriginal: (m['valorOriginal'] as num?)?.toDouble() ?? 0,
      saldo: (m['saldo'] as num?)?.toDouble() ?? 0,
      status: (m['status'] ?? 'aberto').toString(),
      vencimento: _parseDt((m['vencimento'] ?? '').toString()),
      dataQuitacao: _parseDt((m['dataQuitacao'] ?? '').toString()),
      criadoEm: _parseDt((m['criadoEm'] ?? '').toString()),
    );
    final cid = (m['clienteId'] as num?)?.toInt() ?? 0;
    final vid = (m['vendaId'] as num?)?.toInt() ?? 0;
    if (cid > 0) t.cliente.targetId = cid;
    if (vid > 0) t.venda.targetId = vid;
    return t;
  }

  // --- RecebimentoFiado ---
  static Map<String, dynamic> recebimentoFiadoParaMap(RecebimentoFiado r) => {
        'id': r.id,
        'valorTotal': r.valorTotal,
        'formaPagamento': r.formaPagamento,
        'observacao': r.observacao,
        'alocacoesJson': r.alocacoesJson,
        'data': _dt(r.data),
        'criadoEm': _dt(r.criadoEm),
        'clienteId': r.cliente.targetId,
      };

  static RecebimentoFiado recebimentoFiadoDeMap(Map<String, dynamic> m) {
    final r = RecebimentoFiado(
      id: (m['id'] as num?)?.toInt() ?? 0,
      valorTotal: (m['valorTotal'] as num?)?.toDouble() ?? 0,
      formaPagamento: (m['formaPagamento'] ?? 'dinheiro').toString(),
      observacao: (m['observacao'] ?? '').toString(),
      alocacoesJson: (m['alocacoesJson'] ?? '').toString(),
      data: _parseDt((m['data'] ?? '').toString()),
      criadoEm: _parseDt((m['criadoEm'] ?? '').toString()),
    );
    final cid = (m['clienteId'] as num?)?.toInt() ?? 0;
    if (cid > 0) r.cliente.targetId = cid;
    return r;
  }
}
