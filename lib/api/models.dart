import 'dart:convert';

// 数据模型(手写 fromJson,字段与服务端 snake_case 一一对应)

Map<String, dynamic>? _jsonMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

Map<String, dynamic>? _firstJsonMap(dynamic value) {
  final direct = _jsonMap(value);
  if (direct != null) return direct;
  if (value is List) {
    for (final item in value) {
      final map = _jsonMap(item);
      if (map != null) return map;
    }
  }
  return null;
}

bool _jsonFlag(dynamic value) =>
    value == true || value == 1 || value == '1' || value == 'true';

int _jsonInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _jsonIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

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

/// 当前登录用户的个人页资料(只读)
class LKMyProfile {
  final int uid;
  final String nickname;
  final String avatar;
  final String signature;
  final String levelName;
  final int level;
  final int coin;
  final bool isBrave;
  final int followersCount;
  final int followingCount;
  final int postCount;
  final int? bookshelfCount;
  final int? historyCount;
  final List<LKMedal> medals;

  LKMyProfile({
    this.uid = 0,
    this.nickname = '',
    this.avatar = '',
    this.signature = '',
    this.levelName = '',
    this.level = 0,
    this.coin = 0,
    this.isBrave = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
    this.bookshelfCount,
    this.historyCount,
    this.medals = const [],
  });

  factory LKMyProfile.fromJson(Map<String, dynamic> j) {
    final profile = _jsonMap(j['profile']) ?? j;
    final stats = _jsonMap(j['stats']) ?? const <String, dynamic>{};
    final balance = _jsonMap(profile['balance']) ?? const <String, dynamic>{};
    final levelObject = _jsonMap(profile['level']);
    final rawMedals = profile['medals'] ??
        profile['medal_list'] ??
        profile['equipped_medals'] ??
        j['medals'];
    final medals = rawMedals is List
        ? rawMedals
            .whereType<Map>()
            .map((e) => LKMedal.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.image.isNotEmpty)
            .take(5)
            .toList()
        : const <LKMedal>[];
    final rawLevel =
        levelObject?['level'] ?? profile['level_number'] ?? profile['level'];
    final levelName = (profile['level_name'] ??
            profile['levelName'] ??
            profile['level_title'] ??
            profile['group_name'] ??
            profile['user_group_name'] ??
            profile['rank_name'] ??
            profile['role_name'] ??
            levelObject?['name'] ??
            levelObject?['title'] ??
            '')
        .toString();
    return LKMyProfile(
      uid: _jsonInt(profile['uid'] ?? profile['user_id'] ?? profile['id']),
      nickname: (profile['nickname'] ?? profile['username'] ?? '').toString(),
      avatar: (profile['avatar'] ?? profile['avatar_url'] ?? '').toString(),
      signature: (profile['sign'] ?? profile['signature'] ?? '').toString(),
      levelName: levelName,
      level: _jsonInt(rawLevel),
      coin: _jsonInt(profile['coin'] ??
          profile['light_coin'] ??
          profile['lightCoin'] ??
          balance['coin'] ??
          balance['light_coin'] ??
          balance['lightCoin'] ??
          profile['balance']),
      isBrave: _jsonFlag(profile['passer'] ??
          profile['is_passer'] ??
          profile['isBrave'] ??
          profile['brave']),
      followersCount: _jsonInt(stats['followers'] ??
          stats['fans'] ??
          stats['fans_count'] ??
          profile['followers'] ??
          profile['fans_count']),
      followingCount: _jsonInt(stats['following'] ??
          stats['following_count'] ??
          profile['following'] ??
          profile['following_count']),
      postCount: _jsonInt(stats['publish_articles'] ??
          stats['post_count'] ??
          stats['posts'] ??
          profile['post_count'] ??
          j['publish_articles'] ??
          j['post_count']),
      bookshelfCount: _jsonIntOrNull(stats['bookshelf_count'] ??
          stats['my_bookshelf_count'] ??
          stats['my_bookshelf_count_value'] ??
          profile['bookshelf_count'] ??
          profile['my_bookshelf_count'] ??
          j['bookshelf_count'] ??
          j['my_bookshelf_count'] ??
          j['my_bookshelf_count_value'] ??
          j['bookshelfCount']),
      historyCount: _jsonIntOrNull(stats['history_count'] ??
          stats['my_history_count'] ??
          stats['my_history_count_value'] ??
          stats['reading_count'] ??
          profile['history_count'] ??
          profile['my_history_count'] ??
          j['history_count'] ??
          j['my_history_count'] ??
          j['my_history_count_value'] ??
          j['reading_count'] ??
          j['historyCount']),
      medals: medals,
    );
  }
}

/// 关注/粉丝列表中的用户(只读)
class LKFollowUser {
  final int uid;
  final String nickname;
  final String avatar;
  final String signature;
  final String levelName;
  final bool isBrave;
  final bool followed;

  LKFollowUser({
    this.uid = 0,
    this.nickname = '',
    this.avatar = '',
    this.signature = '',
    this.levelName = '',
    this.isBrave = false,
    this.followed = false,
  });

  factory LKFollowUser.fromJson(Map<String, dynamic> j) {
    final relation = _jsonMap(j['relation']) ??
        _jsonMap(j['interaction_state']) ??
        const <String, dynamic>{};
    final levelObject = _jsonMap(j['level']);
    return LKFollowUser(
      uid: _jsonInt(j['uid'] ?? j['user_id'] ?? j['id']),
      nickname:
          (j['nickname'] ?? j['username'] ?? j['name'] ?? j['nick_name'] ?? '')
              .toString(),
      avatar: (j['avatar'] ?? j['avatar_url'] ?? '').toString(),
      signature: (j['sign'] ?? j['signature'] ?? '').toString(),
      levelName: (j['level_name'] ??
              j['levelName'] ??
              j['level_title'] ??
              j['group_name'] ??
              levelObject?['name'] ??
              levelObject?['title'] ??
              '')
          .toString(),
      isBrave: _jsonFlag(j['passer'] ??
          j['is_passer'] ??
          j['isBrave'] ??
          j['brave'] ??
          relation['is_passer'] ??
          relation['isBrave']),
      followed: _jsonFlag(relation['followed'] ??
          relation['is_followed'] ??
          j['followed'] ??
          j['is_followed']),
    );
  }

  LKFollowUser copyWith({bool? followed}) => LKFollowUser(
        uid: uid,
        nickname: nickname,
        avatar: avatar,
        signature: signature,
        levelName: levelName,
        isBrave: isBrave,
        followed: followed ?? this.followed,
      );
}

class LKFollowPage {
  final List<LKFollowUser> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  LKFollowPage({
    this.items = const [],
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.hasMore = false,
  });

  factory LKFollowPage.fromJson(Map<String, dynamic> j,
      {int fallbackPage = 1, int fallbackPageSize = 20}) {
    final rawList = j['items'] ?? j['list'] ?? j['cards'];
    final items = rawList is List
        ? rawList
            .whereType<Map>()
            .map((e) => LKFollowUser.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <LKFollowUser>[];
    final pageInfo = _jsonMap(j['pagination']) ??
        _jsonMap(j['page_info']) ??
        const <String, dynamic>{};
    final page = _jsonInt(pageInfo['page'] ??
        pageInfo['current_page'] ??
        j['page'] ??
        fallbackPage);
    final pageSize = _jsonInt(pageInfo['page_size'] ??
        pageInfo['pageSize'] ??
        pageInfo['per_page'] ??
        j['page_size'] ??
        j['pageSize'] ??
        fallbackPageSize);
    final total = _jsonInt(pageInfo['total'] ??
        pageInfo['total_count'] ??
        pageInfo['count'] ??
        j['total'] ??
        items.length);
    final rawHasMore = pageInfo['has_more'] ??
        pageInfo['hasMore'] ??
        pageInfo['has_next'] ??
        j['has_more'] ??
        j['hasMore'] ??
        j['has_next'];
    final hasMore = rawHasMore == null
        ? (total > page * pageSize || items.length >= pageSize)
        : _jsonFlag(rawHasMore);
    return LKFollowPage(
      items: items,
      page: page > 0 ? page : fallbackPage,
      pageSize: pageSize > 0 ? pageSize : fallbackPageSize,
      total: total,
      hasMore: hasMore,
    );
  }
}

class LKMedal {
  final int medalId;
  final String name;
  final String image;
  final bool equipped;

  LKMedal({
    this.medalId = 0,
    this.name = '',
    this.image = '',
    this.equipped = false,
  });

  factory LKMedal.fromJson(Map<String, dynamic> j) => LKMedal(
        medalId: _jsonInt(j['medal_id'] ?? j['id'] ?? j['goods_id']),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        image: (j['image'] ?? j['img'] ?? j['icon'] ?? j['icon_url'] ?? '')
            .toString(),
        equipped: _jsonFlag(j['equipped'] ?? j['equip'] ?? j['is_equipped']),
      );
}

/// 公开用户主页资料
class LKPublicUserProfile {
  final int uid;
  final String nickname;
  final String avatar;
  final String signature;
  final String levelName;
  final int level;
  final bool isBrave;
  final int followersCount;
  final int followingCount;
  final int postCount;
  final List<LKMedal> medals;
  final bool followed;
  final bool isSelf;
  final bool canFollow;
  final bool publicBookshelf;

  const LKPublicUserProfile({
    this.uid = 0,
    this.nickname = '',
    this.avatar = '',
    this.signature = '',
    this.levelName = '',
    this.level = 0,
    this.isBrave = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
    this.medals = const [],
    this.followed = false,
    this.isSelf = false,
    this.canFollow = true,
    this.publicBookshelf = false,
  });

  factory LKPublicUserProfile.fromJson(Map<String, dynamic> j) {
    final profile = _jsonMap(j['profile']) ?? j;
    final stats = _jsonMap(j['stats']) ?? const <String, dynamic>{};
    final relation = _jsonMap(j['relation']) ?? const <String, dynamic>{};
    final modules = _jsonMap(j['modules']) ?? const <String, dynamic>{};
    final privacy = _jsonMap(j['privacy']) ?? const <String, dynamic>{};
    final levelObject = _jsonMap(profile['level']);
    final rawMedals = profile['medals'] ??
        profile['medal_list'] ??
        profile['equipped_medals'];
    final medals = rawMedals is List
        ? rawMedals
            .whereType<Map>()
            .map((e) => LKMedal.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.image.isNotEmpty)
            .take(5)
            .toList()
        : const <LKMedal>[];
    final rawCanFollow = relation['can_follow'];
    return LKPublicUserProfile(
      uid: _jsonInt(profile['uid'] ?? profile['user_id'] ?? profile['id']),
      nickname:
          (profile['nickname'] ?? profile['username'] ?? profile['name'] ?? '')
              .toString(),
      avatar: (profile['avatar'] ?? profile['avatar_url'] ?? '').toString(),
      signature: (profile['sign'] ?? profile['signature'] ?? '').toString(),
      levelName: (profile['level_name'] ??
              profile['levelName'] ??
              profile['level_title'] ??
              profile['group_name'] ??
              profile['user_group_name'] ??
              profile['rank_name'] ??
              levelObject?['name'] ??
              levelObject?['title'] ??
              '')
          .toString(),
      level: _jsonInt(
          levelObject?['level'] ?? profile['level_number'] ?? profile['level']),
      isBrave: _jsonFlag(profile['passer'] ??
          profile['is_passer'] ??
          profile['isBrave'] ??
          profile['brave']),
      followersCount: _jsonInt(stats['followers'] ??
          stats['fans'] ??
          stats['fans_count'] ??
          profile['followers'] ??
          profile['fans_count']),
      followingCount: _jsonInt(stats['following'] ??
          stats['following_count'] ??
          profile['following'] ??
          profile['following_count']),
      postCount: _jsonInt(stats['publish_articles'] ??
          stats['post_count'] ??
          stats['posts'] ??
          profile['post_count']),
      medals: medals,
      followed: _jsonFlag(relation['followed'] ??
          relation['is_followed'] ??
          profile['followed']),
      isSelf: _jsonFlag(relation['is_self'] ?? relation['self']),
      canFollow: rawCanFollow == null || _jsonFlag(rawCanFollow),
      publicBookshelf: _jsonFlag(modules['public_bookshelf'] ??
          modules['publicBookshelf'] ??
          privacy['bookshelf_visible'] ??
          privacy['bookshelfVisible']),
    );
  }
}

class LKPublicBook {
  final int bookId;
  final String title;
  final String coverUrl;
  final String summary;
  final String updatedAt;
  final String typeText;

  LKPublicBook({
    this.bookId = 0,
    this.title = '',
    this.coverUrl = '',
    this.summary = '',
    this.updatedAt = '',
    this.typeText = '',
  });

  factory LKPublicBook.fromJson(Map<String, dynamic> j) => LKPublicBook(
        bookId: _jsonInt(j['book_id'] ??
            j['bookId'] ??
            j['article_id'] ??
            j['aid'] ??
            j['id']),
        title: (j['title'] ?? j['subject'] ?? j['name'] ?? '').toString(),
        coverUrl: (j['cover_url'] ?? j['cover'] ?? j['image'] ?? j['img'] ?? '')
            .toString(),
        summary:
            (j['summary'] ?? j['description'] ?? j['content'] ?? '').toString(),
        updatedAt: (j['updated_at'] ??
                j['updatedAt'] ??
                j['created_at'] ??
                j['createdAt'] ??
                '')
            .toString(),
        typeText: (j['type_text'] ??
                j['typeText'] ??
                j['category_name'] ??
                j['kind'] ??
                '')
            .toString(),
      );
}

class LKPublicUserPage {
  final LKPublicUserProfile profile;
  final List<LKPublicBook> publications;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  LKPublicUserPage({
    this.profile = const LKPublicUserProfile(),
    this.publications = const [],
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.hasMore = false,
  });

  factory LKPublicUserPage.fromJson(Map<String, dynamic> j,
      {int fallbackPage = 1, int fallbackPageSize = 20}) {
    final profile = LKPublicUserProfile.fromJson(j);
    final publish = _jsonMap(j['publish']) ?? const <String, dynamic>{};
    final books = _jsonMap(publish['books']) ?? const <String, dynamic>{};
    final rawList = j['articles'] ??
        j['article_list'] ??
        books['list'] ??
        books['items'] ??
        const [];
    final publications = rawList is List
        ? rawList
            .whereType<Map>()
            .map((e) => LKPublicBook.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.bookId > 0 && e.title.isNotEmpty)
            .toList()
        : const <LKPublicBook>[];
    final pageInfo = _jsonMap(j['article_page']) ??
        _jsonMap(j['articlePage']) ??
        _jsonMap(books['page_info']) ??
        const <String, dynamic>{};
    final page = _jsonInt(pageInfo['page'] ??
        pageInfo['current_page'] ??
        j['page'] ??
        fallbackPage);
    final pageSize = _jsonInt(pageInfo['page_size'] ??
        pageInfo['pageSize'] ??
        j['page_size'] ??
        j['pageSize'] ??
        fallbackPageSize);
    final total = _jsonInt(pageInfo['total'] ??
        pageInfo['count'] ??
        j['total'] ??
        publications.length);
    final rawHasMore = pageInfo['has_more'] ??
        pageInfo['hasMore'] ??
        pageInfo['has_next'] ??
        j['has_more'] ??
        j['hasMore'];
    final hasMore = rawHasMore == null
        ? total > page * pageSize || publications.length >= pageSize
        : _jsonFlag(rawHasMore);
    return LKPublicUserPage(
      profile: profile,
      publications: publications,
      page: page > 0 ? page : fallbackPage,
      pageSize: pageSize > 0 ? pageSize : fallbackPageSize,
      total: total,
      hasMore: hasMore,
    );
  }
}

class LKPublicBookshelfPage {
  final bool visible;
  final List<LKPublicBook> books;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  LKPublicBookshelfPage({
    this.visible = false,
    this.books = const [],
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.hasMore = false,
  });

  factory LKPublicBookshelfPage.fromJson(Map<String, dynamic> j,
      {int fallbackPage = 1, int fallbackPageSize = 20}) {
    final privacy = _jsonMap(j['privacy']) ?? const <String, dynamic>{};
    final rawList = j['list'] ?? j['items'] ?? j['books'] ?? const [];
    final books = rawList is List
        ? rawList
            .whereType<Map>()
            .map((e) => LKPublicBook.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.bookId > 0 && e.title.isNotEmpty)
            .toList()
        : const <LKPublicBook>[];
    final pageInfo = _jsonMap(j['page_info']) ??
        _jsonMap(j['pagination']) ??
        const <String, dynamic>{};
    final page = _jsonInt(pageInfo['page'] ?? j['page'] ?? fallbackPage);
    final pageSize = _jsonInt(pageInfo['page_size'] ??
        pageInfo['pageSize'] ??
        j['page_size'] ??
        fallbackPageSize);
    final total = _jsonInt(pageInfo['total'] ?? j['total'] ?? books.length);
    final rawHasMore = pageInfo['has_more'] ??
        pageInfo['hasMore'] ??
        pageInfo['has_next'] ??
        j['has_more'] ??
        j['hasMore'];
    return LKPublicBookshelfPage(
      visible: _jsonFlag(j['visible'] ??
          privacy['bookshelf_visible'] ??
          privacy['bookshelfVisible']),
      books: books,
      page: page > 0 ? page : fallbackPage,
      pageSize: pageSize > 0 ? pageSize : fallbackPageSize,
      total: total,
      hasMore: rawHasMore == null
          ? total > page * pageSize || books.length >= pageSize
          : _jsonFlag(rawHasMore),
    );
  }
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
    this.bookId = 0,
    this.title = '',
    this.authorName = '',
    this.coverUrl = '',
    this.summary = '',
    this.tags = const [],
    this.wordCount = 0,
    this.volumeCount = 0,
    this.chapterCount = 0,
    this.defaultVolumeId = 0,
    this.defaultChapterId = 0,
    this.serialStatus = '',
    this.isCompleted = false,
    this.lastReadChapterTitle = '',
    this.unreadChapterCount = 0,
    this.ratingScore = 0,
    this.updatedAt = '',
  });
  factory LKBook.fromJson(Map<String, dynamic> j) => LKBook(
        bookId: (j['book_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        authorName: (j['author_name'] as String?) ?? '',
        coverUrl: (j['cover_url'] as String?) ?? '',
        summary:
            (j['summary'] as String?) ?? (j['summary_short'] as String?) ?? '',
        tags:
            (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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

  Map<String, dynamic> toJson() => {
        'book_id': bookId,
        'title': title,
        'author_name': authorName,
        'cover_url': coverUrl,
        'summary': summary,
        'tags': tags,
        'word_count': wordCount,
        'volume_count': volumeCount,
        'chapter_count': chapterCount,
        'default_volume_id': defaultVolumeId,
        'default_chapter_id': defaultChapterId,
        'serial_status': serialStatus,
        'is_completed': isCompleted ? 1 : 0,
        'last_read_chapter_title': lastReadChapterTitle,
        'unread_chapter_count': unreadChapterCount,
        'rating_score': ratingScore,
        'updated_at': updatedAt,
      };
}

String bookStatusLabel(LKBook book) {
  if (book.isCompleted) return '完结';
  final status = book.serialStatus.trim().toLowerCase();
  if (status.isEmpty ||
      const {
        'serial',
        'serializing',
        'ongoing',
        'in_progress',
        'publishing',
      }.contains(status)) {
    return '连载';
  }
  if (const {'complete', 'completed', 'finished', 'done', 'ended', 'end'}
      .contains(status)) {
    return '完结';
  }
  return book.serialStatus;
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
    this.chapterId = 0,
    this.chapterNo = 0,
    this.title = '',
    this.wordCount = 0,
    this.locked = false,
    this.unlocked = false,
    this.accessType = '',
  });
  factory LKChapter.fromJson(Map<String, dynamic> j) => LKChapter(
        chapterId: (j['chapter_id'] as num?)?.toInt() ?? 0,
        chapterNo: (j['chapter_no'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
        locked: (j['locked'] as num?)?.toInt() == 1,
        unlocked: (j['unlocked'] as num?)?.toInt() == 1,
        accessType:
            (j['access_type'] as String?) ?? (j['accessType'] as String?) ?? '',
      );

  bool get braveOnly => accessType.toLowerCase() == 'brave';
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
    this.chapterId = 0,
    this.volumeId = 0,
    this.title = '',
    this.bookTitle = '',
    this.bodyText = '',
    this.bodyHtml,
    this.locked = false,
    this.unlocked = false,
    this.coinPrice = 0,
    this.prevChapterId,
    this.prevTitle,
    this.prevVolumeId,
    this.nextChapterId,
    this.nextTitle,
    this.nextVolumeId,
  });

  /// 本地正文缓存专用序列化,不包含登录凭据或其他会话信息。
  Map<String, dynamic> toCacheJson() => {
        'chapter_id': chapterId,
        'volume_id': volumeId,
        'title': title,
        'book_title': bookTitle,
        'body_text': bodyText,
        'body_html': bodyHtml,
        'locked': locked,
        'unlocked': unlocked,
        'coin_price': coinPrice,
        'prev_chapter_id': prevChapterId,
        'prev_title': prevTitle,
        'prev_volume_id': prevVolumeId,
        'next_chapter_id': nextChapterId,
        'next_title': nextTitle,
        'next_volume_id': nextVolumeId,
      };

  factory LKChapterDetail.fromCacheJson(Map<String, dynamic> j) =>
      LKChapterDetail(
        chapterId: (j['chapter_id'] as num?)?.toInt() ?? 0,
        volumeId: (j['volume_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        bookTitle: (j['book_title'] as String?) ?? '',
        bodyText: (j['body_text'] as String?) ?? '',
        bodyHtml: j['body_html'] as String?,
        locked: j['locked'] == true,
        unlocked: j['unlocked'] == true,
        coinPrice: (j['coin_price'] as num?)?.toInt() ?? 0,
        prevChapterId: (j['prev_chapter_id'] as num?)?.toInt(),
        prevTitle: j['prev_title'] as String?,
        prevVolumeId: (j['prev_volume_id'] as num?)?.toInt(),
        nextChapterId: (j['next_chapter_id'] as num?)?.toInt(),
        nextTitle: j['next_title'] as String?,
        nextVolumeId: (j['next_volume_id'] as num?)?.toInt(),
      );

  bool hasSameContent(LKChapterDetail other) =>
      bodyText == other.bodyText &&
      bodyHtml == other.bodyHtml &&
      locked == other.locked &&
      unlocked == other.unlocked;

  factory LKChapterDetail.fromJson(Map<String, dynamic> j) {
    String body = '';
    String? html;
    final snap = _firstJsonMap(j['body_snapshot']);
    if (snap != null) {
      if (snap['body_text'] is String) body = snap['body_text'] as String;
      if (snap['body_html'] is String) html = snap['body_html'] as String;
    }
    if (body.isEmpty) {
      final prev = _firstJsonMap(j['render_preview']);
      if (prev != null && prev['body_text'] is String) {
        body = prev['body_text'] as String;
      }
    }
    final nav = _jsonMap(j['navigation']);
    // prev_chapter/next_chapter 可能是对象,也可能是数组(服务端形态不一)
    final prevRaw = nav?['prev_chapter'];
    Map<String, dynamic>? prev0;
    if (prevRaw is Map<String, dynamic>) {
      prev0 = prevRaw;
    } else if (prevRaw is List &&
        prevRaw.isNotEmpty &&
        prevRaw.first is Map<String, dynamic>) {
      prev0 = prevRaw.first as Map<String, dynamic>;
    }
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
      locked: _jsonFlag(j['locked']),
      unlocked: _jsonFlag(j['unlocked']),
      coinPrice: (j['coin_price'] as num?)?.toInt() ?? 0,
      prevChapterId:
          prev0 != null ? (prev0['chapter_id'] as num?)?.toInt() : null,
      prevTitle: prev0 != null ? (prev0['title'] as String?) : null,
      prevVolumeId:
          prev0 != null ? (prev0['volume_id'] as num?)?.toInt() : null,
      nextChapterId:
          next != null ? (next['chapter_id'] as num?)?.toInt() : null,
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
  LKParagraph(
      {this.paragraphNo = 0,
      this.hash = '',
      this.bodyVersion = 0,
      this.text = ''});
  factory LKParagraph.fromJson(Map<String, dynamic> j) => LKParagraph(
        paragraphNo: (j['paragraph_no'] as num?)?.toInt() ?? 0,
        hash: (j['paragraph_hash'] as String?) ?? '',
        bodyVersion: (j['body_version'] as num?)?.toInt() ?? 0,
        text: (j['paragraph_text'] as String?) ??
            (j['paragraph_excerpt'] as String?) ??
            '',
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
  final int userUid;
  final String nickname;
  final String avatar;
  final String content;
  final int likeCount;
  final String time;
  final bool liked;
  final List<LKDynamicMedia> media;
  final int replyCount;
  LKComment({
    this.commentId = 0,
    this.userUid = 0,
    this.nickname = '',
    this.avatar = '',
    this.content = '',
    this.likeCount = 0,
    this.time = '',
    this.liked = false,
    this.media = const [],
    this.replyCount = 0,
  });
  factory LKComment.fromJson(Map<String, dynamic> j) {
    final author = (j['author'] as Map<String, dynamic>?) ??
        (j['user'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final inter = (j['interaction_state'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    dynamic rawMedia = j['media'];
    if (rawMedia is String && rawMedia.isNotEmpty) {
      try {
        rawMedia = jsonDecode(rawMedia);
      } catch (_) {
        rawMedia = null;
      }
    }
    final media = rawMedia is List
        ? rawMedia
            .whereType<Map>()
            .map((e) => LKDynamicMedia.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.url.isNotEmpty)
            .toList()
        : const <LKDynamicMedia>[];
    return LKComment(
      commentId: (j['comment_id'] as num?)?.toInt() ?? 0,
      userUid: _jsonInt(author['uid'] ??
          author['user_id'] ??
          author['id'] ??
          j['author_uid'] ??
          j['user_uid'] ??
          j['uid'] ??
          j['user_id']),
      nickname: (author['nickname'] ?? j['nickname'] ?? '').toString(),
      avatar: (author['avatar'] ?? j['avatar'] ?? '').toString(),
      content:
          (j['content'] as String?) ?? (j['content_text'] as String?) ?? '',
      likeCount: (j['like_count'] as num?)?.toInt() ?? 0,
      time:
          (j['publish_time'] as String?) ?? (j['created_at'] as String?) ?? '',
      liked: (j['liked'] as num?)?.toInt() == 1 ||
          (inter['liked'] as num?)?.toInt() == 1,
      media: media,
      replyCount: _jsonInt(j['reply_count'] ?? j['replyCount']),
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
    this.bookId = 0,
    this.title = '',
    this.authorName = '',
    this.coverUrl = '',
    this.volumeId = 0,
    this.chapterId = 0,
    this.chapterTitle = '',
    this.progressPercent = 0,
    this.lastReadAt = '',
    this.unreadChapters = 0,
  });
  factory LKHistoryItem.fromJson(Map<String, dynamic> j) {
    final h =
        (j['history'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return LKHistoryItem(
      bookId: (j['book_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] as String?) ?? '',
      authorName: (j['author_name'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
      volumeId: (h['volume_id'] as num?)?.toInt() ??
          (j['default_volume_id'] as num?)?.toInt() ??
          0,
      chapterId: (h['chapter_id'] as num?)?.toInt() ??
          (j['last_read_chapter_id'] as num?)?.toInt() ??
          0,
      chapterTitle: (h['chapter_title'] as String?) ??
          (j['last_read_chapter_title'] as String?) ??
          '',
      progressPercent: (h['progress_percent'] as num?)?.toInt() ?? 0,
      lastReadAt: (h['last_read_at'] as String?) ?? '',
      unreadChapters: (j['unread_chapter_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class LKDynamicMedia {
  final String url;
  final int width;
  final int height;
  final String resId;
  final String resUrl;
  final String resPath;
  final String storedUrl;
  final String sourceUrl;

  const LKDynamicMedia({
    this.url = '',
    this.width = 0,
    this.height = 0,
    this.resId = '',
    this.resUrl = '',
    this.resPath = '',
    this.storedUrl = '',
    this.sourceUrl = '',
  });

  factory LKDynamicMedia.fromJson(Map<String, dynamic> j) => LKDynamicMedia(
        url: (j['url'] ??
                j['src'] ??
                j['res_url'] ??
                j['stored_url'] ??
                j['source_url'] ??
                '')
            .toString(),
        width: _jsonInt(j['width']),
        height: _jsonInt(j['height']),
        resId: (j['res_id'] ?? j['resId'] ?? '').toString(),
        resUrl: (j['res_url'] ?? j['resUrl'] ?? '').toString(),
        resPath: (j['res_path'] ?? j['resPath'] ?? '').toString(),
        storedUrl: (j['stored_url'] ?? j['storedUrl'] ?? '').toString(),
        sourceUrl: (j['source_url'] ?? j['sourceUrl'] ?? '').toString(),
      );
}

class LKDynamicPollOption {
  final String id;
  final String text;
  final String image;
  final int voteCount;
  final double percent;
  final bool selected;

  const LKDynamicPollOption({
    this.id = '',
    this.text = '',
    this.image = '',
    this.voteCount = 0,
    this.percent = 0,
    this.selected = false,
  });

  factory LKDynamicPollOption.fromJson(Map<String, dynamic> j, int index) {
    final rawId = j['option_id'] ?? j['optionId'] ?? j['id'] ?? index + 1;
    return LKDynamicPollOption(
      id: rawId.toString(),
      text: (j['text'] ??
              j['title'] ??
              j['content'] ??
              j['label'] ??
              j['name'] ??
              '')
          .toString(),
      image: (j['image'] ?? j['image_url'] ?? j['imageUrl'] ?? '').toString(),
      voteCount: _jsonInt(j['vote_count'] ?? j['votes']),
      percent: (j['percent'] is num)
          ? (j['percent'] as num).toDouble()
          : double.tryParse('${j['percent'] ?? j['ratio'] ?? ''}') ?? 0,
      selected: _jsonFlag(j['voted']),
    );
  }
}

class LKDynamicPoll {
  final String pollId;
  final String title;
  final String description;
  final String deadlineAt;
  final int participantCount;
  final bool ended;
  final bool voted;
  final bool multiple;
  final List<LKDynamicPollOption> options;

  const LKDynamicPoll({
    this.pollId = '',
    this.title = '',
    this.description = '',
    this.deadlineAt = '',
    this.participantCount = 0,
    this.ended = false,
    this.voted = false,
    this.multiple = false,
    this.options = const [],
  });

  static LKDynamicPoll? tryParse(dynamic raw) {
    final j = _jsonMap(raw);
    if (j == null) return null;
    final source = _jsonMap(j['poll']) ?? j;
    final viewer = source['viewer_option_ids'] is List
        ? (source['viewer_option_ids'] as List).map((e) => e.toString()).toSet()
        : <String>{};
    final rawOptions = source['options'] ??
        source['option_list'] ??
        source['optionList'] ??
        source['items'] ??
        source['vote_options'] ??
        const [];
    if (rawOptions is! List) return null;
    final options = rawOptions
        .whereType<Map>()
        .toList()
        .asMap()
        .entries
        .map((e) {
          final option = LKDynamicPollOption.fromJson(
              Map<String, dynamic>.from(e.value), e.key);
          return viewer.contains(option.id) && !option.selected
              ? LKDynamicPollOption(
                  id: option.id,
                  text: option.text,
                  image: option.image,
                  voteCount: option.voteCount,
                  percent: option.percent,
                  selected: true,
                )
              : option;
        })
        .where(
            (e) => e.id.isNotEmpty && (e.text.isNotEmpty || e.image.isNotEmpty))
        .toList();
    if (options.isEmpty) return null;
    return LKDynamicPoll(
      pollId: (source['poll_id'] ?? source['id'] ?? '').toString(),
      title: (source['title'] ?? source['question'] ?? '').toString(),
      description: (source['description'] ?? source['desc'] ?? '').toString(),
      deadlineAt:
          (source['deadline_at'] ?? source['deadlineAt'] ?? '').toString(),
      participantCount: _jsonInt(source['participant_count'] ??
          source['participantCount'] ??
          source['vote_user_count'] ??
          source['user_count'] ??
          source['total_votes']),
      ended:
          _jsonFlag(source['ended'] ?? source['is_ended'] ?? source['expired']),
      voted: _jsonFlag(source['viewer_voted'] ?? source['voted']) ||
          options.any((e) => e.selected),
      multiple: _jsonFlag(source['allow_multiple'] ?? source['multiple']),
      options: options,
    );
  }
}

class LKDynamicItem {
  final int dynamicId;
  final int authorUid;
  final String targetType;
  final String eventType;
  final String nickname;
  final String avatar;
  final List<LKMedal> authorMedals;
  final String title;
  final String summary;
  final int likeCount;
  final int commentCount;
  final int favoriteCount;
  final bool liked;
  final bool favorited;
  final bool read;
  final String time;
  final int bookId; // 作品卡(带作品链接的动态)
  final String bookTitle;
  final String bookCover;
  final List<LKDynamicMedia> media;
  final LKDynamicPoll? poll;
  bool get isWorkPost =>
      bookId > 0 ||
      const {
        'book_created',
        'volume_created',
        'chapter_published',
      }.contains(eventType) ||
      const {'book', 'volume', 'chapter'}.contains(targetType);

  LKDynamicItem({
    this.dynamicId = 0,
    this.authorUid = 0,
    this.targetType = '',
    this.eventType = '',
    this.nickname = '',
    this.avatar = '',
    this.authorMedals = const [],
    this.title = '',
    this.summary = '',
    this.likeCount = 0,
    this.commentCount = 0,
    this.favoriteCount = 0,
    this.liked = false,
    this.favorited = false,
    this.read = false,
    this.time = '',
    this.bookId = 0,
    this.bookTitle = '',
    this.bookCover = '',
    this.media = const [],
    this.poll,
  });
  factory LKDynamicItem.fromJson(Map<String, dynamic> j) {
    final author = _jsonMap(j['author']) ?? const <String, dynamic>{};
    final stats = _jsonMap(j['stats']) ?? const <String, dynamic>{};
    final ist = _jsonMap(j['interaction_state']) ?? const <String, dynamic>{};
    final brief = _jsonMap(j['target_brief']) ?? const <String, dynamic>{};
    final targetType =
        (j['target_type'] ?? brief['target_type'] ?? '').toString();
    // target_brief.target_id 对纯动态指向动态内容本身，不能当作书号。
    final rawBookId = brief['book_id'] ??
        (targetType == 'book' ? brief['target_id'] : j['book_id']);
    final rawMedia = j['media'];
    final rawMedals = author['medals'] ??
        author['medal_list'] ??
        author['equipped_medals'] ??
        const [];
    final authorMedals = rawMedals is List
        ? rawMedals
            .whereType<Map>()
            .map((e) => LKMedal.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.image.isNotEmpty)
            .take(5)
            .toList()
        : const <LKMedal>[];
    final media = rawMedia is List
        ? rawMedia
            .whereType<Map>()
            .map((e) => LKDynamicMedia.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.url.isNotEmpty)
            .toList()
        : const <LKDynamicMedia>[];
    return LKDynamicItem(
      dynamicId: _jsonInt(
          j['dynamic_id'] ?? j['activity_id'] ?? j['feed_id'] ?? j['id']),
      authorUid: _jsonInt(author['uid'] ??
          author['user_id'] ??
          author['id'] ??
          j['author_uid'] ??
          j['user_uid'] ??
          j['uid'] ??
          j['user_id']),
      targetType: targetType,
      eventType: (j['event_type'] ?? '').toString(),
      nickname: (author['nickname'] ?? j['nickname'] ?? '').toString(),
      avatar: (author['avatar'] ?? j['avatar'] ?? '').toString(),
      authorMedals: authorMedals,
      title: (j['title'] ?? '').toString(),
      summary:
          (j['summary'] ?? j['content'] ?? j['content_text'] ?? '').toString(),
      likeCount: _jsonInt(stats['like_count'] ?? j['like_count'] ?? j['likes']),
      commentCount: _jsonInt(
          stats['comment_count'] ?? j['comment_count'] ?? j['comments']),
      favoriteCount: _jsonInt(
          stats['favorite_count'] ?? stats['favorites'] ?? j['favorite_count']),
      liked: _jsonFlag(ist['liked']),
      favorited: _jsonFlag(ist['favorited']),
      read: _jsonFlag(ist['read'] ?? j['read'] ?? j['is_read']),
      time: (j['feed_time'] ??
              j['publish_time'] ??
              j['created_at'] ??
              j['createdAt'] ??
              j['time'] ??
              '')
          .toString(),
      bookId: _jsonInt(rawBookId),
      bookTitle: (brief['title'] ?? '').toString(),
      bookCover: (brief['cover_url'] ?? '').toString(),
      media: media,
      poll: LKDynamicPoll.tryParse(
          j['poll'] ?? j['vote'] ?? j['poll_json'] ?? j['extension']),
    );
  }
}

class LKDynamicPage {
  final List<LKDynamicItem> items;
  final String cursor;
  final bool hasMore;

  LKDynamicPage({
    this.items = const [],
    this.cursor = '',
    this.hasMore = false,
  });

  factory LKDynamicPage.fromJson(Map<String, dynamic> j) {
    final rawList = j['list'] ?? j['items'] ?? j['feed'] ?? const [];
    final items = rawList is List
        ? rawList
            .whereType<Map>()
            .map((e) => LKDynamicItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <LKDynamicItem>[];
    final pageInfo = _jsonMap(j['page_info']) ??
        _jsonMap(j['pagination']) ??
        const <String, dynamic>{};
    final cursor =
        (j['next_cursor'] ?? j['cursor'] ?? pageInfo['next_cursor'] ?? '')
            .toString();
    final rawHasMore = j['has_more'] ??
        j['hasMore'] ??
        j['has_next'] ??
        pageInfo['has_more'] ??
        pageInfo['hasMore'] ??
        pageInfo['has_next'];
    return LKDynamicPage(
      items: items,
      cursor: cursor,
      hasMore: rawHasMore == null ? cursor.isNotEmpty : _jsonFlag(rawHasMore),
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
    this.conversationId = 0,
    this.peerUid = 0,
    this.peerName = '',
    this.peerAvatar = '',
    this.lastMessage = '',
    this.unread = 0,
  });
  factory LKConversation.fromJson(Map<String, dynamic> j) {
    final peerRaw = j['peer'] ?? j['user'];
    final peer =
        peerRaw is Map<String, dynamic> ? peerRaw : const <String, dynamic>{};
    return LKConversation(
      conversationId: (j['conversation_id'] as num?)?.toInt() ?? 0,
      peerUid: (j['peer_uid'] as num?)?.toInt() ??
          (peer['uid'] as num?)?.toInt() ??
          0,
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
  LKDMMessage(
      {this.id = 0, this.senderUid = 0, this.content = '', this.time = ''});
  factory LKDMMessage.fromJson(Map<String, dynamic> j) => LKDMMessage(
        id: (j['id'] as num?)?.toInt() ??
            (j['message_id'] as num?)?.toInt() ??
            0,
        senderUid: (j['sender_uid'] as num?)?.toInt() ?? 0,
        content:
            (j['content_text'] as String?) ?? (j['content'] as String?) ?? '',
        time: (j['created_at'] as String?) ?? '',
      );
}

class LKMessageItem {
  final String title;
  final String content;
  final String nickname;
  final String avatar;
  final String time;
  LKMessageItem(
      {this.title = '',
      this.content = '',
      this.nickname = '',
      this.avatar = '',
      this.time = ''});
  factory LKMessageItem.fromJson(Map<String, dynamic> j) {
    // user 可能是对象、也可能是空数组(如系统消息),安全转换
    final userRaw = j['user'] ?? j['author'];
    final peer =
        userRaw is Map<String, dynamic> ? userRaw : const <String, dynamic>{};
    return LKMessageItem(
      title: (j['title'] as String?) ?? '',
      content: (j['content'] as String?) ??
          (j['summary'] as String?) ??
          (j['body'] as String?) ??
          '',
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
