/// A bounded, reader-local cache. Layout keys include content and metrics;
/// reading position is deliberately not cached here.
class ReaderLayoutCache<K, V> {
  ReaderLayoutCache({this.capacity = 2}) : assert(capacity > 0);
  final int capacity;
  final _entries = <K, V>{};

  V resolve(K key, V Function() build) {
    final cached = _entries.remove(key);
    final value = cached ?? build();
    _entries[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return value;
  }

  void clear() => _entries.clear();
}
