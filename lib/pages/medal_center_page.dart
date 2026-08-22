import 'package:flutter/material.dart';

import '../api/lk_api.dart';
import '../api/lk_client.dart';
import '../api/models.dart';
import '../api/store.dart';
import '../services/avatar_cache.dart';
import '../widgets/common.dart';
import 'medal_shop_page.dart';

class MedalCenterPage extends StatefulWidget {
  const MedalCenterPage({super.key});

  @override
  State<MedalCenterPage> createState() => _MedalCenterPageState();
}

class _MedalCenterPageState extends State<MedalCenterPage> {
  List<LKMedal> _medals = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _imageUrl(String value) {
    final image = value.trim();
    if (image.startsWith('http')) return image;
    if (image.startsWith('/')) return 'https://api.lightnovel.fun$image';
    return image;
  }

  Future<void> _load() async {
    final session = LKClient.shared.session;
    if (!session.isLoggedIn) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '登录后才能查看勋章中心';
        });
      }
      return;
    }
    final cached = await LKStore.cachedMedals(session.uid);
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() {
        _medals = cached;
        _loading = true;
        _error = null;
      });
      YomiruMedalCache.precache(
          context, cached.map((medal) => _imageUrl(medal.image)));
    }
    try {
      final medals = await LKApi.myMedals();
      await LKStore.cacheMedals(session.uid, medals);
      if (!mounted) return;
      setState(() {
        _medals = medals;
        _loading = false;
        _error = null;
      });
      YomiruMedalCache.precache(
          context, medals.map((medal) => _imageUrl(medal.image)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _medals.isEmpty ? e.toString() : null;
        });
      }
    }
  }

  Future<void> _toggle(LKMedal medal) async {
    if (medal.medalId <= 0 || _busy.contains(medal.medalId)) return;
    setState(() => _busy.add(medal.medalId));
    try {
      await LKApi.toggleMedal(medal.medalId, !medal.equipped);
      if (mounted) {
        showLkError(context, medal.equipped ? '已取消装备' : '已装备');
        await _load();
      }
    } catch (e) {
      if (mounted) showLkError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(medal.medalId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('勋章中心'),
        actions: [
          IconButton(
            tooltip: '勋章商城',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MedalShopPage()),
            ),
          ),
        ],
      ),
      body: _loading && _medals.isEmpty
          ? const LkLoadingIndicator()
          : _error != null && _medals.isEmpty
              ? Center(
                  child: FilledButton.tonal(
                    onPressed: _load,
                    child: Text(_error!),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _medals.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 220),
                            Center(child: Text('暂无已拥有勋章')),
                          ],
                        )
                      : GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 190,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _medals.length,
                          itemBuilder: (_, index) => _medalCard(_medals[index]),
                        ),
                ),
    );
  }

  Widget _medalCard(LKMedal medal) {
    final image = _imageUrl(medal.image);
    final busy = _busy.contains(medal.medalId);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Column(
          children: [
            Expanded(
              child: image.isEmpty
                  ? Icon(Icons.military_tech_outlined,
                      size: 58,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : Image(
                      image: YomiruMedalCache.provider(image),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.military_tech_outlined,
                          size: 58,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
            ),
            Text(
              medal.name.isEmpty ? '未命名勋章' : medal.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton(
                onPressed:
                    medal.medalId <= 0 || busy ? null : () => _toggle(medal),
                child: Text(busy
                    ? '处理中'
                    : medal.equipped
                        ? '取消装备'
                        : '装备'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
