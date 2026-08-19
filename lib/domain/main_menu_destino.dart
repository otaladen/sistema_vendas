import 'package:flutter/material.dart';

import '../model/usuario_sistema.dart';
import 'permissao_usuario.dart';
import 'usuario_permissao_helper.dart';

/// Destinos de navegacao do menu principal / shell desktop.
enum MainMenuDestino {
  inicio,
  vendas,
  pdv,
  caixa,
  estoque,
  notasFiscais,
  entregas,
  financeiro,
  cadastros,
  configuracoes,
  motorista;

  /// Modulos fixos do rail (sem inicio e sem atalhos PDV/caixa).
  static const modulosRail = [
    MainMenuDestino.vendas,
    MainMenuDestino.estoque,
    MainMenuDestino.entregas,
    MainMenuDestino.notasFiscais,
    MainMenuDestino.financeiro,
    MainMenuDestino.cadastros,
    MainMenuDestino.configuracoes,
    MainMenuDestino.motorista,
  ];

  /// Atalhos que podem ser favoritados (PDV, caixa).
  static const atalhosFavoritos = [
    MainMenuDestino.pdv,
    MainMenuDestino.caixa,
  ];

  static MainMenuDestino? fromCodigo(String? codigo) {
    if (codigo == null || codigo.trim().isEmpty) return null;
    for (final d in MainMenuDestino.values) {
      if (d.name == codigo) return d;
    }
    return null;
  }

  String get titulo {
    switch (this) {
      case MainMenuDestino.inicio:
        return 'Inicio';
      case MainMenuDestino.vendas:
        return 'Gestao de vendas';
      case MainMenuDestino.pdv:
        return 'Nova venda';
      case MainMenuDestino.caixa:
        return 'Caixa';
      case MainMenuDestino.estoque:
        return 'Estoque';
      case MainMenuDestino.notasFiscais:
        return 'Notas Fiscais';
      case MainMenuDestino.entregas:
        return 'Entregas';
      case MainMenuDestino.financeiro:
        return 'Financeiro';
      case MainMenuDestino.cadastros:
        return 'Cadastros';
      case MainMenuDestino.configuracoes:
        return 'Configuracoes';
      case MainMenuDestino.motorista:
        return 'Modo motorista';
    }
  }

  String? get subtitulo {
    switch (this) {
      case MainMenuDestino.vendas:
        return 'Orcamentos, listagem e relatorios';
      case MainMenuDestino.pdv:
        return 'Ponto de venda';
      case MainMenuDestino.caixa:
        return 'Recebimentos e fechamento';
      case MainMenuDestino.estoque:
        return 'Saldo e movimentacao';
      case MainMenuDestino.notasFiscais:
        return 'NF-e e NFC-e';
      case MainMenuDestino.entregas:
        return 'Expedicao e POD';
      case MainMenuDestino.financeiro:
        return 'Contas a pagar e receber';
      case MainMenuDestino.cadastros:
        return 'Produtos e clientes';
      case MainMenuDestino.configuracoes:
        return 'Empresa e impressao';
      case MainMenuDestino.motorista:
        return 'Entregas do motorista';
      default:
        return null;
    }
  }

  IconData get icone {
    switch (this) {
      case MainMenuDestino.inicio:
        return Icons.home_outlined;
      case MainMenuDestino.vendas:
        return Icons.folder_open_outlined;
      case MainMenuDestino.pdv:
        return Icons.add_shopping_cart_outlined;
      case MainMenuDestino.caixa:
        return Icons.receipt_long_outlined;
      case MainMenuDestino.estoque:
        return Icons.inventory_2_outlined;
      case MainMenuDestino.notasFiscais:
        return Icons.description_outlined;
      case MainMenuDestino.entregas:
        return Icons.local_shipping_outlined;
      case MainMenuDestino.financeiro:
        return Icons.payments_outlined;
      case MainMenuDestino.cadastros:
        return Icons.app_registration_outlined;
      case MainMenuDestino.configuracoes:
        return Icons.settings_outlined;
      case MainMenuDestino.motorista:
        return Icons.drive_eta_outlined;
    }
  }

  bool podeAcessar(UsuarioSistema u) {
    switch (this) {
      case MainMenuDestino.inicio:
        return true;
      case MainMenuDestino.vendas:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.vendasHub);
      case MainMenuDestino.pdv:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv);
      case MainMenuDestino.caixa:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa);
      case MainMenuDestino.estoque:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque);
      case MainMenuDestino.notasFiscais:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.fiscal);
      case MainMenuDestino.entregas:
        return UsuarioPermissaoHelper.podeAcessarModuloEntregas(u);
      case MainMenuDestino.financeiro:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.financeiro);
      case MainMenuDestino.cadastros:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.cadastros);
      case MainMenuDestino.configuracoes:
        return UsuarioPermissaoHelper.tem(u, PermissaoUsuario.configuracoes);
      case MainMenuDestino.motorista:
        return UsuarioPermissaoHelper.podeUsarModoMotorista(u);
    }
  }

  /// Ordem do rail desktop: inicio, favoritos, demais modulos.
  static List<MainMenuDestino> itensRail({
    required UsuarioSistema usuario,
    required List<MainMenuDestino> favoritos,
  }) {
    final vistos = <MainMenuDestino>{};
    final out = <MainMenuDestino>[];

    void add(MainMenuDestino d) {
      if (d == MainMenuDestino.inicio) return;
      if (!d.podeAcessar(usuario)) return;
      if (vistos.add(d)) out.add(d);
    }

    final lista = <MainMenuDestino>[
      MainMenuDestino.inicio,
      ...favoritos,
      ...modulosRail,
      ...atalhosFavoritos,
    ];

    for (final d in lista) {
      if (d == MainMenuDestino.inicio) {
        out.insert(0, MainMenuDestino.inicio);
        vistos.add(MainMenuDestino.inicio);
        continue;
      }
      add(d);
    }
    return out;
  }

  static List<MainMenuDestino> favoritosPadrao(UsuarioSistema u) {
    final out = <MainMenuDestino>[];
    for (final d in atalhosFavoritos) {
      if (d.podeAcessar(u)) out.add(d);
    }
    return out;
  }

  /// Tela aberta logo apos o login (motorista de campo vai direto para a rota).
  static MainMenuDestino inicialAposLogin(UsuarioSistema u) {
    if (UsuarioPermissaoHelper.ehMotoristaCampoSomente(u)) {
      return MainMenuDestino.motorista;
    }
    return MainMenuDestino.inicio;
  }
}
