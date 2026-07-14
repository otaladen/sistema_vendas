/// Regiao e lojas-alvo para referencia de preco de mercado.
///
/// Padrao: Salvador/BA, com prioridade Ferreira Costa, Leroy Merlin e Mercado Livre.
class PrecoMercadoRegiaoConfig {
  const PrecoMercadoRegiaoConfig({
    required this.cidade,
    required this.uf,
    required this.lojas,
  });

  final String cidade;
  final String uf;
  final List<PrecoMercadoLojaAlvo> lojas;

  String get rotulo => '$cidade / $uf';

  String get termosRegiao => '$cidade $uf';

  /// Configuracao padrao da operacao (loja em Salvador).
  static const salvadorBa = PrecoMercadoRegiaoConfig(
    cidade: 'Salvador',
    uf: 'BA',
    lojas: [
      PrecoMercadoLojaAlvo(
        nome: 'Ferreira Costa',
        dominio: 'ferreiracosta.com',
        termosSite: ['ferreiracosta.com', 'ferreiracosta.com.br'],
      ),
      PrecoMercadoLojaAlvo(
        nome: 'Leroy Merlin',
        dominio: 'leroymerlin.com.br',
        termosSite: ['leroymerlin.com.br'],
      ),
      PrecoMercadoLojaAlvo(
        nome: 'Mercado Livre',
        dominio: 'mercadolivre.com.br',
        termosSite: [
          'mercadolivre.com.br',
          'lista.mercadolivre.com.br',
        ],
      ),
    ],
  );

  static const atual = salvadorBa;
}

class PrecoMercadoLojaAlvo {
  const PrecoMercadoLojaAlvo({
    required this.nome,
    required this.dominio,
    required this.termosSite,
  });

  final String nome;
  final String dominio;
  final List<String> termosSite;

  bool correspondeUrl(String url) {
    final u = url.toLowerCase();
    for (final t in termosSite) {
      if (u.contains(t.toLowerCase())) return true;
    }
    return false;
  }
}
