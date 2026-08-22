import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../api/store.dart';
import '../services/avatar_cache.dart';
import '../widgets/common.dart';
import 'book_detail_page.dart';
import 'dm_chat_page.dart';
import 'dynamic_publish_page.dart';
import 'media_viewer_page.dart';
import 'search_page.dart';
import 'user_profile_page.dart';

/// 动态广场(本站动态 / 关注动态)
class DynamicPage extends StatefulWidget {
  /// 内嵌模式(作为底部 Tab 使用时无独立 Scaffold/AppBar)
  final bool embedded;
  const DynamicPage({super.key, this.embedded = false});

  @override
  State<DynamicPage> createState() => _DynamicPageState();
}

class _DynamicPageState extends State<DynamicPage> {
  List<LKDynamicItem> _items = [];
  String _cursor = '';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  String _feedTab = 'mixed';
  String _contentFilter = 'all';
  int _requestSerial = 0;
  Map<int, List<LKMedal>> _globalMedals = {};
  int _unreadCount = 0;
  double _topBarFrac = 1.0;
  // 与主页保持同一伸缩高度,确保筛选胶囊完整显示并让内容紧贴顶栏。
  static const double _topBarFlex = 100.0;

  String _dynamicKey(LKDynamicItem item) {
    if (item.dynamicId > 0) return 'id:${item.dynamicId}';
    return 'fallback:${item.authorUid}:${item.time}:${item.summary}';
  }

  int _compareDynamicItems(LKDynamicItem a, LKDynamicItem b) {
    final aTime = _parseDynamicTime(a.time);
    final bTime = _parseDynamicTime(b.time);
    if (aTime == null && bTime == null) {
      final rawOrder = b.time.compareTo(a.time);
      if (rawOrder != 0) return rawOrder;
    } else {
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final timeOrder = bTime.compareTo(aTime);
      if (timeOrder != 0) return timeOrder;
    }
    return b.dynamicId.compareTo(a.dynamicId);
  }

  List<LKDynamicItem> get _visibleItems {
    final visible = _contentFilter == 'book'
        ? _items.where((item) => item.isWorkPost).toList()
        : [..._items];
    final indexed = visible.asMap().entries.toList();
    indexed.sort((a, b) {
      final order = _compareDynamicItems(a.value, b.value);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    return indexed.map((entry) => entry.value).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadGlobalMedals();
    _loadUnread();
    _load();
  }

  Future<void> _loadUnread() async {
    if (!LKClient.shared.session.isLoggedIn) return;
    try {
      final data = await LKApi.dynamicUnread();
      final raw = data['unread_count'] ??
          data['unreadCount'] ??
          data['count'] ??
          data['total_unread'];
      final count = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
      if (mounted) setState(() => _unreadCount = count.clamp(0, 99));
    } catch (_) {}
  }

  Future<void> _loadGlobalMedals() async {
    final cached = await LKStore.cachedGlobalMedals();
    if (mounted) setState(() => _globalMedals = cached);
  }

  Future<void> _load({bool append = false}) async {
    if (_loading || append && !_hasMore) return;
    final requestSerial = ++_requestSerial;
    final feedTab = _feedTab;
    final page = append ? _page + 1 : 1;
    final previousCursor = _cursor;
    if (mounted) {
      setState(() {
        _loading = true;
        if (!append) {
          _cursor = '';
          _page = 1;
          _hasMore = true;
          _error = null;
        }
      });
    }
    try {
      final result = await LKApi.dynamicFeedPage(
          tab: feedTab,
          cursor: append ? _cursor : '',
          page: page,
          pageSize: 20);
      if (!mounted || requestSerial != _requestSerial || feedTab != _feedTab) {
        return;
      }
      final medalUpdates = <int, List<LKMedal>>{};
      for (final item in result.items) {
        if (item.authorUid > 0 && item.authorMedals.isNotEmpty) {
          medalUpdates[item.authorUid] = item.authorMedals;
        }
      }
      YomiruAvatarCache.precache(
          context, result.items.map((item) => item.avatar));
      setState(() {
        if (append) {
          final knownKeys = _items.map(_dynamicKey).toSet();
          _items.addAll(
              result.items.where((item) => knownKeys.add(_dynamicKey(item))));
        } else {
          _items = [...result.items];
        }
        _cursor = result.cursor;
        _page = page;
        _hasMore = result.hasMore &&
            !(append &&
                result.items.isEmpty &&
                result.cursor == previousCursor);
        _error = null;
      });
      if (medalUpdates.isNotEmpty) {
        await LKStore.cacheGlobalMedals(medalUpdates);
        if (mounted) {
          setState(() {
            _globalMedals = {..._globalMedals, ...medalUpdates};
          });
        }
      }
    } catch (e) {
      if (mounted && requestSerial == _requestSerial) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && requestSerial == _requestSerial) {
        setState(() => _loading = false);
      }
    }
  }

  void _switchFeedTab(String tab) {
    if (_feedTab == tab) return;
    _requestSerial++;
    setState(() {
      _feedTab = tab;
      _items = [];
      _cursor = '';
      _page = 1;
      _hasMore = true;
      _error = null;
      _loading = false;
      _topBarFrac = 1.0;
    });
    _load();
  }

  void _switchContentFilter(String filter) {
    if (_contentFilter == filter) return;
    setState(() {
      _contentFilter = filter;
      _topBarFrac = 1.0;
    });
  }

  List<LKMedal> _medalsFor(LKDynamicItem item) => item.authorMedals.isNotEmpty
      ? item.authorMedals
      : (_globalMedals[item.authorUid] ?? const <LKMedal>[]);

  Widget _dynamicTitle({bool compact = false}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _feedTab == 'mixed' ? null : () => _switchFeedTab('mixed'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8, vertical: 4),
        child: Badge(
          isLabelVisible: _unreadCount > 0,
          label: Text('$_unreadCount'),
          child: Text(
            '动态',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _followChip() => ChoiceChip(
        label: const Text('关注'),
        selected: _feedTab == 'follow',
        onSelected: (selected) => _switchFeedTab(selected ? 'follow' : 'mixed'),
        visualDensity: VisualDensity.compact,
      );

  Widget _onlyWorkChip() {
    return FilterChip(
      label: const Text('仅作品'),
      selected: _contentFilter == 'book',
      onSelected: (selected) => _switchContentFilter(selected ? 'book' : 'all'),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _feedControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          _followChip(),
          const SizedBox(width: 6),
          _onlyWorkChip(),
          const Spacer(),
        ],
      ),
    );
  }

  /// 与主页相同的让渡式收合:顶栏吸收手指滚动距离,内容不会突然跳动。
  Widget _scrollingHeader() {
    return ClipRect(
      child: SizedBox(
        height: _topBarFlex * _topBarFrac,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: -_topBarFlex * (1.0 - _topBarFrac),
              left: 0,
              right: 0,
              height: _topBarFlex,
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                        child: Row(children: [
                          _dynamicTitle(),
                          const Spacer(),
                          if (LKClient.shared.session.isLoggedIn)
                            IconButton(
                              tooltip: '发动态',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_note_rounded),
                              onPressed: () async {
                                final published = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const DynamicPublishPage()),
                                );
                                if (published == true && mounted) _load();
                              },
                            ),
                        ]),
                      ),
                      _feedControls(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 260,
          child: Center(
              child: Text(message, style: const TextStyle(color: Colors.grey))),
        ),
      ],
    );
  }

  double _previewRatio(LKDynamicMedia media) {
    if (media.width <= 0 || media.height <= 0) return 1.45;
    // 信息流不直接按原图像素高度排版,只保留大致方向并限制预览高度。
    return (media.width / media.height).clamp(0.65, 1.8).toDouble();
  }

  Widget _mediaTile(LKDynamicMedia media, {double? width, double? height}) {
    if (media.url.isEmpty) return const SizedBox.shrink();
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: CachedNetworkImage(
        imageUrl: media.url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, __) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: LkLoadingIndicator(size: 22)),
        ),
        errorWidget: (_, __, ___) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MediaViewerPage(url: media.url)),
      ),
      child: image,
    );
  }

  Widget _mediaGallery(List<LKDynamicMedia> media) {
    final visible = media.where((item) => item.url.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (visible.length == 1) {
            final item = visible.first;
            final height = (constraints.maxWidth / _previewRatio(item))
                .clamp(140.0, 280.0)
                .toDouble();
            return _mediaTile(item,
                width: constraints.maxWidth, height: height);
          }
          final size = (constraints.maxWidth - 12) / 3;
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: visible
                .map((item) => _mediaTile(item, width: size, height: size))
                .toList(),
          );
        },
      ),
    );
  }

  bool _onFeedScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0.0;
      if (delta.abs() < 0.5) return false;
      final next = (_topBarFrac - delta / _topBarFlex).clamp(0.0, 1.0);
      final diff = next - _topBarFrac;
      if (diff == 0 || !mounted) return false;
      setState(() => _topBarFrac = next);
      // 顶栏吸收的位移从列表滚动位置中抵消,保持与主页一样跟手。
      Scrollable.of(notification.context!)
          .position
          .correctBy(diff * _topBarFlex);
    } else if (notification is OverscrollNotification) {
      final next =
          (_topBarFrac - notification.overscroll / _topBarFlex).clamp(0.0, 1.0);
      if (next != _topBarFrac && mounted) {
        setState(() => _topBarFrac = next);
      }
    }
    return false;
  }

  Widget _feedBody() {
    final visibleItems = _visibleItems;
    return NotificationListener<ScrollNotification>(
      onNotification: _onFeedScroll,
      child: RefreshIndicator(
        onRefresh: _load,
        child: _error != null && _items.isEmpty
            ? _emptyState(_error!)
            : _loading && visibleItems.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.65,
                        child: const Center(child: LkLoadingIndicator()),
                      ),
                    ],
                  )
                : visibleItems.isEmpty && !_hasMore && !_loading
                    ? _emptyState(
                        _contentFilter == 'book' ? '暂无作品发布动态' : '暂无动态')
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: visibleItems.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (_, i) {
                          if (i == visibleItems.length) {
                            if (_loading) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: LkLoadingIndicator()),
                              );
                            }
                            if (_error != null) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                  child: TextButton.icon(
                                    onPressed: () => _load(append: true),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('加载失败，点击重试'),
                                  ),
                                ),
                              );
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _load(append: true);
                            });
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: LkLoadingIndicator()),
                            );
                          }
                          final d = visibleItems[i];
                          final hasBook =
                              d.bookId > 0 && d.bookTitle.trim().isNotEmpty;
                          final medals = _medalsFor(d);
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: Card(
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: d.dynamicId > 0
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CommentsPage(
                                              dynamicId: d.dynamicId,
                                              dynamicPreview: d,
                                            ),
                                          ),
                                        )
                                    : null,
                                onLongPress: () => _actions(d),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            GestureDetector(
                                              onTap: d.authorUid > 0
                                                  ? () => openUserProfile(
                                                      context, d.authorUid)
                                                  : null,
                                              child: CircleAvatar(
                                                  radius: 16,
                                                  backgroundImage: d
                                                          .avatar.isNotEmpty
                                                      ? YomiruAvatarCache
                                                          .provider(d.avatar)
                                                      : null),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Wrap(
                                                spacing: 5,
                                                runSpacing: 3,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  GestureDetector(
                                                    onTap: d.authorUid > 0
                                                        ? () => openUserProfile(
                                                            context,
                                                            d.authorUid)
                                                        : null,
                                                    child: Text(
                                                        d.nickname.isEmpty
                                                            ? '用户 ${d.authorUid}'
                                                            : d.nickname,
                                                        style: TextStyle(
                                                            color: Colors.indigo
                                                                .shade400,
                                                            fontSize: 13)),
                                                  ),
                                                  ...medals
                                                      .take(5)
                                                      .map((medal) => Tooltip(
                                                            message: medal.name,
                                                            child:
                                                                GestureDetector(
                                                              onTap: () =>
                                                                  ScaffoldMessenger.of(
                                                                          context)
                                                                      .showSnackBar(
                                                                SnackBar(
                                                                    content: Text(
                                                                        medal
                                                                            .name)),
                                                              ),
                                                              child:
                                                                  CircleAvatar(
                                                                radius: 10,
                                                                backgroundColor: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .surfaceContainerHighest,
                                                                backgroundImage:
                                                                    YomiruAvatarCache
                                                                        .provider(
                                                                            medal.image),
                                                              ),
                                                            ),
                                                          )),
                                                  if (d.eventType.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                                    .brightness ==
                                                                Brightness.dark
                                                            ? Colors
                                                                .grey.shade800
                                                            : Colors
                                                                .grey.shade300,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                          _eventLabel(
                                                              d.eventType),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .white)),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ]),
                                      const SizedBox(height: 6),
                                      Text(d.summary),
                                      if (hasBook)
                                        InkWell(
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => BookDetailPage(
                                                    bookId: d.bookId)),
                                          ),
                                          child: Container(
                                            margin:
                                                const EdgeInsets.only(top: 8),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark
                                                  ? const Color(0xFF2A2C33)
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(children: [
                                              CoverImage(
                                                  url: d.bookCover,
                                                  width: 40,
                                                  height: 53),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(d.bookTitle,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                              ),
                                            ]),
                                          ),
                                        ),
                                      _mediaGallery(d.media),
                                      const SizedBox(height: 6),
                                      Row(children: [
                                        Text(
                                            '赞 ${d.likeCount} · 评论 ${d.commentCount}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500)),
                                        const Spacer(),
                                        Text(_shortTime(d.time),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade400)),
                                      ]),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.embedded) {
      return Scaffold(
        body: Column(
          children: [
            SafeArea(bottom: false, child: _scrollingHeader()),
            Expanded(child: _feedBody()),
          ],
        ),
      );
    }
    // 内嵌模式:状态栏区域由 HomePage 的状态栏背景条负责,这里不再加 SafeArea
    return Column(children: [
      _scrollingHeader(),
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

  DateTime? _parseDynamicTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final number = int.tryParse(value);
    if (number != null && number > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
          number > 20000000000 ? number : number * 1000);
    }
    final normalized = value.replaceAll('/', '-').replaceFirst(' ', 'T');
    return DateTime.tryParse(value) ?? DateTime.tryParse(normalized);
  }

  String _shortTime(String raw) {
    final parsed = _parseDynamicTime(raw)?.toLocal();
    if (parsed == null) {
      return raw.replaceFirst('T', ' ').split('.').first;
    }
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    if (parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day) {
      return '${two(parsed.hour)}:${two(parsed.minute)}';
    }
    if (parsed.year == now.year) {
      return '${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
    }
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

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
            leading: Icon(d.favorited ? Icons.star : Icons.star_border),
            title: Text(d.favorited ? '取消收藏' : '收藏'),
            onTap: () async {
              Navigator.pop(context);
              await LKApi.toggleDynamicFavorite(d.dynamicId, !d.favorited);
            },
          ),
        ]),
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
          child: RefreshIndicator(
            onRefresh: _load,
            child: _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 320,
                        child: Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.grey))),
                      ),
                    ],
                  )
                : _tab == 4
                    ? ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom),
                        itemCount: _convs.length,
                        itemBuilder: (_, i) {
                          final c = _convs[i];
                          return ListTile(
                            leading: CircleAvatar(
                                backgroundImage: c.peerAvatar.isNotEmpty
                                    ? YomiruAvatarCache.provider(c.peerAvatar)
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
                                  builder: (_) => DMChatPage(
                                      peerUid: c.peerUid,
                                      peerName: c.peerName)),
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final m = _items[i];
                          return ListTile(
                            leading: CircleAvatar(
                                backgroundImage: m.avatar.isNotEmpty
                                    ? YomiruAvatarCache.provider(m.avatar)
                                    : null),
                            title:
                                Text(m.nickname.isEmpty ? m.title : m.nickname),
                            subtitle: Text(m.content,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          );
                        },
                      ),
          ),
        ),
      ]),
    );
  }
}
