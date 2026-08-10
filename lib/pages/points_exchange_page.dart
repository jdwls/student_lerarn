import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../providers/user_provider.dart';
import 'package:provider/provider.dart';

class PointsExchangePage extends StatefulWidget {
  const PointsExchangePage({super.key});
  @override
  State<PointsExchangePage> createState() => _PointsExchangePageState();
}

class _PointsExchangePageState extends State<PointsExchangePage> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadExchangeItems();
  }

  Future<void> _loadExchangeItems() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await _apiService.getPointsExchangeItems();
      if (!mounted) return;
      if (response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>? ?? [])
            .where((item) => (item as Map<String, dynamic>)['enabled'] == true)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        if (!mounted) return;
        setState(() {
          _items = items;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = response['error'] ?? '加载失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '网络错误: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _redeemItem(Map<String, dynamic> item) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final studentId = userProvider.currentUser?.id ?? '';
    final studentName = userProvider.currentUser?.name ?? '';
    final currentPoints = userProvider.points;
    final pointsCost = item['points_cost'] as int? ?? 0;

    if (currentPoints < pointsCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('积分不足！需要 $pointsCost 积分，当前 $currentPoints 积分'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认兑换'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item['name'] ?? '',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if ((item['description'] ?? '').isNotEmpty)
              Text(item['description'],
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8)),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('消耗 $pointsCost 积分',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8B5CF6))),
                const SizedBox(width: 16),
                Text('剩余 ${currentPoints - pointsCost} 积分',
                    style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white),
              child: const Text('确认兑换')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _apiService.redeemItem(
          studentId: studentId,
          studentName: studentName,
          itemId: item['id'] as int);
      if (!mounted) return;
      if (result['success'] == true) {
        userProvider.setPointsDirectly(
            result['points'] as int? ?? (currentPoints - pointsCost));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '兑换成功！${result['item_name']} -${result['points_cost']}积分'),
              backgroundColor: const Color(0xFF10B981)),
        );
        _loadExchangeItems();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['error'] ?? '兑换失败'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('兑换失败: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final points = userProvider.points;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '积分兑换',
          style: TextStyle(
            fontFamily: '黑体',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        actions: [
          Center(
              child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withAlpha(26),
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.stars, size: 16, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 4),
              Text('$points 积分',
                  style: const TextStyle(
                      fontFamily: '黑体',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF8B5CF6))),
            ]),
          )),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
          : _errorMessage != null
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _loadExchangeItems,
                          child: const Text('重试')),
                    ]))
              : _items.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          const Icon(Icons.card_giftcard,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('暂无可兑换商品',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.grey)),
                        ]))
                  : RefreshIndicator(
                      onRefresh: _loadExchangeItems,
                      color: const Color(0xFF8B5CF6),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final itemWidth = (constraints.maxWidth - 36) / 4;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _items
                                  .map((item) => SizedBox(
                                        width: itemWidth,
                                        child: _buildCard(item, points),
                                      ))
                                  .toList(),
                            );
                          },
                        ),
                      ),
                    ),
    );
  }

  Widget _buildCard(Map<String, dynamic> item, int currentPoints) {
    final pointsCost = item['points_cost'] as int? ?? 0;
    final stock = item['stock'] as int? ?? -1;
    final canAfford = currentPoints >= pointsCost;
    final hasStock = stock == -1 || stock > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canAfford && hasStock ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: canAfford && hasStock
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 名称
          Text(
            item['name'] ?? '',
            style: const TextStyle(
              fontFamily: '黑体',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Color(0xFF1F2937),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // 积分
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withAlpha(26),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              '$pointsCost 积分',
              style: const TextStyle(
                fontFamily: '黑体',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ),
          // 库存
          const SizedBox(height: 4),
          if (stock != -1)
            Text(
              '库存: $stock',
              style: const TextStyle(
                fontFamily: '黑体',
                fontSize: 11,
                color: Colors.grey,
              ),
            )
          else
            const Text(
              '库存: 不限',
              style: TextStyle(
                fontFamily: '黑体',
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          const SizedBox(height: 8),
          // 兑换按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canAfford && hasStock ? () => _redeemItem(item) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                !hasStock
                    ? '已售罄'
                    : !canAfford
                        ? '积分不足'
                        : '兑换',
                style: const TextStyle(
                  fontFamily: '黑体',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
