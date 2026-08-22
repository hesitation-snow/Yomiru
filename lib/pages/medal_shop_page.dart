import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../services/avatar_cache.dart';
import '../widgets/common.dart';

class MedalShopPage extends StatefulWidget {
  const MedalShopPage({super.key});

  @override
  State<MedalShopPage> createState() => _MedalShopPageState();
}

class _MedalShopPageState extends State<MedalShopPage> {
  static const Set<String> _taskKeys = {
    'task_medal_groups',
    'taskmedalgroups',
    'task_medal_list',
    'taskmedallist',
    'task_medals',
    'taskmedals',
    'task_groups',
    'taskgroups',
    'medal_tasks',
    'achievement_medals',
    'task_list',
    'tasks',
    'task',
  };

  static const Set<String> _exchangeKeys = {
    'exchange_medal_groups',
    'exchangemedalgroups',
    'exchange_medal_list',
    'exchangemedallist',
    'exchange_medals',
    'exchangemedals',
    'exchange_groups',
    'exchangegroups',
    'medal_goods',
    'shop_medals',
    'shopmedals',
    'goods',
    'goods_list',
    'exchange',
  };

  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  final Set<String> _busy = <String>{};
  Set<String> _ownedMedalIds = <String>{};
  Set<String> _ownedMedalNames = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!LKClient.shared.session.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '登录后才能查看勋章商城';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await LKApi.medalCenter();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        final owned = _readOwnedMedals(data);
        _ownedMedalIds = owned.$1;
        _ownedMedalNames = owned.$2;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheMedalImages();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  dynamic _findValue(dynamic value, Set<String> keys, [int depth = 0]) {
    if (depth > 5) return null;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (keys.contains(key) && entry.value != null) return entry.value;
      }
      for (final child in value.values) {
        final result = _findValue(child, keys, depth + 1);
        if (result != null) return result;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  dynamic _listPayload(dynamic value, [int depth = 0]) {
    if (value is List) return value;
    if (depth > 4 || value is! Map) return null;
    for (final key in const [
      'groups',
      'group_list',
      'items',
      'list',
      'medals',
      'stages',
      'data',
    ]) {
      final child = value[key];
      if (child is List) return child;
      final nested = _listPayload(child, depth + 1);
      if (nested is List) return nested;
    }
    return null;
  }

  List<Map<String, dynamic>>? _children(Map<String, dynamic> item) {
    for (final key in const [
      'items',
      'list',
      'medals',
      'stages',
      'children',
      'goods',
      'medal_list',
      'reward_list',
      'exchange_list',
    ]) {
      final value = _maps(item[key]);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  List<Map<String, dynamic>> _itemsFor(Set<String> keys) {
    final raw = _findValue(_data ?? const {}, keys);
    final grouped = raw is Map
        ? raw.entries
            .where((entry) => _maps(entry.value).isNotEmpty)
            .map((entry) => <String, dynamic>{
                  'title': entry.key.toString(),
                  'items': entry.value,
                })
            .toList()
        : const <Map<String, dynamic>>[];
    final list = grouped.isNotEmpty ? grouped : _maps(_listPayload(raw) ?? raw);
    if (list.isEmpty) return const [];
    final flat = <Map<String, dynamic>>[];
    void flatten(Iterable<Map<String, dynamic>> entries) {
      for (final item in entries) {
        final children = _children(item);
        if (children == null) {
          flat.add(item);
        } else {
          flatten(children);
        }
      }
    }

    flatten(list);
    return flat;
  }

  String _text(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  int _id(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      final id = value is num ? value.toInt() : int.tryParse('$value');
      if (id != null && id > 0) return id;
    }
    return 0;
  }

  bool _flag(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value == true || value == 1 || value == '1' || value == 'true') {
        return true;
      }
    }
    return false;
  }

  String _imageUrl(Map<String, dynamic> item) {
    final image = _text(item, const [
      'image',
      'image_url',
      'imageUrl',
      'img',
      'icon',
      'icon_url',
      'medal_image',
    ]);
    if (image.startsWith('http')) return image;
    if (image.startsWith('/')) return 'https://api.lightnovel.fun$image';
    return image;
  }

  bool _owned(Map<String, dynamic> item) {
    final state =
        _text(item, const ['status', 'state', 'claim_status']).toLowerCase();
    final explicit = _flag(item, const [
          'owned',
          'is_owned',
          'claimed',
          'is_claimed',
          'received',
          'is_received',
          'obtained',
          'is_obtained',
          'has_medal',
          'hasMedal',
          'all_claimed',
          'taskClaimedToday',
          'taskclaimedtoday',
          'today_claimed',
        ]) ||
        state.contains('owned') ||
        state.contains('claimed') ||
        state.contains('received') ||
        state.contains('obtained') ||
        state.contains('已获得') ||
        state.contains('已领取');
    final medalId = _medalId(item);
    final name = _text(item, const ['name', 'title', 'medal_name']).trim();
    return explicit ||
        (medalId.isNotEmpty && _ownedMedalIds.contains(medalId)) ||
        (name.isNotEmpty && _ownedMedalNames.contains(name));
  }

  bool _claimable(Map<String, dynamic> item) {
    final state =
        _text(item, const ['status', 'state', 'claim_status']).toLowerCase();
    if (_owned(item)) return false;
    if (_flag(item, const ['can_claim', 'claimable', 'eligible', 'achieved'])) {
      return true;
    }
    final progress = _number(item, const ['progress', 'current', 'value']);
    final target = _number(item, const ['target', 'required', 'goal']);
    return (target > 0 && progress >= target) ||
        state.contains('可领取') ||
        state.contains('achieved') ||
        state.contains('达成');
  }

  double _number(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      final number =
          value is num ? value.toDouble() : double.tryParse('$value');
      if (number != null) return number;
    }
    return 0;
  }

  String _medalId(Map<String, dynamic> item) {
    final id = _id(item, const [
      'medal_id',
      'medalId',
      'badge_id',
      'badgeId',
      'goods_id',
      'goodsId',
    ]);
    return id > 0 ? '$id' : '';
  }

  (Set<String>, Set<String>) _readOwnedMedals(Map<String, dynamic> data) {
    final ids = <String>{};
    final names = <String>{};
    const containers = {
      'owned_medals',
      'ownedmedals',
      'my_medals',
      'mymedals',
      'user_medals',
      'usermedals',
      'equipped_medals',
      'equippedmedals',
      'equipped_items',
      'equippeditems',
      'obtained_medals',
      'obtainedmedals',
      'claimed_medals',
      'claimedmedals',
      'medals',
      'medal_list',
      'owned_medal_ids',
      'ownedmedalids',
      'medal_ids',
      'medalids',
      'medal_list_owned',
      'owned_list',
    };

    void addRecord(dynamic value) {
      if (value is List) {
        for (final child in value) {
          addRecord(child);
        }
        return;
      }
      if (value is num && value.toInt() > 0) {
        ids.add('${value.toInt()}');
        return;
      }
      if (value is String && value.trim().isNotEmpty) {
        final id = int.tryParse(value.trim());
        if (id != null && id > 0) {
          ids.add('$id');
        } else {
          names.add(value.trim());
        }
        return;
      }
      if (value is! Map) return;
      final item = Map<String, dynamic>.from(value);
      final id = _medalId(item);
      if (id.isNotEmpty) ids.add(id);
      final name = _text(item, const ['name', 'title', 'medal_name']);
      if (name.trim().isNotEmpty) names.add(name.trim());
      for (final key in const ['items', 'list', 'medals', 'data']) {
        addRecord(item[key]);
      }
    }

    void walk(dynamic value, int depth) {
      if (depth > 6 || value is! Map) return;
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (containers.contains(key)) {
          addRecord(entry.value);
        } else {
          walk(entry.value, depth + 1);
        }
      }
    }

    walk(data, 0);
    return (ids, names);
  }

  void _precacheMedalImages() {
    final groups = [
      ..._itemsFor(_taskKeys),
      ..._itemsFor(_exchangeKeys),
    ];
    YomiruMedalCache.precache(
      context,
      groups.map(_imageUrl),
    );
  }

  Future<void> _claim(Map<String, dynamic> item) async {
    final id = _id(item, const ['task_id', 'taskId', 'id', 'medal_id']);
    final key = 'task:$id';
    if (id <= 0 || _busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await LKApi.claimMedal(id);
      if (mounted) {
        showLkError(context, '领取成功');
        await _load();
      }
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _exchange(Map<String, dynamic> item) async {
    final id =
        _id(item, const ['medal_id', 'medalId', 'goods_id', 'goodsId', 'id']);
    final key = 'exchange:$id';
    if (id <= 0 || _busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await LKApi.exchangeMedal(id);
      if (mounted) {
        showLkError(context, '兑换成功');
        await _load();
      }
    } catch (e) {
      if (mounted) {
        if (e is LKException && e.code >= 500) {
          showLkError(
            context,
            '服务器未确认兑换结果，已刷新勋章状态；请以列表显示为准，不要重复提交。',
          );
          await _load();
        } else {
          showLkError(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _confirmExchange(Map<String, dynamic> item) async {
    final name = _text(item, const ['name', 'title', 'medal_name']);
    final price = _text(item, const [
      'price',
      'coin_price',
      'cost',
      'light_coin',
      'coin',
    ]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认兑换勋章'),
        content: Text(
          '确定要兑换“${name.isEmpty ? '未命名勋章' : name}”吗？\n'
          '${price.isEmpty ? '' : '将消耗 $price 轻币。'}兑换成功后会直接加入你的勋章。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _exchange(item);
  }

  @override
  Widget build(BuildContext context) {
    final taskItems = _itemsFor(_taskKeys);
    final exchangeItems = _itemsFor(_exchangeKeys);
    return Scaffold(
      appBar: AppBar(title: const Text('勋章商城')),
      body: _loading
          ? const LkLoadingIndicator()
          : _error != null
              ? Center(
                  child: FilledButton.tonal(
                      onPressed: _load, child: Text(_error!)))
              : DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: const TabBar(
                          tabs: [
                            Tab(text: '任务勋章'),
                            Tab(text: '兑换勋章'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _sectionView(
                              taskItems,
                              task: true,
                              emptyText: '暂无任务勋章',
                            ),
                            _sectionView(
                              exchangeItems,
                              task: false,
                              emptyText: '暂无可兑换勋章',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionView(
    List<Map<String, dynamic>> items, {
    required bool task,
    required String emptyText,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _sectionTitle(
            task ? '任务勋章' : '兑换勋章',
            task ? '完成站内任务后领取' : '使用轻币兑换并佩戴展示',
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 150),
              child: Center(child: Text(emptyText)),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children:
                    items.map((item) => _medalTile(item, task: task)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      );

  Widget _medalTile(Map<String, dynamic> item, {required bool task}) {
    final isTask = task ||
        _id(item, const ['task_id', 'taskId']) > 0 ||
        item.containsKey('requirement') ||
        item.containsKey('condition') ||
        item.containsKey('condition_text');
    final id = _id(
        item,
        isTask
            ? const ['task_id', 'taskId', 'id', 'medal_id']
            : const ['medal_id', 'medalId', 'goods_id', 'goodsId', 'id']);
    final key = '${isTask ? 'task' : 'exchange'}:$id';
    final name = _text(item, const ['name', 'title', 'medal_name']);
    final description = _text(item, const [
      'condition_text',
      'condition',
      'requirement',
      'description',
      'desc',
      'subtitle',
    ]);
    final price = _text(item, const [
      'price',
      'coin_price',
      'cost',
      'light_coin',
      'coin',
    ]);
    final owned = _owned(item);
    final claimable = isTask && _claimable(item);
    final image = _imageUrl(item);
    final action = owned
        ? '已获得'
        : isTask
            ? claimable
                ? '领取'
                : '未达成'
            : '兑换';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        backgroundImage:
            image.isNotEmpty ? YomiruMedalCache.provider(image) : null,
        child: image.isEmpty ? const Icon(Icons.military_tech_outlined) : null,
      ),
      title: Text(name.isEmpty ? '未命名勋章' : name,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (description.isNotEmpty) description,
        if (!isTask && price.isNotEmpty) '$price 轻币 · 永久有效',
      ].join(' · ')),
      trailing: owned
          ? Text(action, style: TextStyle(color: Colors.grey.shade500))
          : FilledButton.tonal(
              onPressed: id <= 0 || _busy.contains(key)
                  ? null
                  : claimable
                      ? () => _claim(item)
                      : isTask
                          ? null
                          : () => _confirmExchange(item),
              child: Text(_busy.contains(key) ? '处理中' : action),
            ),
    );
  }
}
