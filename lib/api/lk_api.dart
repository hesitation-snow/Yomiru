import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lk_client.dart';
import 'models.dart';

/// 全接口分组封装(静态方法,统一走 LKClient.shared)
class LKApi {
  static final LKClient client = LKClient.shared;

  // ==================== 鉴权 ====================

  static Future<void> login(String username, String password) async {
    final d = await client.post('/api/bff/auth-password-login-v1', {
      'username': username,
      'password': password,
    });
    final auth = (d['auth'] as Map<String, dynamic>?) ?? const {};
    final key = (auth['security_key'] as String?) ?? '';
    if (key.isEmpty) throw LKException(-1, '登录响应缺少 auth');
    client.session
      ..securityKey = key
      ..uid = (auth['uid'] as num?)?.toInt() ?? 0;
    final u = (d['user'] as Map<String, dynamic>?) ?? const {};
    client.session
      ..nickname = (u['nickname'] as String?) ?? ''
      ..avatar = (u['avatar'] as String?) ?? '';
    LKClient.sessionRev.value++;
  }

  static Future<bool> validateSession() async {
    if (!client.session.isLoggedIn) return false;
    final d = await client.post('/api/bff/auth-session-v1', client.authed());
    final ok = (d['logged_in'] as num?)?.toInt() == 1;
    if (!ok) {
      client.session.clear();
      LKClient.sessionRev.value++;
    }
    return ok;
  }

  static Future<void> logout() async {
    if (client.session.isLoggedIn) {
      try {
        await client.post('/api/bff/logout-v1', client.authed());
      } catch (_) {}
    }
    client.session.clear();
    LKClient.sessionRev.value++;
  }

  // ==================== 首页 / 发现 ====================

  static Future<List<LKBook>> homeFeed(String channel, int page,
      {int pageSize = 20}) async {
    final d = await client.post('/api/bff/home-feed-v1', {
      'channel': channel, 'page': page,
      'pageSize': pageSize, 'page_size': pageSize,
    });
    return _bookList(d);
  }

  static Future<List<LKBook>> channelFeed(String path, int page,
      {int pageSize = 20}) async {
    final d = await client
        .post(path, {'page': page, 'pageSize': pageSize, 'page_size': pageSize});
    return _bookList(d);
  }

  static Future<List<LKBook>> rank(int page, {int pageSize = 20}) async {
    final d = await client.post('/api/bff/book-rank-list-v1',
        {'page': page, 'pageSize': pageSize});
    return _bookList(d);
  }

  /// 官网首页「好书推荐」:模块为服务端渲染,无独立客户端接口,
  /// 抓取官网首页 HTML 解析出推荐书籍(仅书号/标题/封面)
  static Future<List<LKBook>> homeRecommend() async {
    final resp = await http
        .get(Uri.parse('https://www.lightnovel.fun/'), headers: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36 LKFlutter/0.1',
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw LKException(resp.statusCode, 'HTTP ${resp.statusCode}');
    }
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final secStart = html.indexOf('<section class="web-recommend"');
    if (secStart < 0) return const [];
    final secEnd = html.indexOf('</section>', secStart);
    final sec = html.substring(
        secStart, secEnd < 0 ? html.length : secEnd);
    // 逐篇解析:书名优先取 img alt,为空则取 <h3>;封面取 img src,
    // 相对路径/官方占位图视为无封面(客户端显示默认封面)
    final artRe = RegExp(
        r'<article[^>]*mini-book[^>]*>[\s\S]*?<a href="/book/(\d+)"[^>]*>([\s\S]*?)</a></article>');
    final out = <LKBook>[];
    for (final m in artRe.allMatches(sec)) {
      final id = int.tryParse(m.group(1) ?? '') ?? 0;
      if (id <= 0) continue;
      final body = m.group(2) ?? '';
      var title = (RegExp(r'<img[^>]*alt="([^"]*)"')
                  .firstMatch(body)
                  ?.group(1) ??
              '')
          .replaceAll('&amp;', '&')
          .trim();
      if (title.isEmpty) {
        title = (RegExp(r'<h3[^>]*>([\s\S]*?)</h3>')
                    .firstMatch(body)
                    ?.group(1) ??
                '')
            .replaceAll('&amp;', '&')
            .trim();
      }
      final raw =
          RegExp(r'<img[^>]*src="([^"]*)"').firstMatch(body)?.group(1) ?? '';
      var cover = '';
      final uri = Uri.tryParse(raw.trim());
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        cover = raw.replaceAll('&amp;', '&').trim();
      }
      out.add(LKBook(bookId: id, title: title, coverUrl: cover));
    }
    return out;
  }

  static Future<List<LKBook>> search(String q, int page,
      {int pageSize = 20,
      String sort = 'relevance',
      String primaryTag = '',
      String preset = '',
      String channelCode = '',
      String workType = ''}) async {
    final d = await client.post('/api/bff/apk-search-result-v1', {
      'q': q,
      'page': page,
      'pageSize': pageSize,
      'sort': sort,
      'primary_tag': primaryTag,
      'preset': preset,
      'channel_code': channelCode,
      'work_type': workType,
      'filters': '{}',
    });
    return _bookList(d);
  }

  /// 搜索分类(标签/频道/预设)
  static Future<Map<String, dynamic>> searchTaxonomy() async =>
      client.post('/api/bff/apk-search-taxonomy-v1', const {});

  static Future<List<LKBook>> searchSuggest(String q) async {
    final d = await client.post('/api/bff/apk-search-suggest-v1',
        {'q': q, 'limit': 10});
    return _bookList(d);
  }

  static List<LKBook> _bookList(Map<String, dynamic> d) {
    final list = d['list'];
    if (list == null) {
      throw LKException(-1, '接口未返回列表(字段: ${d.keys.join(', ')})');
    }
    return (list as List)
        .map((e) => LKBook.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== 阅读 ====================

  static Future<LKBook> bookDetail(int bookId) async =>
      LKBook.fromJson(await client.post('/api/new-content-read/get-book-detail',
          client.authed({'book_id': bookId, 'with_volumes': 0})));

  static Future<List<LKVolume>> volumes(int bookId, int page,
      {int pageSize = 50}) async {
    final d = await client.post('/api/new-content-read/get-book-volumes', {
      'book_id': bookId, 'page': page, 'pageSize': LKClient.clampPageSize(pageSize),
    });
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKVolume.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<LKChapter>> chapters(int bookId, int volumeId, int page,
      {int pageSize = 50}) async {
    final d = await client.post('/api/new-content-read/get-volume-chapters', {
      'book_id': bookId, 'volume_id': volumeId, 'page': page,
      'pageSize': LKClient.clampPageSize(pageSize),
    });
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKChapter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<LKChapterDetail> chapterDetail(int bookId, int chapterId) async =>
      LKChapterDetail.fromJson(
          await client.post('/api/new-content-read/get-chapter-detail',
              client.authed({'book_id': bookId, 'chapter_id': chapterId})));

  static Future<List<LKParagraph>> paragraphs(int bookId, int chapterId) async {
    final d = await client.post('/api/new-content-read/get-chapter-paragraphs',
        {'book_id': bookId, 'chapter_id': chapterId});
    final list = (d['paragraphs'] as List?) ?? (d['list'] as List?) ?? const [];
    return list.map((e) => LKParagraph.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ==================== 书评 / 段评 ====================

  static Future<List<LKComment>> bookComments(int bookId, int page) async {
    final d = await client.post('/api/new-content-read/get-book-comments', {
      'book_id': bookId, 'page': page, 'pageSize': 20,
      'rating_filter': 'all', 'include_user_interactions': 1,
    });
    return _commentList(d);
  }

  /// 本卷评论(volume_id 定位卷;0 则为整书评论)
  static Future<List<LKComment>> volumeComments(
      int bookId, int volumeId, int page) async {
    final d = await client.post('/api/new-content-read/get-book-comments', {
      'book_id': bookId, 'page': page, 'pageSize': 20,
      'rating_filter': 'all', 'include_user_interactions': 1,
      'volume_id': volumeId, 'chapter_id': 0,
    });
    return _commentList(d);
  }

  /// 评论表情包列表
  static Future<List<LKEmojiGroup>> commentEmojis() async {
    final d = await client.post('/api/bff/comment-emoji-list-v1', {});
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKEmojiGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> publishBookComment(int bookId, String content,
          {int volumeId = 0}) =>
      client.post('/api/discuss/publish-book-comment', client.authed({
        'scope': volumeId > 0 ? 'volume' : 'book',
        'book_id': bookId,
        'volume_id': volumeId,
        'chapter_id': 0,
        'root_comment_id': 0,
        'reply_comment_id': 0,
        'content': content,
        'rating_stars': 0,
        'read_duration_seconds': 0,
      }));

  static Future<void> likeBookComment(int bookId, int commentId, bool like,
          {int volumeId = 0}) =>
      client.post('/api/discuss/like-book-comment', client.authed({
        'scope': volumeId > 0 ? 'volume' : 'book',
        'book_id': bookId,
        'volume_id': volumeId,
        'chapter_id': 0,
        'comment_id': commentId,
        'root_comment_id': 0,
        'act': like ? 'like' : 'unlike',
      }));

  static Future<List<LKComment>> paragraphComments(int bookId, int chapterId,
      LKParagraph p) async {
    final d = await client.post('/api/new-content-read/get-paragraph-comments', {
      'book_id': bookId, 'chapter_id': chapterId,
      'paragraph_hash': p.hash, 'body_version': p.bodyVersion,
      'paragraph_no': p.paragraphNo, 'page': 1, 'pageSize': 20,
    });
    return _commentList(d);
  }

  static Future<void> publishParagraphComment(int bookId, int chapterId,
      LKParagraph p, String content) =>
      client.post('/api/new-content-read/publish-paragraph-comment', client.authed({
        'book_id': bookId, 'chapter_id': chapterId,
        'paragraph_hash': p.hash, 'body_version': p.bodyVersion,
        'paragraph_no': p.paragraphNo, 'content': content, 'parent_comment_id': 0,
      }));

  static List<LKComment> _commentList(Map<String, dynamic> d) =>
      ((d['list'] as List?) ?? const [])
          .map((e) => LKComment.fromJson(e as Map<String, dynamic>))
          .toList();

  // ==================== 书架 / 历史 / 进度 ====================

  static Future<bool> inShelf(int bookId) async {
    final d = await client.post('/api/new-content-read/get-book-library-state',
        client.authed({'book_id': bookId}));
    return (d['in_shelf'] as num?)?.toInt() == 1;
  }

  static Future<void> toggleShelf(int bookId, bool add) =>
      client.post('/api/new-content-read/toggle-book-shelf', client.authed({
        'book_id': bookId, 'action': add ? 'add' : 'remove', 'source': 'pc_web',
      }));

  static Future<List<LKBook>> bookshelf(int page, {int pageSize = 50}) async {
    final d = await client.post('/api/bff/bookshelf-v1',
        client.authed({'page': page, 'pageSize': LKClient.clampPageSize(pageSize)}));
    return _bookList(d);
  }

  static Future<List<LKHistoryItem>> cloudHistory(int page,
      {int pageSize = 50}) async {
    final d = await client.post('/api/bff/history-v1',
        client.authed({'page': page, 'pageSize': LKClient.clampPageSize(pageSize)}));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveHistory(int bookId, int volumeId, int chapterId,
      int progressPercent) =>
      client.post('/api/new-content-read/save-book-history', client.authed({
        'book_id': bookId, 'volume_id': volumeId, 'chapter_id': chapterId,
        'progress_percent': progressPercent,
      }));

  static Future<void> deleteHistory(int bookId) =>
      client.post('/api/new-content-read/delete-book-history',
          client.authed({'book_id': bookId}));

  static Future<void> unlockChapter(int chapterId) =>
      client.post('/api/new-content-read/unlock-chapter',
          client.authed({'chapter_id': chapterId}));

  // ==================== 动态 ====================

  static Future<List<LKDynamicItem>> dynamicFeed(
      {String tab = 'follow', String cursor = '', int pageSize = 20}) async {
    final d = await client.post('/api/dynamic/get-feed-v1', client.authed({
      'tab': tab, 'cursor': cursor, 'page': 1,
      'page_size': pageSize, 'pageSize': pageSize,
    }));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKDynamicItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<LKComment>> dynamicComments(int dynamicId) async {
    final d = await client.post('/api/dynamic/get-comments-v1', client.authed({
      'dynamic_id': dynamicId, 'comment_id': 0, 'cursor': '',
      'sort': 'latest', 'page_size': 20, 'pageSize': 20,
    }));
    return _commentList(d);
  }

  static Future<void> toggleDynamicLike(int dynamicId, bool like) =>
      client.post('/api/dynamic/toggle-like-v1',
          client.authed({'dynamic_id': dynamicId, 'act': like ? 'like' : 'unlike'}));

  static Future<void> toggleDynamicFavorite(int dynamicId, bool fav) =>
      client.post('/api/dynamic/toggle-favorite-v1', client.authed(
          {'dynamic_id': dynamicId, 'act': fav ? 'favorite' : 'unfavorite'}));

  // ==================== 消息 / 私信 ====================

  static Future<Map<String, dynamic>> messageUnread() async =>
      client.post('/api/bff/message-unread-v1', client.authed());

  static Future<List<LKMessageItem>> messages(String type, int page) async {
    final path = switch (type) {
      'like' => '/api/bff/message-likes-v1',
      'fan' => '/api/bff/message-fans-v1',
      'system' => '/api/bff/message-system-v1',
      _ => '/api/bff/message-replies-v1',
    };
    final d = await client.post(path,
        client.authed({'page': page, 'page_size': 20}));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKMessageItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> markMessagesRead(String scope) =>
      client.post('/api/bff/message-mark-read-v1', client.authed({
        'scope': scope,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'nonce': DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      }));

  static Future<List<LKConversation>> dmConversations() async {
    final d = await client.post('/api/bff/dm-conversations-v1',
        client.authed({'page': 1, 'page_size': 20}));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKConversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<LKDMMessage>> dmMessages(int peerUid) async {
    final d = await client.post('/api/bff/dm-messages-v1',
        client.authed({'peer_uid': peerUid, 'page': 1, 'page_size': 30}));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKDMMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> dmSend(int peerUid, String content) =>
      client.post('/api/bff/dm-send-v1', client.authed({
        'peer_uid': peerUid, 'content_text': content,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'nonce': DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        'client_msg_id': 'app-${DateTime.now().millisecondsSinceEpoch}',
      }));

  // ==================== 用户 / 设置 ====================

  static Future<Map<String, dynamic>> myHome() async =>
      client.post('/api/bff/my-home-v1', client.authed());

  /// 当前轻币余额
  static Future<int> myCoins() async {
    final d = await client.post('/api/bff/my-home-v1', client.authed());
    final profile = d['profile'] as Map<String, dynamic>?;
    return (profile?['coin'] as num?)?.toInt() ?? 0;
  }

  static Future<void> toggleFollow(int uid, bool follow) =>
      client.post('/api/bff/toggle-user-follow-v1',
          client.authed({'uid': uid, 'act': follow ? 'follow' : 'unfollow'}));

  static Future<void> toggleMedal(int medalId, bool equip) =>
      client.post('/api/bff/toggle-my-medal-v1',
          client.authed({'medal_id': medalId, 'act': equip ? 'equip' : 'unequip'}));

  static Future<Map<String, dynamic>> about() async =>
      client.post('/api/bff/settings-about-v1', const {});

  /// 检查更新:GitHub Releases 最新发布(无发布时返回 null)
  static Future<LKRelease?> latestRelease() async {
    final resp = await http
        .get(
            Uri.parse(
                'https://api.github.com/repos/hesitation-snow/yomiru/releases/latest'),
            headers: const {
              'User-Agent': 'LKFlutter',
              'Accept': 'application/vnd.github+json',
            })
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 404) return null; // 尚未发布任何版本
    if (resp.statusCode != 200) {
      throw LKException(resp.statusCode, '网络异常(HTTP ${resp.statusCode})');
    }
    return LKRelease.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  // ==================== 作者中心 ====================

  static Future<Map<String, dynamic>> authorStatus() async =>
      client.post('/api/bff/author-center-status-v1', client.authed());

  static Future<void> applyAuthor() =>
      client.post('/api/bff/apply-author-v1', client.authed());
}
