import 'package:flutter/material.dart';

import '../../../data/models/ssh_profile.dart';
import '../../states/terminal_state.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_input.dart';
import '../../../theme/radii.dart';
import '../../../theme/typography.dart';

/// Opens the add/edit SSH session dialog.
///
/// Pass [initial] to edit an existing profile; omit it to create a new one.
/// Returns the completed profile, or `null` if the user cancelled.
Future<SshProfile?> showSshSessionDialog(
  BuildContext context, {
  SshProfile? initial,
}) {
  return showDialog<SshProfile>(
    context: context,
    builder: (_) => _SshSessionDialog(initial: initial),
  );
}

class _SshSessionDialog extends StatefulWidget {
  const _SshSessionDialog({this.initial});

  final SshProfile? initial;

  @override
  State<_SshSessionDialog> createState() => _SshSessionDialogState();
}

class _SshSessionDialogState extends State<_SshSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.initial?.name);
  late final _hostController = TextEditingController(text: widget.initial?.host);
  late final _portController =
      TextEditingController(text: (widget.initial?.port ?? 22).toString());
  late final _usernameController =
      TextEditingController(text: widget.initial?.username);
  late final _passwordController =
      TextEditingController(text: widget.initial?.password);

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return '必填项';
    return null;
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port < 1 || port > 65535) {
      return '端口范围 1-65535';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final profile = SshProfile(
      id: widget.initial?.id ?? TerminalState.generateId(),
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.initial != null;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Row(
        children: [
          Icon(Icons.dns_outlined, size: 24, color: colorScheme.secondary),
          const SizedBox(width: 12),
          Text(
            isEditing ? '编辑 SSH 会话' : '新增 SSH 会话',
            style: NexusTypography.headlineSm,
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexusInput(
                controller: _nameController,
                labelText: '名称',
                hintText: '例如：测试服务器',
                autofocus: !isEditing,
                validator: _validateRequired,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: NexusInput(
                      controller: _hostController,
                      labelText: '远程地址',
                      hintText: '主机名或 IP',
                      validator: _validateRequired,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: NexusInput(
                      controller: _portController,
                      labelText: '端口',
                      hintText: '22',
                      keyboardType: TextInputType.number,
                      validator: _validatePort,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              NexusInput(
                controller: _usernameController,
                labelText: '账号',
                hintText: '登录用户名',
                validator: _validateRequired,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              const SizedBox(height: 16),
              NexusInput(
                controller: _passwordController,
                labelText: '密码',
                hintText: '登录密码',
                obscureText: true,
                validator: _validateRequired,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        NexusButton(
          label: isEditing ? '保存' : '保存并连接',
          icon: isEditing ? Icons.check : Icons.bolt_outlined,
          onPressed: _submit,
        ),
      ],
    );
  }
}
