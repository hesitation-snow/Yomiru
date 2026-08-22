import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../api/store.dart';
import '../widgets/common.dart';
import '../services/avatar_cache.dart';
import 'book_detail_page.dart';
import 'media_viewer_page.dart';
import 'user_profile_page.dart';

/// 搜索页:关键词 + 分类(轻小说/原创/同人/EPUB)+ 标签(含"最近更新"更新时间筛选)+ 排序(相关/最新)
class SearchPage extends StatefulWidget {
  /// 从详情页标签跳转时传入的初始标签
  final String? initialTag;
  const SearchPage({super.key, this.initialTag});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final List<dynamic> _items = [];

  /// 热门标签(tag_items):{title, jumpType, jumpValue}
  List<Map<String, String>> _tags = [];
  List<Map<String, String>> _channels = [];
  String? _tag; // 选中的标签 jumpValue
  String? _channel; // 选中的分类 code
  String _sort = 'relevance';
  String? _error;
  bool _loading = false;
  int _page = 0;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
    _loadTaxonomy();
    if (widget.initialTag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(0, false));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadTaxonomy() async {
    try {
      final t = await LKApi.searchTaxonomy();
      // 第一个 tab 的第一个 section = 热门标签(含"最近更新")
      final tags = <Map<String, String>>[];
      final tabs = (t['tabs'] as List?) ?? const [];
      for (final tab in tabs) {
        final groups = (tab['groups'] as List?) ?? const [];
        for (final g in groups) {
          final sections = (g['sections'] as List?) ?? const [];
          for (final s in sections) {
            final items = (s['tag_items'] as List?) ?? const [];
            for (final it in items) {
              final title = (it['title'] as String?) ?? '';
              final jt = (it['jump_type'] as String?) ?? 'tag';
              final jv = (it['jump_value'] as String?) ?? '';
              if (title.isNotEmpty && !tags.any((e) => e['title'] == title)) {
                tags.add({'title': title, 'jumpType': jt, 'jumpValue': jv});
              }
            }
            if (tags.isNotEmpty) break;
          }
          if (tags.isNotEmpty) break;
        }
        if (tags.isNotEmpty) break;
      }
      final channels = <Map<String, String>>[];
      for (final c in (t['channels'] as List?) ?? const []) {
        channels.add({
          'code': (c['code'] as String?) ?? '',
          'label': (c['label'] as String?) ?? '',
        });
      }
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _channels = channels;
      });
    } catch (_) {
      // 分类加载失败不影响搜索
    }
  }

  Future<void> _search(int page, bool append) async {
    var query = _controller.text.trim();
    if (query.isEmpty && _tag == null && _channel == null) return;
    var preset = '';
    var primaryTag = '';
    var channelCode = '';
    var workType = '';
    if (_tag != null) {
      final chip = _tags.firstWhere((e) => e['jumpValue'] == _tag,
          orElse: () => {'title': '', 'jumpType': 'tag', 'jumpValue': _tag!});
      if (chip['jumpType'] == 'keyword') {
        // "最近更新"等关键词预设:替换查询词
        query = _tag!;
        preset = _tag!;
      } else {
        primaryTag = _tag!;
      }
    }
    if (_channel != null) {
      channelCode = _channel!;
      workType = _channel!;
      primaryTag = '';
      preset = '';
    }
    setState(() => _loading = true);
    try {
      final items = await LKApi.search(
        query,
        page,
        sort: _sort,
        primaryTag: primaryTag,
        preset: preset,
        channelCode: channelCode,
        workType: workType,
      );
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

  Future<void> _refresh() async {
    await _loadTaxonomy();
    await _search(0, false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 38,
          margin: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(0, false),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索书名 / 作者 / 标签',
              isDense: true,
              fillColor: isDark ? const Color(0xFF2A2C33) : Colors.white,
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _search(0, false),
            child: const Text('搜索'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 排序
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _segBtn('相关', 'relevance'),
                const SizedBox(width: 8),
                _segBtn('最新', 'new'),
              ],
            ),
          ),
          // 分类
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _chip('全部', _channel == null, () {
                  setState(() => _channel = null);
                  _search(0, false);
                }),
                for (final c in _channels)
                  _chip(c['label']!, _channel == c['code'], () {
                    setState(() {
                      _channel = c['code'];
                      _tag = null;
                    });
                    _search(0, false);
                  }),
              ],
            ),
          ),
          // 标签(含最近更新)
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _chip('全部标签', _tag == null, () {
                    setState(() => _tag = null);
                    _search(0, false);
                  }, trailingPadding: false),
                  for (final t in _tags)
                    _chip(
                      t['title']!,
                      _tag == t['jumpValue'],
                      () {
                        setState(() {
                          _tag = t['jumpValue'];
                          _channel = null;
                        });
                        _search(0, false);
                      },
                      trailingPadding: false,
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _error != null && _items.isEmpty
                  ? _refreshableMessage(_error!)
                  : _items.isEmpty && _loading
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.65,
                              child: const Center(child: LkLoadingIndicator()),
                            ),
                          ],
                        )
                      : _items.isEmpty && !_loading
                          ? _refreshableMessage(_controller.text.isEmpty &&
                                  _tag == null &&
                                  _channel == null
                              ? '输入关键词,或选择标签 / 分类 / 更新时间'
                              : '没有找到相关作品')
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(12, 4, 12,
                                  12 + MediaQuery.of(context).padding.bottom),
                              gridDelegate: bookGridDelegate(),
                              itemCount: _items.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i >= _items.length) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (mounted) _search(_page + 1, true);
                                  });
                                  return const LkLoadingIndicator();
                                }
                                final b = _items[i];
                                return BookGridCard(
                                  book: b,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            BookDetailPage(bookId: b.bookId)),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _refreshableMessage(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Center(
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ),
        ),
      ],
    );
  }

  Widget _segBtn(String label, String value) {
    final sel = _sort == value;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        setState(() => _sort = value);
        _search(0, false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            color: sel ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap,
      {bool trailingPadding = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(right: trailingPadding ? 8 : 0),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary
                : (isDark ? const Color(0xFF1E2025) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: selected ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 服务器书架
class ShelfPage extends StatefulWidget {
  final bool embedded;
  final bool? listMode;

  const ShelfPage({super.key, this.embedded = false, this.listMode});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  List<LKBook> _items = [];
  String? _error;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _listMode = false;
  bool _localMode = false;
  int _loadSerial = 0;
  double _topBarFrac = 1.0;
  static const double _topBarFlex = 56.0;

  @override
  void initState() {
    super.initState();
    _localMode = !LKClient.shared.session.isLoggedIn;
    LKClient.sessionRev.addListener(_onSessionRev);
    LKStore.localShelfRev.addListener(_onLocalShelfRev);
    _loadListMode();
    _load();
  }

  @override
  void dispose() {
    LKClient.sessionRev.removeListener(_onSessionRev);
    LKStore.localShelfRev.removeListener(_onLocalShelfRev);
    super.dispose();
  }

  void _onSessionRev() {
    if (!mounted) return;
    _loadSerial++;
    setState(() {
      _localMode = !LKClient.shared.session.isLoggedIn;
      _items = [];
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    _load();
  }

  void _onLocalShelfRev() {
    if (!_localMode || !mounted) return;
    // 本地书架不需要重新走完整加载流程;即使首次加载尚未结束,也直接同步最新数据。
    LKStore.localShelf().then((items) {
      if (!mounted || !_localMode) return;
      setState(() {
        _items = items;
        _page = 1;
        _hasMore = false;
        _error = null;
      });
    });
  }

  bool _onShelfScroll(ScrollNotification notification) {
    if (!widget.embedded || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() < 0.5) return false;
      final next = (_topBarFrac - delta / _topBarFlex).clamp(0.0, 1.0);
      final diff = next - _topBarFrac;
      if (diff == 0 || !mounted) return false;
      setState(() => _topBarFrac = next);
      Scrollable.of(notification.context!)
          .position
          .correctBy(diff * _topBarFlex);
    } else if (notification is OverscrollNotification) {
      final next =
          (_topBarFrac - notification.overscroll / _topBarFlex).clamp(0.0, 1.0);
      if (next != _topBarFrac && mounted) setState(() => _topBarFrac = next);
    }
    return false;
  }

  Future<void> _loadListMode() async {
    if (widget.listMode != null) {
      if (mounted) setState(() => _listMode = widget.listMode!);
      return;
    }
    final value = await ReaderPrefs.feedListMode();
    if (mounted) setState(() => _listMode = value);
  }

  @override
  void didUpdateWidget(ShelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listMode != null && widget.listMode != oldWidget.listMode) {
      setState(() => _listMode = widget.listMode!);
    }
  }

  Future<void> _load({int page = 1, bool append = false}) async {
    if (_loading || append && !_hasMore) return;
    final requestSerial = ++_loadSerial;
    final localMode = _localMode || !LKClient.shared.session.isLoggedIn;
    setState(() => _loading = true);
    try {
      if (localMode) {
        final items = await LKStore.localShelf();
        if (!mounted || requestSerial != _loadSerial || !_localMode) return;
        setState(() {
          _items = items;
          _page = 1;
          _hasMore = false;
          _error = null;
        });
        return;
      }
      final items = await LKApi.bookshelf(page);
      if (!mounted || requestSerial != _loadSerial || _localMode) return;
      setState(() {
        if (append) {
          _items.addAll(items);
        } else {
          _items = [...items];
        }
        _page = page;
        _hasMore = items.length >= 50;
        _error = null;
      });
    } catch (e) {
      if (mounted && requestSerial == _loadSerial) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && requestSerial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggleShelfSource() {
    if (!LKClient.shared.session.isLoggedIn) {
      if (!_localMode) setState(() => _localMode = true);
      return;
    }
    if (_loading) return;
    _loadSerial++;
    setState(() {
      _localMode = !_localMode;
      _items = [];
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    _load();
  }

  Widget _shelfSourceButton() {
    return TextButton.icon(
      onPressed: _loading ? null : _toggleShelfSource,
      icon: Icon(
        _localMode ? Icons.smartphone_rounded : Icons.cloud_outlined,
        size: 18,
      ),
      label: Text(_localMode ? '本机书架' : '云端书架'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null && _items.isEmpty
        ? Center(
            child: Text(_error!, style: const TextStyle(color: Colors.grey)))
        : RefreshIndicator(
            onRefresh: () => _load(),
            child: _loading && _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.65,
                        child: const Center(child: LkLoadingIndicator()),
                      ),
                    ],
                  )
                : _listMode
                    ? ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(8, 4, 8,
                            12 + MediaQuery.of(context).padding.bottom),
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _items.length) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _load(page: _page + 1, append: true);
                            });
                            return const LkLoadingIndicator();
                          }
                          final b = _items[i];
                          return BookCard(
                            book: b,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      BookDetailPage(bookId: b.bookId)),
                            ),
                          );
                        },
                      )
                    : GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(12, 8, 12,
                            12 + MediaQuery.of(context).padding.bottom),
                        gridDelegate: bookGridDelegate(),
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _items.length) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _load(page: _page + 1, append: true);
                              }
                            });
                            return const LkLoadingIndicator();
                          }
                          final b = _items[i];
                          return BookGridCard(
                            book: b,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      BookDetailPage(bookId: b.bookId)),
                            ),
                          );
                        },
                      ),
          );
    if (!widget.embedded) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_localMode ? '本机书架' : '我的书架'),
          actions: [
            _shelfSourceButton(),
            IconButton(
              tooltip: _listMode ? '切换为网格排版' : '切换为单列排版',
              icon: Icon(_listMode
                  ? Icons.grid_view_rounded
                  : Icons.view_agenda_outlined),
              onPressed: () {
                final value = !_listMode;
                setState(() => _listMode = value);
                ReaderPrefs.setFeedListMode(value);
              },
            ),
          ],
        ),
        body: body,
      );
    }
    final embeddedBody = NotificationListener<ScrollNotification>(
      onNotification: _onShelfScroll,
      child: body,
    );
    return Column(
      children: [
        ClipRect(
          child: SizedBox(
            height: _topBarFlex * _topBarFrac,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: -_topBarFlex * (1 - _topBarFrac),
                  left: 0,
                  right: 0,
                  height: _topBarFlex,
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      // 与动态顶栏的外层间距一致；标题自身再保留 8px
                      // 内边距，避免书架文字比“动态”向左错位。
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Text(
                              _localMode ? '本机书架' : '书架',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          _shelfSourceButton(),
                          IconButton(
                            tooltip: _listMode ? '切换为网格排版' : '切换为单列排版',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(_listMode
                                ? Icons.grid_view_rounded
                                : Icons.view_agenda_outlined),
                            onPressed: () {
                              final value = !_listMode;
                              setState(() => _listMode = value);
                              ReaderPrefs.setFeedListMode(value);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: embeddedBody),
      ],
    );
  }
}

/// 书评 / 本卷评论
class CommentsPage extends StatefulWidget {
  final int bookId;
  final String bookTitle;

  /// 0 = 整书评论;>0 = 本卷评论
  final int volumeId;
  final int dynamicId;
  final LKDynamicItem? dynamicPreview;
  const CommentsPage(
      {super.key,
      this.bookId = 0,
      this.bookTitle = '',
      this.volumeId = 0,
      this.dynamicId = 0,
      this.dynamicPreview});

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  List<dynamic> _comments = [];
  String? _error;
  bool _loading = true;
  final _input = TextEditingController();

  /// 表情包(code → 图片地址),评论渲染与表情面板共用
  final Map<String, String> _emojiUrl = {};
  List<LKEmojiGroup> _emojiGroups = [];
  final _picker = ImagePicker();
  final List<LKDynamicMedia> _pendingMedia = [];
  LKDynamicItem? _dynamicDetail;
  bool _uploadingImage = false;
  final Set<String> _selectedPollOptions = <String>{};
  bool _pollSubmitting = false;

  bool get _isVolume => widget.volumeId > 0;
  bool get _isDynamic => widget.dynamicId > 0;

  /// api.lightnovel.fun/static/... 会 500,统一换 static 域
  static String _fixEmojiUrl(String u) =>
      u.replaceFirst('api.lightnovel.fun/static/', 'static.lightnovel.fun/');

  @override
  void initState() {
    super.initState();
    _load();
    _loadEmojis();
    if (_isDynamic) _loadDynamicDetail();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadEmojis() async {
    try {
      final groups = await LKApi.commentEmojis();
      if (!mounted) return;
      final map = <String, String>{};
      for (final g in groups) {
        for (final it in g.items) {
          // code 是官网评论里实际使用的格式({:neko3:}、[s:1]、{:df000:} 等)
          if (it.isImage && it.code.isNotEmpty) {
            map[it.code] = _fixEmojiUrl(it.url);
          }
        }
      }
      setState(() {
        _emojiGroups = groups;
        _emojiUrl.addAll(map);
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cs = _isDynamic
          ? await LKApi.dynamicComments(widget.dynamicId)
          : _isVolume
              ? await LKApi.volumeComments(widget.bookId, widget.volumeId, 1)
              : await LKApi.bookComments(widget.bookId, 1);
      if (!mounted) return;
      setState(() => _comments = cs);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDynamicDetail() async {
    try {
      final detail = await LKApi.dynamicDetail(widget.dynamicId);
      if (!mounted) return;
      setState(() {
        _dynamicDetail = detail;
        _selectedPollOptions
          ..clear()
          ..addAll(detail.poll?.options
                  .where((option) => option.selected)
                  .map((option) => option.id) ??
              const []);
      });
      await LKApi.markDynamicRead(dynamicId: widget.dynamicId);
    } catch (_) {
      // 详情失败时仍保留信息流传入的预览内容。
    }
  }

  Future<void> _publish() async {
    final content = _input.text.trim();
    if (content.isEmpty) return;
    try {
      if (_isDynamic) {
        await LKApi.publishDynamicComment(widget.dynamicId, content,
            media: _pendingMedia);
      } else if (_isVolume) {
        await LKApi.publishBookComment(widget.bookId, content,
            volumeId: widget.volumeId, media: _pendingMedia);
      } else {
        await LKApi.publishBookComment(widget.bookId, content,
            media: _pendingMedia);
      }
      _input.clear();
      _pendingMedia.clear();
      _load();
    } catch (e) {
      if (mounted) showLkError(context, e);
    }
  }

  Future<void> _pickImage() async {
    if (_uploadingImage || _pendingMedia.length >= 9) return;
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 88, maxWidth: 2048);
    if (file == null) return;
    setState(() => _uploadingImage = true);
    try {
      final media = await LKApi.uploadCommentImage(file.path);
      if (mounted) setState(() => _pendingMedia.add(media));
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  /// 渲染评论内容:把表情代码({:xx:} / [s:数字] 等)替换为表情图片
  Widget _renderContent(String content) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\{:[^:]+:\}|\[[a-zA-Z]+:\d+\]');
    var pos = 0;
    for (final m in re.allMatches(content)) {
      if (m.start > pos) {
        spans.add(TextSpan(text: content.substring(pos, m.start)));
      }
      final code = m.group(0)!;
      final url = _emojiUrl[code];
      if (url != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Image.network(
              url,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Text(code, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(text: code));
      }
      pos = m.end;
    }
    if (pos < content.length) {
      spans.add(TextSpan(text: content.substring(pos)));
    }
    return Text.rich(TextSpan(children: spans));
  }

  String _formatCommentTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final number = int.tryParse(value);
    final date = number == null
        ? DateTime.tryParse(value.replaceFirst(' ', 'T'))
        : DateTime.fromMillisecondsSinceEpoch(
            number > 20000000000 ? number : number * 1000);
    if (date == null) return value.replaceFirst('T', ' ').split('.').first;
    String two(int n) => n.toString().padLeft(2, '0');
    final local = date.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// 点赞/取消点赞(乐观更新,失败回滚)
  Future<void> _toggleLike(dynamic c) async {
    final wasLiked = c.liked as bool;
    final idx = _comments.indexOf(c);
    if (idx < 0) return;
    setState(() {
      _comments[idx] = LKComment(
        commentId: c.commentId,
        userUid: c.userUid,
        nickname: c.nickname,
        avatar: c.avatar,
        content: c.content,
        time: c.time,
        likeCount: (c.likeCount as int) + (wasLiked ? -1 : 1),
        liked: !wasLiked,
        media: c.media,
        replyCount: c.replyCount,
      );
    });
    try {
      if (_isDynamic) {
        await LKApi.toggleDynamicCommentLike(
            widget.dynamicId, c.commentId, !wasLiked);
      } else {
        await LKApi.likeBookComment(widget.bookId, c.commentId, !wasLiked,
            volumeId: widget.volumeId);
      }
    } catch (e) {
      // 失败回滚
      if (!mounted) return;
      setState(() => _comments[idx] = c);
      showLkError(context, e);
    }
  }

  Widget _likeButton(dynamic c) {
    final liked = c.liked as bool;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${c.likeCount}',
          style: TextStyle(
              fontSize: 11,
              color: liked ? Colors.redAccent : Colors.grey.shade500)),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color: liked ? Colors.redAccent : Colors.grey.shade500,
        ),
        onPressed: () => _toggleLike(c),
      ),
    ]);
  }

  /// 长按复制评论
  Future<void> _copyComment(dynamic c) async {
    // 去掉表情代码,复制纯文本
    final text = (c.content as String)
        .replaceAll(RegExp(r'\{:[^:]+:\}|\[[a-zA-Z]+:\d+\]'), '');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showLkError(context, '已复制评论');
  }

  Widget _mediaGallery(List<LKDynamicMedia> media) {
    if (media.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: media
            .map((item) => GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MediaViewerPage(url: item.url)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(item.url,
                        width: 92, height: 92, fit: BoxFit.cover),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _dynamicHeader() {
    final item = _dynamicDetail ?? widget.dynamicPreview;
    if (item == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LkLoadingIndicator(minHeight: 180),
      );
    }
    final poll = item.poll;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: item.avatar.isNotEmpty
                    ? YomiruAvatarCache.provider(item.avatar)
                    : null,
                child: item.avatar.isEmpty ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.nickname.isEmpty ? '未知用户' : item.nickname,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(item.time,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 12),
            if (item.title.isNotEmpty) ...[
              Text(item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
            ],
            if (item.summary.isNotEmpty) Text(item.summary),
            _mediaGallery(item.media),
            if (poll != null) _pollCard(poll),
            const SizedBox(height: 8),
            Text('评论 ${item.commentCount} · 赞 ${item.likeCount}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _pollCard(LKDynamicPoll poll) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(poll.title.isEmpty ? '投票' : poll.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (poll.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(poll.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            ...poll.options.map((option) {
              final selected = _selectedPollOptions.contains(option.id);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected,
                title: Text(option.text),
                subtitle: poll.voted || poll.ended
                    ? Text(
                        '${option.voteCount} 票${option.percent > 0 ? ' · ${option.percent.toStringAsFixed(1)}%' : ''}')
                    : null,
                onChanged: poll.voted || poll.ended
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            if (!poll.multiple) _selectedPollOptions.clear();
                            _selectedPollOptions.add(option.id);
                          } else {
                            _selectedPollOptions.remove(option.id);
                          }
                        });
                      },
              );
            }),
            if (!poll.voted && !poll.ended)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _pollSubmitting || _selectedPollOptions.isEmpty
                      ? null
                      : () async {
                          setState(() => _pollSubmitting = true);
                          try {
                            await LKApi.submitDynamicPollVote(widget.dynamicId,
                                _selectedPollOptions.toList());
                            await _loadDynamicDetail();
                          } catch (e) {
                            if (mounted) showLkError(context, e);
                          } finally {
                            if (mounted) {
                              setState(() => _pollSubmitting = false);
                            }
                          }
                        },
                  child: Text(_pollSubmitting ? '提交中' : '投票'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 评论采用左侧头像 + 右侧正文布局，日期统一放在昵称下方。
  Widget _commentItem(dynamic c) {
    final avatar = CircleAvatar(
      radius: 24,
      backgroundImage:
          c.avatar.isNotEmpty ? YomiruAvatarCache.provider(c.avatar) : null,
      child: c.avatar.isEmpty ? const Icon(Icons.person) : null,
    );
    final author = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.nickname,
            style: TextStyle(fontSize: 13, color: Colors.indigo.shade400)),
        if (c.time.isNotEmpty)
          Text(
            _formatCommentTime(c.time),
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
          ),
      ],
    );
    return InkWell(
      onTap: c.userUid > 0 ? () => openUserProfile(context, c.userUid) : null,
      onLongPress: () => _copyComment(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Align(alignment: Alignment.topCenter, child: avatar),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: author),
                      _likeButton(c),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _renderContent(c.content),
                  _mediaGallery(c.media),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 键盘 inset 只由输入行处理:动画期间评论列表不重建,交互更流畅
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
          title: Text(_isDynamic
              ? '动态详情'
              : _isVolume
                  ? '本卷评论 · ${widget.bookTitle}'
                  : '书评 · ${widget.bookTitle}')),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const LkLoadingIndicator()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _comments.isEmpty && !_isDynamic
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 280,
                              child: Center(
                                child: Text(
                                    _error ??
                                        (_isVolume ? '本卷还没有评论' : '还没有书评,来抢沙发'),
                                    style: const TextStyle(color: Colors.grey)),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom),
                          itemCount: _comments.length + (_isDynamic ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (_isDynamic && i == 0) return _dynamicHeader();
                            final c = _comments[i - (_isDynamic ? 1 : 0)];
                            return _commentItem(c);
                          },
                        ),
                ),
        ),
        _CommentsInputBar(
          controller: _input,
          emojiGroups: _emojiGroups,
          isVolume: _isVolume,
          hintText: _isDynamic ? '写下你的动态评论…' : null,
          onPickImage: _pickImage,
          pendingImageUrl:
              _pendingMedia.isEmpty ? null : _pendingMedia.last.url,
          onRemoveImage: _pendingMedia.isEmpty
              ? null
              : () => setState(() => _pendingMedia.removeLast()),
          onPublish: _publish,
        ),
      ]),
    );
  }
}

/// 底部评论输入区。独立于评论列表，避免键盘 inset 动画触发整页重建。
class _CommentsInputBar extends StatefulWidget {
  final TextEditingController controller;
  final List<LKEmojiGroup> emojiGroups;
  final bool isVolume;
  final String? hintText;
  final VoidCallback? onPickImage;
  final String? pendingImageUrl;
  final VoidCallback? onRemoveImage;
  final VoidCallback onPublish;

  const _CommentsInputBar({
    required this.controller,
    required this.emojiGroups,
    required this.isVolume,
    this.hintText,
    this.onPickImage,
    this.pendingImageUrl,
    this.onRemoveImage,
    required this.onPublish,
  });

  @override
  State<_CommentsInputBar> createState() => _CommentsInputBarState();
}

class _CommentsInputBarState extends State<_CommentsInputBar> {
  final _focus = FocusNode();
  bool _showEmoji = false;
  double _lastKeyboardH = 0;
  bool _keyboardReturning = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    if (widget.emojiGroups.isEmpty) {
      showLkError(context, '表情加载中,请稍后再试');
      return;
    }
    if (_showEmoji) {
      _keyboardReturning = true;
      setState(() => _showEmoji = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _showEmoji = true);
    }
  }

  void _pickEmoji(String code) {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    widget.controller.text = text.replaceRange(start, end, code);
    widget.controller.selection =
        TextSelection.collapsed(offset: start + code.length);
  }

  @override
  Widget build(BuildContext context) {
    // 系统已经在动画中逐帧更新 viewInsets，不再叠加 AnimatedPadding。
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 0 && inset > _lastKeyboardH) _lastKeyboardH = inset;
    final panelH =
        _showEmoji ? (_lastKeyboardH > 0 ? _lastKeyboardH : 300.0) : 0.0;
    final double bottomPad;
    if (_showEmoji) {
      bottomPad = panelH;
    } else if (_keyboardReturning) {
      bottomPad = _lastKeyboardH;
      if (inset >= _lastKeyboardH - 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _keyboardReturning = false;
        });
      }
    } else {
      bottomPad = inset;
    }

    return Stack(children: [
      if (_showEmoji)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: panelH,
          child: Material(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E2025)
                : Colors.white,
            child: SafeArea(
              top: false,
              child: _EmojiPanel(
                groups: widget.emojiGroups,
                onPick: _pickEmoji,
              ),
            ),
          ),
        ),
      Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              if (widget.pendingImageUrl != null &&
                  widget.pendingImageUrl!.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(widget.pendingImageUrl!,
                              width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: -8,
                          top: -8,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.cancel, size: 18),
                            onPressed: widget.onRemoveImage,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(children: [
                IconButton(
                  tooltip: _showEmoji ? '键盘' : '表情',
                  icon: Icon(_showEmoji
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined),
                  onPressed: _toggleEmoji,
                ),
                if (widget.onPickImage != null)
                  IconButton(
                    tooltip: '添加图片',
                    icon: const Icon(Icons.image_outlined),
                    onPressed: widget.onPickImage,
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    onTap: () {
                      if (_showEmoji) {
                        _keyboardReturning = true;
                        setState(() => _showEmoji = false);
                      }
                    },
                    decoration: InputDecoration(
                        hintText: widget.hintText ??
                            (widget.isVolume ? '写下本卷评论…' : '写下你的书评…'),
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: widget.onPublish, child: const Text('发布')),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// 评论表情选择面板(分组页签 + 网格)
class _EmojiPanel extends StatefulWidget {
  final List<LKEmojiGroup> groups;
  final void Function(String code) onPick;
  const _EmojiPanel({required this.groups, required this.onPick});

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final g = widget.groups[_tab];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: widget.groups.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final sel = i == _tab;
            return GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel
                      ? Theme.of(context).colorScheme.primary
                      : (isDark
                          ? const Color(0xFF2A2C33)
                          : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  widget.groups[i].name,
                  style: TextStyle(
                    fontSize: 13,
                    color: sel ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: g.items.length,
          itemBuilder: (_, i) {
            final it = g.items[i];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => widget.onPick(it.code),
              child: it.isImage
                  ? Image.network(
                      it.url.replaceFirst('api.lightnovel.fun/static/',
                          'static.lightnovel.fun/'),
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          size: 20,
                          color: Colors.grey),
                    )
                  : Center(
                      child:
                          Text(it.code, style: const TextStyle(fontSize: 22))),
            );
          },
        ),
      ),
    ]);
  }
}
