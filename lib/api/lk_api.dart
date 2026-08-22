import 'dart:async';
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
    final d = await client.post(
        '/api/bff/home-feed-v1',
        {
          'channel': channel,
          'page': page,
          'pageSize': pageSize,
          'page_size': pageSize,
        },
        cacheKey: 'home_feed_$channel-$page-$pageSize',
        cacheTtl: const Duration(minutes: 5));
    return _bookList(d);
  }

  /// 官网首页「最新」频道的专用信息流。
  static Future<List<LKBook>> homeRecentUpdatesFeed(int page,
      {int pageSize = 20}) async {
    final size = LKClient.clampPageSize(pageSize);
    final d = await client.post(
      '/api/bff/home-recent-updates-feed-v1',
      {'page': page, 'pageSize': size, 'page_size': size},
      cacheKey: 'home_recent_updates-$page-$size',
      cacheTtl: const Duration(minutes: 5),
    );
    return _bookList(d);
  }

  static Future<List<LKBook>> channelFeed(String path, int page,
      {int pageSize = 20}) async {
    final d = await client.post(
        path, {'page': page, 'pageSize': pageSize, 'page_size': pageSize},
        cacheKey: 'channel_feed_${Uri.encodeComponent(path)}-$page-$pageSize',
        cacheTtl: const Duration(minutes: 5));
    return _bookList(d);
  }

  static Future<List<LKBook>> rank(int page, {int pageSize = 20}) async {
    final d = await client.post(
        '/api/bff/book-rank-list-v1', {'page': page, 'pageSize': pageSize},
        cacheKey: 'book_rank-$page-$pageSize',
        cacheTtl: const Duration(minutes: 5));
    return _bookList(d);
  }

  /// 官网首页「好书推荐」,直接使用服务端推荐接口,避免依赖网页 HTML 结构。
  static Future<List<LKBook>> homeRecommend({int pageSize = 8}) async {
    final d = await client.post('/api/bff/home-promo-v1', {
      'page': 1,
      'pageSize': LKClient.clampPageSize(pageSize),
      'page_size': LKClient.clampPageSize(pageSize),
    });
    return _bookList(d);
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
      client.post('/api/bff/apk-search-taxonomy-v1', const {},
          cacheKey: 'search_taxonomy', cacheTtl: const Duration(hours: 12));

  static Future<List<LKBook>> searchSuggest(String q) async {
    final d = await client
        .post('/api/bff/apk-search-suggest-v1', {'q': q, 'limit': 10});
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
          client.authed({'book_id': bookId, 'with_volumes': 0}),
          cacheKey: 'book_detail_${client.session.uid}-$bookId',
          cacheTtl: const Duration(minutes: 10)));

  static Future<List<LKVolume>> volumes(int bookId, int page,
      {int pageSize = 50}) async {
    final d = await client.post(
        '/api/new-content-read/get-book-volumes',
        {
          'book_id': bookId,
          'page': page,
          'pageSize': LKClient.clampPageSize(pageSize),
        },
        cacheKey: 'book_volumes_$bookId-$page-$pageSize',
        cacheTtl: const Duration(minutes: 10));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKVolume.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<LKChapter>> chapters(int bookId, int volumeId, int page,
      {int pageSize = 50}) async {
    final d = await client.post(
        '/api/new-content-read/get-volume-chapters',
        {
          'book_id': bookId,
          'volume_id': volumeId,
          'page': page,
          'pageSize': LKClient.clampPageSize(pageSize),
        },
        cacheKey: 'volume_chapters_$bookId-$volumeId-$page-$pageSize',
        cacheTtl: const Duration(minutes: 10));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKChapter.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<LKChapterDetail> chapterDetail(
      int bookId, int chapterId) async {
    final loggedIn = client.session.isLoggedIn;
    final accessMessage = loggedIn
        ? '无法阅读\n没有权限访问或者内容已删除'
        : '该正文可能需要登录或勇者权限才能访问,请先登录;如果登录后仍无法打开,可能是当前账号没有访问权限。';
    late final Map<String, dynamic> data;
    try {
      data = await client.post(
        '/api/new-content-read/get-chapter-detail',
        client.authed({'book_id': bookId, 'chapter_id': chapterId}),
        accessErrorMessage: accessMessage,
      );
    } on LKException catch (e) {
      if (e.code == 403 ||
          e.message.contains('没有权限') ||
          e.message.contains('无权限') ||
          e.message.contains('无法阅读') ||
          e.message.contains('内容已删除')) {
        throw LKException(e.code, accessMessage, accessRestricted: true);
      }
      rethrow;
    }

    // 未登录或没有勇者权限时,接口仍可能返回 code=0,但正文区域为空。
    // 先识别访问状态,避免模型在 render_preview=[] 等形态上强制类型转换。
    final accessTypeValue = data['access_type'] ?? data['accessType'];
    final accessType =
        accessTypeValue is String ? accessTypeValue.toLowerCase() : '';
    final braveRequired = accessType == 'brave' ||
        _flag(data['brave_required']) ||
        _flag(data['braveRequired']);
    final unlocked = _flag(data['unlocked']);
    if (!_hasChapterBody(data) && braveRequired && !unlocked) {
      throw LKException(403, accessMessage, accessRestricted: true);
    }
    return LKChapterDetail.fromJson(data);
  }

  static bool _flag(dynamic value) =>
      value == true || value == 1 || value == '1' || value == 'true';

  static bool _hasChapterBody(Map<String, dynamic> data) {
    bool hasBody(dynamic value) {
      if (value is Map) {
        final text = value['body_text'];
        final html = value['body_html'];
        return (text is String && text.isNotEmpty) ||
            (html is String && html.isNotEmpty);
      }
      if (value is List) return value.any(hasBody);
      return false;
    }

    return hasBody(data['body_snapshot']) || hasBody(data['render_preview']);
  }

  static Future<List<LKParagraph>> paragraphs(int bookId, int chapterId) async {
    final d = await client.post('/api/new-content-read/get-chapter-paragraphs',
        {'book_id': bookId, 'chapter_id': chapterId});
    final list = (d['paragraphs'] as List?) ?? (d['list'] as List?) ?? const [];
    return list
        .map((e) => LKParagraph.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== 书评 / 段评 ====================

  static Future<List<LKComment>> bookComments(int bookId, int page) async {
    final d = await client.post('/api/new-content-read/get-book-comments', {
      'book_id': bookId,
      'page': page,
      'pageSize': 20,
      'rating_filter': 'all',
      'include_user_interactions': 1,
    });
    return _commentList(d);
  }

  /// 本卷评论(volume_id 定位卷;0 则为整书评论)
  static Future<List<LKComment>> volumeComments(
      int bookId, int volumeId, int page) async {
    final d = await client.post('/api/new-content-read/get-book-comments', {
      'book_id': bookId,
      'page': page,
      'pageSize': 20,
      'rating_filter': 'all',
      'include_user_interactions': 1,
      'volume_id': volumeId,
      'chapter_id': 0,
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
      {int volumeId = 0, List<LKDynamicMedia> media = const []}) {
    final body = client.authed({
      'scope': volumeId > 0 ? 'volume' : 'book',
      'book_id': bookId,
      'volume_id': volumeId,
      'chapter_id': 0,
      'root_comment_id': 0,
      'reply_comment_id': 0,
      'content': content,
      'rating_stars': 0,
      'read_duration_seconds': 0,
    });
    if (media.isNotEmpty) {
      body['media_json'] = jsonEncode(media.map(_mediaJson).toList());
    }
    return client.post('/api/discuss/publish-book-comment', body);
  }

  static Future<void> likeBookComment(int bookId, int commentId, bool like,
          {int volumeId = 0}) =>
      client.post(
          '/api/discuss/like-book-comment',
          client.authed({
            'scope': volumeId > 0 ? 'volume' : 'book',
            'book_id': bookId,
            'volume_id': volumeId,
            'chapter_id': 0,
            'comment_id': commentId,
            'root_comment_id': 0,
            'act': like ? 'like' : 'unlike',
          }));

  static Future<List<LKComment>> paragraphComments(
      int bookId, int chapterId, LKParagraph p) async {
    final d =
        await client.post('/api/new-content-read/get-paragraph-comments', {
      'book_id': bookId,
      'chapter_id': chapterId,
      'paragraph_hash': p.hash,
      'body_version': p.bodyVersion,
      'paragraph_no': p.paragraphNo,
      'page': 1,
      'pageSize': 20,
    });
    return _commentList(d);
  }

  static Future<void> publishParagraphComment(
          int bookId, int chapterId, LKParagraph p, String content) =>
      client.post(
          '/api/new-content-read/publish-paragraph-comment',
          client.authed({
            'book_id': bookId,
            'chapter_id': chapterId,
            'paragraph_hash': p.hash,
            'body_version': p.bodyVersion,
            'paragraph_no': p.paragraphNo,
            'content': content,
            'parent_comment_id': 0,
          }));

  static List<LKComment> _commentList(Map<String, dynamic> d) =>
      ((d['list'] as List?) ?? const [])
          .map((e) => LKComment.fromJson(e as Map<String, dynamic>))
          .toList();

  static Map<String, dynamic> _mediaJson(LKDynamicMedia media) => {
        'url': media.url,
        'res_url': media.resUrl,
        'res_path': media.resPath,
        'stored_url': media.storedUrl,
        'source_url': media.sourceUrl,
        'width': media.width,
        'height': media.height,
        'res_id': media.resId,
      };

  static Future<LKDynamicMedia> uploadCommentImage(String filePath) async {
    final d = await client.uploadMultipart(
        '/api/dynamic/upload-image-v1', filePath, {'scene': 'book_comment'});
    return LKDynamicMedia.fromJson(d);
  }

  // ==================== 书架 / 历史 / 进度 ====================

  static Future<bool> inShelf(int bookId) async {
    final d = await client.post('/api/new-content-read/get-book-library-state',
        client.authed({'book_id': bookId}));
    return (d['in_shelf'] as num?)?.toInt() == 1;
  }

  static Future<void> toggleShelf(int bookId, bool add) => client.post(
      '/api/new-content-read/toggle-book-shelf',
      client.authed({
        'book_id': bookId,
        'action': add ? 'add' : 'remove',
        'source': 'pc_web',
      }));

  static Future<List<LKBook>> bookshelf(int page, {int pageSize = 50}) async {
    final d = await client.post(
        '/api/bff/bookshelf-v1',
        client.authed(
            {'page': page, 'pageSize': LKClient.clampPageSize(pageSize)}));
    return _bookList(d);
  }

  static Future<List<LKHistoryItem>> cloudHistory(int page,
      {int pageSize = 50}) async {
    final d = await client.post(
        '/api/bff/history-v1',
        client.authed(
            {'page': page, 'pageSize': LKClient.clampPageSize(pageSize)}));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveHistory(
          int bookId, int volumeId, int chapterId, int progressPercent) =>
      client.post(
          '/api/new-content-read/save-book-history',
          client.authed({
            'book_id': bookId,
            'volume_id': volumeId,
            'chapter_id': chapterId,
            'progress_percent': progressPercent,
          }));

  /// 上报真实阅读会话的进度。服务器是否计入阅读任务、是否产生奖励，
  /// 由站点自行校验；客户端不在本地增加轻币。
  static Future<Map<String, dynamic>> reportReadingProgress({
    required int bookId,
    required int volumeId,
    required int chapterId,
    required int progressPercent,
    required int readDurationSeconds,
    int? activeSecondsDelta,
  }) =>
      client.post(
          '/api/new-content-read/report-reading-progress',
          client.authed({
            'book_id': bookId,
            'volume_id': volumeId,
            'chapter_id': chapterId,
            'progress_percent': progressPercent.clamp(0, 100),
            'read_duration_seconds': readDurationSeconds.clamp(0, 86400),
            'active_seconds_delta':
                (activeSecondsDelta ?? readDurationSeconds).clamp(0, 86400),
          }));

  static Future<void> deleteHistory(int bookId) => client.post(
      '/api/new-content-read/delete-book-history',
      client.authed({'book_id': bookId}));

  static Future<void> unlockChapter(int chapterId) => client.post(
      '/api/new-content-read/unlock-chapter',
      client.authed({'chapter_id': chapterId}));

  /// 读取阅读奖励状态，不触发领取。
  static Future<Map<String, dynamic>> welfareEarnCoinDetail() =>
      client.post('/api/bff/welfare-earn-coin-detail-v1', client.authed());

  /// 领取服务器确认可领取的阅读奖励。
  static Future<Map<String, dynamic>> claimWelfareEarnCoin(
      {String taskKey = ''}) {
    final body = <String, dynamic>{};
    if (taskKey.isNotEmpty) body['task_key'] = taskKey;
    return client.post(
        '/api/bff/claim-welfare-earn-coin-v1', client.authed(body));
  }

  // ==================== 动态 ====================

  static Future<LKDynamicPage> dynamicFeedPage(
      {String tab = 'mixed',
      String cursor = '',
      int page = 1,
      int pageSize = 20}) async {
    final d = await client.post(
        '/api/dynamic/get-feed-v1',
        client.authed({
          'tab': tab,
          'cursor': cursor,
          'page': page,
          'page_size': pageSize,
          'pageSize': pageSize,
        }));
    return LKDynamicPage.fromJson(d);
  }

  static Future<List<LKDynamicItem>> dynamicFeed(
      {String tab = 'mixed',
      String cursor = '',
      int page = 1,
      int pageSize = 20}) async {
    return (await dynamicFeedPage(
            tab: tab, cursor: cursor, page: page, pageSize: pageSize))
        .items;
  }

  static Future<List<LKComment>> dynamicComments(int dynamicId) async {
    final d = await client.post(
        '/api/dynamic/get-comments-v1',
        client.authed({
          'dynamic_id': dynamicId,
          'comment_id': 0,
          'cursor': '',
          'sort': 'latest',
          'page_size': 20,
          'pageSize': 20,
        }));
    return _commentList(d);
  }

  static Future<LKDynamicItem> dynamicDetail(int dynamicId) async {
    final d = await client.post(
        '/api/dynamic/get-detail-v1', client.authed({'dynamic_id': dynamicId}));
    final raw = d['dynamic'] ?? d['detail'] ?? d;
    if (raw is! Map) throw LKException(-1, '动态详情格式错误');
    return LKDynamicItem.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<Map<String, dynamic>> dynamicUnread() =>
      client.post('/api/dynamic/get-unread-v1', client.authed());

  static Future<void> markDynamicRead({int dynamicId = 0}) => client.post(
      '/api/dynamic/mark-read-v1',
      client.authed({
        'dynamic_id': dynamicId,
        'last_read_dynamic_id': dynamicId,
        'current_time': DateTime.now().toIso8601String(),
      }));

  static Future<LKComment> publishDynamicComment(int dynamicId, String content,
      {int replyCommentId = 0, List<LKDynamicMedia> media = const []}) async {
    final d = await client.post(
        '/api/dynamic/publish-comment-v1',
        client.authed({
          'dynamic_id': dynamicId,
          'content': content,
          'reply_comment_id': replyCommentId,
          'media_json': jsonEncode(media.map(_mediaJson).toList()),
        }));
    final raw = d['comment'] ?? d['reply'] ?? d;
    if (raw is! Map) throw LKException(-1, '评论响应格式错误');
    return LKComment.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<LKDynamicMedia> uploadDynamicImage(String filePath) async {
    final d = await client.uploadMultipart(
        '/api/dynamic/upload-image-v1', filePath, {'scene': 'dynamic'});
    return LKDynamicMedia.fromJson(d);
  }

  static Future<LKDynamicItem> publishShortDynamic(String content,
      {List<LKDynamicMedia> media = const []}) async {
    final d = await client.post(
        '/api/dynamic/publish-short-post-v1',
        client.authed({
          'title': '',
          'summary': content,
          'content': content,
          'media_json': jsonEncode(media.map(_mediaJson).toList()),
          'target_type': '',
          'feed_scope': 'follow',
          'visibility': 'public',
          'request_id': 'short-post-${DateTime.now().millisecondsSinceEpoch}',
        }));
    final raw = d['dynamic'] ?? d;
    if (raw is! Map) throw LKException(-1, '发布动态响应格式错误');
    return LKDynamicItem.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<Map<String, dynamic>> toggleDynamicCommentLike(
          int dynamicId, int commentId, bool like) =>
      client.post(
          '/api/dynamic/toggle-comment-vote-v1',
          client.authed({
            'dynamic_id': dynamicId,
            'comment_id': commentId,
            'act': like ? 'like' : 'unlike',
          }));

  static Future<Map<String, dynamic>> submitDynamicPollVote(
          int dynamicId, List<String> optionIds) =>
      client.post(
          '/api/dynamic/submit-poll-vote-v1',
          client.authed({
            'dynamic_id': dynamicId,
            'option_ids': optionIds,
            'request_id':
                'poll-vote-$dynamicId-${DateTime.now().millisecondsSinceEpoch}',
          }));

  static Future<void> toggleDynamicLike(int dynamicId, bool like) =>
      client.post(
          '/api/dynamic/toggle-like-v1',
          client.authed(
              {'dynamic_id': dynamicId, 'act': like ? 'like' : 'unlike'}));

  static Future<void> toggleDynamicFavorite(
          int dynamicId, bool fav) =>
      client.post(
          '/api/dynamic/toggle-favorite-v1',
          client.authed({
            'dynamic_id': dynamicId,
            'act': fav ? 'favorite' : 'unfavorite'
          }));

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
    final d =
        await client.post(path, client.authed({'page': page, 'page_size': 20}));
    return ((d['list'] as List?) ?? const [])
        .map((e) => LKMessageItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> markMessagesRead(String scope) => client.post(
      '/api/bff/message-mark-read-v1',
      client.authed({
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

  static Future<void> dmSend(int peerUid, String content) => client.post(
      '/api/bff/dm-send-v1',
      client.authed({
        'peer_uid': peerUid,
        'content_text': content,
        'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'nonce': DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        'client_msg_id': 'app-${DateTime.now().millisecondsSinceEpoch}',
      }));

  // ==================== 用户 / 设置 ====================

  static Future<Map<String, dynamic>> myHome() async =>
      client.post('/api/bff/my-home-v1', client.authed());

  static Future<Map<String, dynamic>> _profileLibraryCount(String path) async {
    try {
      return await client.post(
        path,
        client.authed({
          'page': 1,
          'pageSize': 1,
          'page_size': 1,
        }),
      );
    } catch (_) {
      // 个人资料仍可正常显示,某个统计接口失败时保留未知值。
      return const <String, dynamic>{};
    }
  }

  static int? _profilePageTotal(Map<String, dynamic> data) {
    final pageInfo = data['pagination'] is Map
        ? Map<String, dynamic>.from(data['pagination'] as Map)
        : data['page_info'] is Map
            ? Map<String, dynamic>.from(data['page_info'] as Map)
            : const <String, dynamic>{};
    final raw = pageInfo['total'] ??
        pageInfo['total_count'] ??
        pageInfo['count'] ??
        data['total'] ??
        data['total_count'] ??
        data['count'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  /// 当前登录用户的个人资料(只读)
  static Future<LKMyProfile> myProfile() async {
    final results = await Future.wait<Map<String, dynamic>>([
      client.post('/api/bff/my-home-v1', client.authed()),
      _profileLibraryCount('/api/bff/bookshelf-v1'),
      _profileLibraryCount('/api/bff/history-v1'),
    ]);
    final data = Map<String, dynamic>.from(results[0]);
    final bookshelfCount = _profilePageTotal(results[1]);
    final historyCount = _profilePageTotal(results[2]);
    if (bookshelfCount != null) data['bookshelf_count'] = bookshelfCount;
    if (historyCount != null) data['history_count'] = historyCount;
    return LKMyProfile.fromJson(data);
  }

  /// 当前登录用户的关注列表(只读)
  static Future<LKFollowPage> myFollowing(int page, {int pageSize = 20}) async {
    final d = await client.post(
        '/api/bff/user-following-v1',
        client.authed({
          'uid': client.session.uid,
          'page': page,
          'pageSize': LKClient.clampPageSize(pageSize),
        }));
    return LKFollowPage.fromJson(d,
        fallbackPage: page, fallbackPageSize: pageSize);
  }

  /// 当前登录用户的粉丝列表(只读)
  static Future<LKFollowPage> myFollowers(int page, {int pageSize = 20}) async {
    final d = await client.post(
        '/api/bff/user-followers-v1',
        client.authed({
          'uid': client.session.uid,
          'page': page,
          'pageSize': LKClient.clampPageSize(pageSize),
        }));
    return LKFollowPage.fromJson(d,
        fallbackPage: page, fallbackPageSize: pageSize);
  }

  /// 公开用户主页资料与公开发布(只读)
  static Future<LKPublicUserPage> publicUserHome(int uid, int page,
      {int pageSize = 20}) async {
    final d = await client.post(
        '/api/bff/public-user-home-v1',
        client.authed({
          'uid': uid,
          'page': page,
          'pageSize': LKClient.clampPageSize(pageSize),
        }),
        cacheKey: 'public_user_${client.session.uid}-$uid-$page-$pageSize',
        cacheTtl: const Duration(minutes: 5));
    return LKPublicUserPage.fromJson(d,
        fallbackPage: page, fallbackPageSize: pageSize);
  }

  /// 公开用户书架(只读,不附带会话凭据)
  static Future<LKPublicBookshelfPage> publicUserBookshelf(int uid, int page,
      {int pageSize = 20}) async {
    final d = await client.post(
        '/api/bff/public-user-bookshelf-v1',
        {
          'uid': uid,
          'page': page,
          'pageSize': LKClient.clampPageSize(pageSize),
        },
        cacheKey: 'public_bookshelf_$uid-$page-$pageSize',
        cacheTtl: const Duration(minutes: 5));
    return LKPublicBookshelfPage.fromJson(d,
        fallbackPage: page, fallbackPageSize: pageSize);
  }

  /// 用户公开动态(只读)
  static Future<LKDynamicPage> publicUserDynamics(int uid,
      {String cursor = '', int pageSize = 20}) async {
    final size = LKClient.clampPageSize(pageSize);
    final d = await client.post(
        '/api/dynamic/get-user-feed-v1',
        client.authed({
          'author_uid': uid,
          'cursor': cursor,
          'page_size': size,
          'pageSize': size,
        }),
        cacheKey:
            'public_dynamic_${client.session.uid}-$uid-${Uri.encodeComponent(cursor)}-$size',
        cacheTtl: const Duration(minutes: 2));
    return LKDynamicPage.fromJson(d);
  }

  /// 当前轻币余额
  static Future<int> myCoins() async {
    final d = await client.post('/api/bff/my-home-v1', client.authed());
    final profile = d['profile'] as Map<String, dynamic>?;
    return (profile?['coin'] as num?)?.toInt() ?? 0;
  }

  static Future<void> toggleFollow(int uid, bool follow) => client.post(
      '/api/bff/toggle-user-follow-v1',
      client.authed({'uid': uid, 'act': follow ? 'follow' : 'unfollow'}));

  static Future<List<LKMedal>> myMedals() async {
    final d = await client.post('/api/bff/my-medals-v1', client.authed());
    final raw = d['list'] ?? d['medals'] ?? d['items'] ?? const [];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LKMedal.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.image.isNotEmpty || e.medalId > 0)
        .toList();
  }

  static Future<Map<String, dynamic>> medalCenter() => client.post(
      '/api/bff/my-medal-center-v1',
      client.authed({'page': 1, 'pageSize': 50, 'page_size': 50}));

  static Future<void> exchangeMedal(int goodsId) => client.post(
      '/api/bff/exchange-my-medal-v1',
      client.authed({'medal_id': goodsId, 'goods_id': goodsId}));

  static Future<void> claimMedal(int taskId) => client.post(
      '/api/bff/claim-my-medal-v1',
      client.authed({'task_id': taskId, 'medal_id': taskId}));

  // 福利中心接口统一沿用当前客户端的正式站点地址，不读取或复用其他 APK 的服务器配置。
  static Future<Map<String, dynamic>> welfareHome() => client.post(
      '/api/bff/welfare-home-v1', client.authed({'includeTaskList': 1}));

  static Future<Map<String, dynamic>> welfareSignDetail() =>
      client.post('/api/bff/welfare-sign-detail-v1', client.authed());

  static Future<Map<String, dynamic>> welfareTaskList() =>
      client.post('/api/bff/welfare-task-list-v1', client.authed());

  /// 读取“睡觉赚轻币”的服务器状态与倒计时，不改变任务状态。
  static Future<Map<String, dynamic>> welfareSleepDetail() =>
      client.post('/api/bff/welfare-sleep-detail-v1', client.authed());

  /// 开始一次由服务器计时的睡眠任务。
  static Future<Map<String, dynamic>> startWelfareSleep() =>
      client.post('/api/bff/start-welfare-sleep-v1', client.authed());

  /// 领取服务器确认已完成的睡眠奖励。
  static Future<Map<String, dynamic>> claimWelfareSleep() =>
      client.post('/api/bff/claim-welfare-sleep-v1', client.authed());

  static Future<Map<String, dynamic>> claimWelfareSign() =>
      client.post('/api/bff/claim-welfare-sign-v1', client.authed());

  static Future<Map<String, dynamic>> claimWelfareTask(
      {int taskId = 0, String taskKey = ''}) {
    final body = <String, dynamic>{};
    if (taskId > 0) body['task_id'] = taskId;
    if (taskKey.isNotEmpty) body['task_key'] = taskKey;
    return client.post('/api/bff/claim-welfare-task-v1', client.authed(body));
  }

  static Future<Map<String, dynamic>> welfareTreasureBoxDetail() =>
      client.post('/api/bff/welfare-treasure-box-detail-v1', client.authed());

  static Future<Map<String, dynamic>> claimWelfareTreasureBox(
          {int campaignId = 0, int campaignDay = 0}) =>
      client.post(
          '/api/bff/claim-welfare-treasure-box-v1',
          client.authed({
            'campaign_id': campaignId,
            'campaign_day': campaignDay,
          }));

  static Future<Map<String, dynamic>> welfareCoinRecords(int page,
      {int pageSize = 30}) async {
    final size = LKClient.clampPageSize(pageSize);
    return client.post('/api/bff/welfare-coin-records-v1',
        client.authed({'page': page, 'pageSize': size, 'page_size': size}));
  }

  static Future<void> toggleMedal(int medalId, bool equip) => client.post(
      '/api/bff/toggle-my-medal-v1',
      client.authed({'medal_id': medalId, 'act': equip ? 'equip' : 'unequip'}));

  static Future<Map<String, dynamic>> about() async =>
      client.post('/api/bff/settings-about-v1', const {});

  /// 检查更新:GitHub Releases 最新发布(无发布时返回 null)
  static Future<LKRelease?> latestRelease() async {
    late final http.Response resp;
    try {
      resp = await http.get(
          Uri.parse(
              'https://api.github.com/repos/hesitation-snow/yomiru/releases/latest'),
          headers: const {
            'User-Agent': 'LKFlutter',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          }).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw LKException(-1, '更新检查连接超时，请稍后重试');
    } catch (_) {
      throw LKException(-1, '更新检查连接失败，请稍后重试');
    }
    if (resp.statusCode == 404) return null; // 尚未发布任何版本
    if (resp.statusCode != 200) {
      if (resp.statusCode == 403 &&
          resp.headers['x-ratelimit-remaining'] == '0') {
        throw LKException(403, 'GitHub 更新接口暂时达到访问限制，请稍后重试');
      }
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
