/// Politica de acesso a dados em telas operacionais (PDV, Caixa, Entregas).
///
/// Evite carregar colecoes inteiras na RAM:
/// - [VendaRepository.listarTodas] e [ProdutoRepository.listarTodos] em UI operacional
/// - [ClienteRepository.listarTodos] no PDV (use [ClienteRepository.pesquisar] ou [ClienteRepository.listarPaginado])
///
/// Consultas indexadas preferidas: [pesquisar], [listarPaginado], [listarUltimasVendasFinalizadas],
/// [listarEntregasPaginadas], etc.
///
/// Alteracoes de [Produto.estoqueReal] / [Produto.estoqueReservado] devem passar por
/// [GerenciadorEstoqueService] (entradas NF-e, vendas, ajustes, reservas).
///
/// Escritas em [produtoBox.put] permitidas fora do gerenciador:
/// - [GerenciadorEstoqueService.persistirProduto] / [persistirProdutoMetadados]
/// - [VendaRepository] — apenas [Produto.ultimaVendaEm] (metadado)
/// - [ProdutoRepository.salvar] — orquestra ajuste via gerenciador + metadados
/// - [ProdutoRepository] migracao/normalizacao legada, custo medio, cadastro sem estoque
/// - [NfeEntradaRepository] — custo medio e cadastro (estoque via gerenciador)
/// - [ReajustePrecoRepository], [ComprasPreditivasService] — precos e metricas, sem fisico
/// - [sync_full_sync.dart] — merge LAN com [ProdutoEstoqueSync]
///
/// Excecoes pontuais com `// policy-allow: motivo` no arquivo.
library;

/// Caminhos de UI considerados operacionais (monitorados por teste).
const operationalUiPaths = <String>[
  'lib/ui/caixa/',
  'lib/ui/ponto_de_venda_page.dart',
  'lib/ui/entregas_page.dart',
  'lib/ui/pdv_consulta_produtos_page.dart',
];

/// Padroes proibidos em UI operacional (salvo linha com policy-allow).
const operationalForbiddenPatterns = <String>[
  '.listarTodas(',
  '.listarTodos(',
];
