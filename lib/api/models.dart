// 数据模型(手写 fromJson,字段与服务端 snake_case 一一对应)

class LKUser {
  final int uid;
  final String nickname;
  final String avatar;
  final String sign;
  LKUser({this.uid = 0, this.nickname = '', this.avatar = '', this.sign = ''});
  factory LKUser.fromJson(Map<String, dynamic> j) => LKUser(
        uid: (j['uid'] as num?)?.toInt() ?? 0,
        nickname: (j['nickname'] as String?) ?? '',
        avatar: (j['avatar'] as String?) ?? '',
        sign: (j['sign'] as String?) ?? (j['signature'] as String?) ?? '',
      );
}

class LKBook {
  final int bookId;
  final String title;
  final String authorName;
  final String coverUrl;
  final String summary;
  final List<String> tags;
  final int wordCount;
  final int volumeCount;
  final int chapterCount;
  final int defaultVolumeId;
  final int defaultChapterId;
  final String serialStatus;
  final bool isCompleted;
  final String lastReadChapterTitle;
  final int unreadChapterCount;
  final double ratingScore;
  final String updatedAt;
  LKBook({
    this.bookId = 0, this.title = '', this.authorName = '', this.coverUrl = '',
    this.summary = '', this.tags = const [], this.wordCount = 0,
    this.volumeCount = 0, this.chapterCount = 0, this.defaultVolumeId = 0,
    this.defaultChapterId = 0, this.serialStatus = '', this.isCompleted = false,
    this.lastReadChapterTitle = '', this.unreadChapterCount = 0, this.ratingScore = 0,
    this.updatedAt = '',
  });
  factory LKBook.fromJson(Map<String, dynamic> j) => LKBook(
        bookId: (j['book_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        authorName: (j['author_name'] as String?) ?? '',
        coverUrl: (j['cover_url'] as String?) ?? '',
        summary: (j['summary'] as String?) ??
            (j['summary_short'] as String?) ??
            '',
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
        volumeCount: (j['volume_count'] as num?)?.toInt() ?? 0,
        chapterCount: (j['chapter_count'] as num?)?.toInt() ?? 0,
        defaultVolumeId: (j['default_volume_id'] as num?)?.toInt() ?? 0,
        defaultChapterId: (j['default_chapter_id'] as num?)?.toInt() ?? 0,
        serialStatus: (j['serial_status'] as String?) ?? '',
        isCompleted: (j['is_completed'] as num?)?.toInt() == 1,
        lastReadChapterTitle: (j['last_read_chapter_title'] as String?) ?? '',
        unreadChapterCount: (j['unread_chapter_count'] as num?)?.toInt() ?? 0,
        ratingScore: (j['rating_score'] as num?)?.toDouble() ?? 0,
        updatedAt: (j['latest_book_updated_at'] as String?) ??
            (j['updated_at'] as String?) ??
            '',
      );
}

class LKVolume {
  final int volumeId;
  final String title;
  final String intro;
  LKVolume({this.volumeId = 0, this.title = '', this.intro = ''});
  factory LKVolume.fromJson(Map<String, dynamic> j) => LKVolume(
        volumeId: (j['volume_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        intro: (j['intro'] as String?) ?? '',
      );
}

class LKChapter {
  final int chapterId;
  final int chapterNo;
  final String title;
  final int wordCount;
  final bool locked;
  final bool unlocked;
  final String accessType;
  LKChapter({
    this.chapterId = 0, this.chapterNo = 0, this.title = '', this.wordCount = 0,
    this.locked = false, this.unlocked = false, this.accessType = '',
  });
  factory LKChapter.fromJson(Map<String, dynamic> j) => LKChapter(
        chapterId: (j['chapter_id'] as num?)?.toInt() ?? 0,
        chapterNo: (j['chapter_no'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
        locked: (j['locked'] as num?)?.toInt() == 1,
        unlocked: (j['unlocked'] as num?)?.toInt() == 1,
        accessType: (j['access_type'] as String?) ?? '',
      );
}

class LKChapterDetail {
  final int chapterId;
  final int volumeId;
  final String title;
  final String bookTitle;
  final String bodyText;
  final String? bodyHtml;
  final bool locked;
  final bool unlocked;
  final int coinPrice;
  final int? prevChapterId;
  final String? prevTitle;
  final int? prevVolumeId;
  final int? nextChapterId;
  final String? nextTitle;
  final int? nextVolumeId;
  LKChapterDetail({
    this.chapterId = 0, this.volumeId = 0, this.title = '', this.bookTitle = '', this.bodyText = '',
    this.bodyHtml, this.locked = false, this.unlocked = false, this.coinPrice = 0,
    this.prevChapterId, this.prevTitle, this.prevVolumeId,
    this.nextChapterId, this.nextTitle, this.nextVolumeId,
  });
  factory LKChapterDetail.fromJson(Map<String, dynamic> j) {
    String body = '';
    String? html;
    final snap = j['body_snapshot'] as Map<String, dynamic>?;
    if (snap != null) {
      if (snap['body_text'] is String) body = snap['body_text'] as String;
      if (snap['body_html'] is String) html = snap['body_html'] as String;
    }
    if (body.isEmpty) {
      final prev = j['render_preview'] as Map<String, dynamic>?;
      if (prev != null && prev['body_text'] is String) body = prev['body_text'] as String;
    }
    final nav = j['navigation'] as Map<String, dynamic>?;
    // prev_chapter 可能是数组;next_chapter 可能是对象、也可能是数组(服务端形态不一)
    final prevList = nav?['prev_chapter'] as List?;
    final prev0 = (prevList != null && prevList.isNotEmpty)
        ? prevList.first as Map<String, dynamic>
        : null;
    final nextRaw = nav?['next_chapter'];
    Map<String, dynamic>? next;
    if (nextRaw is Map<String, dynamic>) {
      next = nextRaw;
    } else if (nextRaw is List &&
        nextRaw.isNotEmpty &&
        nextRaw.first is Map<String, dynamic>) {
      next = nextRaw.first as Map<String, dynamic>;
    }
    return LKChapterDetail(
      chapterId: (j['chapter_id'] as num?)?.toInt() ?? 0,
      volumeId: (j['volume_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] as String?) ?? '',
      bookTitle: (j['book_title'] as String?) ?? '',
      bodyText: body,
      bodyHtml: html,
      locked: (j['locked'] as num?)?.toInt() == 1,
      unlocked: (j['unlocked'] as num?)?.toInt() == 1,
      coinPrice: (j['coin_price'] as num?)?.toInt() ?? 0,
      prevChapterId: prev0 != null ? (prev0['chapter_id'] as num?)?.toInt() : null,
      prevTitle: prev0 != null ? (prev0['title'] as String?) : null,
      prevVolumeId: prev0 != null ? (prev0['volume_id'] as num?)?.toInt() : null,
      nextChapterId: next != null ? (next['chapter_id'] as num?)?.toInt() : null,
      nextTitle: next != null ? (next['title'] as String?) : null,
      nextVolumeId: next != null ? (next['volume_id'] as num?)?.toInt() : null,
    );
  }
}

class LKParagraph {
  final int paragraphNo;
  final String hash;
  final int bodyVersion;
  final String text;
  LKParagraph({this.paragraphNo = 0, this.hash = '', this.bodyVersion = 0, this.text = ''});
  factory LKParagraph.fromJson(Map<String, dynamic> j) => LKParagraph(
        paragraphNo: (j['paragraph_no'] as num?)?.toInt() ?? 0,
        hash: (j['paragraph_hash'] as String?) ?? '',
        bodyVersion: (j['body_version'] as num?)?.toInt() ?? 0,
        text: (j['paragraph_text'] as String?) ?? (j['paragraph_excerpt'] as String?) ?? '',
      );
}

/// 评论表情(单个)
class LKEmojiItem {
  final String id;
  final String code; // 如 {:neko3:} 或原生 emoji 字符
  final String url; // 图片地址(原生 emoji 时为空字符串)
  LKEmojiItem({this.id = '', this.code = '', this.url = ''});
  bool get isImage => url.startsWith('http');
  factory LKEmojiItem.fromJson(Map<String, dynamic> j) {
    // id 可能是数字或字符串("13")
    final rawId = j['id'];
    return LKEmojiItem(
      id: rawId is num ? rawId.toString() : (rawId as String? ?? ''),
      code: (j['code'] as String?) ?? '',
      url: (j['url'] as String?) ?? '',
    );
  }
}

/// 评论表情分组
class LKEmojiGroup {
  final String name;
  final String icon; // 分组图标(网络图)
  final List<LKEmojiItem> items;
  LKEmojiGroup({this.name = '', this.icon = '', this.items = const []});
  factory LKEmojiGroup.fromJson(Map<String, dynamic> j) => LKEmojiGroup(
        name: (j['name'] as String?) ?? '',
        icon: (j['icon'] as String?) ?? '',
        items: ((j['items'] as List?) ?? const [])
            .map((e) => LKEmojiItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LKComment {
  final int commentId;
  final String nickname;
  final String avatar;
  final String content;
  final int likeCount;
  final String time;
  final bool liked;
  LKComment({
    this.commentId = 0, this.nickname = '', this.avatar = '', this.content = '',
    this.likeCount = 0, this.time = '', this.liked = false,
  });
  factory LKComment.fromJson(Map<String, dynamic> j) {
    final author = (j['author'] as Map<String, dynamic>?) ??
        (j['user'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final inter = (j['interaction_state'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    return LKComment(
      commentId: (j['comment_id'] as num?)?.toInt() ?? 0,
      nickname: (author['nickname'] as String?) ?? '',
      avatar: (author['avatar'] as String?) ?? '',
      content: (j['content'] as String?) ?? (j['content_text'] as String?) ?? '',
      likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
      time: (j['publish_time'] as String?) ?? (j['created_at'] as String?) ?? '',
      liked: (j['liked'] as num?)?.toInt() == 1 ||
          (inter['liked'] as num?)?.toInt() == 1,
    );
  }
}

class LKHistoryItem {
  final int bookId;
  final String title;
  final String authorName;
  final String coverUrl;
  final int volumeId;
  final int chapterId;
  final String chapterTitle;
  final int progressPercent;
  final String lastReadAt;
  final int unreadChapters;
  LKHistoryItem({
    this.bookId = 0, this.title = '', this.authorName = '', this.coverUrl = '',
    this.volumeId = 0, this.chapterId = 0, this.chapterTitle = '',
    this.progressPercent = 0, this.lastReadAt = '', this.unreadChapters = 0,
  });
  factory LKHistoryItem.fromJson(Map<String, dynamic> j) {
    final h = (j['history'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return LKHistoryItem(
      bookId: (j['book_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] as String?) ?? '',
      authorName: (j['author_name'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
      volumeId: (h['volume_id'] as num?)?.toInt() ?? (j['default_volume_id'] as num?)?.toInt() ?? 0,
      chapterId: (h['chapter_id'] as num?)?.toInt() ?? (j['last_read_chapter_id'] as num?)?.toInt() ?? 0,
      chapterTitle: (h['chapter_title'] as String?) ?? (j['last_read_chapter_title'] as String?) ?? '',
      progressPercent: (h['progress_percent'] as num?)?.toInt() ?? 0,
      lastReadAt: (h['last_read_at'] as String?) ?? '',
      unreadChapters: (j['unread_chapter_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class LKDynamicItem {
  final int dynamicId;
  final String eventType;
  final String nickname;
  final String avatar;
  final String summary;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final String time;
  final int bookId; // 作品卡(带作品链接的动态)
  final String bookTitle;
  final String bookCover;
  LKDynamicItem({
    this.dynamicId = 0, this.eventType = '', this.nickname = '', this.avatar = '',
    this.summary = '', this.likeCount = 0, this.commentCount = 0, this.liked = false,
    this.time = '', this.bookId = 0, this.bookTitle = '', this.bookCover = '',
  });
  factory LKDynamicItem.fromJson(Map<String, dynamic> j) {
    final author = (j['author'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final stats = (j['stats'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final ist = (j['interaction_state'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final brief = (j['target_brief'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return LKDynamicItem(
      dynamicId: (j['dynamic_id'] as num?)?.toInt() ?? 0,
      eventType: (j['event_type'] as String?) ?? '',
      nickname: (author['nickname'] as String?) ?? '',
      avatar: (author['avatar'] as String?) ?? '',
      summary: (j['summary'] as String?) ?? (j['content'] as String?) ?? '',
      likeCount: (stats['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (stats['comment_count'] as num?)?.toInt() ?? 0,
      liked: (ist['liked'] as num?)?.toInt() == 1,
      time: (j['feed_time'] as String?) ?? (j['publish_time'] as String?) ?? '',
      bookId: (brief['book_id'] as num?)?.toInt() ?? (brief['target_id'] as num?)?.toInt() ?? 0,
      bookTitle: (brief['title'] as String?) ?? '',
      bookCover: (brief['cover_url'] as String?) ?? '',
    );
  }
}

class LKConversation {
  final int conversationId;
  final int peerUid;
  final String peerName;
  final String peerAvatar;
  final String lastMessage;
  final int unread;
  LKConversation({
    this.conversationId = 0, this.peerUid = 0, this.peerName = '',
    this.peerAvatar = '', this.lastMessage = '', this.unread = 0,
  });
  factory LKConversation.fromJson(Map<String, dynamic> j) {
    final peerRaw = j['peer'] ?? j['user'];
    final peer = peerRaw is Map<String, dynamic>
        ? peerRaw
        : const <String, dynamic>{};
    return LKConversation(
      conversationId: (j['conversation_id'] as num?)?.toInt() ?? 0,
      peerUid: (j['peer_uid'] as num?)?.toInt() ?? (peer['uid'] as num?)?.toInt() ?? 0,
      peerName: (peer['nickname'] as String?) ?? '',
      peerAvatar: (peer['avatar'] as String?) ?? '',
      // last_message 是对象 {message_id, preview, sender_uid, time}
      lastMessage: _msgText(j['last_message']),
      unread: (j['unread'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 消息文本:可能是 String 或 {content/preview/text} 对象
String _msgText(dynamic v) {
  if (v is String) return v;
  if (v is Map) {
    for (final k in const ['preview', 'content', 'text', 'summary']) {
      final s = v[k];
      if (s is String && s.isNotEmpty) return s;
    }
  }
  return '';
}

class LKDMMessage {
  final int id;
  final int senderUid;
  final String content;
  final String time;
  bool isMine(int myUid) => senderUid == myUid;
  LKDMMessage({this.id = 0, this.senderUid = 0, this.content = '', this.time = ''});
  factory LKDMMessage.fromJson(Map<String, dynamic> j) => LKDMMessage(
        id: (j['id'] as num?)?.toInt() ?? (j['message_id'] as num?)?.toInt() ?? 0,
        senderUid: (j['sender_uid'] as num?)?.toInt() ?? 0,
        content: (j['content_text'] as String?) ?? (j['content'] as String?) ?? '',
        time: (j['created_at'] as String?) ?? '',
      );
}

class LKMessageItem {
  final String title;
  final String content;
  final String nickname;
  final String avatar;
  final String time;
  LKMessageItem({this.title = '', this.content = '', this.nickname = '', this.avatar = '', this.time = ''});
  factory LKMessageItem.fromJson(Map<String, dynamic> j) {
    // user 可能是对象、也可能是空数组(如系统消息),安全转换
    final userRaw = j['user'] ?? j['author'];
    final peer =
        userRaw is Map<String, dynamic> ? userRaw : const <String, dynamic>{};
    return LKMessageItem(
      title: (j['title'] as String?) ?? '',
      content: (j['content'] as String?) ?? (j['summary'] as String?) ?? (j['body'] as String?) ?? '',
      nickname: (peer['nickname'] as String?) ?? '',
      avatar: (peer['avatar'] as String?) ?? '',
      time: (j['created_at'] as String?) ?? '',
    );
  }
}

/// GitHub Release 信息(检查更新)
class LKRelease {
  final String tag; // 如 v0.1.0
  final String name;
  final String url;
  final String body;
  LKRelease({this.tag = '', this.name = '', this.url = '', this.body = ''});
  factory LKRelease.fromJson(Map<String, dynamic> j) => LKRelease(
        tag: (j['tag_name'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        url: (j['html_url'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
      );
}

/// 版本号比较(忽略前导 v 与构建号),a>b 返回 1,a<b 返回 -1
int compareVersions(String a, String b) {
  final pa = a.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.');
  final pb = b.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? (int.tryParse(pa[i]) ?? 0) : 0;
    final y = i < pb.length ? (int.tryParse(pb[i]) ?? 0) : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}
