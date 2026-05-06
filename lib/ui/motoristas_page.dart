import 'package:flutter/material.dart';

import '../data/motorista_repository.dart';
import '../model/motorista.dart';

class MotoristasPage extends StatefulWidget {
  const MotoristasPage({super.key, required this.motoristaRepository});

  final MotoristaRepository motoristaRepository;

  @override
  State<MotoristasPage> createState() => _MotoristasPageState();
}

class _MotoristasPageState extends State<MotoristasPage> {
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _pesquisaController = TextEditingController();
  int? _motoristaEmEdicaoId;
  bool _ativo = true;
  String _status = '';

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _pesquisaController.dispose();
    super.dispose();
  }

  void _limparFormulario() {
    setState(() {
      _motoristaEmEdicaoId = null;
      _nomeController.clear();
      _telefoneController.clear();
      _ativo = true;
      _status = '';
    });
  }

  void _editar(Motorista m) {
    setState(() {
      _motoristaEmEdicaoId = m.id;
      _nomeController.text = m.nome;
      _telefoneController.text = m.telefone;
      _ativo = m.ativo;
      _status = 'Editando: ${m.nome}';
    });
  }

  void _salvar() {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      setState(() => _status = 'Informe o nome do motorista.');
      return;
    }
    final idAtual = _motoristaEmEdicaoId ?? 0;
    if (widget.motoristaRepository.existeNomeParaOutro(
      nomeNormalizado: nome,
      ignorarId: idAtual,
    )) {
      setState(() => _status = 'Ja existe um motorista com este nome.');
      return;
    }
    Motorista? atual;
    if (_motoristaEmEdicaoId != null) {
      for (final m in widget.motoristaRepository.listarTodos()) {
        if (m.id == _motoristaEmEdicaoId) {
          atual = m;
          break;
        }
      }
    }
    final motorista = Motorista(
      id: atual?.id ?? 0,
      nome: nome,
      telefone: _telefoneController.text.trim(),
      ativo: _ativo,
      criadoEm: atual?.criadoEm,
    );
    final id = widget.motoristaRepository.salvar(motorista);
    setState(() {
      _motoristaEmEdicaoId = id;
      _status = 'Motorista salvo com sucesso.';
    });
  }

  Future<void> _remover(Motorista m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover motorista'),
        content: Text('Deseja remover "${m.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.motoristaRepository.remover(m.id);
    if (_motoristaEmEdicaoId == m.id) _limparFormulario();
    setState(() => _status = 'Motorista removido.');
  }

  @override
  Widget build(BuildContext context) {
    final listados = widget.motoristaRepository.pesquisar(_pesquisaController.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de motoristas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nomeController,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _telefoneController,
            decoration: const InputDecoration(labelText: 'Telefone'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _ativo,
            onChanged: (v) => setState(() => _ativo = v),
            title: const Text('Ativo'),
            contentPadding: EdgeInsets.zero,
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _salvar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _motoristaEmEdicaoId == null ? 'Salvar' : 'Atualizar',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _limparFormulario,
                icon: const Icon(Icons.add),
                label: const Text('Novo'),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _pesquisaController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Pesquisar motoristas',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (listados.isEmpty)
            const Text('Nenhum motorista cadastrado.')
          else
            ...listados.map(
              (m) => Card(
                child: ListTile(
                  title: Text(m.nome),
                  subtitle: Text(
                    '${m.telefone.isEmpty ? 'Sem telefone' : m.telefone}${m.ativo ? '' : ' · inativo'}',
                  ),
                  onTap: () => _editar(m),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _editar(m),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => _remover(m),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
