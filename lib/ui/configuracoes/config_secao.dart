import 'package:flutter/material.dart';

class ConfigSecaoInfo {
  const ConfigSecaoInfo({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.icon,
  });

  final String id;
  final String titulo;
  final String descricao;
  final IconData icon;
}

/// Secoes do hub de configuracoes (ordem de exibicao).
abstract final class ConfigSecoes {
  ConfigSecoes._();

  static const breakpointRail = 900.0;
  static const maxLarguraConteudo = 880.0;

  /// Secoes com muitos cartoes usam duas colunas em monitor de balcao.
  static const maxLarguraConteudoAmplo = 1340.0;
  static const breakpointDuasColunas = 1120.0;

  static const List<ConfigSecaoInfo> todas = [
    ConfigSecaoInfo(
      id: 'empresa',
      titulo: 'Empresa',
      descricao: 'Nome, contato e endereço',
      icon: Icons.storefront_outlined,
    ),
    ConfigSecaoInfo(
      id: 'pdv',
      titulo: 'Ponto de venda',
      descricao: 'Vendedor, descontos e atendimento',
      icon: Icons.point_of_sale_outlined,
    ),
    ConfigSecaoInfo(
      id: 'caixa',
      titulo: 'Caixa',
      descricao: 'Fechamento, fila e autorizações',
      icon: Icons.payments_outlined,
    ),
    ConfigSecaoInfo(
      id: 'fiscal',
      titulo: 'Fiscal e IA',
      descricao: 'NFC-e, NF-e e padronização',
      icon: Icons.receipt_long_outlined,
    ),
    ConfigSecaoInfo(
      id: 'impressao',
      titulo: 'Impressão',
      descricao: 'PDF, cupom e impressora',
      icon: Icons.print_outlined,
    ),
    ConfigSecaoInfo(
      id: 'rede',
      titulo: 'Rede e terminais',
      descricao: 'API dos terminais (:8788) e rede local',
      icon: Icons.lan_outlined,
    ),
    ConfigSecaoInfo(
      id: 'backup',
      titulo: 'Backup e segurança',
      descricao: 'Cópias, restauração e proteção dos dados',
      icon: Icons.backup_outlined,
    ),
    ConfigSecaoInfo(
      id: 'sistema',
      titulo: 'Sistema',
      descricao: 'Data, hora e diagnóstico',
      icon: Icons.schedule_outlined,
    ),
  ];

  static int indiceDeId(String id) {
    final i = todas.indexWhere((s) => s.id == id);
    return i >= 0 ? i : 0;
  }
}
