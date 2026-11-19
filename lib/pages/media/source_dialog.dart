import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../data/models/media_item.dart';
import '../../data/sources/media_source.dart';
import '../../design/ps_tokens.dart';
import '../core/text_entry.dart';
import '../widgets/ps_button.dart';

/// Add / edit a backend.
///
/// Mirrors the six ways the app can reach media. Everything is a URL plus
/// optional credentials except `local`, which is a folder picked with the OS
/// dialog — so the same form covers Emby, Jellyfin, m3u, OpenList, WebDAV and a
/// bare stream URL.
class SourceDialog extends StatefulWidget {
  const SourceDialog({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.initial,
  });

  final SourceConfig? initial;
  final VoidCallback onCancel;
  final ValueChanged<SourceConfig> onSave;

  @override
  State<SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<SourceDialog> {
  late SourceKind _kind = widget.initial?.kind ?? SourceKind.emby;
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.initial?.url ?? '');
  late final TextEditingController _user =
      TextEditingController(text: widget.initial?.username ?? '');
  late final TextEditingController _pass =
      TextEditingController(text: widget.initial?.password ?? '');
  late final TextEditingController _path =
      TextEditingController(text: widget.initial?.path ?? '');
  String? _error;

  static const List<(SourceKind, String)> _choices = <(SourceKind, String)>[
    (SourceKind.emby, 'Emby'),
    (SourceKind.jellyfin, 'Jellyfin'),
    (SourceKind.iptv, 'IPTV'),
    (SourceKind.openlist, 'OpenList'),
    (SourceKind.webdav, 'WebDAV'),
    (SourceKind.local, '本地文件夹'),
    (SourceKind.directUrl, '直链'),
  ];

  @override
  void initState() {
    super.initState();
    TextEntry.active.value = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    TextEntry.active.value = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _path.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return true;
    }
    return false;
  }

  bool get _needsUrl => _kind != SourceKind.local;
  bool get _needsAccount =>
      _kind == SourceKind.emby ||
      _kind == SourceKind.jellyfin ||
      _kind == SourceKind.openlist ||
      _kind == SourceKind.webdav;

  Future<void> _pickFolder() async {
    try {
      final String? directory = await getDirectoryPath();
      if (directory != null && directory.isNotEmpty) {
        setState(() => _path.text = directory);
      }
    } on Object {
      // No picker available: the path can still be typed.
    }
  }

  void _save() {
    final String name = _name.text.trim();
    final String url = _url.text.trim();
    final String path = _path.text.trim();
    if (_needsUrl && url.isEmpty) {
      setState(() => _error = S.connectHint);
      return;
    }
    if (!_needsUrl && path.isEmpty) {
      setState(() => _error = '请选择一个文件夹');
      return;
    }
    final String id = widget.initial?.id ??
        '${_kind.name}-${DateTime.now().millisecondsSinceEpoch}';
    widget.onSave(
      SourceConfig(
        id: id,
        kind: _kind,
        name: name.isEmpty ? _labelFor(_kind) : name,
        url: url,
        username: _user.text.trim(),
        password: _pass.text,
        path: path,
        token: widget.initial?.token ?? '',
        userId: widget.initial?.userId ?? '',
      ),
    );
  }

  static String _labelFor(SourceKind kind) {
    for (final (SourceKind value, String label) in _choices) {
      if (value == kind) {
        return label;
      }
    }
    return kind.name;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          onTap: widget.onCancel,
          child: ColoredBox(color: const Color(0xFF000000).withValues(alpha: 0.62)),
        ),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PsRadius.sheet),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                width: 1120,
                padding: const EdgeInsets.all(52),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161F).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(PsRadius.sheet),
                  border: Border.all(color: PsColor.text.withValues(alpha: 0.16), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.initial == null ? S.addSource : S.editSource,
                      style: PsType.page.copyWith(fontSize: 44),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        for (final (SourceKind kind, String label) in _choices)
                          _KindChip(
                            label: label,
                            selected: kind == _kind,
                            onSelect: () => setState(() {
                              _kind = kind;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              _field(S.sourceName, _name, hint: _labelFor(_kind), autofocus: true),
                              const SizedBox(height: 18),
                              if (_needsUrl)
                                _field(S.sourceUrl, _url, hint: 'https://'),
                              if (!_needsUrl) _pathField(),
                            ],
                          ),
                        ),
                        if (_needsAccount) ...<Widget>[
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                _field(S.sourceUser, _user),
                                const SizedBox(height: 18),
                                _field(S.sourcePassword, _pass, obscure: true),
                              ],
                            ),
                          ),
                        ] else
                          const SizedBox(width: 0),
                      ],
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 18),
                      Text(_error!, style: PsType.label.copyWith(color: PsColor.danger)),
                    ],
                    const SizedBox(height: 34),
                    Row(
                      children: <Widget>[
                        PsButton(
                          label: widget.initial == null ? S.connect : '保存',
                          icon: Icons.check_rounded,
                          primary: true,
                          width: 200,
                          onSelect: _save,
                        ),
                        const SizedBox(width: 18),
                        PsButton(label: '取消', width: 160, onSelect: widget.onCancel),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(S.sourcePath, style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 1.6)),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(child: _input(_path, hint: r'D:\Movies')),
            const SizedBox(width: 12),
            PsButton(label: '选择…', icon: Icons.folder_rounded, height: 56, onSelect: _pickFolder),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    bool autofocus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: PsType.micro.copyWith(fontSize: 15, letterSpacing: 1.6)),
        const SizedBox(height: 8),
        _input(controller, hint: hint, obscure: obscure, autofocus: autofocus),
      ],
    );
  }

  Widget _input(
    TextEditingController controller, {
    String? hint,
    bool obscure = false,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      cursorColor: PsColor.text,
      style: PsType.meta.copyWith(color: PsColor.text, fontSize: 22),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: PsColor.text.withValues(alpha: 0.06),
        hintText: hint,
        hintStyle: PsType.meta.copyWith(color: PsColor.textFaint, fontSize: 22),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: PsColor.text, width: 2),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.selected, required this.onSelect});

  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return PsButton(
      label: label,
      primary: selected,
      height: 52,
      onSelect: onSelect,
    );
  }
}
