import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_open_chinese_convert/flutter_open_chinese_convert.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../api/reader_cache.dart';
import '../api/store.dart';
import '../widgets/common.dart';
import 'login_page.dart';
import 'search_page.dart';

/// 正文块:文本(可含链接区间)或插画
class _BodyBlock {
  final String? image;
  final double? aspect; // 插画宽高比(width/height),用于翻页模式精确命中区域
  final String text;

  /// 链接区间 (start, end, url),相对于 [text] 的下标
  final List<(int, int, String)> links;
  _BodyBlock.text(this.text, [this.links = const []])
      : image = null,
        aspect = null;
  _BodyBlock.image(this.image, {this.aspect})
      : text = '',
        links = const [];
}

/// 翻页模式:一页内的条目(切分后的文本/插画)
class _PageItem {
  final String? image;
  final double? aspect;
  final String text;
  final List<(int, int, String)> links;
  _PageItem.text(this.text, this.links)
      : image = null,
        aspect = null;
  _PageItem.image(this.image, {this.aspect})
      : text = '',
        links = const [];
}

/// 翻页模式:一页
class _Page {
  final List<_PageItem> items;
  final bool chapterEnd; // 章末导航页
  final bool unlockCard; // 付费解锁卡片页
  _Page(this.items, {this.chapterEnd = false, this.unlockCard = false});
}

/// 阅读器(LightNovelReader + Apple Books 风格):
/// - 全屏沉浸,点击唤出,滑动隐藏,小齿轮设置
/// - 设置面板三页签:外观/操作/边距
/// - 点击翻页 / 音量键翻页 / 保持常亮 / 隐藏状态栏 / 指示器
class ReaderPage extends StatefulWidget {
  final int bookId;
  final String bookTitle;
  final int chapterId;
  final String chapterTitle;
  final int volumeId;
  const ReaderPage(
      {super.key,
      required this.bookId,
      required this.bookTitle,
      required this.chapterId,
      required this.chapterTitle,
      required this.volumeId});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  String _title = '';
  List<_BodyBlock> _blocks = [_BodyBlock.text('加载中…')];
  int? _prevId;
  String? _prevTitle;
  int? _prevVolumeId;
  int? _nextId;
  String? _nextTitle;
  int? _nextVolumeId;
  bool _locked = false;
  bool _unlocked = false;
  bool _loading = true;
  String? _loadError;
  bool _chrome = true;

  /// 章节真实所在卷(详情接口返回,入口传的 volumeId 可能是默认卷,不可靠)
  int _effectiveVolumeId = 0;
  bool _unlocking = false;
  int _coinPrice = 0;
  int _coins = -1; // -1 表示余额未知
  bool _paged = false;
  final PageController _pageController = PageController();
  List<_Page> _pages = [_Page(const [], chapterEnd: true)];
  int _pageIndex = 0;
  bool _chapterSwitching = false;

  /// 翻页模式分页缓存键(内容/尺寸变化时重建分页)
  String _pagedKey = '';

  /// 已参与分页的正文块(内容变化检测)
  List<_BodyBlock> _pagesSource = const [];

  // 偏好
  double _fontSize = 17;
  double _lineHeight = 1.7;
  int _bg = 0;
  bool _bgChosen = false;

  /// 外观:跟随系统深浅色
  bool _bgFollowSystem = true;
  bool _keepOn = false;
  bool _hideBar = false;
  bool _tapTurn = false;
  bool _autoMargin = true;
  double _mt = 56, _mb = 70, _ml = 20, _mr = 20;
  bool _indicators = true;
  bool _traditional = false;
  bool _simplified = false;

  /// 缓存的章节详情(切换简繁时本地重解析,不重新请求)
  LKChapterDetail? _detail;

  final _sc = ScrollController();
  final _shareButtonKey = GlobalKey();
  double _progress = 0;
  double _lastScrollOffset = 0;

  /// 滚动进度通知(正文指示器实时刷新,无需整页重建)
  final ValueNotifier<double> _progressN = ValueNotifier<double>(0);

  static const _presets = [
    (Color(0xFFFFFFFF), Color(0xFF333333), '白'),
    (Color(0xFFF7F1E3), Color(0xFF3D362A), '米黄'),
    (Color(0xFF2A2D34), Color(0xFFC9CDD6), '深灰'),
    (Color(0xFF000000), Color(0xFF9AA0A6), '纯黑'),
  ];

  bool get _sysDark => Theme.of(context).brightness == Brightness.dark;
  int get _bgEff => _bgFollowSystem ? (_sysDark ? 2 : 0) : _bg;
  Color get _bgColor => _presets[_bgEff].$1;
  Color get _textColor => _presets[_bgEff].$2;
  bool get _isDarkBg => _bgEff >= 2;

  @override
  void initState() {
    super.initState();
    _title = widget.chapterTitle;
    _effectiveVolumeId = widget.volumeId;
    _sc.addListener(_onScroll);
    _load();
    _loadPrefs();
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    final offset = _sc.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;
    // ListView.builder 的总高度会随着懒加载变化。总高度变化但滚动位置未变
    // 时不刷新，避免百分比被 maxScrollExtent 的中间值反复拉回。
    if (delta.abs() < 0.5) return;
    final max = _sc.position.maxScrollExtent;
    final raw = max <= 0 ? 1.0 : (offset / max).clamp(0.0, 1.0);
    // 同一方向滚动时只接受该方向的变化，过滤懒加载造成的反向抖动；
    // 用户真正反向拖动时，delta 会切换方向，进度仍可正常回退。
    final next = delta > 0
        ? (raw > _progress ? raw : _progress)
        : (raw < _progress ? raw : _progress);
    if ((next - _progress).abs() < 0.001) return;
    _progress = next;
    _progressN.value = next;
  }

  @override
  void dispose() {
    _savePos();
    _sc.dispose();
    _pageController.dispose();
    _progressN.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// 保存本章阅读位置(滚动模式按滚动进度,翻页模式按页码进度)
  void _savePos() {
    final frac = _paged
        ? (_pages.length <= 1 ? 0.0 : _pageIndex / (_pages.length - 1))
        : _progress;
    if (frac > 0.005) {
      ReaderPrefs.setReadPosFrac(widget.chapterId, frac);
    }
  }

  Future<void> _loadPrefs() async {
    final bg = await ReaderPrefs.bgPreset();
    final bgSys = await ReaderPrefs.bgFollowSystem();
    final fontSize = await ReaderPrefs.fontSize();
    final lineHeight = await ReaderPrefs.lineHeight();
    final keepOn = await ReaderPrefs.keepScreenOn();
    final hideBar = await ReaderPrefs.hideStatusBar();
    final tapTurn = await ReaderPrefs.tapTurnPage();
    final autoMargin = await ReaderPrefs.autoMargin();
    final mt = await ReaderPrefs.marginTop();
    final mb = await ReaderPrefs.marginBottom();
    final ml = await ReaderPrefs.marginLeft();
    final mr = await ReaderPrefs.marginRight();
    final ind = await ReaderPrefs.showIndicators();
    final trad = await ReaderPrefs.traditional();
    final simp = await ReaderPrefs.simplified();
    final paged = await ReaderPrefs.pagedMode();
    final tradChanged = _traditional != trad || _simplified != simp;
    if (!mounted) return;
    setState(() {
      _fontSize = fontSize;
      _lineHeight = lineHeight;
      if (bg >= 0) {
        _bg = bg;
        _bgChosen = true;
        // 选过具体预设的老用户保持固定;新用户默认跟随系统
        _bgFollowSystem = bgSys;
      }
      _keepOn = keepOn;
      _hideBar = hideBar;
      _tapTurn = tapTurn;
      _autoMargin = autoMargin;
      _mt = mt;
      _mb = mb;
      _ml = ml;
      _mr = mr;
      _indicators = ind;
      _traditional = trad;
      _simplified = simp;
      _paged = paged;
    });
    // 偏好到达后,若章节已加载且简繁状态有变化,则本地重解析
    if (tradChanged && _detail != null) {
      _blocks = await _parseBlocks(_detail);
      if (mounted) setState(() {});
    }
    WakelockPlus.toggle(enable: _keepOn);
    _applyImmersive();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bgChosen) {
      _bg = Theme.of(context).brightness == Brightness.dark ? 2 : 0;
    }
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(
        _hideBar ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  // ==================== 加载与解析 ====================

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    // 上次阅读位置(重新打开本章时自动跳转)
    final savedFrac = await ReaderPrefs.readPosFrac(widget.chapterId);
    final restore = (savedFrac > 0.02 && savedFrac < 0.98) ? savedFrac : 0.0;

    // 先展示本机已经读过的正文,避免每次打开都等待网络。
    final cached =
        await ReaderContentCache.read(widget.bookId, widget.chapterId);
    if (!mounted) return;
    if (cached != null) {
      await _renderDetail(cached, restore: restore, restorePosition: true);
      if (!mounted) return;
      setState(() => _loading = false);
      _resolveAdjacentOrPrefetch();
      // 缓存只负责快速展示,仍在后台向服务端刷新,防止正文过期。
      unawaited(_refreshFromNetwork(restore));
      return;
    }

    // 没有缓存时保持原来的在线加载流程。
    await _refreshFromNetwork(restore, initialLoad: true);
  }

  Future<void> _refreshFromNetwork(double restore,
      {bool initialLoad = false}) async {
    try {
      final d = await LKApi.chapterDetail(widget.bookId, widget.chapterId);
      if (!mounted) return;
      final old = _detail;
      if (old == null || !old.hasSameContent(d)) {
        // 首次在线加载恢复上次进度;缓存刷新时不打断用户当前阅读位置。
        await _renderDetail(d,
            restore: restore, restorePosition: initialLoad && old == null);
      } else {
        // 正文没有变化时只刷新锁定状态、标题和前后章信息,避免重排版。
        _updateDetailState(d);
      }
      if (!mounted) return;
      setState(() => _loading = false);

      // 只缓存公开正文或当前账号已解锁的付费正文。
      await ReaderContentCache.write(widget.bookId, d);
      if (d.locked && !d.unlocked) _refreshCoins();
      if (LKClient.shared.session.isLoggedIn && !d.locked) {
        try {
          await LKApi.saveHistory(
              widget.bookId,
              _effectiveVolumeId,
              widget.chapterId,
              (initialLoad ? restore : _progress * 100).round().clamp(0, 100));
        } catch (_) {}
      }
      _resolveAdjacentOrPrefetch();
    } catch (e) {
      // 有缓存时网络失败不覆盖正文;只有首次加载失败才显示错误。
      if (initialLoad && mounted) {
        final accessError = e is LKException && e.accessRestricted;
        setState(() {
          if (accessError) {
            _loadError = e.message;
            _blocks = const [];
          } else {
            _blocks = [_BodyBlock.text('加载失败: $e')];
          }
          _loading = false;
        });
      }
    }
  }

  Future<void> _renderDetail(LKChapterDetail d,
      {required double restore, required bool restorePosition}) async {
    final blocks = await _parseBlocks(d);
    if (!mounted) return;
    _updateDetailState(d, blocks: blocks);
    if (restorePosition) {
      _lastScrollOffset = 0;
      _progress = restore;
      _progressN.value = restore;
      // ListView 懒加载下 maxScrollExtent 随构建逐渐增大,
      // 分多次跳转直到接近目标,保证恢复位置准确。
      if (!_paged && restore > 0) _scheduleRestoreJumps(restore);
    }
  }

  void _updateDetailState(LKChapterDetail d, {List<_BodyBlock>? blocks}) {
    _detail = d;
    if (!mounted) return;
    setState(() {
      _title = d.title.isEmpty ? _title : d.title;
      if (blocks != null) _blocks = blocks;
      _locked = d.locked;
      _unlocked = d.unlocked;
      _coinPrice = d.coinPrice;
      _effectiveVolumeId = d.volumeId > 0 ? d.volumeId : widget.volumeId;
      _prevId = d.prevChapterId;
      _prevTitle = d.prevTitle;
      _prevVolumeId = d.prevVolumeId;
      _nextId = d.nextChapterId;
      _nextTitle = d.nextTitle;
      _nextVolumeId = d.nextVolumeId;
    });
  }

  void _resolveAdjacentOrPrefetch() {
    if (_prevId == null || _nextId == null) {
      unawaited(_resolveAdjacent());
    } else {
      unawaited(_prefetchNextChapter());
    }
  }

  /// 后台预取下一章,只在下一章未缓存时发起一次请求。
  Future<void> _prefetchNextChapter() async {
    final nextId = _nextId;
    if (nextId == null || nextId == widget.chapterId) return;
    if (await ReaderContentCache.contains(widget.bookId, nextId)) return;
    try {
      final d = await LKApi.chapterDetail(widget.bookId, nextId);
      await ReaderContentCache.write(widget.bookId, d);
    } catch (_) {
      // 预取失败不影响当前章节阅读。
    }
  }

  /// 分多次跳转到目标阅读位置(滚动模式)
  void _scheduleRestoreJumps(double restore) {
    for (final delay in const [0, 150, 400, 900, 1500]) {
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted && _sc.hasClients) {
          final target = _sc.position.maxScrollExtent * restore;
          if (target > 0) _sc.jumpTo(target);
        }
      });
    }
  }

  /// 拉取轻币余额(失败静默,余额显示保持未知)
  Future<void> _refreshCoins() async {
    try {
      final c = await LKApi.myCoins();
      if (mounted && _locked && !_unlocked) setState(() => _coins = c);
    } catch (_) {}
  }

  /// 拉取某卷的全部章节(翻页直到页尾)
  Future<List<dynamic>> _chaptersAll(int volumeId) async {
    final all = <dynamic>[];
    for (var p = 1; p <= 10; p++) {
      final page = await LKApi.chapters(widget.bookId, volumeId, p);
      if (page.isEmpty) break;
      all.addAll(page);
      if (page.length < 50) break;
    }
    return all;
  }

  /// 拉取全书全部卷
  Future<List<dynamic>> _allVolumes() async {
    final all = <dynamic>[];
    for (var p = 1; p <= 10; p++) {
      final page = await LKApi.volumes(widget.bookId, p);
      if (page.isEmpty) break;
      all.addAll(page);
      if (page.length < 50) break;
    }
    return all;
  }

  /// 客户端计算前后章:先卷内,再跨卷(上一卷最后一章 / 下一卷第一章)
  /// 服务端 navigation 经常缺失,登录态尤其如此,必须自己兜底
  Future<void> _resolveAdjacent() async {
    try {
      final chs = await _chaptersAll(_effectiveVolumeId);
      if (!mounted) return;
      final idx = chs.indexWhere((c) => c.chapterId == widget.chapterId);
      if (idx < 0) {
        // 传入的卷不对时,扫全书找到章节真实所在卷
        await _findRealVolume();
      } else {
        if (_prevId == null && idx > 0) {
          _prevId = chs[idx - 1].chapterId;
          _prevTitle = chs[idx - 1].title;
          _prevVolumeId = _effectiveVolumeId;
        }
        if (_nextId == null && idx < chs.length - 1) {
          _nextId = chs[idx + 1].chapterId;
          _nextTitle = chs[idx + 1].title;
          _nextVolumeId = _effectiveVolumeId;
        }
        if (_prevId == null || _nextId == null) {
          await _crossVolumeAdjacent();
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// 章节不在当前卷时:扫描全部卷,定位真实卷并修正,再算前后章
  Future<void> _findRealVolume() async {
    final vols = await _allVolumes();
    for (final v in vols) {
      if (!mounted) return;
      if (v.volumeId == _effectiveVolumeId) continue;
      final chs = await _chaptersAll(v.volumeId);
      if (!mounted) return;
      final idx = chs.indexWhere((c) => c.chapterId == widget.chapterId);
      if (idx >= 0) {
        _effectiveVolumeId = v.volumeId;
        if (_prevId == null && idx > 0) {
          _prevId = chs[idx - 1].chapterId;
          _prevTitle = chs[idx - 1].title;
          _prevVolumeId = v.volumeId;
        }
        if (_nextId == null && idx < chs.length - 1) {
          _nextId = chs[idx + 1].chapterId;
          _nextTitle = chs[idx + 1].title;
          _nextVolumeId = v.volumeId;
        }
        if (_prevId == null || _nextId == null) {
          await _crossVolumeAdjacent();
        }
        return;
      }
    }
  }

  /// 跨卷兜底:本卷没有上一章时取上一卷最后一章;没有下一章时取下一卷第一章
  Future<void> _crossVolumeAdjacent() async {
    final vols = await _allVolumes();
    if (!mounted) return;
    final vi = vols.indexWhere((v) => v.volumeId == _effectiveVolumeId);
    if (vi < 0) return;
    if (_prevId == null && vi > 0) {
      final prevChs = await _chaptersAll(vols[vi - 1].volumeId);
      if (!mounted) return;
      if (prevChs.isNotEmpty) {
        _prevId = prevChs.last.chapterId;
        _prevTitle = prevChs.last.title;
        _prevVolumeId = vols[vi - 1].volumeId;
      }
    }
    if (_nextId == null && vi < vols.length - 1) {
      final nextChs = await _chaptersAll(vols[vi + 1].volumeId);
      if (!mounted) return;
      if (nextChs.isNotEmpty) {
        _nextId = nextChs.first.chapterId;
        _nextTitle = nextChs.first.title;
        _nextVolumeId = vols[vi + 1].volumeId;
      }
    }
  }

  Future<List<_BodyBlock>> _parseBlocks(dynamic d) async {
    var html = d.bodyHtml as String?;
    if (html != null && html.isNotEmpty) {
      // 简繁转换(整章一次转换;OpenCC 不影响 HTML 标签/实体)
      if (_traditional) {
        html = await ChineseConverter.convert(html, S2T());
      } else if (_simplified) {
        html = await ChineseConverter.convert(html, T2S());
      }
      final blocks = <_BodyBlock>[];
      final imgRe = RegExp(r'<img[^>]*src="([^"]+)"[^>]*>');
      var pos = 0;
      for (final m in imgRe.allMatches(html)) {
        _addTextBlocks(blocks, html.substring(pos, m.start));
        final tag = m.group(0)!;
        final w =
            RegExp(r'(?:img-width|width)="(\d+)"').firstMatch(tag)?.group(1);
        final h =
            RegExp(r'(?:img-height|height)="(\d+)"').firstMatch(tag)?.group(1);
        final wi = int.tryParse(w ?? '') ?? 0;
        final hi = int.tryParse(h ?? '') ?? 0;
        final imageUrl = m.group(1)!.trim();
        final imageUri = Uri.tryParse(imageUrl);
        if (imageUri != null &&
            imageUri.scheme == 'https' &&
            imageUri.host.isNotEmpty) {
          blocks.add(_BodyBlock.image(imageUrl,
              aspect: (wi > 0 && hi > 0) ? wi / hi : null));
        }
        pos = m.end;
      }
      _addTextBlocks(blocks, html.substring(pos));
      if (blocks.isNotEmpty) return blocks;
    }
    var text = (d.bodyText ?? '') as String;
    if (_traditional) {
      text = await ChineseConverter.convert(text, S2T());
    } else if (_simplified) {
      text = await ChineseConverter.convert(text, T2S());
    }
    final blocks = <_BodyBlock>[];
    _addTextBlocks(blocks, text);
    return blocks.isEmpty ? [_BodyBlock.text('(本章暂无内容)')] : blocks;
  }

  static final RegExp _aTagRe = RegExp(
      r'<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true);
  static final RegExp _urlRe = RegExp(r"(?:https?://|www\.)[^\s<>"
      "'（）()\[\]「」『』]+"); // ignore: unnecessary_string_escapes

  void _addTextBlocks(List<_BodyBlock> blocks, String seg) {
    var t = seg
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        // 正文里的资源占位符(如 [res]0,369356[/res])不展示
        .replaceAll(RegExp(r'\[res\][^[]+\[/res\]'), '')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</p>'), '\n');
    final paras =
        t.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    for (final p in paras) {
      final blk = _paraBlock(p);
      // 纯标签段落(<p> 等)去掉标签后为空,跳过,否则翻页模式会出现空白页
      if (blk.text.isNotEmpty) blocks.add(blk);
    }
  }

  /// 把一段(可能含 <a> 与裸 URL 的)文本解析成带链接区间的正文块
  _BodyBlock _paraBlock(String raw) {
    final buf = StringBuffer();
    final links = <(int, int, String)>[];
    var pos = 0;
    for (final m in _aTagRe.allMatches(raw)) {
      _appendScanningUrls(buf, links, raw.substring(pos, m.start));
      final label = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      final url = (m.group(1) ?? '').trim();
      if (label.isNotEmpty && url.isNotEmpty) {
        links.add((buf.length, buf.length + label.length, url));
        buf.write(label);
      }
      pos = m.end;
    }
    _appendScanningUrls(buf, links, raw.substring(pos));
    return _BodyBlock.text(buf.toString(), links);
  }

  /// 去标签后,扫描裸 URL(www./http/https),附加为链接区间
  void _appendScanningUrls(
      StringBuffer buf, List<(int, int, String)> links, String seg) {
    final clean = seg.replaceAll(RegExp(r'<[^>]+>'), '');
    var pos = 0;
    for (final m in _urlRe.allMatches(clean)) {
      if (m.start > pos) buf.write(clean.substring(pos, m.start));
      var u = m.group(0)!;
      // 去掉结尾误吞的中文标点
      u = u.replaceFirst(RegExp(r'[。，！？；、,;:!?)）】』」]+$'), '');
      links.add((buf.length, buf.length + u.length, u));
      buf.write(u);
      pos = m.end;
    }
    if (pos < clean.length) buf.write(clean.substring(pos));
  }

  void _open(int chapterId, String title, {int? volumeId}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => ReaderPage(
                bookId: widget.bookId,
                bookTitle: widget.bookTitle,
                chapterId: chapterId,
                chapterTitle: title,
                volumeId: volumeId ?? _effectiveVolumeId,
              )),
    );
  }

  /// 付费解锁:试读内容下方的解锁卡片直接调用,不再弹窗确认
  Future<void> _unlock() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    try {
      await LKApi.unlockChapter(widget.chapterId);
      if (!mounted) return;
      showLkError(context, '解锁成功');
      await _load();
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Color get _linkColor =>
      _isDarkBg ? const Color(0xFF7EB6FF) : const Color(0xFF2F6FBF);

  /// 正文内链接:系统浏览器打开
  Future<void> _openLink(String url) async {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    try {
      final uri = Uri.tryParse(u);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        if (mounted) showLkError(context, '链接协议不受支持');
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showLkError(context, '无法打开链接');
    } catch (e) {
      if (mounted) showLkError(context, '无法打开链接: $e');
    }
  }

  /// 全屏查看插画(可缩放、可保存到相册)
  void _showImageViewer(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ImageViewer(url: url)),
    );
  }

  // ==================== 翻页 ====================

  void _pageUp() {
    if (_paged) {
      _turnPrev();
      return;
    }
    final h = MediaQuery.of(context).size.height;
    _sc.animateTo(
        (_sc.offset - h * 0.85).clamp(0.0, _sc.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut);
  }

  void _pageDown() {
    if (_paged) {
      _turnNext();
      return;
    }
    final h = MediaQuery.of(context).size.height;
    _sc.animateTo(
        (_sc.offset + h * 0.85).clamp(0.0, _sc.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut);
  }

  // ==================== 设置面板(三页签) ====================

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E2025)
          : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (_, setSheet) => DefaultTabController(
            length: 3,
            child: SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.55,
              child: Column(children: [
                const TabBar(
                  tabs: [
                    Tab(
                        icon: Icon(Icons.palette_outlined, size: 20),
                        text: '外观'),
                    Tab(
                        icon: Icon(Icons.touch_app_outlined, size: 20),
                        text: '操作'),
                    Tab(
                        icon: Icon(Icons.aspect_ratio_rounded, size: 20),
                        text: '边距'),
                  ],
                ),
                Expanded(
                  child: TabBarView(children: [
                    // ---- 外观 ----
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _switchTile(scheme, Icons.brightness_6_outlined,
                            '保持屏幕常亮', _keepOn, (v) async {
                          setSheet(() {});
                          setState(() => _keepOn = v);
                          ReaderPrefs.setKeepScreenOn(v);
                          WakelockPlus.toggle(enable: v);
                        }),
                        _switchTile(scheme, Icons.hide_image_outlined,
                            '隐藏系统状态栏', _hideBar, (v) {
                          setSheet(() {});
                          setState(() => _hideBar = v);
                          ReaderPrefs.setHideStatusBar(v);
                          _applyImmersive();
                        }),
                        _switchTile(
                            scheme, Icons.info_outline, '正文指示器', _indicators,
                            (v) {
                          setSheet(() {});
                          setState(() => _indicators = v);
                          ReaderPrefs.setShowIndicators(v);
                        }),
                        _switchTile(scheme, Icons.translate_rounded,
                            '繁体显示(简→繁)', _traditional, (v) async {
                          setSheet(() {});
                          setState(() {
                            _traditional = v;
                            if (v) _simplified = false;
                          });
                          ReaderPrefs.setTraditional(v);
                          if (v) ReaderPrefs.setSimplified(false);
                          if (_detail != null) {
                            _blocks = await _parseBlocks(_detail);
                            if (mounted) setState(() {});
                          }
                        }),
                        _switchTile(scheme, Icons.translate_rounded,
                            '简体显示(繁→简)', _simplified, (v) async {
                          setSheet(() {});
                          setState(() {
                            _simplified = v;
                            if (v) _traditional = false;
                          });
                          ReaderPrefs.setSimplified(v);
                          if (v) ReaderPrefs.setTraditional(false);
                          if (_detail != null) {
                            _blocks = await _parseBlocks(_detail);
                            if (mounted) setState(() {});
                          }
                        }),
                        const SizedBox(height: 6),
                        Text('字号',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                        Slider(
                          value: _fontSize,
                          min: 12,
                          max: 28,
                          divisions: 16,
                          onChanged: (v) {
                            setSheet(() {});
                            setState(() => _fontSize = v);
                            ReaderPrefs.setFontSize(v);
                          },
                        ),
                        Text('行距',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                        Slider(
                          value: _lineHeight,
                          min: 1.2,
                          max: 2.4,
                          divisions: 12,
                          onChanged: (v) {
                            setSheet(() {});
                            setState(() => _lineHeight = v);
                            ReaderPrefs.setLineHeight(v);
                          },
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            for (var i = 0; i < _presets.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: GestureDetector(
                                  onTap: () {
                                    setSheet(() {});
                                    setState(() {
                                      _bg = i;
                                      _bgChosen = true;
                                      _bgFollowSystem = false;
                                    });
                                    ReaderPrefs.setBgPreset(i);
                                    ReaderPrefs.setBgFollowSystem(false);
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _presets[i].$1,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: !_bgFollowSystem && _bg == i
                                            ? scheme.primary
                                            : (isDark
                                                ? Colors.grey.shade700
                                                : Colors.grey.shade300),
                                        width: !_bgFollowSystem && _bg == i
                                            ? 2.5
                                            : 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(_presets[i].$3,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: _presets[i].$2)),
                                    ),
                                  ),
                                ),
                              ),
                            // 跟随系统
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: GestureDetector(
                                onTap: () {
                                  setSheet(() {});
                                  setState(() {
                                    _bgFollowSystem = true;
                                    _bgChosen = true;
                                  });
                                  ReaderPrefs.setBgFollowSystem(true);
                                },
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2A2D34)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: _bgFollowSystem
                                          ? scheme.primary
                                          : (isDark
                                              ? Colors.grey.shade700
                                              : Colors.grey.shade300),
                                      width: _bgFollowSystem ? 2.5 : 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.brightness_auto_rounded,
                                    size: 20,
                                    color: _bgFollowSystem
                                        ? scheme.primary
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // ---- 操作 ----
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _switchTile(scheme, Icons.touch_app_outlined,
                            '点击翻页(左右 1/3 区域翻页)', _tapTurn, (v) {
                          setSheet(() {});
                          setState(() => _tapTurn = v);
                          ReaderPrefs.setTapTurnPage(v);
                        }),
                        _switchTile(scheme, Icons.auto_stories_rounded,
                            '翻页模式(整页左右翻)', _paged, (v) {
                          setSheet(() {});
                          setState(() => _paged = v);
                          ReaderPrefs.setPagedMode(v);
                          _pagedKey = '';
                          if (v) _sc.jumpTo(0);
                        }),
                        if (_locked && !_unlocked)
                          _aaTile(scheme, Icons.lock_open_rounded,
                              _coinPrice > 0 ? '解锁本章($_coinPrice 轻币)' : '解锁本章',
                              () {
                            Navigator.pop(sheetCtx);
                            _unlock();
                          }),
                        _aaTile(scheme, Icons.arrow_upward_rounded, '回顶部', () {
                          Navigator.pop(sheetCtx);
                          _sc.jumpTo(0);
                        }),
                      ],
                    ),
                    // ---- 边距 ----
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _switchTile(scheme, Icons.fit_screen_outlined, '自动边距',
                            _autoMargin, (v) {
                          setSheet(() {});
                          setState(() => _autoMargin = v);
                          ReaderPrefs.setAutoMargin(v);
                        }),
                        if (!_autoMargin) ...[
                          _marginSlider('上边距', _mt, (v) {
                            setSheet(() {});
                            setState(() => _mt = v);
                            ReaderPrefs.setMarginTop(v);
                          }),
                          _marginSlider('下边距', _mb, (v) {
                            setSheet(() {});
                            setState(() => _mb = v);
                            ReaderPrefs.setMarginBottom(v);
                          }),
                          _marginSlider('左边距', _ml, (v) {
                            setSheet(() {});
                            setState(() => _ml = v);
                            ReaderPrefs.setMarginLeft(v);
                          }),
                          _marginSlider('右边距', _mr, (v) {
                            setSheet(() {});
                            setState(() => _mr = v);
                            ReaderPrefs.setMarginRight(v);
                          }),
                        ],
                      ],
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _switchTile(ColorScheme scheme, IconData icon, String title,
      bool value, Function(bool) onChanged) {
    return SwitchListTile(
      dense: true,
      secondary: Icon(icon, color: scheme.primary),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: (v) => onChanged(v),
    );
  }

  Widget _marginSlider(String label, double value, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toInt()}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        Slider(
          value: value,
          min: 0,
          max: 128,
          onChanged: (v) => onChanged(v),
        ),
      ],
    );
  }

  Widget _aaTile(
      ColorScheme scheme, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: scheme.primary),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    );
  }

  /// 底栏左右角的 上一章/下一章 按钮
  Widget _cornerChapterBtn(
      IconData icon, String label, bool enabled, VoidCallback onTap) {
    final color = enabled ? _textColor : _textColor.withValues(alpha: 0.35);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(fontSize: 13, color: color)),
      ),
    );
  }

  /// 滚动模式正文(整章连续滚动)
  Widget _scrollBody(
      double viewTop, double viewBottom, bool locked, bool lockedBody) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification && _chrome) {
          setState(() => _chrome = false);
        }
        return false;
      },
      // 视口整体避开系统栏:未隐藏时文本/章末按钮都不会进入状态栏与手势条区域
      child: Padding(
        padding: EdgeInsets.only(top: viewTop, bottom: viewBottom),
        child: ListView.builder(
          controller: _sc,
          padding: _bodyPadding,
          itemCount: _blocks.length + 1 + (locked ? 1 : 0),
          itemBuilder: (_, i) {
            if (i < _blocks.length) {
              final b = _blocks[i];
              if (b.image != null) {
                return GestureDetector(
                  onTap: () => _showImageViewer(b.image!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: b.image!,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        placeholder: (_, __) => Container(
                          height: 180,
                          color: _isDarkBg
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.05),
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 120,
                          alignment: Alignment.center,
                          child: Icon(Icons.broken_image_outlined,
                              color: _textColor.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  ),
                );
              }
              // 锁定且无试读文本时给出提示
              final hint =
                  lockedBody && b.links.isEmpty && b.text == '(本章暂无内容)';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text.rich(
                  TextSpan(
                    style: _bodyTextStyle,
                    children: hint
                        ? const [TextSpan(text: '本章需要轻币解锁')]
                        : _spansFor(b),
                  ),
                ),
              );
            }
            // 试读内容下方:付费解锁卡片
            if (locked && i == _blocks.length) {
              return _unlockCard();
            }
            // 章末:上一章/下一章(首章只显下一章,末章只显上一章)
            if (_loading) {
              return const SizedBox.shrink();
            }
            return _chapterEndNav();
          },
        ),
      ),
    );
  }

  Widget _loadErrorView() {
    final loggedIn = LKClient.shared.session.isLoggedIn;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 42, color: _textColor.withValues(alpha: 0.65)),
              const SizedBox(height: 14),
              Text(_loadError ?? '正文暂时无法加载',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _textColor, fontSize: 15, height: 1.6)),
              const SizedBox(height: 18),
              if (!loggedIn)
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LoginPage()));
                    if (mounted && LKClient.shared.session.isLoggedIn) {
                      _load();
                    }
                  },
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('去登录'),
                ),
              if (!loggedIn) const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 翻页模式正文(整页左右翻,末页/首页超滑切章)
  Widget _pagedBody(
      double vh, double viewTop, double viewBottom, bool lockedBody) {
    final contentH =
        (vh - viewTop - viewBottom - _bodyPadding.top - _bodyPadding.bottom)
            .clamp(120.0, 4000.0);
    return Padding(
      padding: EdgeInsets.only(top: viewTop, bottom: viewBottom),
      child: NotificationListener<OverscrollNotification>(
        onNotification: (n) {
          if (n.overscroll > 0) {
            if (_pageIndex >= _pages.length - 1 &&
                _nextId != null &&
                !_chapterSwitching) {
              _chapterSwitching = true;
              _open(_nextId!, _nextTitle ?? '', volumeId: _nextVolumeId);
            }
          } else if (n.overscroll < 0) {
            if (_pageIndex <= 0 && _prevId != null && !_chapterSwitching) {
              _chapterSwitching = true;
              _open(_prevId!, _prevTitle ?? '', volumeId: _prevVolumeId);
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          itemCount: _pages.length,
          physics: const ClampingScrollPhysics(),
          onPageChanged: (i) {
            setState(() {
              _pageIndex = i;
              _progress = _pages.length <= 1
                  ? 1
                  : (i / (_pages.length - 1)).clamp(0.0, 1.0);
            });
          },
          itemBuilder: (_, i) {
            final page = _pages[i];
            if (page.unlockCard) {
              return Padding(
                padding: _bodyPadding,
                child:
                    Align(alignment: Alignment.topCenter, child: _unlockCard()),
              );
            }
            if (page.chapterEnd) {
              return Padding(
                padding: _bodyPadding,
                child: SizedBox(
                    height: contentH, child: Center(child: _chapterEndNav())),
              );
            }
            return Padding(
              padding: _bodyPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final it in page.items)
                    if (it.image != null)
                      // 展示层铺满页面的 contain,但只有插画实际区域可点
                      // (无宽高信息时取中央 72% 作为命中区),空白处点击
                      // 走翻页/工具栏逻辑
                      Builder(builder: (_) {
                        final pad = _bodyPadding;
                        final contentW = MediaQuery.of(context).size.width -
                            pad.left -
                            pad.right;
                        final availH = contentH - 12;
                        double hitW, hitH;
                        final aspect = it.aspect;
                        if (aspect != null && aspect > 0) {
                          hitH = availH;
                          hitW = hitH * aspect;
                          if (hitW > contentW) {
                            hitW = contentW;
                            hitH = hitW / aspect;
                          }
                        } else {
                          hitW = contentW * 0.72;
                          hitH = availH * 0.72;
                        }
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: contentW,
                              height: availH,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8)),
                              child: CachedNetworkImage(
                                imageUrl: it.image!,
                                width: contentW,
                                height: availH,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => Container(
                                  color: _isDarkBg
                                      ? Colors.white10
                                      : Colors.black.withValues(alpha: 0.05),
                                  child: const Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  alignment: Alignment.center,
                                  child: Icon(Icons.broken_image_outlined,
                                      color: _textColor.withValues(alpha: 0.5)),
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showImageViewer(it.image!),
                              child: SizedBox(width: hitW, height: hitH),
                            ),
                          ],
                        );
                      })
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text.rich(
                          TextSpan(
                            style: _bodyTextStyle,
                            children: (lockedBody &&
                                    it.links.isEmpty &&
                                    it.text == '(本章暂无内容)')
                                ? const [TextSpan(text: '本章需要轻币解锁')]
                                : _spans(it.text, it.links),
                          ),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ==================== 章末导航 / 目录 / 本卷评论 ====================

  /// 付费章节:试读内容下方的解锁卡片(轻币价格 + 余额,免弹窗直接解锁)
  Widget _unlockCard() {
    final accent = _linkColor;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: _isDarkBg
              ? Colors.white.withValues(alpha: 0.05)
              : _textColor.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_rounded, size: 18, color: accent),
            const SizedBox(width: 8),
            Text('本章需要轻币解锁',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textColor)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.monetization_on_outlined, size: 18, color: accent),
            const SizedBox(width: 6),
            Text('$_coinPrice 轻币',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: accent)),
            if (_coins >= 0) ...[
              const SizedBox(width: 12),
              Text('余额 $_coins',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: _textColor.withValues(alpha: 0.55))),
            ],
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _unlocking ? null : _unlock,
              icon: _unlocking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(_unlocking ? '解锁中…' : '解锁本章($_coinPrice 轻币)'),
            ),
          ),
        ]),
      ),
    );
  }

  /// 章末的 上一章/下一章(首章只显下一章,末章只显上一章)
  Widget _chapterEndNav() {
    final style = OutlinedButton.styleFrom(
      foregroundColor: _textColor,
      side: BorderSide(color: _textColor.withValues(alpha: 0.35), width: 1),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    Widget btn(IconData icon, String label, String? title, VoidCallback onTap) {
      return Expanded(
        child: OutlinedButton.icon(
          style: style,
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(
            title == null || title.isEmpty ? label : '$label\n$title',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 24),
      child: Row(children: [
        if (_prevId != null)
          btn(Icons.chevron_left_rounded, '上一章', _prevTitle,
              () => _open(_prevId!, _prevTitle ?? '', volumeId: _prevVolumeId)),
        if (_prevId != null && _nextId != null) const SizedBox(width: 12),
        if (_nextId != null)
          btn(Icons.chevron_right_rounded, '下一章', _nextTitle,
              () => _open(_nextId!, _nextTitle ?? '', volumeId: _nextVolumeId)),
      ]),
    );
  }

  void _openVolumeComments() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CommentsPage(
                bookId: widget.bookId,
                bookTitle: widget.bookTitle,
                volumeId: _effectiveVolumeId,
              )),
    );
  }

  void _showCatalog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E2025)
          : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: _CatalogSheet(
          bookId: widget.bookId,
          volumeId: _effectiveVolumeId,
          currentChapterId: widget.chapterId,
          onPick: (chapterId, title, volumeId) {
            Navigator.pop(context);
            _open(chapterId, title, volumeId: volumeId);
          },
        ),
      ),
    );
  }

  // ==================== 界面 ====================

  EdgeInsets get _bodyPadding {
    if (_autoMargin) {
      return const EdgeInsets.fromLTRB(20, 56, 20, 70);
    }
    return EdgeInsets.fromLTRB(_ml, _mt, _mr, _mb);
  }

  /// 正文链接区间 → InlineSpan(链接用主题色+下划线,点击系统浏览器打开)
  List<InlineSpan> _spansFor(_BodyBlock b) => _spans(b.text, b.links);

  List<InlineSpan> _spans(String text, List<(int, int, String)> links) {
    if (links.isEmpty) return [TextSpan(text: text)];
    final out = <InlineSpan>[];
    final linkStyle = TextStyle(
        color: _linkColor,
        decoration: TextDecoration.underline,
        decorationColor: _linkColor);
    var pos = 0;
    for (final (s, e, url) in links) {
      if (s > pos) out.add(TextSpan(text: text.substring(pos, s)));
      out.add(TextSpan(
          text: text.substring(s, e),
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => _openLink(url)));
      pos = e;
    }
    if (pos < text.length) out.add(TextSpan(text: text.substring(pos)));
    return out;
  }

  // ==================== 翻页模式 ====================

  TextStyle get _bodyTextStyle => TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      color: _textColor,
      letterSpacing: 0.3);

  /// 把整章正文切分成翻页页面
  void _buildPages(double viewW, double viewH) {
    final pad = _bodyPadding;
    final contentW = (viewW - pad.left - pad.right).clamp(80.0, 2000.0);
    final contentH = (viewH - pad.top - pad.bottom).clamp(120.0, 4000.0);
    final pages = <_Page>[];
    var cur = <_PageItem>[];
    var used = 0.0;
    void flush() {
      if (cur.isNotEmpty) {
        pages.add(_Page(cur));
        cur = [];
        used = 0;
      }
    }

    // 渲染时每个文本条目底部有 12px 段间距,分页高度计算必须计入,否则 BOTTOM OVERFLOW
    const gap = 12.0;
    for (final b in _blocks) {
      if (b.image != null) {
        flush();
        pages.add(_Page([_PageItem.image(b.image!, aspect: b.aspect)]));
        continue;
      }
      if (b.text.trim().isEmpty) continue; // 空文本块不占页
      for (final chunk in _splitTextBlock(b, contentW, contentH)) {
        if (chunk.text.isEmpty) continue;
        final h = _measureText(chunk.text, contentW) + gap;
        if (used + h > contentH && used > 0) flush();
        cur.add(_PageItem.text(chunk.text, chunk.links));
        used += h;
      }
    }
    flush();
    if (_locked && !_unlocked) pages.add(_Page(const [], unlockCard: true));
    pages.add(_Page(const [], chapterEnd: true));
    _pages = pages;
    // 保持大致阅读进度
    final total = pages.length - 1;
    final target = total <= 0 ? 0 : (_progress * total).round().clamp(0, total);
    _pageIndex = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(target);
      }
    });
  }

  /// 文本段按行切分(每页高度 contentH),链接区间随之重映射
  List<_PageItem> _splitTextBlock(_BodyBlock b, double w, double h) {
    final tp = TextPainter(
      text: TextSpan(text: b.text, style: _bodyTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: w);
    final lms = tp.computeLineMetrics();
    if (lms.isEmpty) {
      return [_PageItem.text(b.text, b.links)];
    }
    int lineEnd(int idx) {
      final pos = tp.getPositionForOffset(Offset(0, lms[idx].baseline));
      return tp.getLineBoundary(pos).end;
    }

    final out = <_PageItem>[];
    var lineIdx = 0;
    var start = 0;
    var usedH = 0.0;
    while (lineIdx < lms.length) {
      final lh = lms[lineIdx].height;
      if (usedH + lh > h && usedH > 0) {
        final end = lineEnd(lineIdx - 1);
        if (end > start) {
          out.add(_PageItem.text(
              b.text.substring(start, end), _remapLinks(b.links, start, end)));
        }
        start = end;
        usedH = 0;
      } else {
        usedH += lh;
        lineIdx++;
      }
    }
    final end = lineEnd(lms.length - 1);
    if (end > start) {
      out.add(_PageItem.text(
          b.text.substring(start, end), _remapLinks(b.links, start, end)));
    }
    if (end < b.text.length) {
      out.add(_PageItem.text(b.text.substring(end), const []));
    }
    return out;
  }

  /// 链接区间裁剪重映射到子串坐标
  List<(int, int, String)> _remapLinks(
      List<(int, int, String)> links, int start, int end) {
    final out = <(int, int, String)>[];
    for (final (s, e, url) in links) {
      if (e <= start || s >= end) continue;
      final ns = (s - start).clamp(0, end - start);
      final ne = (e - start).clamp(ns, end - start);
      if (ne > ns) out.add((ns, ne, url));
    }
    return out;
  }

  double _measureText(String text, double w) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _bodyTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: w);
    return tp.height;
  }

  /// 分享本章:系统分享菜单,内容为小说链接
  Future<void> _share() async {
    final url =
        'https://www.lightnovel.fun/reader/${widget.bookId}/${widget.chapterId}';
    try {
      // iPad 的 UIActivityViewController 使用 popover,必须传入分享按钮
      // 自身在 controller.view 坐标系中的有效矩形,不能使用页面根 context。
      final renderObject =
          _shareButtonKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        if (mounted) showLkError(context, '分享按钮暂不可用,请稍后重试');
        return;
      }
      final sharePositionOrigin =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (sharePositionOrigin.isEmpty) {
        if (mounted) showLkError(context, '分享按钮暂不可用,请稍后重试');
        return;
      }
      await Share.share(
        url,
        subject: _title,
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      if (mounted) showLkError(context, '分享失败: $e');
    }
  }

  void _turnPrev() {
    if (_pageIndex <= 0) return; // 边界交给超滑/底栏按钮
    _pageController.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  void _turnNext() {
    if (_pageIndex >= _pages.length - 1) return;
    _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked && !_unlocked;
    final lockedBody = locked && _blocks.length == 1;
    final barColor = _bgColor.withValues(alpha: 0.96);
    final padTop = MediaQuery.of(context).padding.top;
    // 未隐藏系统栏时:顶部避开状态栏、底部避开手势导航条
    final viewTopPadding = _hideBar ? 0.0 : padTop;
    final viewBottomPadding =
        _hideBar ? 0.0 : MediaQuery.of(context).padding.bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _isDarkBg ? Brightness.light : Brightness.dark,
        statusBarBrightness: _isDarkBg ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bgColor,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final w = MediaQuery.of(context).size.width;
            if (_paged) {
              // 翻页模式:左右 1/3 翻页,中间唤出/隐藏工具栏
              if (d.globalPosition.dx < w / 3) {
                _turnPrev();
                return;
              }
              if (d.globalPosition.dx > w * 2 / 3) {
                _turnNext();
                return;
              }
              setState(() => _chrome = !_chrome);
              return;
            }
            if (_tapTurn) {
              if (d.globalPosition.dx < w / 3) {
                _pageUp();
                return;
              }
              if (d.globalPosition.dx > w * 2 / 3) {
                _pageDown();
                return;
              }
            }
            setState(() => _chrome = !_chrome);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: _loading
                    ? LkLoadingIndicator(color: _textColor)
                    : _loadError != null
                        ? _loadErrorView()
                        : LayoutBuilder(builder: (ctx, cons) {
                        final vw = cons.maxWidth;
                        final vh = cons.maxHeight;
                        // 翻页模式:内容/排版/尺寸变化时重建分页
                        if (_paged) {
                          final key = '$_fontSize|$_lineHeight|$_mt|$_mb|'
                              '$_ml|$_mr|$_autoMargin|${vw.round()}|${vh.round()}|'
                              '${viewTopPadding.round()}|${viewBottomPadding.round()}|'
                              '$_locked|$_unlocked|${identical(_blocks, _pagesSource)}';
                          if (key != _pagedKey) {
                            _pagedKey = key;
                            _pagesSource = _blocks;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _buildPages(vw,
                                    vh - viewTopPadding - viewBottomPadding);
                                setState(() {});
                              }
                            });
                          }
                          return _pagedBody(vh, viewTopPadding,
                              viewBottomPadding, lockedBody);
                        }
                        return _scrollBody(viewTopPadding, viewBottomPadding,
                            locked, lockedBody);
                      }),
              ),
              if (_indicators && !_chrome && !_loading)
                Positioned(
                  top: _hideBar ? 6.0 : padTop + 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: _textColor.withValues(alpha: 0.45)),
                    ),
                  ),
                ),
              if (_indicators && !_chrome && !_loading)
                Positioned(
                  bottom: 8,
                  right: 16,
                  child: _paged
                      ? Text(
                          '第 ${_pageIndex + 1}/${_pages.length} 页',
                          style: TextStyle(
                              fontSize: 11,
                              color: _textColor.withValues(alpha: 0.45)),
                        )
                      : ValueListenableBuilder<double>(
                          valueListenable: _progressN,
                          builder: (_, v, __) => Text(
                            '${(v * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                                fontSize: 11,
                                color: _textColor.withValues(alpha: 0.45)),
                          ),
                        ),
                ),
              // 顶栏
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                top: _chrome ? 0 : -90,
                left: 0,
                right: 0,
                child: Container(
                  color: barColor,
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left_rounded,
                              color: _textColor),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _textColor),
                          ),
                        ),
                        IconButton(
                          key: _shareButtonKey,
                          tooltip: '分享',
                          icon: Icon(Icons.ios_share_rounded,
                              size: 22, color: _textColor),
                          onPressed: _share,
                        ),
                        IconButton(
                          tooltip: '本卷评论',
                          icon: Icon(Icons.chat_bubble_outline_rounded,
                              size: 22, color: _textColor),
                          onPressed: _openVolumeComments,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 底栏:上一章 / 设置+目录 / 下一章
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                bottom: _chrome ? 0 : -120,
                left: 0,
                right: 0,
                child: Container(
                  color: barColor,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          _cornerChapterBtn(Icons.chevron_left_rounded, '上一章',
                              _prevId != null, () {
                            if (_prevId != null) {
                              _open(_prevId!, _prevTitle ?? '',
                                  volumeId: _prevVolumeId);
                            }
                          }),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_locked && !_unlocked)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.lock_outline_rounded,
                                        size: 16, color: _textColor),
                                  ),
                                IconButton(
                                  tooltip: '阅读设置',
                                  icon: Icon(Icons.settings_rounded,
                                      size: 22, color: _textColor),
                                  onPressed: _showSettings,
                                ),
                                TextButton.icon(
                                  onPressed: _showCatalog,
                                  icon: Icon(Icons.menu_book_rounded,
                                      size: 18, color: _textColor),
                                  label: Text('目录',
                                      style: TextStyle(
                                          fontSize: 13, color: _textColor)),
                                ),
                              ],
                            ),
                          ),
                          _cornerChapterBtn(Icons.chevron_right_rounded, '下一章',
                              _nextId != null, () {
                            if (_nextId != null) {
                              _open(_nextId!, _nextTitle ?? '',
                                  volumeId: _nextVolumeId);
                            }
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 阅读器目录弹层:卷就地展开章节,点章节跳转;打开时自动定位当前卷/章
class _CatalogSheet extends StatefulWidget {
  final int bookId;
  final int volumeId;
  final int currentChapterId;
  final void Function(int chapterId, String title, int volumeId) onPick;
  const _CatalogSheet(
      {required this.bookId,
      required this.volumeId,
      required this.currentChapterId,
      required this.onPick});

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  List<dynamic> _volumes = [];
  String? _error;
  int? _expanded;
  final Map<int, List<dynamic>> _chapters = {};
  final ScrollController _sc = ScrollController();
  final Map<int, GlobalKey> _volKeys = {};
  final GlobalKey _curChapterKey = GlobalKey();
  bool _located = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.volumeId; // 打开即展开当前卷
    _loadVolumes();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _loadVolumes() async {
    try {
      // 拉全所有卷(多页),保证当前卷一定在列表里
      final vs = <dynamic>[];
      for (var p = 1; p <= 10; p++) {
        final page = await LKApi.volumes(widget.bookId, p);
        if (page.isEmpty) break;
        vs.addAll(page);
        if (page.length < 50) break;
      }
      if (!mounted) return;
      setState(() => _volumes = vs);
      _loadChapters(widget.volumeId);
      _revealCurrent();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadChapters(int vid) async {
    if (_chapters.containsKey(vid)) return;
    try {
      final cs = await LKApi.chapters(widget.bookId, vid, 1);
      if (!mounted) return;
      setState(() => _chapters[vid] = cs);
      if (vid == widget.volumeId) _revealCurrent();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggle(int vid) async {
    if (_expanded == vid) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = vid);
    _loadChapters(vid);
  }

  /// 滚动定位到当前卷与当前章节
  void _revealCurrent() {
    if (_located) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _volumes.isEmpty) return;
      final vi = _volumes.indexWhere((v) => v.volumeId == widget.volumeId);
      if (vi < 0) return;
      // 1) 当前卷:已构建则 ensureVisible,否则按估计偏移跳
      final vctx = _volKeys[widget.volumeId]?.currentContext;
      if (vctx != null) {
        Scrollable.ensureVisible(vctx,
            duration: const Duration(milliseconds: 250), alignment: 0.15);
      } else if (_sc.hasClients) {
        final est = (vi * 56.0).clamp(0.0, _sc.position.maxScrollExtent);
        _sc.jumpTo(est);
      }
      // 2) 当前章节(在展开的当前卷内):已构建则精确定位,否则按行高估计
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cctx = _curChapterKey.currentContext;
        if (cctx != null) {
          _located = true;
          Scrollable.ensureVisible(cctx,
              duration: const Duration(milliseconds: 250), alignment: 0.45);
          return;
        }
        final chs = _chapters[widget.volumeId];
        if (_sc.hasClients && chs != null) {
          final ci =
              chs.indexWhere((c) => c.chapterId == widget.currentChapterId);
          if (ci > 0) {
            final est = (vi * 56.0 + ci * 42.0)
                .clamp(0.0, _sc.position.maxScrollExtent);
            _sc.jumpTo(est);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final ctx2 = _curChapterKey.currentContext;
              if (ctx2 != null) {
                _located = true;
                Scrollable.ensureVisible(ctx2,
                    duration: const Duration(milliseconds: 200),
                    alignment: 0.45);
              }
            });
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Text('目录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ]),
      ),
      Expanded(
        child: _error != null && _volumes.isEmpty
            ? Center(
                child:
                    Text(_error!, style: const TextStyle(color: Colors.grey)))
            : ListView.builder(
                controller: _sc,
                padding: EdgeInsets.fromLTRB(
                    12, 0, 12, 12 + MediaQuery.of(context).padding.bottom),
                itemCount: _volumes.length,
                itemBuilder: (_, i) {
                  final v = _volumes[i];
                  final vid = v.volumeId as int;
                  final expanded = _expanded == vid;
                  final chs = _chapters[vid];
                  final isCur = vid == widget.volumeId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      key: _volKeys.putIfAbsent(vid, GlobalKey.new),
                      color: isDark
                          ? const Color(0xFF2A2C33)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        InkWell(
                          onTap: () => _toggle(vid),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(children: [
                              Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_down_rounded
                                      : Icons.chevron_right_rounded,
                                  size: 20,
                                  color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(v.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: isCur ? scheme.primary : null)),
                              ),
                              if (isCur)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color:
                                        scheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('当前',
                                      style: TextStyle(
                                          fontSize: 10, color: scheme.primary)),
                                ),
                            ]),
                          ),
                        ),
                        if (expanded && chs == null)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        if (expanded && chs != null)
                          ...chs.map((c) => InkWell(
                                onTap: () =>
                                    widget.onPick(c.chapterId, c.title, vid),
                                child: Container(
                                  key: c.chapterId == widget.currentChapterId
                                      ? _curChapterKey
                                      : null,
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  color: c.chapterId == widget.currentChapterId
                                      ? scheme.primary.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  child: Text(c.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: c.chapterId ==
                                                  widget.currentChapterId
                                              ? scheme.primary
                                              : null)),
                                ),
                              )),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

/// 全屏插画查看:双指缩放、点击空白关闭、一键保存到相册
class _ImageViewer extends StatefulWidget {
  final String url;
  const _ImageViewer({required this.url});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final resp = await http.get(Uri.parse(widget.url), headers: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 LKFlutter'
      }).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('下载失败 HTTP ${resp.statusCode}');
      }
      await Gal.putImageBytes(
        resp.bodyBytes,
        name: 'lk_${DateTime.now().millisecondsSinceEpoch}',
        album: 'Yomiru',
      );
      if (!mounted) return;
      showLkError(context, '已保存到相册');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showLkError(context, '保存失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.url,
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (_, __, ___) => const Center(
                      child: CircularProgressIndicator(color: Colors.white70)),
                  errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white38, size: 48)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top,
          left: 8,
          child: IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 24 + MediaQuery.of(context).padding.bottom,
          child: SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, size: 20),
              label: Text(_saving ? '保存中…' : '保存图片到相册'),
            ),
          ),
        ),
      ]),
    );
  }
}
