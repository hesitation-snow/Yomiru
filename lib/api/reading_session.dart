/// 当前进程内最近一次真实阅读会话。
///
/// 这份数据只用于调试服务器的阅读进度校验，不负责发放轻币，也不接受
/// 外部传入的虚构时长或进度。正式版不会展示依赖它的诊断入口。
class LKReadingSnapshot {
  final int bookId;
  final int volumeId;
  final int chapterId;
  final int progressPercent;
  final int readDurationSeconds;
  final DateTime startedAt;

  const LKReadingSnapshot({
    required this.bookId,
    required this.volumeId,
    required this.chapterId,
    required this.progressPercent,
    required this.readDurationSeconds,
    required this.startedAt,
  });
}

class LKReadingSession {
  LKReadingSession._();

  static final shared = LKReadingSession._();

  int _bookId = 0;
  int _volumeId = 0;
  int _chapterId = 0;
  int _progressPercent = 0;
  DateTime? _startedAt;
  DateTime? _activeSince;
  Duration _activeDuration = Duration.zero;

  void begin({
    required int bookId,
    required int volumeId,
    required int chapterId,
  }) {
    if (_bookId == bookId && _chapterId == chapterId && _startedAt != null) {
      return;
    }
    _bookId = bookId;
    _volumeId = volumeId;
    _chapterId = chapterId;
    _progressPercent = 0;
    _startedAt = DateTime.now();
    _activeSince = _startedAt;
    _activeDuration = Duration.zero;
  }

  /// 暂停前台计时，例如应用进入后台或阅读器即将退出。
  void pause() {
    final activeSince = _activeSince;
    if (activeSince == null) return;
    _activeDuration += DateTime.now().difference(activeSince);
    _activeSince = null;
  }

  /// 恢复前台计时。不会重置当前章节的累计时长。
  void resume() {
    if (_startedAt == null || _activeSince != null) return;
    _activeSince = DateTime.now();
  }

  void update({required int volumeId, required double progress}) {
    if (_startedAt == null || _volumeId == 0) return;
    _volumeId = volumeId > 0 ? volumeId : _volumeId;
    final value = (progress * 100).round().clamp(0, 100);
    if (value > _progressPercent) _progressPercent = value;
  }

  LKReadingSnapshot? snapshot() {
    final startedAt = _startedAt;
    if (startedAt == null || _bookId <= 0 || _chapterId <= 0) return null;
    var activeDuration = _activeDuration;
    final activeSince = _activeSince;
    if (activeSince != null) {
      activeDuration += DateTime.now().difference(activeSince);
    }
    return LKReadingSnapshot(
      bookId: _bookId,
      volumeId: _volumeId,
      chapterId: _chapterId,
      progressPercent: _progressPercent,
      readDurationSeconds: activeDuration.inSeconds.clamp(0, 86400),
      startedAt: startedAt,
    );
  }
}
