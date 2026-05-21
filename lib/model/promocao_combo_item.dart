import 'package:objectbox/objectbox.dart';

import 'promocao.dart';

/// Produto obrigatorio em campanha [PromocaoCadastro.tipoComboAb].
@Entity()
class PromocaoComboItem {
  PromocaoComboItem({
    this.id = 0,
    this.produtoAlvoId = 0,
    this.quantidade = 1,
    this.ordem = 0,
  });

  @Id()
  int id;

  int produtoAlvoId;
  int quantidade;
  int ordem;

  final promocao = ToOne<Promocao>();
}
