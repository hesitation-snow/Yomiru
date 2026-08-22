import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../services/avatar_cache.dart';
import '../widgets/common.dart';
import 'user_profile_page.dart';

/// 关注与粉丝列表。当前仅提供只读浏览，不执行关注/取关操作。
class FollowListPage extends StatefulWidget {
  final int initialTab;

  const FollowListPage({super.key, this.initialTab = 0});

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _following = <LKFollowUser>[];
  final _followers = <LKFollowUser>[];
  int _followingPage = 0;
  int _followersPage = 0;
  int _followingTotal = 0;
  int _followersTotal = 0;
  bool _followingHasMore = true;
  bool _followersHasMore = true;
  bool _followingLoading = false;
  bool _followersLoading = false;
  String? _followingError;
  String? _followersError;
  final Set<int> _followActionUids = <int>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 2, initialIndex: widget.initialTab == 1 ? 1 : 0, vsync: this);
    _loadFollowing(reset: true);
    _loadFollowers(reset: true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing({bool reset = false}) async {
    if (!LKClient.shared.session.isLoggedIn || _followingLoading) return;
    if (!reset && !_followingHasMore) return;
    final page = reset ? 1 : _followingPage + 1;
    if (mounted) {
      setState(() {
        _followingLoading = true;
        if (reset) _followingError = null;
      });
    }
    try {
      final result = await LKApi.myFollowing(page);
      if (!mounted) return;
      YomiruAvatarCache.precache(
          context, result.items.map((item) => item.avatar));
      setState(() {
        if (reset) _following.clear();
        _appendUnique(_following, result.items);
        _followingPage = result.page;
        _followingTotal = result.total;
        _followingHasMore = result.hasMore;
        _followingError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _followingError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _followingLoading = false);
    }
  }

  Future<void> _loadFollowers({bool reset = false}) async {
    if (!LKClient.shared.session.isLoggedIn || _followersLoading) return;
    if (!reset && !_followersHasMore) return;
    final page = reset ? 1 : _followersPage + 1;
    if (mounted) {
      setState(() {
        _followersLoading = true;
        if (reset) _followersError = null;
      });
    }
    try {
      final result = await LKApi.myFollowers(page);
      if (!mounted) return;
      YomiruAvatarCache.precache(
          context, result.items.map((item) => item.avatar));
      setState(() {
        if (reset) _followers.clear();
        _appendUnique(_followers, result.items);
        _followersPage = result.page;
        _followersTotal = result.total;
        _followersHasMore = result.hasMore;
        _followersError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _followersError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _followersLoading = false);
    }
  }

  void _appendUnique(List<LKFollowUser> target, List<LKFollowUser> items) {
    final existing = target.map((e) => e.uid).toSet();
    for (final item in items) {
      if (item.uid > 0 && existing.add(item.uid)) target.add(item);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadFollowing(reset: true),
      _loadFollowers(reset: true),
    ]);
  }

  Future<void> _toggleFollow(LKFollowUser user, bool following) async {
    if (user.uid <= 0 || _followActionUids.contains(user.uid)) return;
    setState(() => _followActionUids.add(user.uid));
    try {
      await LKApi.toggleFollow(user.uid, !following);
      if (!mounted) return;
      setState(() {
        if (following) {
          _following.removeWhere((item) => item.uid == user.uid);
          if (_followingTotal > 0) _followingTotal--;
        } else {
          final index = _followers.indexWhere((item) => item.uid == user.uid);
          if (index >= 0) {
            _followers[index] = _followers[index].copyWith(followed: true);
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(following ? '已取消关注' : '已关注')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _followActionUids.remove(user.uid));
    }
  }

  String _friendlyError(Object error) {
    if (error is LKException && error.code == 8) return '登录状态已失效，请重新登录';
    return '加载失败，请点击重试';
  }

  @override
  Widget build(BuildContext context) {
    if (!LKClient.shared.session.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('关注列表')),
        body: const Center(child: Text('登录后才能查看关注列表')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('关注列表'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _followingLoading || _followersLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '关注 ${_followingTotal > 0 ? _followingTotal : ''}'),
            Tab(text: '粉丝 ${_followersTotal > 0 ? _followersTotal : ''}'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildList(
              items: _following,
              followingTab: true,
              loading: _followingLoading,
              hasMore: _followingHasMore,
              error: _followingError,
              onRetry: () => _loadFollowing(reset: true),
              onLoadMore: () => _loadFollowing(),
            ),
            _buildList(
              items: _followers,
              followingTab: false,
              loading: _followersLoading,
              hasMore: _followersHasMore,
              error: _followersError,
              onRetry: () => _loadFollowers(reset: true),
              onLoadMore: () => _loadFollowers(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList({
    required List<LKFollowUser> items,
    required bool followingTab,
    required bool loading,
    required bool hasMore,
    required String? error,
    required VoidCallback onRetry,
    required VoidCallback onLoadMore,
  }) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: FilledButton.tonal(
          onPressed: onRetry,
          child: Text(error),
        ),
      );
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: Text('这里暂时没有用户')),
        ],
      );
    }
    final showLoadMore = hasMore || loading;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length + (showLoadMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        if (index == items.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onLoadMore();
          });
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: LkLoadingIndicator()),
          );
        }
        return _userTile(items[index], followingTab: followingTab);
      },
    );
  }

  Widget _userTile(LKFollowUser user, {required bool followingTab}) {
    final subtitle = <String>[];
    if (user.levelName.isNotEmpty) subtitle.add(user.levelName);
    if (user.isBrave) subtitle.add('勇者');
    if (user.signature.isNotEmpty) subtitle.add(user.signature);
    final following = followingTab || user.followed;
    final busy = _followActionUids.contains(user.uid);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: user.avatar.isNotEmpty
            ? YomiruAvatarCache.provider(user.avatar)
            : null,
        child: user.avatar.isEmpty ? const Icon(Icons.person_outline) : null,
      ),
      title: Text(
        user.nickname.isEmpty ? '未知用户' : user.nickname,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle.isEmpty ? '暂无签名' : subtitle.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: user.uid <= 0
          ? null
          : OutlinedButton(
              onPressed: busy ? null : () => _toggleFollow(user, following),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(busy
                  ? '处理中'
                  : following
                      ? '取消关注'
                      : '关注'),
            ),
      onTap: user.uid > 0 ? () => openUserProfile(context, user.uid) : null,
    );
  }
}
