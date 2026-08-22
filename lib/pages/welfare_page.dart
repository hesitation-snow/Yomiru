import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/reading_session.dart';
import '../widgets/common.dart';

// 本地协议测试开关：默认关闭，需显式 --dart-define 才会编译入口。
const _enableWelfareProtocolProbe =
    bool.fromEnvironment('YOMIRU_WELFARE_PROTOCOL_PROBE');

/// 任务中心：签到、任务、宝箱和轻币记录。
/// 所有请求都走 Yomiru 当前配置的正式站点，不读取其他客户端的服务器地址。
class WelfarePage extends StatefulWidget {
  const WelfarePage({super.key});

  @override
  State<WelfarePage> createState() => _WelfarePageState();
}

class _WelfarePageState extends State<WelfarePage> {
  Map<String, dynamic>? _home;
  Map<String, dynamic> _signDetail = const {};
  Map<String, dynamic> _earnCoin = const {};
  Map<String, dynamic> _sleep = const {};
  List<Map<String, dynamic>> _tasks = const [];
  bool _loading = true;
  String? _error;
  String _action = '';
  Timer? _sleepTimer;
  int _sleepRemainingSeconds = 0;
  bool _sleepCountdownExpired = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool forceTaskList = false}) async {
    _sleepTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final home = await LKApi.welfareHome();
      final root = _root(home);
      if (!mounted) return;
      // 首页数据到达后立即显示页面，详情接口在后台继续验证和补全卡片。
      setState(() {
        _home = home;
        _loading = false;
      });

      final detailsFuture = Future.wait<Map<String, dynamic>>([
        _safeDetail(LKApi.welfareSignDetail()),
        _safeDetail(LKApi.welfareEarnCoinDetail()),
        _safeDetail(LKApi.welfareSleepDetail()),
      ]);
      var tasks = _extractTasks(root);
      if (forceTaskList || tasks.isEmpty) {
        try {
          final refreshedTasks =
              _extractTasks(_root(await LKApi.welfareTaskList()));
          if (refreshedTasks.isNotEmpty) tasks = refreshedTasks;
        } catch (_) {
          // 主页数据已经足够展示时，任务列表接口失败不影响其他模块。
        }
      }
      tasks = _visibleTasks(tasks);
      final details = await detailsFuture;
      final signDetail = details[0];
      final homeEarnCoin =
          _section(root, const ['earn_coin', 'earnCoin', 'welfare_earn_coin']);
      final earnCoin = details[1].isNotEmpty ? details[1] : homeEarnCoin;
      final sleep = details[2];
      _sleepRemainingSeconds = _sleepRemainingSecondsFrom(sleep);
      _sleepCountdownExpired = false;
      if (!mounted) return;
      setState(() {
        _signDetail = signDetail;
        _earnCoin = earnCoin;
        _sleep = sleep;
        _tasks = tasks;
        _loading = false;
      });
      _syncSleepTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<Map<String, dynamic>> _safeDetail(
      Future<Map<String, dynamic>> request) async {
    try {
      return await request;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _claimSign() async {
    await _runAction('sign', () => LKApi.claimWelfareSign());
  }

  Future<void> _claimEarnCoin() async {
    await _runAction(
        'earn-coin', () => LKApi.claimWelfareEarnCoin(taskKey: _earnTaskKey));
  }

  Future<void> _startSleep() async {
    await _runAction('sleep-start', LKApi.startWelfareSleep);
  }

  Future<void> _claimSleep() async {
    await _runAction('sleep-claim', LKApi.claimWelfareSleep);
  }

  Future<void> _claimTask(Map<String, dynamic> task) async {
    final taskId = _taskId(task);
    final taskKey = _taskKey(task);
    await _runAction('task:$taskId:$taskKey',
        () => LKApi.claimWelfareTask(taskId: taskId, taskKey: taskKey));
  }

  Future<void> _claimTreasure(Map<String, dynamic> treasure) async {
    final campaignId = _int(
        treasure['campaign_id'] ?? treasure['campaignId'] ?? treasure['id']);
    final campaignDay = _int(
        treasure['campaign_day'] ?? treasure['campaignDay'] ?? treasure['day']);
    await _runAction(
        'treasure',
        () => LKApi.claimWelfareTreasureBox(
            campaignId: campaignId, campaignDay: campaignDay));
  }

  Future<void> _runAction(
      String action, Future<Map<String, dynamic>> Function() request) async {
    if (_action.isNotEmpty) return;
    setState(() => _action = action);
    try {
      await request();
      if (!mounted) return;
      showLkError(context, '操作成功');
      await _load(forceTaskList: action.startsWith('task:'));
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _action = '');
    }
  }

  Map<String, dynamic> _root(Map<String, dynamic> data) {
    return _map(data['home']) ?? _map(data['welfare']) ?? data;
  }

  Map<String, dynamic>? _map(dynamic value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  dynamic _taskField(Map<String, dynamic> task, List<String> keys,
      [int depth = 0]) {
    for (final key in keys) {
      if (task.containsKey(key) && task[key] != null) return task[key];
    }
    if (depth >= 4) return null;
    for (final key in const [
      'task',
      'task_info',
      'taskInfo',
      'task_data',
      'taskData',
      'reward_task',
      'rewardTask',
      'data',
      'detail',
      'payload',
    ]) {
      final nested = _map(task[key]);
      if (nested != null) {
        final value = _taskField(nested, keys, depth + 1);
        if (value != null) return value;
      }
    }
    return null;
  }

  int _taskId(Map<String, dynamic> task) =>
      _int(_deepField(task, const ['task_id', 'taskId', 'taskID']));

  String _taskKey(Map<String, dynamic> task) =>
      _text(_deepField(task, const ['task_key', 'taskKey', 'taskKEY', 'key']));

  String _taskType(Map<String, dynamic> task) =>
      _text(_deepField(task, const ['task_type', 'taskType', 'type', 'action']))
          .toLowerCase();

  bool _isEarnCoinTask(Map<String, dynamic> task) {
    final text =
        '${_taskTitle(task)} ${_taskDescription(task)} ${_taskKey(task)} '
                '${_taskType(task)}'
            .toLowerCase();
    final raw = task.toString().toLowerCase();
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final readingNode = (raw.contains('reward_nodes') ||
            raw.contains('reward_days') ||
            raw.contains('week_rewards') ||
            raw.contains('progress_nodes')) &&
        (raw.contains('read') ||
            raw.contains('reader') ||
            raw.contains('active_seconds') ||
            raw.contains('read_duration') ||
            raw.contains('阅读') ||
            raw.contains('轻币'));
    return text.contains('15分钟') ||
        text.contains('15min') ||
        text.contains('阅读赚轻币') ||
        text.contains('earn_coin') ||
        text.contains('reading_reward') ||
        text.contains('read_coin') ||
        text.contains('daily_read_15m') ||
        raw.contains('daily_read_15m') ||
        compact.contains('15分钟') ||
        compact.contains('15min') ||
        readingNode ||
        (raw.contains('progress_minutes') &&
            (raw.contains('reward_nodes') ||
                raw.contains('reward_days') ||
                raw.contains('read_duration')));
  }

  bool _isSignTask(Map<String, dynamic> task) {
    final text =
        '${_taskTitle(task)} ${_taskDescription(task)} ${_taskKey(task)} '
                '${_taskType(task)}'
            .toLowerCase();
    final raw = task.toString().toLowerCase();
    return text.contains('签到') ||
        text.contains('sign_in') ||
        text.contains('seven_day_sign') ||
        text.contains('new_user_7day_sign') ||
        text.contains('daily_sign') ||
        text.contains('7day') ||
        text.contains('7_day') ||
        text.contains('7日') ||
        text.contains('七日') ||
        text.contains('1-7') ||
        text.contains('1～7') ||
        raw.contains('new_user_7day_sign') ||
        (raw.contains('daily_all') && raw.contains('reward')) ||
        _listFor(task, const ['sign_days', 'daily_all']).length >= 2;
  }

  bool _hasTaskIdentity(Map<String, dynamic> task) =>
      _taskId(task) > 0 || _taskKey(task).isNotEmpty;

  /// 七日阅读/签到进度在任务接口中会被拆成“第 N 天”的独立行，
  /// 但它们已经由上方专用卡片展示，不应在通用任务奖励中重复出现。
  bool _isRewardScheduleTask(Map<String, dynamic> task) {
    final title = _taskTitle(task).replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^第[1-7]天$').hasMatch(title);
  }

  List<Map<String, dynamic>> _visibleTasks(
          Iterable<Map<String, dynamic>> tasks) =>
      tasks
          .where((task) =>
              _hasTaskIdentity(task) &&
              !_isRewardScheduleTask(task) &&
              !_isEarnCoinTask(task) &&
              !_isSignTask(task))
          .toList();

  bool _isSleepTask(Map<String, dynamic> task) {
    final text =
        '${_taskTitle(task)} ${_taskDescription(task)} ${_taskKey(task)} '
                '${_taskType(task)}'
            .toLowerCase();
    return text.contains('睡觉') || text.contains('sleep');
  }

  List<Map<String, dynamic>> get _displayTasks => _visibleTasks(_tasks)
      .where((task) => _sleepData.isEmpty || !_isSleepTask(task))
      .toList();

  Map<String, dynamic> _sleepDataFor(Map<String, dynamic> data) {
    final nested = _map(data['detail']) ??
        _map(data['sleep_detail']) ??
        _map(data['sleepDetail']) ??
        _map(data['sleep']) ??
        _map(data['result']) ??
        _map(data['payload']) ??
        _map(data['data']) ??
        const <String, dynamic>{};
    // 外层是任务汇总状态,detail 才是睡眠任务的实际生命周期状态。
    // 例如外层可能为 in_progress,但 detail.status=idle,此时仍应允许开始睡觉。
    if (nested.isNotEmpty &&
        (nested.containsKey('status') ||
            nested.containsKey('sleep_start_at') ||
            nested.containsKey('remaining_seconds'))) {
      return {...data, ...nested};
    }
    if (data.containsKey('task_key') ||
        data.containsKey('sleep_start_at') ||
        data.containsKey('claim_at_text') ||
        data.containsKey('button_text')) {
      return data;
    }
    return nested;
  }

  Map<String, dynamic> get _sleepData => _sleepDataFor(_sleep);

  String get _sleepStatus =>
      _text(_taskField(_sleepData, const ['status', 'sleep_status']))
          .toLowerCase();

  bool get _sleepClaimed =>
      _flag(_taskField(_sleepData, const ['claimed', 'is_claimed'])) ||
      _statusIs(_sleepStatus, const ['claimed', 'received']);

  bool get _sleepClaimable {
    final action =
        _text(_taskField(_sleepData, const ['button_action', 'buttonAction']))
            .toLowerCase();
    return !_sleepClaimed &&
        (_flag(_taskField(_sleepData, const [
              'claimable',
              'can_claim',
              'is_claimable',
            ])) ||
            _statusIs(_sleepStatus,
                const ['claimable', 'ready', 'completed', 'finished']) ||
            action == 'claim' ||
            action == 'receive');
  }

  bool get _sleepStarted {
    if (_sleepClaimed || _sleepClaimable) return true;
    final startedAt =
        _text(_taskField(_sleepData, const ['sleep_start_at', 'started_at']));
    return startedAt.isNotEmpty ||
        _statusIs(_sleepStatus, const ['sleeping', 'in_progress', 'running']) ||
        _sleepRemainingSeconds > 0;
  }

  String get _sleepButtonText =>
      _text(_taskField(_sleepData, const ['button_text', 'buttonText']));

  String get _sleepDescription => _text(_taskField(
      _sleepData, const ['sub_title', 'subtitle', 'description', 'task_desc']));

  String get _sleepCountdown {
    if (_sleepRemainingSeconds > 0) {
      return _formatDuration(_sleepRemainingSeconds);
    }
    if (_sleepCountdownExpired) return '';
    return _text(
        _taskField(_sleepData, const ['countdown_text', 'countdownText']));
  }

  String get _sleepClaimAt => _text(_taskField(_sleepData,
      const ['claim_at_text', 'claimAtText', 'target_duration_text']));

  int _sleepRemainingSecondsFrom(Map<String, dynamic> data) {
    final sleep = _sleepDataFor(data);
    for (final key in const [
      'countdown_seconds',
      'countdownSeconds',
      'remaining_seconds',
      'remainingSeconds',
      'remain_seconds',
      'remainSeconds',
    ]) {
      final seconds = _int(_taskField(sleep, [key]));
      if (seconds > 0) return seconds;
    }
    final target = _parseServerDate(_taskField(sleep, const [
      'claim_at',
      'claimAt',
      'sleep_end_at',
      'sleepEndAt',
      'end_at',
      'endAt',
      'target_at',
      'targetAt',
    ]));
    if (target != null) {
      final remaining = target.difference(DateTime.now()).inSeconds;
      if (remaining > 0) return remaining;
    }
    final countdownText =
        _text(_taskField(sleep, const ['countdown_text', 'countdownText']));
    return _parseCountdownText(countdownText);
  }

  DateTime? _parseServerDate(dynamic value) {
    if (value is num) {
      final number = value.toInt();
      if (number <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
          number > 20000000000 ? number : number * 1000);
    }
    final text = _text(value).trim();
    if (text.isEmpty) return null;
    final numeric = int.tryParse(text);
    if (numeric != null && numeric > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
          numeric > 20000000000 ? numeric : numeric * 1000);
    }
    return DateTime.tryParse(text);
  }

  int _parseCountdownText(String text) {
    final value = text.trim();
    if (value.isEmpty) return 0;
    final parts = value.split(':');
    if (parts.length >= 2 &&
        parts.every((part) => int.tryParse(part) != null)) {
      final numbers = parts.map(int.parse).toList();
      if (numbers.length == 2) return numbers[0] * 60 + numbers[1];
      return numbers[numbers.length - 3] * 3600 +
          numbers[numbers.length - 2] * 60 +
          numbers[numbers.length - 1];
    }
    final match = RegExp(
            r'(?:(\d+)\s*(?:小时|时|h))?\s*(?:(\d+)\s*(?:分钟|分|m))?\s*(?:(\d+)\s*(?:秒|s))?')
        .firstMatch(value);
    if (match == null) return 0;
    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  void _syncSleepTimer() {
    _sleepTimer?.cancel();
    if (_sleepRemainingSeconds <= 0 || _sleepClaimed || _sleepClaimable) {
      return;
    }
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_sleepRemainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _sleepRemainingSeconds = 0;
          _sleepCountdownExpired = true;
        });
        _load();
        return;
      }
      setState(() => _sleepRemainingSeconds--);
    });
  }

  Map<String, dynamic> _earnDataFor(Map<String, dynamic> data) {
    // 详情接口已经直接返回阅读任务时，优先保留这一层。
    // 某些响应会同时带有通用 data 字段；它并不一定是阅读任务本身。
    if (data.containsKey('task_key') ||
        data.containsKey('progress') ||
        data.containsKey('button_text') ||
        data.containsKey('reader_target')) {
      return data;
    }
    return _map(data['earn_coin']) ??
        _map(data['earnCoin']) ??
        _map(data['welfare_earn_coin']) ??
        _map(data['reading_reward']) ??
        _map(data['read_earn']) ??
        _map(data['reading']) ??
        _map(data['module']) ??
        _map(data['module_data']) ??
        _map(data['reward']) ??
        _map(data['detail']) ??
        _map(data['result']) ??
        _map(data['payload']) ??
        _map(data['data']) ??
        data;
  }

  Map<String, dynamic> get _earnData => _earnDataFor(_earnCoin);

  String get _earnTaskKey => _text(
      _deepField(_earnData, const ['task_key', 'taskKey', 'reading_task_key']));

  bool get _earnClaimed {
    final status = _taskField(_earnData, const [
      'taskClaimedToday',
      'task_claimed_today',
      'today_claimed',
      'today_reward_claimed',
      'isClaimedToday',
      'today_reward_status',
      'reward_status',
      'status',
      'reward_result',
      'claimed',
      'is_claimed',
    ]);
    final nestedStatus = _deepField(_earnData, const [
      'taskClaimedToday',
      'task_claimed_today',
      'today_claimed',
      'today_reward_claimed',
      'isClaimedToday',
      'today_reward_status',
      'reward_status',
      'claimed',
      'is_claimed',
    ]);
    return _flag(status) ||
        _statusIs(status, const ['claimed', 'received', 'rewarded']) ||
        _flag(nestedStatus) ||
        _statusIs(nestedStatus, const ['claimed', 'received', 'rewarded']);
  }

  bool get _earnClaimable {
    if (_earnClaimed) return false;
    final state = _deepState(
      _earnData,
      flagKeys: const [
        'claimable',
        'can_claim',
        'is_claimable',
        'eligible',
        'is_eligible',
        'completed',
        'is_completed',
        'finished',
        'is_finished',
        'done',
        'is_done',
        'achieved',
        'is_achieved',
        'taskCompletedToday',
        'task_completed_today',
        'taskClaimableToday',
        'task_claimable_today',
      ],
      statusKeys: const [
        'claim_status',
        'reward_status',
        'status',
        'reward_result',
      ],
      trueStatuses: const [
        'claimable',
        'can_claim',
        'ready',
        'eligible',
        'completed',
        'finished',
        'done',
        'achieved',
      ],
      falseStatuses: const [
        'claimed',
        'received',
        'in_progress',
        'pending',
        'not_ready',
        'not_eligible',
        'incomplete',
      ],
    );
    if (state != null) return state;
    return _earnProgressSeconds >= _earnTargetSeconds;
  }

  List<Map<String, dynamic>> get _earnDayRewards => _listFor(_earnData, const [
        'nodes',
        'week_rewards',
        'week_plan',
        'day_rewards',
        'reward_days',
        'rewardDays',
        'reward_nodes',
        'rewardNodes',
        'reward_items',
        'rewardItems',
        'reward_list',
        'rewardList',
        'task_nodes',
        'taskNodes',
        'rewards',
        'days',
        'day_list',
        'items',
        'list',
      ]);

  int get _earnCurrentDay {
    final direct = _int(_taskField(_earnData, const [
      'campaign_day',
      'current_day',
      'today_day',
      'day',
      'reward_day',
      'current_reward_day',
      'today_reward_day',
    ]));
    if (direct > 0) return direct.clamp(1, 7);
    final index = _earnDayRewards.indexWhere((day) => !_dayClaimed(day));
    return index < 0 ? 7 : index + 1;
  }

  int get _earnProgressSeconds {
    var foundSeconds = false;
    for (final key in const [
      'active_seconds_total',
      'active_seconds',
      'read_duration_seconds',
      'today_read_seconds',
      'progress_seconds',
      'current_seconds',
    ]) {
      final value = _deepField(_earnData, [key]);
      if (value == null) continue;
      foundSeconds = true;
      final seconds = _durationSeconds(value);
      if (seconds > 0) return seconds;
    }
    for (final key in const [
      'progress_minutes',
      'today_read_minutes',
      'read_minutes',
      'active_minutes',
    ]) {
      final minutes = _deepField(_earnData, [key]);
      if (minutes == null) continue;
      final value = _durationSeconds(minutes);
      if (value > 0) return value * 60;
    }
    if (foundSeconds) return 0;
    final progress = _int(_deepField(_earnData, const [
      'progress',
      'progress_percent',
      'today_progress',
      'total_progress',
    ]));
    if (progress <= 1) return progress * 900;
    if (progress <= 100) return (progress * 9).round();
    return progress;
  }

  String get _earnProgressText => _text(_deepField(_earnData, const [
        'read_duration_text',
        'progress_text',
        'progressText',
      ]));

  int get _earnTargetSeconds {
    final seconds = _int(_deepField(_earnData, const [
      'target_seconds',
      'required_seconds',
      'duration_seconds',
      'reader_target_seconds',
    ]));
    if (seconds > 0) return seconds;
    final minutes = _int(_deepField(_earnData, const [
      'target_minutes',
      'required_minutes',
      'duration_minutes',
      'reader_target_minutes',
    ]));
    return minutes > 0 ? minutes * 60 : 900;
  }

  int _dayNumber(Map<String, dynamic> day, int fallback) =>
      _int(_taskField(day, const [
                'day',
                'day_num',
                'dayNumber',
                'campaign_day',
                'reward_day',
                'day_index',
                'sort_index',
              ])) >
              0
          ? _int(_taskField(day, const [
              'day',
              'day_num',
              'dayNumber',
              'campaign_day',
              'reward_day',
              'day_index',
              'sort_index',
            ]))
          : fallback;

  int _dayReward(Map<String, dynamic> day) => _int(_taskField(day, const [
        'reward_amount',
        'rewardAmount',
        'reward_coin',
        'light_coin',
        'daily_coin',
        'today_coin',
        'today_reward_coin',
        'today_reward_amount',
        'daily_amount',
        'coin',
        'amount',
        'reward',
      ]));

  bool _dayClaimed(Map<String, dynamic> day) {
    final status = _taskField(day, const [
      'reward_status',
      'status',
      'claimed',
      'signed',
      'completed',
      'is_claimed',
      'taskClaimedToday',
      'task_claimed_today',
      'today_claimed',
      'today_reward_claimed',
      'isClaimedToday',
    ]);
    return _flag(status) ||
        _statusIs(status, const ['claimed', 'completed', 'signed', 'done']);
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is List) {
      final result = <Map<String, dynamic>>[];
      for (var index = 0; index < value.length; index++) {
        final item = value[index];
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        } else if (item is num || int.tryParse(item.toString()) != null) {
          result.add({'day': index + 1, 'reward_amount': _int(item)});
        }
      }
      return result;
    }
    if (value is Map) {
      final direct = Map<String, dynamic>.from(value);
      final hasDayFields = direct.keys.any((key) => const [
            'day',
            'day_num',
            'dayNumber',
            'reward_day',
            'reward_amount',
            'reward_coin',
            'daily_coin',
          ].contains(key));
      if (hasDayFields) return [direct];

      final result = <Map<String, dynamic>>[];
      for (final entry in direct.entries) {
        final digits = entry.key.replaceAll(RegExp(r'[^0-9]'), '');
        final day = int.tryParse(digits);
        if (day == null || day <= 0 || day > 7) continue;
        if (entry.value is Map) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          item.putIfAbsent('day', () => day);
          result.add(item);
        } else if (entry.value is num ||
            int.tryParse(entry.value.toString()) != null) {
          result.add({'day': day, 'reward_amount': _int(entry.value)});
        }
      }
      return result;
    }
    return const [];
  }

  /// 官方福利模型会把阅读目标放在 reward_nodes/task_nodes 的子节点中，
  /// 这里只做只读字段搜索，不改变或合并服务器返回的数据。
  dynamic _deepField(dynamic value, List<String> keys, [int depth = 0]) {
    if (depth > 6) return null;
    if (value is Map) {
      for (final key in keys) {
        if (value.containsKey(key) && value[key] != null) return value[key];
      }
      for (final child in value.values) {
        final found = _deepField(child, keys, depth + 1);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final child in value) {
        final found = _deepField(child, keys, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _listFor(
      Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final direct = _maps(data[key]);
      if (direct.isNotEmpty) return direct;
      final nested = _map(data[key]);
      if (nested != null) {
        for (final listKey in const ['list', 'items', 'data']) {
          final list = _maps(nested[listKey]);
          if (list.isNotEmpty) return list;
        }
        for (final listKey in const [
          'days',
          'day_list',
          'week_rewards',
          'week_plan',
          'reward_days',
          'reward_nodes',
          'rewardNodes',
          'reward_items',
          'rewardItems',
          'reward_list',
          'rewardList',
          'task_nodes',
          'taskNodes',
          'rewards',
          'reward',
          'daily_rewards',
          'daily_coin',
          'reward_amounts',
          'sign_days',
          'sign_day_list',
          'signDayList',
          'daily_all',
          'list',
          'items',
          'data',
        ]) {
          final list = _maps(nested[listKey]);
          if (list.isNotEmpty) return list;
        }
      }
    }
    return const [];
  }

  /// 福利接口不同版本会把任务放在 data/result/items 等多层结构中。
  /// 只收集带任务字段的对象，避免把签到天数或宝箱信息误当成任务。
  List<Map<String, dynamic>> _extractTasks(dynamic value) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    void visit(dynamic node) {
      if (node is List) {
        for (final item in node) {
          visit(item);
        }
        return;
      }
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node);
      final title = _taskTitle(map);
      final taskKey = _taskKey(map);
      final id = _taskId(map);
      final hasTaskMarker = title.isNotEmpty && (taskKey.isNotEmpty || id > 0);
      final isSignTask = _isSignTask(map);
      if (hasTaskMarker && !isSignTask && !_isEarnCoinTask(map)) {
        final identity = taskKey.isNotEmpty ? taskKey : '$title:$id';
        if (seen.add(identity)) result.add(map);
      }
      for (final child in map.values) {
        visit(child);
      }
    }

    visit(value);
    return result;
  }

  Map<String, dynamic> _section(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _map(data[key]);
      if (value != null) return value;
    }
    return const {};
  }

  dynamic _pick(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key) && data[key] != null) return data[key];
    }
    return null;
  }

  int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _durationSeconds(dynamic value) {
    if (value is num) return value.round();
    if (value is Map) {
      final nested = _deepField(value, const [
        'seconds',
        'active_seconds',
        'read_duration_seconds',
        'value',
        'total_progress',
      ]);
      return nested == null ? 0 : _durationSeconds(nested);
    }
    final text = value?.toString().trim() ?? '';
    final clock = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(text);
    if (clock != null) {
      final first = int.tryParse(clock.group(1)!) ?? 0;
      final second = int.tryParse(clock.group(2)!) ?? 0;
      final third = int.tryParse(clock.group(3) ?? '') ?? 0;
      return clock.group(3) == null
          ? first * 60 + second
          : first * 3600 + second * 60 + third;
    }
    return int.tryParse(text) ?? double.tryParse(text)?.round() ?? 0;
  }

  String _text(dynamic value) => value?.toString() ?? '';

  bool _flag(dynamic value) {
    return value == true || value == 1 || value == '1' || value == 'true';
  }

  bool _statusIs(dynamic value, List<String> words) {
    final status = _text(value).toLowerCase();
    return words.any(status.contains);
  }

  int _coinBalance(Map<String, dynamic> root) {
    final wallet = _map(root['wallet']) ?? _map(root['balance']);
    final value = _pick(root, const [
      'coin_balance',
      'light_coin',
      'today_light_coin',
      'coins',
      'coin',
    ]);
    return _int(value ??
        _pick(wallet ?? const {}, const [
          'coin_balance',
          'light_coin',
          'coins',
          'coin',
        ]));
  }

  Map<String, dynamic> get _rootData => _root(_home ?? const {});

  Map<String, dynamic> get _sign {
    const keys = [
      'sign',
      'sign_module',
      'welfare_sign',
      'daily_sign',
      'seven_day_sign',
      'sign_7day',
      'new_user_7day_sign_v1',
      'sign_in',
      'free_sign',
      'data',
      'result',
      'detail',
    ];
    if (_signDetail.isNotEmpty) {
      final detail = _section(_signDetail, keys);
      if (detail.isNotEmpty) return detail;
      return _signDetail;
    }
    return _section(_rootData, keys);
  }

  Map<String, dynamic> get _treasure => _section(_rootData,
      const ['treasure_box', 'treasureBox', 'daily_treasure_box_v1']);

  List<Map<String, dynamic>> get _signDays {
    final days = _listFor(_sign, const [
      'days',
      'day_list',
      'week_rewards',
      'reward_days',
      'rewardDays',
      'reward_items',
      'rewardItems',
      'reward_list',
      'rewardList',
      'week_plan',
      'sign_days',
      'sign_day_list',
      'signDayList',
      'day_rewards',
      'rewards',
      'reward',
      'items',
      'daily_rewards',
      'daily_coin',
      'reward_amounts',
      'daily_all',
      'list',
    ]);
    return days.isNotEmpty ? days : _weekDayMaps(_sign);
  }

  List<Map<String, dynamic>> _weekDayMaps(dynamic value, [int depth = 0]) {
    if (depth > 5) return const [];
    if (value is Map) {
      final days = <Map<String, dynamic>>[];
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final match = RegExp(r'(?:week[_-]?day|day)[_-]?(\d+)').firstMatch(key);
        if (match == null) continue;
        final day = int.tryParse(match.group(1) ?? '') ?? 0;
        if (day <= 0 || day > 7) continue;
        if (entry.value is Map) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          item.putIfAbsent('day', () => day);
          days.add(item);
        } else if (entry.value is num ||
            int.tryParse(entry.value.toString()) != null) {
          days.add({'day': day, 'reward_amount': _int(entry.value)});
        }
      }
      if (days.isNotEmpty) {
        days.sort((a, b) => _dayNumber(a, 0).compareTo(_dayNumber(b, 0)));
        return days;
      }
      for (final child in value.values) {
        final nested = _weekDayMaps(child, depth + 1);
        if (nested.isNotEmpty) return nested;
      }
    } else if (value is List) {
      for (final child in value) {
        final nested = _weekDayMaps(child, depth + 1);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  int get _signCurrentDay {
    final direct = _int(_taskField(_sign, const [
      'campaign_day',
      'current_day',
      'today_day',
      'sign_day',
      'current_sign_day',
      'reward_day',
      'day',
    ]));
    if (direct > 0) return direct.clamp(1, 7);
    final index = _signDays.indexWhere((day) => !_dayClaimed(day));
    return index < 0 ? 7 : index + 1;
  }

  bool get _signed {
    final status = _text(_taskField(_sign, const [
      'sign_status',
      'signed_status',
      'status',
      'today_status',
    ])).toLowerCase();
    if (status == 'not_signed' || status == 'unsigned') return false;
    return _flag(_taskField(_sign, const [
          'signed',
          'is_signed',
          'signed_today',
          'today_claimed',
          'today_signed',
        ])) ||
        _statusIs(status, const ['signed', 'completed', 'claimed']);
  }

  bool _taskClaimable(Map<String, dynamic> task) {
    if (_taskClaimed(task)) return false;
    final state = _deepState(
      task,
      flagKeys: const [
        'claimable',
        'can_claim',
        'is_claimable',
        'eligible',
        'is_eligible',
        'completed',
        'is_completed',
        'finished',
        'is_finished',
        'done',
        'is_done',
        'achieved',
        'is_achieved',
        'taskCompletedToday',
        'task_completed_today',
        'taskClaimableToday',
        'task_claimable_today',
      ],
      statusKeys: const [
        'claim_status',
        'reward_status',
        'status',
        'reward_result',
      ],
      trueStatuses: const [
        'claimable',
        'can_claim',
        'ready',
        'eligible',
        'completed',
        'finished',
        'done',
        'achieved',
      ],
      falseStatuses: const [
        'claimed',
        'received',
        'in_progress',
        'pending',
        'not_ready',
        'not_eligible',
        'incomplete',
      ],
    );
    if (state != null) return state;
    return _taskProgressComplete(task);
  }

  bool _taskClaimed(Map<String, dynamic> task) {
    return _deepState(
          task,
          flagKeys: const [
            'claimed',
            'is_claimed',
            'reward_claimed',
            'is_rewarded',
            'received',
            'is_received',
            'today_claimed',
            'today_reward_claimed',
            'taskClaimedToday',
            'task_claimed_today',
          ],
          statusKeys: const [
            'claim_status',
            'reward_status',
            'status',
            'reward_result',
          ],
          trueStatuses: const ['claimed', 'received', 'rewarded'],
          falseStatuses: const [
            'unclaimed',
            'not_claimed',
            'claimable',
            'in_progress',
            'pending',
          ],
        ) ==
        true;
  }

  bool _taskProgressComplete(Map<String, dynamic> task) {
    final current = _int(_deepField(task, const [
      'progress',
      'current',
      'current_count',
      'progress_count',
      'completed_count',
      'count',
      'value',
    ]));
    final total = _int(_deepField(task, const [
      'total',
      'target',
      'required',
      'goal',
      'need',
      'target_count',
      'required_count',
    ]));
    if (total > 0 && current >= total) return true;
    final percent = _int(_deepField(task, const [
      'progress_percent',
      'progressPercentage',
      'completion_percent',
    ]));
    return percent >= 100;
  }

  bool? _deepState(
    dynamic value, {
    required List<String> flagKeys,
    required List<String> statusKeys,
    required List<String> trueStatuses,
    required List<String> falseStatuses,
  }) {
    int visit(dynamic node) {
      var result = -1;
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        for (final key in flagKeys) {
          if (!map.containsKey(key)) continue;
          final parsed = _parseFlag(map[key]);
          if (parsed == true) return 1;
          if (parsed == false) result = 0;
        }
        for (final key in statusKeys) {
          if (!map.containsKey(key)) continue;
          final status = _statusState(map[key],
              trueStatuses: trueStatuses, falseStatuses: falseStatuses);
          if (status == true) return 1;
          if (status == false) result = 0;
        }
        for (final child in map.values) {
          final nested = visit(child);
          if (nested == 1) return 1;
          if (nested == 0) result = 0;
        }
      } else if (node is List) {
        for (final child in node) {
          final nested = visit(child);
          if (nested == 1) return 1;
          if (nested == 0) result = 0;
        }
      }
      return result;
    }

    final result = visit(value);
    return result < 0 ? null : result == 1;
  }

  bool? _statusState(dynamic value,
      {required List<String> trueStatuses,
      required List<String> falseStatuses}) {
    final status = _text(value).toLowerCase().replaceAll(' ', '_');
    if (status.isEmpty) return null;
    if (falseStatuses.any(status.contains)) return false;
    if (trueStatuses.any(status.contains)) return true;
    return null;
  }

  bool? _parseFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = _text(value).toLowerCase();
    if (const ['1', 'true', 'yes', 'y', '是'].contains(text)) return true;
    if (const ['0', 'false', 'no', 'n', '否'].contains(text)) return false;
    return null;
  }

  String _taskTitle(Map<String, dynamic> task) => _text(_deepField(task, const [
        'task_title',
        'taskTitle',
        'task_name',
        'title',
        'name',
      ]));

  String _displayTaskTitle(String title) {
    final normalized = title.replaceAll(RegExp(r'\s+'), '');
    if (normalized == '其它任务' || normalized == '其他任务') {
      return '浏览一个作品';
    }
    return title;
  }

  String _taskDescription(Map<String, dynamic> task) => _text(_deepField(task,
      const ['task_desc', 'taskDesc', 'description', 'desc', 'subtitle']));

  int _taskReward(Map<String, dynamic> task) => _int(_deepField(task, const [
        'reward_amount',
        'rewardAmount',
        'reward_coin',
        'reward',
      ]));

  String _rewardText(int reward) => reward > 0 ? '+$reward 轻币' : '轻币奖励';

  @override
  Widget build(BuildContext context) {
    if (!LKClient.shared.session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('任务中心')),
        body: const Center(child: Text('登录后才能使用任务中心')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('任务中心')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _home == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _loadingCard(78),
                  const SizedBox(height: 10),
                  _loadingCard(145),
                  const SizedBox(height: 10),
                  _loadingCard(120),
                ],
              )
            : _error != null && _home == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 260,
                        child: Center(
                          child: FilledButton.tonal(
                            onPressed: _load,
                            child: Text(_error!),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      _buildBalanceCard(_rootData),
                      const SizedBox(height: 10),
                      _buildSignCard(),
                      if (_earnData.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildEarnCoinCard(),
                      ],
                      if (_sleepData.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildSleepCard(),
                      ],
                      if (_displayTasks.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildTaskCard(),
                      ],
                      if (_treasure.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildTreasureCard(),
                      ],
                      if (kDebugMode && _enableWelfareProtocolProbe) ...[
                        const SizedBox(height: 10),
                        _buildServerValidationCard(),
                      ],
                      const SizedBox(height: 12),
                      Text('奖励以站点实际返回结果为准',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12)),
                    ],
                  ),
      ),
    );
  }

  Widget _buildBalanceCard(Map<String, dynamic> root) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.monetization_on_outlined,
                color: scheme.onPrimaryContainer, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前轻币',
                    style: TextStyle(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 3),
                Text('${_coinBalance(root)}',
                    style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WelfareCoinRecordsPage()),
              ),
              child: const Text('轻币记录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignCard() {
    final days = _signDays;
    final currentDay = _signCurrentDay;
    final signed = _signed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                    child: Text('每日签到',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold))),
                FilledButton.tonal(
                  onPressed: signed || _action == 'sign' ? null : _claimSign,
                  child: Text(signed
                      ? '今日已签到'
                      : _action == 'sign'
                          ? '处理中'
                          : '签到'),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('每日签到可获得对应轻币奖励',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
            if (days.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: days.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final day = days[index];
                    final claimed = _dayClaimed(day);
                    final reward = _dayReward(day);
                    final dayNo = _dayNumber(day, index + 1);
                    final active = dayNo == currentDay;
                    return Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 7),
                      decoration: BoxDecoration(
                        color: claimed || active
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: active
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('第$dayNo天',
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 3),
                          Text(reward > 0 ? '+$reward' : '—',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 1),
                          Text(claimed ? '已签到' : '轻币',
                              style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEarnCoinCard() {
    final target = _earnTargetSeconds;
    final progress = (_earnProgressSeconds / target).clamp(0.0, 1.0);
    final rewards = _earnDayRewards;
    final currentDay = _earnCurrentDay;
    final claimed = _earnClaimed;
    final claimable = _earnClaimable;
    final progressMinutes = _earnProgressSeconds ~/ 60;
    final targetMinutes = (target / 60).ceil();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('15分钟阅读',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                FilledButton.tonal(
                  onPressed: !claimable || _action == 'earn-coin'
                      ? null
                      : _claimEarnCoin,
                  child: Text(claimed
                      ? '今日已领取'
                      : _action == 'earn-coin'
                          ? '处理中'
                          : claimable
                              ? '领取'
                              : '未达标'),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('每天阅读15分钟可获得对应轻币奖励',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 7),
            const SizedBox(height: 6),
            Text(
                _earnProgressText.isNotEmpty
                    ? '今日阅读 $_earnProgressText'
                    : '今日阅读 $progressMinutes / $targetMinutes 分钟',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
            if (rewards.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: rewards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final day = rewards[index];
                    final dayNo = _dayNumber(day, index + 1);
                    final dayClaimed = _dayClaimed(day);
                    final active = dayNo == currentDay;
                    return Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 7),
                      decoration: BoxDecoration(
                        color: dayClaimed || active
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: active
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('第$dayNo天',
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 3),
                          Text('+${_dayReward(day)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 1),
                          Text(dayClaimed ? '已领取' : '轻币',
                              style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSleepCard() {
    final claimed = _sleepClaimed;
    final claimable = _sleepClaimable;
    final started = _sleepStarted;
    final reward = _taskReward(_sleepData);
    final action = claimed
        ? ''
        : claimable
            ? 'sleep-claim'
            : started
                ? ''
                : 'sleep-start';
    final buttonText = claimed
        ? '今日已领取'
        : claimable
            ? '领取奖励'
            : started
                ? (_sleepButtonText.isEmpty ? '睡觉中' : _sleepButtonText)
                : (_sleepButtonText.isEmpty ? '开始睡觉' : _sleepButtonText);
    final description = _sleepDescription.isNotEmpty
        ? _sleepDescription
        : claimed
            ? '今日睡眠奖励已领取'
            : started
                ? '已开始睡觉，等待服务器开放领取'
                : '开始后由服务器计时，到时间即可领取奖励';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    claimed ? Icons.check : Icons.bedtime_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('睡觉赚轻币',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      if (reward > 0)
                        Text(_rewardText(reward),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12)),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: action.isEmpty || _action.isNotEmpty
                      ? null
                      : action == 'sleep-claim'
                          ? _claimSleep
                          : _startSleep,
                  child: Text(_action == action && action.isNotEmpty
                      ? '处理中'
                      : buttonText),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(description,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13)),
            if (_sleepCountdown.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('倒计时：$_sleepCountdown',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            if (_sleepClaimAt.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('领取时间：$_sleepClaimAt',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('任务奖励',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final task in _displayTasks) _buildTaskTile(task),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(Map<String, dynamic> task) {
    final title = _displayTaskTitle(_taskTitle(task));
    final description = _taskDescription(task);
    final claimed = _taskClaimed(task);
    final claimable = !claimed && _taskClaimable(task);
    final taskId = _taskId(task);
    final taskKey = _taskKey(task);
    final key = 'task:$taskId:$taskKey';
    final progress = _int(_taskField(task, const ['progress', 'current']));
    final total = _int(_taskField(task, const ['total', 'target', 'required']));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(claimed ? Icons.check : Icons.task_alt_outlined),
      ),
      title: Text(title.isEmpty ? '每日任务' : title),
      subtitle: Text([
        if (description.isNotEmpty) description,
        if (total > 0) '$progress / $total',
        _rewardText(_taskReward(task)),
      ].join(' · ')),
      trailing: claimable
          ? FilledButton.tonal(
              onPressed: _action == key ? null : () => _claimTask(task),
              child: Text(_action == key ? '处理中' : '领取'),
            )
          : Text(claimed ? '已领取' : '进行中',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }

  Widget _buildTreasureCard() {
    final claimable = _flag(_pick(_treasure, const [
          'claimable',
          'can_claim',
          'opened',
        ])) ||
        _statusIs(_pick(_treasure, const ['status', 'reward_status']),
            const ['claimable', 'ready']);
    final reward = _int(_pick(_treasure, const [
      'reward_coin',
      'reward_amount',
      'reward',
      'rewardAmount',
    ]));
    final title = _text(_pick(_treasure, const [
      'title',
      'treasureBoxLabel',
      'name',
    ]));
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.card_giftcard)),
        title: Text(title.isEmpty ? '每日宝箱' : title),
        subtitle: Text(reward > 0 ? '可获得 $reward 轻币' : '完成进度后可领取奖励'),
        trailing: claimable
            ? FilledButton.tonal(
                onPressed: _action == 'treasure'
                    ? null
                    : () => _claimTreasure(_treasure),
                child: Text(_action == 'treasure' ? '处理中' : '领取'),
              )
            : const Text('进行中'),
      ),
    );
  }

  Widget _buildServerValidationCard() {
    final snapshot = LKReadingSession.shared.snapshot();
    final hasSession = snapshot != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('服务器验证（调试）',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(
              hasSession
                  ? '使用最近一次真实阅读会话：已阅读 ${snapshot.readDurationSeconds} 秒，进度 ${snapshot.progressPercent}%'
                  : '请先登录并打开一本小说阅读，返回后再测试。',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: hasSession && _action.isEmpty
                      ? _reportRealReadingSession
                      : null,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('验证阅读报告'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      hasSession && _action.isEmpty ? _verifyShelfSync : null,
                  icon: const Icon(Icons.bookmark_outline, size: 18),
                  label: const Text('验证书架同步'),
                ),
                OutlinedButton.icon(
                  onPressed: hasSession && _action.isEmpty
                      ? _reportFifteenMinuteProbe
                      : null,
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('协议测试：15分钟'),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('仅本地调试探针显示；不自动领取轻币，书架测试会临时添加后恢复原状态。',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _reportRealReadingSession() async {
    final snapshot = LKReadingSession.shared.snapshot();
    if (snapshot == null || _action.isNotEmpty) return;
    if (snapshot.readDurationSeconds < 1) {
      if (mounted) showLkError(context, '阅读时间不足，暂时无法上报');
      return;
    }
    setState(() => _action = 'reading-report');
    try {
      final report = await LKApi.reportReadingProgress(
        bookId: snapshot.bookId,
        volumeId: snapshot.volumeId,
        chapterId: snapshot.chapterId,
        progressPercent: snapshot.progressPercent,
        readDurationSeconds: snapshot.readDurationSeconds,
        activeSecondsDelta: snapshot.readDurationSeconds > 300
            ? 300
            : snapshot.readDurationSeconds,
      );
      Map<String, dynamic>? detail;
      try {
        detail = await LKApi.welfareEarnCoinDetail();
      } catch (_) {
        // 报告成功但奖励状态查询失败时，仍展示报告结果。
      }
      if (!mounted) return;
      final taskKey = _text(_pick(report, const ['task_key', 'taskKey']));
      if (detail != null || taskKey.isNotEmpty) {
        setState(() {
          if (detail != null) _earnCoin = detail;
          if (taskKey.isNotEmpty) {
            _earnCoin = {..._earnCoin, 'task_key': taskKey};
          }
        });
      }
      final claimable = _flag(_pick(detail ?? const {}, const [
            'claimable',
            'can_claim',
            'is_claimable',
          ])) ||
          _statusIs(
              _pick(detail ?? const {}, const ['status', 'reward_status']),
              const ['claimable', 'ready']);
      await _showDiagnostic(
        '阅读报告已被服务器接受',
        [
          '服务器已收到真实阅读数据。',
          if (taskKey.isNotEmpty) '任务标识：$taskKey',
          if (detail != null) claimable ? '当前状态：有可领取奖励' : '当前状态：暂未达到领取条件',
          if (detail == null) '奖励状态：查询失败，请稍后刷新任务中心',
        ],
      );
    } catch (e) {
      if (mounted) await _showDiagnostic('阅读报告被服务器拒绝', [_errorText(e)]);
    } finally {
      if (mounted) setState(() => _action = '');
    }
  }

  /// 本地协议测试：沿用当前真实书籍、章节和进度，只将时长固定为官方
  /// 约定的 15 分钟测试值。入口需要显式 dart-define，且不触发领取。
  Future<void> _reportFifteenMinuteProbe() async {
    final snapshot = LKReadingSession.shared.snapshot();
    if (snapshot == null || _action.isNotEmpty) return;
    setState(() => _action = 'reading-probe');
    try {
      final report = await LKApi.reportReadingProgress(
        bookId: snapshot.bookId,
        volumeId: snapshot.volumeId,
        chapterId: snapshot.chapterId,
        progressPercent: snapshot.progressPercent,
        readDurationSeconds: 900,
        // active_seconds_delta 是单次心跳增量，服务器限制最大 300 秒；
        // 总计 15 分钟仍由 read_duration_seconds 表示。
        activeSecondsDelta: 300,
      );
      Map<String, dynamic>? detail;
      try {
        detail = await LKApi.welfareEarnCoinDetail();
      } catch (_) {}
      if (!mounted) return;
      final taskKey = _text(_pick(report, const ['task_key', 'taskKey']));
      if (detail != null || taskKey.isNotEmpty) {
        setState(() {
          if (detail != null) _earnCoin = detail;
          if (taskKey.isNotEmpty) {
            _earnCoin = {..._earnCoin, 'task_key': taskKey};
          }
        });
      }
      final claimable = _flag(_pick(detail ?? const {}, const [
            'claimable',
            'can_claim',
            'is_claimable',
          ])) ||
          _statusIs(
              _pick(detail ?? const {}, const ['status', 'reward_status']),
              const ['claimable', 'ready']);
      await _showDiagnostic(
        '15分钟协议测试已返回',
        [
          '服务器已接受报告请求。',
          if (taskKey.isNotEmpty) '任务标识：$taskKey',
          if (detail != null) claimable ? '当前状态：有可领取奖励' : '当前状态：暂未达到领取条件',
          if (detail == null) '奖励状态：查询失败，请稍后刷新任务中心',
          '本次未调用领取接口。',
        ],
      );
    } catch (e) {
      if (mounted) await _showDiagnostic('15分钟协议测试被服务器拒绝', [_errorText(e)]);
    } finally {
      if (mounted) setState(() => _action = '');
    }
  }

  Future<void> _verifyShelfSync() async {
    final snapshot = LKReadingSession.shared.snapshot();
    if (snapshot == null || _action.isNotEmpty) return;
    setState(() => _action = 'shelf-sync');
    try {
      final before = await LKApi.inShelf(snapshot.bookId);
      await LKApi.toggleShelf(snapshot.bookId, true);
      final afterAdd = await LKApi.inShelf(snapshot.bookId);
      var restored = true;
      if (!before) {
        await LKApi.toggleShelf(snapshot.bookId, false);
        restored = !(await LKApi.inShelf(snapshot.bookId));
      }
      if (!mounted) return;
      await _showDiagnostic(
        afterAdd ? '书架同步验证通过' : '服务器未确认加入书架',
        [
          '加入前：${before ? '已在书架' : '不在书架'}',
          '加入后：${afterAdd ? '已在书架' : '未在书架'}',
          if (!before) '恢复原状态：${restored ? '成功' : '失败'}',
        ],
      );
    } catch (e) {
      if (mounted) await _showDiagnostic('书架操作被服务器拒绝', [_errorText(e)]);
    } finally {
      if (mounted) setState(() => _action = '');
    }
  }

  Future<void> _showDiagnostic(String title, List<String> lines) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(lines.join('\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  String _errorText(Object error) =>
      error is LKException ? '${error.message}（错误码 ${error.code}）' : '$error';

  static Widget _loadingCard(double height) => Card(
        child: SizedBox(
          height: height,
          child: const Center(child: LkLoadingIndicator()),
        ),
      );
}

class WelfareCoinRecordsPage extends StatefulWidget {
  const WelfareCoinRecordsPage({super.key});

  @override
  State<WelfareCoinRecordsPage> createState() => _WelfareCoinRecordsPageState();
}

class _WelfareCoinRecordsPageState extends State<WelfareCoinRecordsPage> {
  final _records = <Map<String, dynamic>>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (_loading || append && !_hasMore) return;
    setState(() {
      _loading = true;
      if (!append) _error = null;
    });
    try {
      final data = await LKApi.welfareCoinRecords(append ? _page + 1 : 1);
      final raw = data['list'] ??
          data['records'] ??
          data['items'] ??
          data['free_coin_records_list'] ??
          const [];
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const <Map<String, dynamic>>[];
      final pageInfo = data['page_info'] is Map
          ? Map<String, dynamic>.from(data['page_info'] as Map)
          : const <String, dynamic>{};
      final rawMore = pageInfo['has_more'] ??
          pageInfo['hasMore'] ??
          data['has_more'] ??
          data['hasMore'];
      if (!mounted) return;
      setState(() {
        if (!append) _records.clear();
        _records.addAll(items);
        _page = append ? _page + 1 : 1;
        _hasMore = rawMore == null
            ? items.length >= 30
            : rawMore == true || rawMore == 1 || rawMore == '1';
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(dynamic value) => value?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('轻币记录')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _records.isEmpty && _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 420, child: LkLoadingIndicator()),
                ],
              )
            : _records.isEmpty && _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 260,
                        child: Center(
                          child: FilledButton.tonal(
                            onPressed: _load,
                            child: Text(_error!),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _records.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      if (index == _records.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _load(append: true);
                        });
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: LkLoadingIndicator()),
                        );
                      }
                      final record = _records[index];
                      final amount = record['amount'] ??
                          record['coin'] ??
                          record['light_coin'] ??
                          record['reward_amount'] ??
                          '';
                      final title = _text(record['title'] ??
                          record['name'] ??
                          record['reason'] ??
                          record['description'] ??
                          '轻币变动');
                      final time = _text(record['created_at'] ??
                          record['time'] ??
                          record['record_time'] ??
                          '');
                      return ListTile(
                        leading: Icon(
                          _text(amount).startsWith('-')
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                          color: _text(amount).startsWith('-')
                              ? Colors.orange
                              : Colors.green,
                        ),
                        title: Text(title),
                        subtitle: time.isEmpty ? null : Text(time),
                        trailing: Text(_text(amount)),
                      );
                    },
                  ),
      ),
    );
  }
}
