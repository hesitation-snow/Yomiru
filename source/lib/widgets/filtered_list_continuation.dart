import 'package:flutter/material.dart';

/// 正常列表触底只发起一次请求，失败后等待用户重试。
class ListContinuation extends StatefulWidget {
  const ListContinuation(
      {super.key,
      required this.pageKey,
      required this.loading,
      required this.onLoadMore,
      this.error});
  final Object pageKey;
  final bool loading;
  final VoidCallback onLoadMore;
  final String? error;

  @override
  State<ListContinuation> createState() => _ListContinuationState();
}

class _ListContinuationState extends State<ListContinuation> {
  Object? _requestedPage;

  @override
  Widget build(BuildContext context) {
    if (!widget.loading &&
        widget.error == null &&
        _requestedPage != widget.pageKey) {
      _requestedPage = widget.pageKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.loading && widget.error == null) {
          widget.onLoadMore();
        }
      });
    }
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(12),
      child: TextButton(
          onPressed: widget.loading ? null : widget.onLoadMore,
          child: Text(widget.loading
              ? '正在加载…'
              : widget.error != null
                  ? '加载失败，点击重试'
                  : '继续加载')),
    ));
  }
}

/// 当前页被过滤不代表服务器没有下一页。最多自动补两页，避免持续空页
/// 导致后台无限抓取；之后保留明确的继续加载/重试入口。
class FilteredListContinuation extends StatefulWidget {
  const FilteredListContinuation({
    super.key,
    required this.message,
    required this.hasMore,
    required this.loading,
    required this.pageKey,
    required this.onLoadMore,
    this.error,
  });

  final String message;
  final bool hasMore;
  final bool loading;
  final Object pageKey;
  final VoidCallback onLoadMore;
  final String? error;

  @override
  State<FilteredListContinuation> createState() =>
      _FilteredListContinuationState();
}

class _FilteredListContinuationState extends State<FilteredListContinuation> {
  int _automaticRequests = 0;
  Object? _requestedPage;

  @override
  Widget build(BuildContext context) {
    if (widget.hasMore &&
        !widget.loading &&
        widget.error == null &&
        _automaticRequests < 2 &&
        _requestedPage != widget.pageKey) {
      _requestedPage = widget.pageKey;
      _automaticRequests++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.hasMore &&
            !widget.loading &&
            widget.error == null) {
          widget.onLoadMore();
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (widget.hasMore) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.loading ? null : widget.onLoadMore,
              child: Text(widget.loading
                  ? '正在查找更多作品…'
                  : widget.error != null
                      ? '加载失败，点击重试'
                      : '继续加载'),
            ),
          ],
        ],
      ),
    );
  }
}
