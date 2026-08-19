import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../widgets/common.dart';
import 'reader_page.dart';
import 'search_page.dart';

Widget _braveAccessBadge(BuildContext context) {
  final color = Theme.of(context).colorScheme.primary;
  return Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text('勇者可读',
        style: TextStyle(
            color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
  );
}

/// 书籍详情(LightNovelReader 风格):
/// - 大封面头部 + 状态
/// - 可点击标签(跳转标签搜索)
/// - 滚动感知的"继续阅读/开始阅读" FAB
/// - 卷目录(云进度标记"读到")
class BookDetailPage extends StatefulWidget {
  final int bookId;
  const BookDetailPage({super.key, required this.bookId});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  dynamic _book;
  List<dynamic> _volumes = [];
  bool _inShelf = false;
  int _latestChapterId = 0;
  String _latestChapterTitle = '';
  bool _hasHistory = false;
  String? _error;
  final _scroll = ScrollController();
  bool _fabVisible = true;
  double _lastOffset = 0;

  /// 目录中当前就地展开的卷;展开后章节列表直接显示在卷卡片下方
  int? _expandedVolumeId;
  final Map<int, List<dynamic>> _volumeChapters = {};
  final Map<int, String> _volumeErrors = {};

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      final o = _scroll.offset;
      final down = o > _lastOffset + 2;
      _lastOffset = o;
      final v = o < 80 || !down;
      if (v != _fabVisible && mounted) setState(() => _fabVisible = v);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final book = await LKApi.bookDetail(widget.bookId);
      final vols = await LKApi.volumes(widget.bookId, 1);
      if (!mounted) return;
      setState(() {
        _book = book;
        _volumes = vols;
        _error = null;
      });
      if (LKClient.shared.session.isLoggedIn) {
        try {
          final st = await LKApi.client.post(
              '/api/new-content-read/get-book-library-state',
              LKApi.client.authed({'book_id': widget.bookId}));
          if (!mounted) return;
          setState(() {
            _inShelf = (st['in_shelf'] as num?)?.toInt() == 1;
            _hasHistory = (st['has_history'] as num?)?.toInt() == 1;
            _latestChapterId = (st['latest_chapter_id'] as num?)?.toInt() ?? 0;
            _latestChapterTitle =
                (st['latest_chapter_title'] as String?) ?? '';
          });
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggleShelf() async {
    try {
      await LKApi.toggleShelf(widget.bookId, !_inShelf);
      if (mounted) setState(() => _inShelf = !_inShelf);
    } catch (e) {
      if (mounted) showLkError(context, e);
    }
  }

  void _openReading() {
    final b = _book;
    if (b == null) return;
    if (_hasHistory && _latestChapterId > 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReaderPage(
                  bookId: b.bookId,
                  bookTitle: b.title,
                  chapterId: _latestChapterId,
                  chapterTitle: _latestChapterTitle,
                  volumeId: b.defaultVolumeId,
                )),
      );
      return;
    }
    if (b.defaultChapterId > 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReaderPage(
                  bookId: b.bookId,
                  bookTitle: b.title,
                  chapterId: b.defaultChapterId,
                  chapterTitle: '',
                  volumeId: b.defaultVolumeId,
                )),
      );
      return;
    }
    if (b.defaultVolumeId > 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChaptersPage(
                  bookId: b.bookId,
                  volumeId: b.defaultVolumeId,
                  volumeTitle: b.title,
                  bookTitle: b.title,
                )),
      );
    }
  }

  String get _fabLabel {
    if (_hasHistory && _latestChapterId > 0) {
      return _latestChapterTitle.isEmpty
          ? '继续阅读'
          : '继续阅读 · $_latestChapterTitle';
    }
    return '开始阅读';
  }

  @override
  Widget build(BuildContext context) {
    final b = _book;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: _error != null && b == null
          ? Center(
              child:
                  Text(_error!, style: const TextStyle(color: Colors.grey)))
          : b == null
              ? const LkLoadingIndicator()
              : CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      elevation: 0,
                      scrolledUnderElevation: 0.5,
                      backgroundColor:
                          isDark ? const Color(0xFF1B1C21) : Colors.white,
                      foregroundColor:
                          isDark ? Colors.white : const Color(0xFF263238),
                      expandedHeight: 8,
                      title: Text(b.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CoverImage(
                                    url: b.coverUrl,
                                    width: 112,
                                    height: 152,
                                    radius: 10),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(b.title,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              height: 1.3)),
                                      const SizedBox(height: 8),
                                      Text('作者: ${b.authorName}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600)),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        _miniBadge(scheme,
                                            b.isCompleted ? '完结' : '连载'),
                                        const SizedBox(width: 6),
                                        Text(
                                            '${b.volumeCount}卷 · ${b.chapterCount}章',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500)),
                                      ]),
                                      const SizedBox(height: 4),
                                      Text(
                                        b.wordCount >= 10000
                                            ? '${(b.wordCount / 10000).toStringAsFixed(1)} 万字'
                                            : '${b.wordCount} 字',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (b.tags.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 32,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: b.tags.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (_, i) => GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => SearchPage(
                                              initialTag: b.tags[i])),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 5),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scheme.primary
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(b.tags[i],
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.primary)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: LKClient
                                          .shared.session.isLoggedIn
                                      ? _toggleShelf
                                      : null,
                                  icon: Icon(
                                      _inShelf
                                          ? Icons.bookmark_added_rounded
                                          : Icons.bookmark_add_outlined,
                                      size: 18),
                                  label:
                                      Text(_inShelf ? '已加书架' : '加入书架'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CommentsPage(
                                            bookId: b.bookId,
                                            bookTitle: b.title)),
                                  ),
                                  icon: const Icon(
                                      Icons.chat_bubble_outline,
                                      size: 18),
                                  label: const Text('书评'),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 18),
                            const Text('简介',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(b.summary,
                                style: TextStyle(
                                    height: 1.6,
                                    fontSize: 13.5,
                                    color: Colors.grey.shade700)),
                            const SizedBox(height: 18),
                            Row(children: [
                              const Text('目录',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Text('${b.volumeCount} 卷',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500)),
                            ]),
                            const SizedBox(height: 8),
                            ..._volumes.map((v) => _volumeCard(v)),
                            SizedBox(
                                height: 90 +
                                    MediaQuery.of(context).padding.bottom),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _fabVisible ? 1 : 0,
          child: FloatingActionButton.extended(
            onPressed: _fabVisible ? _openReading : null,
            icon: const Icon(Icons.menu_book_rounded),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(_fabLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniBadge(ColorScheme scheme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: scheme.primary.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: scheme.primary,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _volumeCard(dynamic v) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expanded = _expandedVolumeId == v.volumeId;
    final chs = _volumeChapters[v.volumeId];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? const Color(0xFF1E2025) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => _toggleVolume(v),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Text(v.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      color: Colors.grey.shade400),
                ]),
              ),
            ),
            if (expanded) ..._chapterRows(v, chs),
          ],
        ),
      ),
    );
  }

  /// 点击卷:就地展开/收起章节列表(首次展开时加载)
  Future<void> _toggleVolume(dynamic v) async {
    final id = v.volumeId as int;
    if (_expandedVolumeId == id) {
      setState(() => _expandedVolumeId = null);
      return;
    }
    setState(() {
      _expandedVolumeId = id;
      _volumeErrors.remove(id);
    });
    if (_volumeChapters.containsKey(id)) return;
    try {
      final chs = await LKApi.chapters(_book.bookId, id, 1);
      if (!mounted) return;
      setState(() => _volumeChapters[id] = chs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _volumeErrors[id] = e.toString());
    }
  }

  List<Widget> _chapterRows(dynamic v, List<dynamic>? chs) {
    if (chs == null) {
      if (_volumeErrors[v.volumeId] != null) {
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
            child: Text('章节加载失败,请收起后重试',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
        ];
      }
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(14, 2, 14, 14),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    return chs
        .map((c) => InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ReaderPage(
                          bookId: _book.bookId,
                          bookTitle: _book.title,
                          chapterId: c.chapterId,
                          chapterTitle: c.title,
                          volumeId: v.volumeId,
                        )),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  if (c.braveOnly) _braveAccessBadge(context),
                  Expanded(
                    child: Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    c.wordCount >= 10000
                        ? '${(c.wordCount / 10000).toStringAsFixed(1)}万字'
                        : '${c.wordCount}字',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (c.locked && !c.unlocked)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child:
                          Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                    ),
                ]),
              ),
            ))
        .toList();
  }
}

/// 卷内章节列表
class ChaptersPage extends StatefulWidget {
  final int bookId;
  final int volumeId;
  final String volumeTitle;
  final String bookTitle;
  const ChaptersPage(
      {super.key,
      required this.bookId,
      required this.volumeId,
      required this.volumeTitle,
      required this.bookTitle});

  @override
  State<ChaptersPage> createState() => _ChaptersPageState();
}

class _ChaptersPageState extends State<ChaptersPage> {
  List<dynamic> _chapters = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chs = await LKApi.chapters(widget.bookId, widget.volumeId, 1);
      if (!mounted) return;
      setState(() => _chapters = chs);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.volumeTitle.isEmpty ? '章节列表' : widget.volumeTitle)),
      body: _error != null && _chapters.isEmpty
          ? Center(
              child:
                  Text(_error!, style: const TextStyle(color: Colors.grey)))
          : ListView.separated(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom),
              itemCount: _chapters.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = _chapters[i];
                return ListTile(
                  // 网站标题本身已含"第X章",不再重复拼接
                  title: Row(children: [
                    if (c.braveOnly) _braveAccessBadge(context),
                    Expanded(
                      child: Text(c.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  subtitle: Text(c.wordCount >= 10000
                      ? '${(c.wordCount / 10000).toStringAsFixed(1)}万字'
                      : '${c.wordCount}字'),
                  trailing: c.locked && !c.unlocked
                      ? const Icon(Icons.lock_outline, size: 18)
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ReaderPage(
                              bookId: widget.bookId,
                              bookTitle: widget.bookTitle,
                              chapterId: c.chapterId,
                              chapterTitle: c.title,
                              volumeId: widget.volumeId,
                            )),
                  ),
                );
              },
            ),
    );
  }
}
