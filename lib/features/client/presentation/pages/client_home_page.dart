import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../data/client_service.dart';
import '../widgets/shared/business_avatar.dart';
import '../widgets/shared/business_rewards_sheet.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key, this.onVerTodos});

  final VoidCallback? onVerTodos;

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _businessPoints = [];
  List<Map<String, dynamic>> _availableRewards = [];
  List<Map<String, dynamic>> _closeRewards = [];
  List<Map<String, dynamic>> _memberships = [];
  List<dynamic> _recentActivity = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _user = await SecureStorage.getUser();

      final pointsData = await ClientService.getUserPoints();
      final rawBP = (pointsData['businessPoints'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      // Enrich business points with metadata in parallel
      final enriched = await Future.wait(rawBP.map((bp) async {
        try {
          final biz = await ClientService.getBusinessById(bp['businessId'] as String);
          return {
            ...bp,
            'businessName': biz['username'] ?? biz['name'] ?? 'Negocio',
            'businessLogoUrl': biz['logoUrl'] ?? biz['profilePicture'] ?? biz['logo'],
          };
        } catch (_) {
          return {...bp, 'businessName': 'Negocio'};
        }
      }));

      // Find available and close rewards in parallel
      final available = <Map<String, dynamic>>[];
      final close = <Map<String, dynamic>>[];
      await Future.wait(enriched.map((bp) async {
        try {
          final rewards = await ClientService.getBusinessRewards(
            bp['businessId'] as String,
          );
          final userPoints = (bp['points'] as num?)?.toInt() ?? 0;
          final userStamps = (bp['stamps'] as num?)?.toInt() ?? 0;
          // avgPointsPerVisit: used to estimate if a single visit closes the gap
          final avgPPV = userStamps > 0 ? userPoints / userStamps : null;

          final meta = {
            'businessName': bp['businessName'],
            'businessId': bp['businessId'],
            'businessLogoUrl': bp['businessLogoUrl'],
            'userPoints': bp['points'],
            'userStamps': bp['stamps'],
          };

          for (final r in rewards.cast<Map<String, dynamic>>()) {
            if (r['isActive'] == false) continue;
            final isPoints = r['type'] == 'points' || r['pointsRequired'] != null;
            final required = isPoints
                ? (r['pointsRequired'] as num?)?.toInt() ?? 0
                : (r['stampsRequired'] ?? r['targetStamps'] as num?)?.toInt() ?? 0;
            final current = isPoints ? userPoints : userStamps;
            if (required <= 0) continue;

            if (current >= required) {
              available.add({...r, ...meta});
            } else {
              final gap = required - current;
              final isClose = !isPoints
                  ? gap <= 1
                  : avgPPV != null
                      ? gap <= avgPPV
                      : current >= required * 0.75;
              if (isClose) {
                close.add({...r, ...meta, 'gap': gap, 'isPoints': isPoints});
              }
            }
          }
        } catch (_) {}
      }));

      // Memberships
      final rawMem = await ClientService.getMyMemberships().catchError((_) => []);
      final memberships = await Future.wait(
        rawMem.cast<Map<String, dynamic>>().map((m) async {
          final bizId = m['businessId'] as String?;
          if (bizId == null) return m;
          try {
            final biz = await ClientService.getBusinessById(bizId);
            return {
              ...m,
              'businessName': biz['username'] ?? biz['name'] ?? 'Negocio',
              'businessLogoUrl': biz['logoUrl'] ?? biz['profilePicture'] ?? biz['logo'],
            };
          } catch (_) {
            return m;
          }
        }),
      );

      // Recent activity (last 5 transactions)
      final tx = await ClientService.getUserTransactions(limit: 3)
          .catchError((_) => <dynamic>[]);

      if (mounted) {
        setState(() {
          _businessPoints = enriched.toList();
          _availableRewards = available;
          _closeRewards = close;
          _memberships = memberships.toList();
          _recentActivity = tx;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _openBusinessSheet(Map<String, dynamic> business) {
    openBusinessRewardsSheet(context, business);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingView();
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }

    final totalPoints = _businessPoints.fold<int>(
      0, (s, b) => s + ((b['points'] as num?)?.toInt() ?? 0));
    final totalStamps = _businessPoints.fold<int>(
      0, (s, b) => s + ((b['stamps'] as num?)?.toInt() ?? 0));
    final userId = _user?['id'] as String? ?? _user?['_id'] as String? ?? '';

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // Stats
          _StatsSection(
            totalPoints: totalPoints,
            totalStamps: totalStamps,
            businesses: _businessPoints.length,
          ),
          const SizedBox(height: 16),

          // QR
          _QRSection(userId: userId),
          const SizedBox(height: 16),

          // Close rewards (shown only when no rewards are fully available)
          if (_availableRewards.isEmpty && _closeRewards.isNotEmpty) ...[
            _CloseRewardsSection(
              rewards: _closeRewards,
              onBusinessTap: (businessId) {
                final bp = _businessPoints.firstWhere(
                  (b) => b['businessId'] == businessId,
                  orElse: () => {'businessId': businessId},
                );
                _openBusinessSheet(bp);
              },
            ),
            const SizedBox(height: 16),
          ],

          // Available rewards
          if (_availableRewards.isNotEmpty) ...[
            _AvailableRewardsSection(
              rewards: _availableRewards,
              onBusinessTap: (businessId) {
                final bp = _businessPoints.firstWhere(
                  (b) => b['businessId'] == businessId,
                  orElse: () => _availableRewards.firstWhere(
                    (r) => r['businessId'] == businessId,
                    orElse: () => {},
                  ),
                );
                _openBusinessSheet(bp);
              },
            ),
            const SizedBox(height: 16),
          ],

          // Memberships
          if (_memberships.isNotEmpty) ...[
            _MembershipsSection(
              memberships: _memberships,
              onTap: (m) {
                final bizId = m['businessId'] as String?;
                if (bizId == null) return;
                final bp = _businessPoints.firstWhere(
                  (b) => b['businessId'] == bizId,
                  orElse: () => m,
                );
                _openBusinessSheet(bp);
              },
            ),
            const SizedBox(height: 16),
          ],

          // Recent activity
          _RecentActivitySection(
            transactions: _recentActivity,
            businessPoints: _businessPoints,
            onBusinessTap: (businessId) {
              final bp = _businessPoints.firstWhere(
                (b) => b['businessId'] == businessId,
                orElse: () => {'businessId': businessId},
              );
              _openBusinessSheet(bp);
            },
            onVerTodos: widget.onVerTodos,
          ),
        ],
      ),
    );
  }
}

// ── Stats ─────────────────────────────────────────────────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection({
    required this.totalPoints,
    required this.totalStamps,
    required this.businesses,
  });

  final int totalPoints;
  final int totalStamps;
  final int businesses;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          value: totalPoints.toString(),
          label: 'Puntos',
          color: AppColors.primary,
          bgColor: AppColors.primaryMuted,
          icon: Icons.stars_rounded,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: totalStamps.toString(),
          label: 'Sellos',
          color: const Color(0xFF22A06B),
          bgColor: const Color(0x1F22A06B),
          icon: Icons.local_offer_rounded,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: businesses.toString(),
          label: 'Negocios',
          color: const Color(0xFF6366F1),
          bgColor: const Color(0x1F6366F1),
          icon: Icons.store_rounded,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String value;
  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR ────────────────────────────────────────────────────────────────────────

class _QRSection extends StatefulWidget {
  const _QRSection({required this.userId});
  final String userId;

  @override
  State<_QRSection> createState() => _QRSectionState();
}

class _QRSectionState extends State<_QRSection> {
  bool _loadingApple = false;
  bool _loadingGoogle = false;
  String? _error;

  Future<void> _addToAppleWallet() async {
    setState(() { _loadingApple = true; _error = null; });
    try {
      await ClientService.addToAppleWallet();
    } catch (_) {
      setState(() => _error = 'No se pudo generar el pase. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loadingApple = false);
    }
  }

  Future<void> _openGoogleWallet() async {
    setState(() { _loadingGoogle = true; _error = null; });
    try {
      await ClientService.openGoogleWallet();
    } catch (_) {
      setState(() => _error = 'No se pudo generar el pase. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_rounded, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text(
                'Mi Código QR',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.userId.isNotEmpty)
            QrImageView(
              data: widget.userId,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.textPrimary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textPrimary,
              ),
            )
          else
            const SizedBox(
              height: 180,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Muestra este código en el negocio para acumular puntos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (Platform.isIOS) _AppleWalletButton(
            loading: _loadingApple,
            onTap: _loadingApple ? null : _addToAppleWallet,
          ) else _GoogleWalletButton(
            loading: _loadingGoogle,
            onTap: _loadingGoogle ? null : _openGoogleWallet,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppleWalletButton extends StatelessWidget {
  const _AppleWalletButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: loading ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              else ...[
                const Icon(Icons.apple, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                const Text(
                  'Agregar a Apple Wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleWalletButton extends StatelessWidget {
  const _GoogleWalletButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: loading ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: AppColors.textPrimary,
                    strokeWidth: 2,
                  ),
                )
              else ...[
                _GoogleIcon(),
                const SizedBox(width: 6),
                const Text(
                  'Guardar en Google Wallet',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  const _GoogleIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Blue arc (top-right + right)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.57, 2.09, false,
      Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.28,
    );
    // Red arc (top-left)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -3.67, 1.05, false,
      Paint()..color = const Color(0xFFEA4335)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.28,
    );
    // Yellow arc (bottom-left + bottom)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.09, 1.05, false,
      Paint()..color = const Color(0xFFFBBC05)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.28,
    );
    // Green arc (bottom-right)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      3.14, 0.52, false,
      Paint()..color = const Color(0xFF34A853)..style = PaintingStyle.stroke..strokeWidth = size.width * 0.28,
    );
    // White bar (right side cutout for the "G" gap) + blue bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.14, r * 0.9, size.height * 0.28),
      barPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.14, r * 0.9, size.height * 0.28),
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Available rewards ─────────────────────────────────────────────────────────

// ── Close rewards (almost there) ──────────────────────────────────────────────

class _CloseRewardsSection extends StatelessWidget {
  const _CloseRewardsSection({required this.rewards, this.onBusinessTap});
  final List<Map<String, dynamic>> rewards;
  final void Function(String businessId)? onBusinessTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Estás cerca!',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Con tu próxima visita podrías alcanzarla',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xBFFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Reward rows
          ...rewards.map((r) {
            final gap = r['gap'] as num? ?? 0;
            final isPoints = r['isPoints'] == true;
            final gapLabel = isPoints
                ? '~${gap.ceil()} pts más'
                : gap == 1 ? '1 sello más' : '${gap.toInt()} sellos más';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: onBusinessTap != null
                    ? () => onBusinessTap!(r['businessId'] as String)
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: BusinessAvatar(
                          logoUrl: r['businessLogoUrl'] as String?,
                          name: r['businessName'] as String? ?? '?',
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['name'] as String? ?? 'Recompensa',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r['businessName'] as String? ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.70),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          gapLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Available rewards ─────────────────────────────────────────────────────────

class _AvailableRewardsSection extends StatelessWidget {
  const _AvailableRewardsSection({required this.rewards, this.onBusinessTap});
  final List<Map<String, dynamic>> rewards;
  final void Function(String businessId)? onBusinessTap;

  // Group individual rewards by businessId
  List<Map<String, dynamic>> get _grouped {
    final map = <String, Map<String, dynamic>>{};
    for (final r in rewards) {
      final id = r['businessId'] as String? ?? '';
      if (map.containsKey(id)) {
        map[id]!['rewardCount'] = (map[id]!['rewardCount'] as int) + 1;
      } else {
        map[id] = {
          'businessId': id,
          'businessName': r['businessName'],
          'businessLogoUrl': r['businessLogoUrl'],
          'rewardCount': 1,
        };
      }
    }
    return map.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    final title = groups.length == 1
        ? '¡Recompensa disponible!'
        : '¡Recompensas en ${groups.length} negocios!';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF22A06B),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22A06B).withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_giftcard_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Toca para ver tus recompensas',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Business rows
          ...groups.map((biz) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RewardBusinessRow(
              biz: biz,
              onTap: onBusinessTap != null
                  ? () => onBusinessTap!(biz['businessId'] as String)
                  : null,
            ),
          )),
        ],
      ),
    );
  }
}

class _RewardBusinessRow extends StatelessWidget {
  const _RewardBusinessRow({required this.biz, this.onTap});
  final Map<String, dynamic> biz;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = biz['businessName'] as String? ?? 'Negocio';
    final logoUrl = biz['businessLogoUrl'] as String?;
    final count = biz['rewardCount'] as int? ?? 1;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Avatar with white border
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
            ),
            child: BusinessAvatar(logoUrl: logoUrl, name: name, size: 38),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 1 ? '1 recompensa' : '$count recompensas',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.60), size: 20),
        ],
      ),
    ));
  }
}

// ── Memberships ───────────────────────────────────────────────────────────────

class _MembershipsSection extends StatelessWidget {
  const _MembershipsSection({required this.memberships, this.onTap});
  final List<Map<String, dynamic>> memberships;
  final void Function(Map<String, dynamic>)? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0x1F6366F1),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.card_membership_rounded, size: 14, color: Color(0xFF6366F1)),
            ),
            const SizedBox(width: 8),
            const Text(
              'Membresías activas',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...memberships.map((m) => _MembershipCard(
          membership: m,
          onTap: onTap != null ? () => onTap!(m) : null,
        )),
      ],
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.membership, this.onTap});
  final Map<String, dynamic> membership;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bizName = membership['businessName'] as String? ?? 'Membresía';
    final logoUrl = membership['businessLogoUrl'] as String?
        ?? membership['businessLogo'] as String?;
    final benefit = (membership['planSnapshot'] as Map<String, dynamic>?)?['benefit'] as String?;
    final daysLeft = membership['daysLeft'] as int?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          BusinessAvatar(logoUrl: logoUrl, name: bizName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bizName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (benefit != null && benefit.isNotEmpty)
                  Text(
                    benefit,
                    style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (daysLeft != null)
                  Text(
                    daysLeft == 0 ? 'Vence hoy' : '$daysLeft día${daysLeft != 1 ? 's' : ''} restante${daysLeft != 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x1F22A06B),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Activa',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF22A06B),
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
              ],
            ],
          ),
        ],
      ),
    ));
  }
}

// ── Recent activity ───────────────────────────────────────────────────────────

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({
    required this.transactions,
    required this.businessPoints,
    this.onBusinessTap,
    this.onVerTodos,
  });

  final List<dynamic> transactions;
  final List<Map<String, dynamic>> businessPoints;
  final void Function(String businessId)? onBusinessTap;
  final VoidCallback? onVerTodos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.primaryMuted,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.history_rounded, size: 14, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Actividad reciente',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (onVerTodos != null)
              GestureDetector(
                onTap: onVerTodos,
                child: const Text(
                  'Ver todos',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: transactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Sin actividad reciente',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: transactions
                      .cast<Map<String, dynamic>>()
                      .map((tx) {
                        final bizId = tx['businessId'] as String?;
                        final bp = bizId != null
                            ? businessPoints.firstWhere(
                                (b) => b['businessId'] == bizId,
                                orElse: () => {},
                              )
                            : <String, dynamic>{};
                        final logoUrl = bp['businessLogoUrl'] as String?;
                        final bizName = tx['businessName'] as String?
                            ?? bp['businessName'] as String?
                            ?? 'Negocio';
                        return _ActivityRow(
                          tx: {...tx, 'businessName': bizName, 'businessLogoUrl': logoUrl},
                          onTap: onBusinessTap != null && bizId != null
                              ? () => onBusinessTap!(bizId)
                              : null,
                        );
                      })
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.tx, this.onTap});
  final Map<String, dynamic> tx;
  final VoidCallback? onTap;

  static const _typeConfig = {
    'add': ('Compra', Color(0xFF22A06B)),
    'redeem': ('Canje', AppColors.primary),
    'subtract': ('Ajuste', AppColors.textMuted),
  };

  @override
  Widget build(BuildContext context) {
    final type = tx['type'] as String? ?? 'add';
    final (label, color) = _typeConfig[type] ?? ('Compra', const Color(0xFF22A06B));
    final pts = (tx['totalPointsChange'] as num?)?.toInt() ?? 0;
    final stamps = (tx['totalStampsChange'] as num?)?.toInt() ?? 0;
    final bizName = tx['businessName'] as String? ?? 'Negocio';
    final logoUrl = tx['businessLogoUrl'] as String?;

    final typeIcon = type == 'redeem'
        ? Icons.redeem_rounded
        : type == 'subtract'
            ? Icons.remove_rounded
            : Icons.add_rounded;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(0),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0EDE8))),
      ),
      child: Row(
        children: [
          // Business avatar with type badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              BusinessAvatar(logoUrl: logoUrl, name: bizName, size: 40),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(typeIcon, size: 9, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bizName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (pts != 0)
                Text(
                  '${pts > 0 ? '+' : ''}$pts pts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: pts > 0 ? AppColors.primary : AppColors.error,
                  ),
                ),
              if (stamps != 0)
                Text(
                  '${stamps > 0 ? '+' : ''}$stamps sellos',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: stamps > 0 ? const Color(0xFF22A06B) : AppColors.error,
                  ),
                ),
            ],
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
            ),
        ],
      ),
    ));
  }
}

// ── Loading / Error ───────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        4,
        (_) => Container(
          height: 120,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar tu información',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
