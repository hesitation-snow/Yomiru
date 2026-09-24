/// Content identity is stable before and after pagination; it must not depend
/// on whether that content has already been assigned to the page cache.
class ReaderPaginationKey {
  final Object content;
  final Object layout;

  const ReaderPaginationKey({required this.content, required this.layout});

  @override
  bool operator ==(Object other) =>
      other is ReaderPaginationKey &&
      identical(content, other.content) &&
      layout == other.layout;

  @override
  int get hashCode => Object.hash(identityHashCode(content), layout);
}
