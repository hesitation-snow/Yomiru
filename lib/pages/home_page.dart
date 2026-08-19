import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../api/store.dart';
import '../widgets/common.dart';
import 'book_detail_page.dart';
import 'channel_page.dart';
import 'dm_chat_page.dart';
import 'dynamic_page.dart';
import 'login_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  /// 顶栏/底栏可见比例 0..1,随首页滚动 1:1 伸缩(滑一点露一点)
  double _barFrac = 1.0;
  /// 顶栏可伸缩部分的高度(不含状态栏区域)
  static const double _barFlex = 104.0;

  static const _channels = [
    ('hot', '热门', '/api/bff/home-feed-v1'),
    ('new', '最新', '/api/bff/home-feed-v1'),
    ('rank', '排行榜', 'rank'),
  ];
  int _channel = 0;
  bool _listMode = false;

  @override
  void initState() {
    super.initState();
    // 登录/登出后刷新顶栏头像等会话相关 UI
    LKClient.sessionRev.addListener(_onSessionRev);
    _loadListMode();
  }

  Future<void> _loadListMode() async {
    final v = await ReaderPrefs.feedListMode();
    if (mounted) setState(() => _listMode = v);
  }

  @override
  void dispose() {
    LKClient.sessionRev.removeListener(_onSessionRev);
    super.dispose();
  }

  void _onSessionRev() {
    if (mounted) setState(() {});
  }

  /// 首页滚动时顶栏向上滑出(参考 PiliPlus):
  /// 把拖动增量让渡给顶栏,并用 correctBy 抵消内容自身的滚动,
  /// 视觉上顶栏和内容一起向上移动、顶栏从顶部滑出,而不是原地被内容覆盖。
  void _onFeedScroll(ScrollNotification n) {
    if (_tab != 0) return;
    if (n is ScrollUpdateNotification) {
      // 只响应手指拖动;惯性滚动/程序修正产生的通知不参与
      if (n.dragDetails == null) return;
      if (n.metrics.axis == Axis.horizontal) return;
      final delta = n.scrollDelta ?? 0.0;
      if (delta == 0) return;
      final newFrac = (_barFrac - delta / _barFlex).clamp(0.0, 1.0);
      final diff = newFrac - _barFrac;
      if (diff == 0) return;
      setState(() => _barFrac = newFrac);
      // 顶栏吸收的这部分位移从滚动位置里抵消,内容保持跟手
      Scrollable.of(n.context!).position.correctBy(diff * _barFlex);
    } else if (n is OverscrollNotification) {
      // 顶部下拉回弹:让顶栏跟随露出
      final newFrac = (_barFrac - n.overscroll / _barFlex).clamp(0.0, 1.0);
      if (newFrac != _barFrac) setState(() => _barFrac = newFrac);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padTop = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? const SystemUiOverlayStyle(
              statusBarColor: Color(0xFF1B1C21),
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.white,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
      child: Scaffold(
      body: Column(
        children: [
          // 顶栏:状态栏条固定,搜索框+头像+频道胶囊随滚动向上滑出
          // (参考 PiliPlus 的让渡式收合);其它 Tab 只留状态栏背景
          SizedBox(
            height: padTop,
            width: double.infinity,
            child: ColoredBox(
              color: _tab == 0
                  ? (isDark ? const Color(0xFF1B1C21) : Colors.white)
                  : (isDark
                      ? const Color(0xFF121316)
                      : const Color(0xFFF6F7FB)),
            ),
          ),
          SizedBox(
            height: _tab == 0 ? _barFlex * _barFrac : 0.0,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: _tab == 0 ? -_barFlex * (1.0 - _barFrac) : 0.0,
                  left: 0,
                  right: 0,
                  height: _barFlex,
                  child: ColoredBox(
                    color: isDark ? const Color(0xFF1B1C21) : Colors.white,
                    // 用不可滚动的 ScrollView 吸收高度变化中间帧的约束,避免溢出警告
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const SearchPage())),
                                      child: Container(
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14),
                                        alignment: Alignment.centerLeft,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                                      .brightness ==
                                                  Brightness.dark
                                              ? const Color(0xFF1E2025)
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.search_rounded,
                                                size: 19,
                                                color:
                                                    Colors.grey.shade500),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                '搜索书名 / 作者',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 13.5,
                                                    color: Colors
                                                        .grey.shade500),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // LK 用户头像:点击跳转"我的"
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      _tab = 3;
                                      _barFrac = 1.0;
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.indigo.shade200,
                                            width: 1.6),
                                      ),
                                      child: CircleAvatar(
                                        radius: 15,
                                        backgroundColor:
                                            Colors.indigo.shade100,
                                        backgroundImage: LKClient.shared
                                                .session.avatar.isNotEmpty
                                            ? NetworkImage(LKClient.shared
                                                .session.avatar)
                                            : null,
                                        child: LKClient.shared
                                                .session.avatar.isNotEmpty
                                            ? null
                                            : const Icon(Icons.person,
                                                size: 18,
                                                color: Colors.indigo),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  // 首页排版切换(网格/单列)
                                  IconButton(
                                    tooltip: _listMode
                                        ? '切换为网格排版'
                                        : '切换为单列排版',
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      _listMode
                                          ? Icons.grid_view_rounded
                                          : Icons.view_agenda_outlined,
                                      size: 21,
                                    ),
                                    onPressed: () {
                                      setState(
                                          () => _listMode = !_listMode);
                                      ReaderPrefs.setFeedListMode(_listMode);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          // 频道胶囊(热门/最新),随顶栏一起滑出
                          SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(
                          left: 12, right: 12, bottom: 4),
                      itemCount: _channels.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final sel = i == _channel;
                        final scheme = Theme.of(context).colorScheme;
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _channel = i);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel
                                  ? scheme.primary
                                  : (isDark
                                      ? const Color(0xFF2A2C33)
                                      : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: sel
                                  ? [
                                      BoxShadow(
                                          color: scheme.primary
                                              .withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2)),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              _channels[i].$2,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: sel
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: sel
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade700),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // 顶栏随滚动向上滑出(拖动增量让渡给顶栏)
                  _onFeedScroll(n);
                  return false;
                },
                child: IndexedStack(
                  index: _tab,
                  children: [
                    FeedTab(
                      channelCode: _channels[_channel].$1,
                      path: _channels[_channel].$3,
                      listMode: _listMode,
                    ),
                    const SectionTab(),
                    const DynamicPage(embedded: true),
                    const MyTab(),
                  ],
                ),
              ),
            ),
          ],
        ),
      bottomNavigationBar: ClipRect(
        // 底栏随顶栏一起 1:1 伸缩(仅首页;切 Tab 时重置为完整显示)
        child: SizedBox(
          height: (64 + MediaQuery.of(context).padding.bottom) * _barFrac,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              setState(() {
                _tab = i;
                _barFrac = 1.0;
              });
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页'),
              NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: '分区'),
              NavigationDestination(
                  icon: Icon(Icons.dynamic_feed_outlined),
                  selectedIcon: Icon(Icons.dynamic_feed),
                  label: '动态'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的'),
            ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ==================== 首页信息流 ====================

class FeedTab extends StatefulWidget {
  final String channelCode;
  final String path;
  final bool listMode;
  const FeedTab(
      {super.key,
      required this.channelCode,
      required this.path,
      required this.listMode});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final List<dynamic> _items = [];
  static const _recommendCacheKey = 'home_recommend_v1';
  List<LKBook> _recommendBooks = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  bool get _isRank => widget.path == 'rank';
  bool get _listMode => widget.listMode;

  @override
  void initState() {
    super.initState();
    _loadRecommend();
    _load(1, false);
  }

  /// 推荐卡只由信息流父状态加载一次，列表/网格模式共用同一份数据。
  Future<void> _loadRecommend() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_recommendCacheKey);
    if (raw != null) {
      try {
        final cached = (jsonDecode(raw) as List)
            .map((e) => LKBook.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        if (mounted && cached.isNotEmpty) {
          setState(() => _recommendBooks = cached);
        }
      } catch (_) {}
    }
    try {
      final books = await LKApi.homeRecommend();
      if (!mounted) return;
      if (books.isNotEmpty) setState(() => _recommendBooks = books);
      await p.setString(
        _recommendCacheKey,
        jsonEncode(books
            .map((b) => {
                  'book_id': b.bookId,
                  'title': b.title,
                  'cover_url': b.coverUrl,
                })
            .toList()),
      );
    } catch (_) {}
  }

  @override
  void didUpdateWidget(FeedTab old) {
    super.didUpdateWidget(old);
    if (old.channelCode != widget.channelCode || old.path != widget.path) {
      _load(1, false);
    }
  }

  Future<void> _load(int page, bool append) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = _isRank
          ? await LKApi.rank(page, pageSize: 20)
          : (widget.path == '/api/bff/home-feed-v1'
              ? await LKApi.homeFeed(widget.channelCode, page)
              : await LKApi.channelFeed(widget.path, page));
      if (!mounted) return;
      setState(() {
        if (append) {
          _items.addAll(items);
        } else {
          _items
            ..clear()
            ..addAll(items);
        }
        _page = page;
        _hasMore = items.length >= 20;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 主页排行榜不显示名次,正常展示
  int? _rankOf(int i) => null;

  @override
  Widget build(BuildContext context) {
    // 注意:IndexedStack 的子组件不能包 Expanded(非法 ParentDataWidget,
    // release 模式会抛类型转换异常导致整个信息流区域空白),直接返回即可。
    if (_error != null && _items.isEmpty) {
      return _feedHint(
          icon: Icons.wifi_off_rounded,
          text: _error!,
          onRetry: () => _load(1, false));
    }
    if (_items.isEmpty && _loading) {
      return const LkLoadingIndicator();
    }
    if (_items.isEmpty) {
      return _feedHint(
          icon: Icons.inbox_outlined,
          text: '没有获取到内容,请点击重试',
          onRetry: () => _load(1, false));
    }

    final listView = ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      itemCount: _items.length + 1 + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == 0) return _HomeRecommendCard(books: _recommendBooks);
        final j = i - 1;
        if (j >= _items.length) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _load(_page + 1, true));
          return const Padding(
            padding: EdgeInsets.all(12),
            child: LkLoadingIndicator(),
          );
        }
        final book = _items[j];
        return BookCard(
          book: book,
          rank: _rankOf(j),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BookDetailPage(bookId: book.bookId)),
          ),
        );
      },
    );

    final gridView = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
            child: _HomeRecommendCard(books: _recommendBooks)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          sliver: SliverGrid(
            gridDelegate: bookGridDelegate(),
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                if (i >= _items.length) {
                  // 触底加载更多(延迟到帧后,避免 build 期间 setState)
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _load(_page + 1, true));
                  return const LkLoadingIndicator();
                }
                final book = _items[i];
                return BookGridCard(
                  book: book,
                  rank: _rankOf(i),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            BookDetailPage(bookId: book.bookId)),
                  ),
                );
              },
              childCount: _items.length + (_hasMore ? 1 : 0),
            ),
          ),
        ),
      ],
    );

    return Stack(children: [
      Positioned.fill(child: _listMode ? listView : gridView),
    ]);
  }

  /// 首页信息流的错误/空状态提示(带重试)
  Widget _feedHint(
      {required IconData icon,
      required String text,
      required VoidCallback onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 首页好书推荐(官网模块) ====================

class _HomeRecommendCard extends StatelessWidget {
  final List<LKBook> books;

  const _HomeRecommendCard({required this.books});

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Material(
        color: isDark ? const Color(0xFF1E2025) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.pink.shade300, Colors.deepPurple.shade400]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('好书推荐',
                    style: TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              itemCount: books.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final b = books[i];
                return SizedBox(
                  width: 96,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              BookDetailPage(bookId: b.bookId)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoverImage(
                            url: b.coverUrl,
                            width: 96,
                            height: 128,
                            radius: 10),
                        const SizedBox(height: 5),
                        Text(
                          b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF37474F),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ==================== 分区 ====================

class SectionTab extends StatefulWidget {
  const SectionTab({super.key});

  @override
  State<SectionTab> createState() => _SectionTabState();
}

class _SectionTabState extends State<SectionTab> {
  static const _sections = [
    (Icons.auto_stories_rounded, '轻小说', '日轻翻译 / 文库本', '/api/bff/home-lightnovel-feed-v1'),
    (Icons.lightbulb_outline_rounded, '原创', '站内原创作品', '/api/bff/home-original-feed-v1'),
    (Icons.groups_2_outlined, '同人', '同人 / 二创', '/api/bff/home-fanfic-feed-v1'),
    (Icons.menu_book_outlined, 'EPUB', 'EPUB 电子书', '/api/bff/home-epub-feed-v1'),
    (Icons.bolt_rounded, '更新', '最近更新', '/api/bff/home-recent-updates-feed-v1'),
  ];

  /// path -> 分区内最新 3 部(先读本地缓存,再后台刷新并写回)
  final Map<String, List<LKBook>> _latest = {};
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadCache();
    await _refreshAll();
  }

  String _cacheKey(String path) => 'section_latest_$path';

  /// 读取本地缓存的「最新三部」
  Future<void> _loadCache() async {
    final p = await SharedPreferences.getInstance();
    for (final s in _sections) {
      final raw = p.getString(_cacheKey(s.$4));
      if (raw == null) continue;
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => LKBook.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        if (!mounted) return;
        setState(() => _latest[s.$4] = list);
      } catch (_) {}
    }
  }

  /// 后台刷新每个分区的最新 5 部,并保存到本地
  Future<void> _refreshAll() async {
    final p = await SharedPreferences.getInstance();
    for (final s in _sections) {
      try {
        final items = await LKApi.channelFeed(s.$4, 1, pageSize: 5);
        final top = items.take(5).toList();
        if (!mounted) return;
        setState(() => _latest[s.$4] = top);
        await p.setString(
            _cacheKey(s.$4), jsonEncode(top.map(_bookJson).toList()));
      } catch (_) {}
    }
    if (mounted) setState(() => _refreshed = true);
  }

  static Map<String, dynamic> _bookJson(LKBook b) => {
        'book_id': b.bookId,
        'title': b.title,
        'author_name': b.authorName,
        'cover_url': b.coverUrl,
      };

  void _openBook(LKBook b) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailPage(bookId: b.bookId)),
    );
  }

  /// 分区卡片下方的「最新五部」横向滑动列表(大封面)
  Widget _latestRow(String path) {
    final items = _latest[path];
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 高度按字体缩放动态计算,避免 BOTTOM OVERFLOW
    final titleLine =
        MediaQuery.textScalerOf(context).scale(12) * 1.3;
    final rowH = 191 + 6 + titleLine * 2 + 10;
    return SizedBox(
      height: rowH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final b = items[i];
          return SizedBox(
            width: 143,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openBook(b),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoverImage(
                        url: b.coverUrl,
                        width: 143,
                        height: 191,
                        radius: 10),
                    const SizedBox(height: 6),
                    Text(
                      b.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF37474F)),
                    ),
                  ]),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('分区',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF263238))),
        const SizedBox(height: 4),
        Text('按类型浏览作品,每类附最新五部',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
        const SizedBox(height: 14),
        ..._sections.map((s) {
          final latest = _latest[s.$4];
          final loading = (latest == null || latest.isEmpty) && !_refreshed;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: isDark ? const Color(0xFF1E2025) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ChannelPage(path: s.$4, label: s.$2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(s.$1, color: scheme.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$2,
                                  style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600)),
                              Text(s.$3,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500)),
                            ]),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                    ]),
                  ),
                ),
                if (latest != null && latest.isNotEmpty) _latestRow(s.$4),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: LkLoadingIndicator(
                      minHeight: 32,
                      size: 16,
                      strokeWidth: 2,
                    ),
                  ),
              ]),
            ),
          );
        }),
        // (排行榜已移到首页频道:热门 / 最新 / 排行榜)
      ],
    );
  }
}

// ==================== 云端历史 ====================

class CloudHistoryTab extends StatefulWidget {
  const CloudHistoryTab({super.key});

  @override
  State<CloudHistoryTab> createState() => _CloudHistoryTabState();
}

class _CloudHistoryTabState extends State<CloudHistoryTab> {
  List<dynamic> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!LKClient.shared.session.isLoggedIn) {
        setState(() {
          _error = '未登录';
          _items = [];
        });
        return;
      }
      final items = await LKApi.cloudHistory(1);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == '未登录') {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('登录后可同步网页端阅读记录', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const LoginPage()))
                  .then((_) => _load()),
              child: const Text('去登录')),
        ]),
      );
    }
    if (_loading && _items.isEmpty) {
      return const LkLoadingIndicator();
    }
    if (_error != null && _items.isEmpty) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (_, i) {
          final h = _items[i];
          return InkWell(
            // 历史项点击进详情页(详情页有"继续阅读"按钮),长按删除
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BookDetailPage(bookId: h.bookId)),
            ),
            onLongPress: () async {
              try {
                await LKApi.deleteHistory(h.bookId);
                _load();
              } catch (e) {
                if (context.mounted) showLkError(context, e);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Material(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E2025)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BookDetailPage(bookId: h.bookId)),
                  ),
                  onLongPress: () async {
                    try {
                      await LKApi.deleteHistory(h.bookId);
                      _load();
                    } catch (e) {
                      if (context.mounted) showLkError(context, e);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      CoverImage(url: h.coverUrl, width: 50, height: 66, radius: 8),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${h.title} · ${h.authorName}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3)),
                              const SizedBox(height: 4),
                              if (h.chapterTitle.isNotEmpty)
                                Text('读到 ${h.chapterTitle}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.indigo.shade400)),
                              const SizedBox(height: 6),
                              if (h.progressPercent > 0)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (h.progressPercent / 100).clamp(0.0, 1.0),
                                    minHeight: 5,
                                    backgroundColor: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade200,
                                  ),
                                ),
                              const SizedBox(height: 5),
                              Text(
                                [
                                  if (h.progressPercent > 0) '进度 ${h.progressPercent}%',
                                  if (h.lastReadAt.isNotEmpty) h.lastReadAt,
                                  if (h.unreadChapters > 0) '未读 ${h.unreadChapters} 章',
                                ].join(' · '),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==================== 我的 ====================

class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  @override
  void initState() {
    super.initState();
    // 登录/登出后刷新用户卡片
    LKClient.sessionRev.addListener(_onRev);
  }

  @override
  void dispose() {
    LKClient.sessionRev.removeListener(_onRev);
    super.dispose();
  }

  void _onRev() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = LKClient.shared.session;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 头部卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.indigo.shade400, Colors.indigo.shade600],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.indigo.shade200.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 2),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                backgroundImage:
                    s.avatar.isNotEmpty ? NetworkImage(s.avatar) : null,
                child: s.avatar.isEmpty
                    ? const Icon(Icons.person, size: 30, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.isLoggedIn ? s.nickname : '未登录',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 3),
                Text(
                    s.isLoggedIn
                        ? 'UID: ${s.uid}'
                        : '登录后可同步书架、阅读进度、书评与消息',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          ]),
        ),
        const SizedBox(height: 16),
        if (!s.isLoggedIn)
          FilledButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LoginPage())),
            child: const Text('登录 / 注册'),
          )
        else
          OutlinedButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LoginPage())),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('退出登录'),
          ),
        const SizedBox(height: 8),
        _row(context, Icons.collections_bookmark_outlined, '我的书架',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShelfPage()))),
        _row(context, Icons.history_rounded, '阅读历史',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('阅读历史')),
                          body: const CloudHistoryTab(),
                        )))),
        _row(context, Icons.chat_bubble_outline, '消息中心',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesPage()))),
        _row(context, Icons.settings_outlined, '设置与资料',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
