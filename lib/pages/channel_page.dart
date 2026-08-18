import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/store.dart';
import '../widgets/common.dart';
import 'book_detail_page.dart';

/// 分区频道页(轻小说/原创/同人/EPUB/更新)
class ChannelPage extends StatefulWidget {
  final String path;
  final String label;
  const ChannelPage({super.key, required this.path, required this.label});

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  final List<dynamic> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  bool _listMode = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load(1, false);
  }

  Future<void> _loadPrefs() async {
    final v = await ReaderPrefs.feedListMode();
    if (mounted) setState(() => _listMode = v);
  }

  void _toggleListMode() {
    setState(() => _listMode = !_listMode);
    ReaderPrefs.setFeedListMode(_listMode);
  }

  Future<void> _load(int page, bool append) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final items = widget.path == '/api/bff/home-feed-v1'
          ? await LKApi.homeFeed('hot', page)
          : await LKApi.channelFeed(widget.path, page);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: [
          IconButton(
            tooltip: _listMode ? '切换网格排版' : '切换单列排版',
            icon: Icon(
                _listMode ? Icons.grid_view_rounded : Icons.view_agenda_outlined),
            onPressed: _toggleListMode,
          ),
        ],
      ),
      body: _error != null && _items.isEmpty
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
          : _listMode
              ? ListView.builder(
                  padding: EdgeInsets.fromLTRB(8, 8, 8,
                      12 + MediaQuery.of(context).padding.bottom),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _load(_page + 1, true));
                      return const Center(child: CircularProgressIndicator());
                    }
                    final book = _items[i];
                    return BookCard(
                      book: book,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                BookDetailPage(bookId: book.bookId)),
                      ),
                    );
                  },
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(12, 8, 12,
                      12 + MediaQuery.of(context).padding.bottom),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.56,
                  ),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _load(_page + 1, true));
                      return const Center(child: CircularProgressIndicator());
                    }
                    final book = _items[i];
                    return BookGridCard(
                      book: book,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                BookDetailPage(bookId: book.bookId)),
                      ),
                    );
                  },
                ),
    );
  }
}

/// 排行榜页
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  List<dynamic> _items = [];
  String? _error;
  bool _listMode = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load();
  }

  Future<void> _loadPrefs() async {
    final v = await ReaderPrefs.feedListMode();
    if (mounted) setState(() => _listMode = v);
  }

  void _toggleListMode() {
    setState(() => _listMode = !_listMode);
    ReaderPrefs.setFeedListMode(_listMode);
  }

  Future<void> _load() async {
    try {
      final items = await LKApi.rank(1, pageSize: 50);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        actions: [
          IconButton(
            tooltip: _listMode ? '切换网格排版' : '切换单列排版',
            icon: Icon(
                _listMode ? Icons.grid_view_rounded : Icons.view_agenda_outlined),
            onPressed: _toggleListMode,
          ),
        ],
      ),
      body: _error != null && _items.isEmpty
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
          : RefreshIndicator(
              onRefresh: _load,
              child: _listMode
                  ? ListView.builder(
                      padding: EdgeInsets.fromLTRB(8, 8, 8,
                          12 + MediaQuery.of(context).padding.bottom),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final book = _items[i];
                        return BookCard(
                          book: book,
                          rank: i + 1,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    BookDetailPage(bookId: book.bookId)),
                          ),
                        );
                      },
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(12, 8, 12,
                          12 + MediaQuery.of(context).padding.bottom),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.56,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final book = _items[i];
                        return BookGridCard(
                          book: book,
                          rank: i + 1,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    BookDetailPage(bookId: book.bookId)),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
