import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../data/client_service.dart';
import 'business_avatar.dart';

void openBusinessRewardsSheet(BuildContext context, Map<String, dynamic> business) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => BusinessRewardsSheet(business: business),
  );
}

class BusinessRewardsSheet extends StatefulWidget {
  const BusinessRewardsSheet({super.key, required this.business});
  final Map<String, dynamic> business;

  @override
  State<BusinessRewardsSheet> createState() => _BusinessRewardsSheetState();
}

class _BusinessRewardsSheetState extends State<BusinessRewardsSheet> {
  List<Map<String, dynamic>> _rewards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRewards();
  }

  Future<void> _fetchRewards() async {
    final bizId = widget.business['businessId'] as String? ?? '';
    if (bizId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final list = await ClientService.getBusinessRewards(bizId);
      if (mounted) {
        setState(() {
          _rewards = list
              .cast<Map<String, dynamic>>()
              .where((r) => r['isActive'] != false)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.business['businessName'] as String? ??
        widget.business['name'] as String? ??
        'Negocio';
    final logoUrl = widget.business['businessLogoUrl'] as String? ??
        widget.business['logoUrl'] as String?;
    final points = (widget.business['points'] as num?)?.toInt() ?? 0;
    final stamps = (widget.business['stamps'] as num?)?.toInt() ?? 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
            child: Row(
              children: [
                BusinessAvatar(logoUrl: logoUrl, name: name, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (points > 0) ...[
                            Text(
                              '$points pts',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (stamps > 0)
                            Text(
                              '$stamps sellos',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF22A06B),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.textMuted),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Body
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2.5),
                    ),
                  )
                : _rewards.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.card_giftcard_outlined,
                                size: 48, color: AppColors.border),
                            const SizedBox(height: 12),
                            const Text(
                              'Sin recompensas activas',
                              style: TextStyle(
                                  fontSize: 14, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        itemCount: _rewards.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _RewardCard(
                          reward: _rewards[i],
                          userPoints: points,
                          userStamps: stamps,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.userPoints,
    required this.userStamps,
  });

  final Map<String, dynamic> reward;
  final int userPoints;
  final int userStamps;

  @override
  Widget build(BuildContext context) {
    final isPoints =
        reward['type'] == 'points' || reward['pointsRequired'] != null;
    final required = isPoints
        ? (reward['pointsRequired'] as num?)?.toInt() ?? 0
        : (reward['stampsRequired'] ?? reward['targetStamps'] as num?)
                ?.toInt() ??
            0;
    final current = isPoints ? userPoints : userStamps;
    final canRedeem = required > 0 && current >= required;
    final pct = required > 0 ? (current / required).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: canRedeem ? const Color(0xFFF0FBF6) : AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: canRedeem ? const Color(0xFFD3F0E3) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward['name'] as String? ?? 'Recompensa',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if ((reward['description'] as String?)?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 2),
                      Text(
                        reward['description'] as String,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: canRedeem
                      ? const Color(0xFF22A06B)
                      : const Color(0xFFF0EDE8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  canRedeem
                      ? '¡Listo!'
                      : '${required - current} ${isPoints ? 'pts' : 'sellos'} más',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: canRedeem ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$current ${isPoints ? 'pts' : 'sellos'}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              Text(
                '$required ${isPoints ? 'pts' : 'sellos'}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: const Color(0xFFF0EDE8),
              valueColor: AlwaysStoppedAnimation(
                canRedeem ? const Color(0xFF22A06B) : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
