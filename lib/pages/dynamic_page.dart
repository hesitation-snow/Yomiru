import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../widgets/common.dart';
import 'book_detail_page.dart';
import 'dm_chat_page.dart';

/// 动态广场(tab=follow)
class DynamicPage extends StatefulWidget {
  /// 内嵌模式(作为底部 Tab 使用时无独立 Scaffold/AppBar)
  final bool embedded;
  const DynamicPage({super.key, this.embedded = false});

  @override
  State<DynamicPage> createState() => _DynamicPageState();
}

class _DynamicPageState extends State<DynamicPage> {
  List<dynamic> _items = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await LKApi.dynamicFeed();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Widget _feedBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: _error != null && _items.isEmpty
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = _items[i];
                final hasBook =
                    d.bookId > 0 && d.bookTitle.trim().isNotEmpty;
                return InkWell(
                  onTap: () => _showComments(d.dynamicId),
                  onLongPress: () => _actions(d),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(
                              radius: 16,
                              backgroundImage: d.avatar.isNotEmpty
                                  ? NetworkImage(d.avatar)
                                  : null),
                          const SizedBox(width: 8),
                          Text(d.nickname,
                              style: TextStyle(
                                  color: Colors.indigo.shade400, fontSize: 13)),
                          const SizedBox(width: 8),
                          if (d.eventType.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(_eventLabel(d.eventType),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white)),
                              ),
                          ]),
                          const SizedBox(height: 6),
                          Text(d.summary),
                          if (hasBook)
                            InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        BookDetailPage(bookId: d.bookId)),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF2A2C33)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(children: [
                                  CoverImage(url: d.bookCover, width: 40, height: 53),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(d.bookTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ]),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(children: [
                            Text('赞 ${d.likeCount} · 评论 ${d.commentCount}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500)),
                            const Spacer(),
                            Text(_shortTime(d.time),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade400)),
                          ]),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.embedded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('动态 · 关注'),
        ),
        body: _feedBody(),
      );
    }
    // 内嵌模式:状态栏区域由 HomePage 的状态栏背景条负责,这里不再加 SafeArea
    return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Text('动态 · 关注',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF263238))),
            const Spacer(),
          ]),
        ),
        Expanded(child: _feedBody()),
      ]);
  }

  String _eventLabel(String e) {
    if (e.endsWith('book_created')) return '新作品';
    if (e.contains('book')) return '作品';
    if (e.endsWith('short_post_published')) return '动态';
    if (e.contains('repost')) return '转发';
    return e.replaceAll('_', ' ');
  }

  String _shortTime(String t) => t.length > 10 ? t.substring(5, 16) : t;

  void _actions(dynamic d) {
    if (!LKClient.shared.session.isLoggedIn) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.thumb_up_outlined),
            title: Text(d.liked ? '取消赞' : '点赞'),
            onTap: () async {
              Navigator.pop(context);
              await LKApi.toggleDynamicLike(d.dynamicId, !d.liked);
              _load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('收藏'),
            onTap: () async {
              Navigator.pop(context);
              await LKApi.toggleDynamicFavorite(d.dynamicId, true);
            },
          ),
        ]),
      ),
    );
  }

  void _showComments(int dynamicId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: 420,
        child: FutureBuilder(
          future: LKApi.dynamicComments(dynamicId),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LkLoadingIndicator();
            }
            if (snap.hasError) {
              return Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.grey)));
            }
            final list = snap.data ?? [];
            return list.isEmpty
                ? const Center(child: Text('还没有评论', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          backgroundImage:
                              list[i].avatar.isNotEmpty ? NetworkImage(list[i].avatar) : null),
                      title: Text(list[i].nickname,
                          style: TextStyle(fontSize: 12, color: Colors.indigo.shade400)),
                      subtitle: Text(list[i].content),
                    ),
                  );
          },
        ),
      ),
    );
  }
}

/// 消息中心(4 类消息 + 私信会话)
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int _tab = 0;
  static const _types = ['reply', 'like', 'fan', 'system'];
  static const _labels = ['回复', '赞', '粉丝', '系统'];
  List<dynamic> _items = [];
  List<dynamic> _convs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_tab == 4) {
        final convs = await LKApi.dmConversations();
        if (!mounted) return;
        setState(() {
          _convs = convs;
          _error = null;
        });
      } else {
        final items = await LKApi.messages(_types[_tab], 0);
        if (!mounted) return;
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              try {
                await LKApi.markMessagesRead('all');
                if (!context.mounted) return;
                showLkError(context, '已标记全部已读');
              } catch (e) {
                if (!context.mounted) return;
                showLkError(context, e);
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < 5; i++)
              ButtonSegment(value: i, label: Text([..._labels, '私信'][i])),
          ],
          selected: {_tab},
          onSelectionChanged: (s) {
            setState(() => _tab = s.first);
            _load();
          },
        ),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
              : _tab == 4
                  ? ListView.builder(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom),
                      itemCount: _convs.length,
                      itemBuilder: (_, i) {
                        final c = _convs[i];
                        return ListTile(
                          leading: CircleAvatar(
                              backgroundImage: c.peerAvatar.isNotEmpty
                                  ? NetworkImage(c.peerAvatar)
                                  : null),
                          title: Text(c.peerName),
                          subtitle: Text(c.lastMessage,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: c.unread > 0
                              ? Badge(label: Text('${c.unread}'))
                              : null,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    DMChatPage(peerUid: c.peerUid, peerName: c.peerName)),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final m = _items[i];
                        return ListTile(
                          leading: CircleAvatar(
                              backgroundImage:
                                  m.avatar.isNotEmpty ? NetworkImage(m.avatar) : null),
                          title: Text(m.nickname.isEmpty ? m.title : m.nickname),
                          subtitle: Text(m.content,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
