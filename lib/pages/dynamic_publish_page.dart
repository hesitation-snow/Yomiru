import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../widgets/common.dart';

class DynamicPublishPage extends StatefulWidget {
  const DynamicPublishPage({super.key});

  @override
  State<DynamicPublishPage> createState() => _DynamicPublishPageState();
}

class _DynamicPublishPageState extends State<DynamicPublishPage> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _media = <LKDynamicMedia>[];
  List<LKEmojiGroup> _emojiGroups = const [];
  bool _uploading = false;
  bool _publishing = false;

  static String _fixEmojiUrl(String url) =>
      url.replaceFirst('api.lightnovel.fun/static/', 'static.lightnovel.fun/');

  @override
  void initState() {
    super.initState();
    _loadEmojis();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadEmojis() async {
    try {
      final groups = await LKApi.commentEmojis();
      if (mounted) setState(() => _emojiGroups = groups);
    } catch (_) {}
  }

  void _insertEmoji(String code) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start.clamp(0, value.text.length);
    final end = selection.end.clamp(start, value.text.length);
    final text = value.text.replaceRange(start, end, code);
    _controller.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: start + code.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _showEmojiPicker() async {
    if (_emojiGroups.isEmpty) {
      showLkError(context, '表情加载中,请稍后再试');
      return;
    }
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 360,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _emojiGroups
                  .map(
                    (group) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (group.name.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(group.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: group.items
                                .where((item) => item.isImage)
                                .map(
                                  (item) => InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () =>
                                        Navigator.pop(context, item.code),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Image.network(
                                        _fixEmojiUrl(item.url),
                                        width: 38,
                                        height: 38,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            Text(item.code),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
    if (code != null) _insertEmoji(code);
  }

  Future<void> _pickImage() async {
    if (_uploading || _media.length >= 9) return;
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 88, maxWidth: 2048);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final uploaded = await LKApi.uploadDynamicImage(file.path);
      if (mounted) setState(() => _media.add(uploaded));
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _publish() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _publishing || _uploading) return;
    if (!LKClient.shared.session.isLoggedIn) {
      showLkError(context, '请先登录');
      return;
    }
    setState(() => _publishing = true);
    try {
      await LKApi.publishShortDynamic(content, media: _media);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发动态'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _publishing || _uploading ? null : _publish,
              child: Text(_publishing ? '发布中' : '发布'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            minLines: 6,
            maxLines: 12,
            maxLength: 2000,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '分享此刻想说的话…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._media.asMap().entries.map((entry) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(entry.value.url,
                            width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.cancel, color: Colors.white),
                          onPressed: () =>
                              setState(() => _media.removeAt(entry.key)),
                        ),
                      ),
                    ],
                  )),
              OutlinedButton.icon(
                onPressed: _showEmojiPicker,
                icon: const Icon(Icons.emoji_emotions_outlined),
                label: const Text('表情'),
              ),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickImage,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: const Text('添加图片'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
