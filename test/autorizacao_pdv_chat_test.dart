import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/mensagem_interna_repository.dart';
import 'package:sistema_vendas/domain/autorizacao_pdv_chat.dart';
import 'package:sistema_vendas/model/mensagem_interna.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';
import 'package:sistema_vendas/ui/widgets/chat/autorizacao_pdv_chat_hub.dart';

void main() {
  test('payload roundtrip preserva venda, operador e valores', () {
    final original = AutorizacaoPdvChatPayload(
      solicitacaoId: 'abc-123',
      tipoOperacao: AutorizacaoPdvChatTipo.descontoAcimaTeto,
      operadorLogin: 'joao',
      operadorNome: 'Joao Silva',
      timestamp: DateTime.utc(2026, 9, 7, 15, 30),
      vendaId: 88,
      carrinhoId: 'cart-1',
      valorOriginal: 200,
      valorSolicitado: 40,
      descricaoAcao: 'Desconto de 20%',
      stationId: 'term-1',
    );
    final copia = AutorizacaoPdvChatPayload.fromMap(original.toMap());
    expect(copia.solicitacaoId, 'abc-123');
    expect(copia.tipoOperacao, AutorizacaoPdvChatTipo.descontoAcimaTeto);
    expect(copia.operadorLogin, 'joao');
    expect(copia.vendaId, 88);
    expect(copia.valorOriginal, 200);
    expect(copia.valorSolicitado, 40);
    expect(copia.descricaoAcao, 'Desconto de 20%');
    expect(copia.status, AutorizacaoPdvChatStatus.pendente);
    expect(copia.textoResumoChat(), contains('@gerente'));
  });

  test('mensagem interna serializa tipo e payload de autorizacao', () {
    final payload = AutorizacaoPdvChatPayload(
      solicitacaoId: 's1',
      tipoOperacao: AutorizacaoPdvChatTipo.descontoAcimaTeto,
      operadorLogin: 'op',
      operadorNome: 'Operador',
      timestamp: DateTime.utc(2026, 1, 1),
      valorOriginal: 100,
      valorSolicitado: 15,
      descricaoAcao: 'Desconto de 15%',
    );
    final msg = MensagemInterna(
      id: 7,
      vendedor: 'Operador',
      texto: payload.textoResumoChat(),
      dataHora: DateTime.utc(2026, 1, 1),
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: payload.toMap(),
      mencoes: const ['gerente'],
    );
    final volta = MensagemInterna.fromMap(msg.toMap());
    expect(volta.ehAutorizacaoPdv, isTrue);
    expect(volta.autorizacaoPdv?.solicitacaoId, 's1');
    expect(volta.mencoes, contains('gerente'));
  });

  test('copyWith marca aprovada com quem e quando', () {
    final p = AutorizacaoPdvChatPayload(
      solicitacaoId: 's2',
      tipoOperacao: AutorizacaoPdvChatTipo.descontoAcimaTeto,
      operadorLogin: 'op',
      operadorNome: 'Op',
      timestamp: DateTime.utc(2026, 1, 1),
    ).copyWith(
      status: AutorizacaoPdvChatStatus.aprovada,
      respondidoPor: 'gerente1',
      respondidoEm: DateTime.utc(2026, 1, 1, 12),
      motivo: 'Cliente fiel',
    );
    expect(p.pendente, isFalse);
    expect(p.respondidoPor, 'gerente1');
    expect(p.motivo, 'Cliente fiel');
    expect(AutorizacaoPdvChatStatus.ehFinal(p.status), isTrue);
  });

  test('admin e gerente podem responder; vendedor comum nao', () {
    const admin = UsuarioSistema(
      id: '1',
      nome: 'Admin',
      login: 'admin',
      senha: 'x',
      admin: true,
    );
    const gerente = UsuarioSistema(
      id: '2',
      nome: 'Gerente',
      login: 'gerente',
      senha: 'x',
      perfil: 'gerente',
      podeAlterarPrecoPdv: true,
    );
    const vendedor = UsuarioSistema(
      id: '3',
      nome: 'Vendedor',
      login: 'vend',
      senha: 'x',
      perfil: 'vendedor',
    );
    expect(usuarioPodeResponderAutorizacaoPdvChat(admin), isTrue);
    expect(usuarioPodeResponderAutorizacaoPdvChat(gerente), isTrue);
    expect(usuarioPodeResponderAutorizacaoPdvChat(vendedor), isFalse);
    const dono = UsuarioSistema(
      id: '4',
      nome: 'Dono',
      login: 'dono',
      senha: 'x',
      perfil: 'dono',
    );
    expect(usuarioPodeResponderAutorizacaoPdvChat(dono), isTrue);
  });

  test('payload com solicitacaoId vale como card mesmo sem tipo', () {
    final m = MensagemInterna.fromMap({
      'id': 2,
      'vendedor': 'Operador',
      'texto': 'Solicitacao de Autorizacao - PDV',
      'dataHora': '2026-01-01T10:00:00Z',
      'payload': {
        'solicitacaoId': 'req-x',
        'tipoOperacao': 'desconto_acima_teto',
        'operadorLogin': 'op',
        'operadorNome': 'Op',
        'timestamp': '2026-01-01T10:00:00Z',
        'status': 'pendente',
        'valorOriginal': 100,
        'valorSolicitado': 20,
      },
    });
    expect(m.ehAutorizacaoPdv, isTrue);
    expect(m.autorizacaoPdv?.solicitacaoId, 'req-x');
    expect(m.autorizacaoPdv?.pendente, isTrue);
  });

  test('mensagem antiga sem tipo continua texto', () {
    final m = MensagemInterna.fromMap({
      'id': 1,
      'vendedor': 'Caixa',
      'texto': 'cafe na copa',
      'dataHora': '2026-01-01T10:00:00Z',
    });
    expect(m.ehAutorizacaoPdv, isFalse);
    expect(m.tipo, kMensagemInternaTipoTexto);
    expect(m.texto, 'cafe na copa');
  });

  test('repositorio persiste e atualiza solicitacao de autorizacao', () async {
    final dir = await Directory.systemTemp.createTemp('chat_auth_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = MensagemInternaRepository(storeDirectoryPath: dir.path);
    final payload = AutorizacaoPdvChatPayload(
      solicitacaoId: 'req-9',
      tipoOperacao: AutorizacaoPdvChatTipo.descontoAcimaTeto,
      operadorLogin: 'op',
      operadorNome: 'Operador',
      timestamp: DateTime.now().toUtc(),
      vendaId: 15,
      valorOriginal: 100,
      valorSolicitado: 20,
      descricaoAcao: 'Desconto de 20%',
    );
    await repo.enviar(
      vendedor: 'Operador',
      texto: payload.textoResumoChat(),
      tipo: kMensagemInternaTipoAutorizacaoPdv,
      payload: payload.toMap(),
      mencoes: const ['gerente'],
    );
    final achou = await repo.buscarAutorizacaoPdv('req-9');
    expect(achou, isNotNull);
    expect(achou!.autorizacaoPdv?.pendente, isTrue);

    final atualizado = await repo.atualizarAutorizacaoPdv(
      solicitacaoId: 'req-9',
      payload: payload.copyWith(
        status: AutorizacaoPdvChatStatus.aprovada,
        respondidoPor: 'gerente1',
        respondidoEm: DateTime.now().toUtc(),
        motivo: 'ok',
      ),
    );
    expect(atualizado.autorizacaoPdv?.status, AutorizacaoPdvChatStatus.aprovada);
    expect(atualizado.autorizacaoPdv?.respondidoPor, 'gerente1');
  });

  test('hub completa espera ao receber resposta de aprovacao', () async {
    final future = AutorizacaoPdvChatHub.instance.aguardar('wait-1');
    AutorizacaoPdvChatHub.instance.aplicarResposta(
      const AutorizacaoPdvChatResposta(
        solicitacaoId: 'wait-1',
        status: AutorizacaoPdvChatStatus.aprovada,
        respondidoPor: 'gerente1',
        motivo: 'liberado',
      ),
    );
    final resp = await future;
    expect(resp.aprovada, isTrue);
    expect(resp.respondidoPor, 'gerente1');
  });
}
