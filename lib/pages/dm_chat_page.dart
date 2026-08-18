import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../api/store.dart';
import '../widgets/common.dart';

/// 私信聊天
class DMChatPage extends StatefulWidget {
  final int peerUid;
  final String peerName;
  const DMChatPage({super.key, required this.peerUid, required this.peerName});

  @override
  State<DMChatPage> createState() => _DMChatPageState();
}

class _DMChatPageState extends State<DMChatPage> {
  List<dynamic> _messages = [];
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final msgs = await LKApi.dmMessages(widget.peerUid);
      if (!mounted) return;
      setState(() => _messages = msgs);
    } catch (e) {
      if (mounted) showLkError(context, e);
    }
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty) return;
    try {
      await LKApi.dmSend(widget.peerUid, content);
      _input.clear();
      _load();
    } catch (e) {
      if (mounted) showLkError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = LKClient.shared.session.uid;
    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName.isEmpty ? '私信' : widget.peerName)),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (_, i) {
              final m = _messages[i];
              final mine = m.isMine(myUid);
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: const BoxConstraints(maxWidth: 280),
                  decoration: BoxDecoration(
                    color: mine
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF35523F)
                            : Colors.lightGreen.shade200)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2A2C33)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(m.content),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(
                      hintText: '发消息…',
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _send, child: const Text('发送')),
            ]),
          ),
        ),
      ]),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final mode = LKStore.themeMode.value;
    final modeLabel = switch (mode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      ThemeMode.system => '跟随系统',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('设置与资料')),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('深色模式'),
          subtitle: Text('当前: $modeLabel'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _darkMode(context),
        ),
        ListTile(
          leading: const Icon(Icons.military_tech_outlined),
          title: const Text('我的勋章(可装备)'),
          onTap: () => _medals(context),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于'),
          onTap: () async {
            try {
              final d = await LKApi.about();
              if (!context.mounted) return;
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('关于'),
                  content: Text('轻之国度 https://www.lightnovel.fun\n版本: ${d['version'] ?? ''}'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('好'))],
                ),
              );
            } catch (e) {
              if (context.mounted) showLkError(context, e);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('检查更新'),
          onTap: () async {
            try {
              final info = await PackageInfo.fromPlatform();
              final rel = await LKApi.latestRelease();
              if (!context.mounted) return;
              final cur = '${info.version}+${info.buildNumber}';
              if (rel == null || rel.tag.isEmpty) {
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('检查更新'),
                    content: Text('当前版本 $cur\n\n无法获取 GitHub 发布信息\n(仓库为私有或暂无发布)'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('好')),
                    ],
                  ),
                );
                return;
              }
              final latest = rel.tag.replaceFirst(RegExp(r'^v'), '');
              final newer = compareVersions(latest, info.version) > 0;
              final body = rel.body.trim();
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(newer ? '发现新版本' : '已是最新版本'),
                  content: Text(
                    newer
                        ? '当前版本 $cur\n最新版本 $latest\n\n${body.length > 300 ? '${body.substring(0, 300)}…' : body}'
                        : '当前版本 $cur 已是最新',
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('好')),
                    if (newer)
                      FilledButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          if (rel.url.isNotEmpty) {
                            await launchUrl(Uri.parse(rel.url),
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Text('去 GitHub 下载'),
                      ),
                  ],
                ),
              );
            } catch (e) {
              if (context.mounted) showLkError(context, e);
            }
          },
        ),
      ]),
    );
  }

  void _darkMode(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('深色模式',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          for (final (label, value) in [
            ('跟随系统', ThemeMode.system),
            ('浅色', ThemeMode.light),
            ('深色', ThemeMode.dark),
          ])
            ListTile(
              title: Text(label),
              trailing: LKStore.themeMode.value == value
                  ? Icon(Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : const Icon(Icons.circle_outlined,
                      color: Colors.grey),
              onTap: () {
                LKStore.setThemeMode(value);
                Navigator.pop(sheetCtx);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _medals(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => FutureBuilder(
        future: LKApi.client.post('/api/bff/my-medals-v1', LKApi.client.authed()),
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LkLoadingIndicator(minHeight: 200);
          }
          if (snap.hasError) return Text('${snap.error}');
          final list = ((snap.data?['list'] as List?) ?? const []);
          if (list.isEmpty) return const Center(child: Text('暂无勋章'));
          return ListView(
            children: list.map((m) {
              final name = m['name'] ?? '';
              final equipped = (m['equipped'] as num?)?.toInt() == 1;
              final id = (m['medal_id'] as num?)?.toInt() ?? (m['id'] as num?)?.toInt() ?? 0;
              return ListTile(
                title: Text('$name${equipped ? '(已装备)' : ''}'),
                onTap: () async {
                  await LKApi.toggleMedal(id, !equipped);
                  if (context.mounted) showLkError(context, '已切换');
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
