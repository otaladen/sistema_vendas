import '../../model/fornecedor_nfe.dart';
import '../../model/fechamento_rh_funcionario.dart';
import '../../model/funcionario.dart';
import '../../model/lancamento_funcionario.dart';
import '../../model/historico_entrada.dart';
import '../../model/conferencia_carga_romaneio.dart';
import '../../model/historico_entrega.dart';
import '../../model/kit_orcamento.dart';
import '../../model/promocao.dart';
import '../../model/promocao_item.dart';
import '../../model/linha_devolucao_entrada.dart';
import '../../model/linha_troca_saida.dart';
import '../../model/mensagem_template.dart';
import '../../model/motorista.dart';
import '../../model/recebimento_fiado.dart';
import '../../model/titulo_receber.dart';
import '../../model/nfe_importada_registro.dart';
import '../../model/registro_devolucao.dart';
import '../../model/usuario_sistema.dart';
import '../../model/vinculo_fornecedor_produto.dart';
import '../../domain/auditoria_retencao.dart';
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
        'nome': m.nome,
        'telefone': m.telefone,
        'ativo': m.ativo,
        'criadoEm': _dt(m.criadoEm),
      };

  static Motorista motoristaDeMap(Map<String, dynamic> m) => Motorista(
        id: (m['id'] as num?)?.toInt() ?? 0,
        nome: (m['nome'] ?? '').toString(),
        telefone: (m['telefone'] ?? '').toString(),
        ativo: m['ativo'] != false,
        criadoEm: _parseDt((m['criadoEm'] ?? '').toString()),
      );

  // --- Fornecedor NF-e ---
  static Map<String, dynamic> fornecedorNfeParaMap(FornecedorNfe f) => {
        'id': f.id,
        'cnpj': f.cnpj,
        'razaoSocial': f.razaoSocial,
        'nomeFantasia': f.nomeFantasia,
      };

  static FornecedorNfe fornecedorNfeDeMap(Map<String, dynamic> m) =>
      FornecedorNfe(
        id: (m['id'] as num?)?.toInt() ?? 0,
        cnpj: (m['cnpj'] ?? '').toString(),
        razaoSocial: (m['razaoSocial'] ?? '').toString(),
        nomeFantasia: (m['nomeFantasia'] ?? '').toString(),
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

  static HistoricoEntrada historicoEntradaDeMap(Map<String, dynamic> m) =>
      HistoricoEntrada(
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
    'abrirGavetaAutomatica',
    'gavetaPino',
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
        'whatsappApiVersion': c.whatsappApiVersion,
        'whatsappPhoneNumberId': c.whatsappPhoneNumberId,
        'whatsappAccessToken': c.whatsappAccessToken,
        'mensageriaBackendUrl': c.mensageriaBackendUrl,
        'backupAutomaticoAtivo': c.backupAutomaticoAtivo,
        'backupAutomaticoIntervaloMinutos': c.backupAutomaticoIntervaloMinutos,
        'layoutImpressaoJson': c.layoutImpressaoJson,
        'auditoriaRetencaoDias': c.auditoriaRetencaoDias,
        'margemMinimaPercentualPadrao': c.margemMinimaPercentualPadrao,
        'umCaixaAbertoPorLoja': c.umCaixaAbertoPorLoja,
        'alertasProativosWhatsappAtivos': c.alertasProativosWhatsappAtivos,
        'whatsappDonoNumero': c.whatsappDonoNumero,
        'alertasProativosIntervaloMinutos': c.alertasProativosIntervaloMinutos,
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
      whatsappApiVersion:
          (m['whatsappApiVersion'] ?? base.whatsappApiVersion).toString(),
      whatsappPhoneNumberId:
          (m['whatsappPhoneNumberId'] ?? base.whatsappPhoneNumberId).toString(),
      whatsappAccessToken:
          (m['whatsappAccessToken'] ?? base.whatsappAccessToken).toString(),
      mensageriaBackendUrl:
          (m['mensageriaBackendUrl'] ?? base.mensageriaBackendUrl).toString(),
      backupAutomaticoAtivo:
          m['backupAutomaticoAtivo'] as bool? ?? base.backupAutomaticoAtivo,
      backupAutomaticoIntervaloMinutos:
          (m['backupAutomaticoIntervaloMinutos'] as num?)?.toInt() ??
              base.backupAutomaticoIntervaloMinutos,
      layoutImpressaoJson:
          (m['layoutImpressaoJson'] ?? base.layoutImpressaoJson).toString(),
      auditoriaRetencaoDias: AuditoriaRetencaoOpcoes.normalizar(
        (m['auditoriaRetencaoDias'] as num?)?.toInt() ??
            base.auditoriaRetencaoDias,
      ),
      margemMinimaPercentualPadrao: () {
        final v = (m['margemMinimaPercentualPadrao'] as num?)?.toDouble();
        if (v == null) return base.margemMinimaPercentualPadrao;
        return v.clamp(0, 99).toDouble();
      }(),
      umCaixaAbertoPorLoja:
          m['umCaixaAbertoPorLoja'] as bool? ?? base.umCaixaAbertoPorLoja,
      alertasProativosWhatsappAtivos:
          m['alertasProativosWhatsappAtivos'] as bool? ??
              base.alertasProativosWhatsappAtivos,
      whatsappDonoNumero:
          (m['whatsappDonoNumero'] ?? base.whatsappDonoNumero).toString(),
      alertasProativosIntervaloMinutos: () {
        final v = (m['alertasProativosIntervaloMinutos'] as num?)?.toInt();
        if (v == null) return base.alertasProativosIntervaloMinutos;
        return v.clamp(15, 1440);
      }(),
    );
  }

  static Map<String, dynamic> mensageriaTemplatesParaMap(
    List<MensagemTemplate> lista,
  ) =>
      {'templates': lista.map((t) => t.toMap()).toList()};

  static List<MensagemTemplate> mensageriaTemplatesDeMap(
    Map<String, dynamic> m,
  ) {
    final raw = m['templates'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => MensagemTemplate.fromMap(e.cast<String, dynamic>()))
        .toList();
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
    final raw = m['usuarios'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => UsuarioSistema.fromMap(e.cast<String, dynamic>()))
        .toList();
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
