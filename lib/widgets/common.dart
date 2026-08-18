import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';

/// 无封面书籍的默认封面(站点官方占位图)
const String kDefaultCover =
    'https://www.lightnovel.fun/sample-assets/legacy/default_article_cover_v.jpg';

/// 带缓存、圆角与阴影的封面/头像
class CoverImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;
  const CoverImage({
    super.key,
    required this.url,
    this.width = 48,
    this.height = 64,
    this.radius = 8,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade100, Colors.indigo.shade200],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.menu_book_rounded,
          color: Colors.indigo.shade400, size: width * 0.45),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
                imageUrl: url.isEmpty ? kDefaultCover : url,
                width: width,
                height: height,
                fit: fit,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// 书籍卡片:白底圆角 + 封面阴影 + 标签胶囊 + 状态徽章
class BookCard extends StatelessWidget {
  final LKBook book;
  final VoidCallback onTap;
  final int? rank;
  const BookCard({super.key, required this.book, required this.onTap, this.rank});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E2025) : Colors.white;
    final titleColor = isDark ? const Color(0xFFECEDF1) : const Color(0xFF263238);
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final status = book.isCompleted
        ? '完结'
        : (book.serialStatus.isEmpty ? '连载' : book.serialStatus);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (rank != null) _rankBadge(scheme, rank!),
                if (rank != null) const SizedBox(width: 10),
                CoverImage(url: book.coverUrl, width: 76, height: 101, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: titleColor),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              book.authorName.isEmpty ? '佚名' : book.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _statusBadge(scheme, status, borderColor),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // 过长的 tag(如整段书名式 tag)不展示,避免 RIGHT OVERFLOW
                          ..._shortTags(book.tags)
                              .take(3)
                              .map((t) => _tagChip(scheme, t)),
                          if (book.wordCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                _fmtWord(book.wordCount),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey.shade500
                                        : Colors.grey.shade500),
                              ),
                            ),
                        ],
                      ),
                      // 小说介绍(单列卡片的简介)
                      if (book.summary.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          book.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600),
                        ),
                      ],
                      // 最后更新时间
                      if (book.updatedAt.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(children: [
                          Icon(Icons.schedule_rounded,
                              size: 12,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '更新于 ${book.updatedAt.length > 16 ? book.updatedAt.substring(0, 16) : book.updatedAt}',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(ColorScheme scheme, int r) {
    final Color color;
    if (r == 1) {
      color = const Color(0xFFF57F17);
    } else if (r == 2) {
      color = const Color(0xFF78909C);
    } else if (r == 3) {
      color = const Color(0xFFBF6B4A);
    } else {
      color = Colors.grey.shade400;
    }
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        '$r',
        style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13),
      ),
    );
  }

  Widget _statusBadge(ColorScheme scheme, String status, Color borderColor) {
    final done = status == '完结';
    final color = done ? Colors.teal : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _tagChip(ColorScheme scheme, String tag) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      constraints: const BoxConstraints(maxWidth: 110),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5, color: scheme.primary)),
    );
  }

  /// 过长的 tag 在主页不展示(12 字以内)
  static List<String> _shortTags(List<String> tags) =>
      tags.where((t) => t.length <= 12).toList();

  static String _fmtWord(int n) =>
      n >= 10000 ? '${(n / 10000).toStringAsFixed(1)}万字' : '$n字';
}

/// 过长的 tag(如整段书名式 tag)过滤掉,避免溢出
List<String> shortTags(List<String> tags) =>
    tags.where((t) => t.length <= 12).toList();

/// 视频网站风格:大封面竖排卡(双列网格用)
class BookGridCard extends StatelessWidget {
  final LKBook book;
  final VoidCallback onTap;
  final int? rank;
  const BookGridCard({super.key, required this.book, required this.onTap, this.rank});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final status = book.isCompleted
        ? '完结'
        : (book.serialStatus.isEmpty ? '连载' : book.serialStatus);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 大封面(3:4)
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CoverImage(
                      url: book.coverUrl, width: double.infinity, height: double.infinity, radius: 12),
                ),
                if (rank != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rank! <= 3
                            ? (rank == 1
                                ? const Color(0xFFF57F17)
                                : rank == 2
                                    ? const Color(0xFF78909C)
                                    : const Color(0xFFBF6B4A))
                            : Colors.black54,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4),
                        ],
                      ),
                      child: Text('$rank',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  ),
                // 状态角标
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: isDark ? const Color(0xFFECEDF1) : const Color(0xFF263238)),
          ),
          const SizedBox(height: 3),
          Row(children: [
            if (book.tags.isNotEmpty)
              Expanded(
                child: Text(
                  shortTags(book.tags).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: scheme.primary),
                ),
              ),
            if (book.wordCount > 0)
              Text(
                book.wordCount >= 10000
                    ? '${(book.wordCount / 10000).toStringAsFixed(1)}万字'
                    : '${book.wordCount}字',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
              ),
          ]),
        ],
      ),
    );
  }
}

/// 统一的错误提示条
void showLkError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(e.toString()),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
}
