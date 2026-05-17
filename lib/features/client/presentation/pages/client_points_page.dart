import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/client_service.dart';
import '../widgets/shared/business_avatar.dart';
import '../widgets/shared/business_rewards_sheet.dart';

class ClientPointsPage extends StatefulWidget {
  const ClientPointsPage({super.key});

  @override
  State<ClientPointsPage> createState() => _ClientPointsPageState();
}

class _ClientPointsPageState extends State<ClientPointsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _businessPoints = [];
  List<Map<String, dynamic>> _transactions = [];
  Map<String, String?> _businessLogos = {};
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // 'all' | 'points' | 'stamps'
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ClientService.getUserPoints(),
        ClientService.getUserTransactions(limit: 50),
      ]);

      final pointsData = results[0] as Map<String, dynamic>;
      final txList = results[1] as List<dynamic>;

      final rawBP = (pointsData['businessPoints'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final enriched = await Future.wait(rawBP.map((bp) async {
        try {
          final biz = await ClientService.getBusinessById(bp['businessId'] as String);
          return {
            ...bp,
            'businessName': biz['username'] ?? biz['name'] ?? 'Negocio',
            'businessLogoUrl': biz['logoUrl'],
          };
        } catch (_) {
          return {...bp, 'businessName': 'Negocio'};
        }
      }));

      // Build logos map — reuse already-fetched data, fetch the rest
      final metaMap = {for (final b in enriched) b['businessId'] as String: b};
      final txCast = txList.cast<Map<String, dynamic>>();
      final uniqueIds = txCast
          .map((t) => t['businessId'] as String?)
          .whereType<String>()
          .toSet();

      final logos = <String, String?>{};
      await Future.wait(uniqueIds.map((id) async {
        if (metaMap[id]?['businessLogoUrl'] != null) {
          logos[id] = metaMap[id]!['businessLogoUrl'] as String?;
        } else {
          try {
            final biz = await ClientService.getBusinessById(id);
            logos[id] = biz['logoUrl'] as String?;
          } catch (_) {}
        }
      }));

      if (mounted) {
        setState(() {
          _businessPoints = enriched.toList();
          _transactions = txCast;
          _businessLogos = logos;
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

  List<Map<String, dynamic>> get _filtered {
    return _businessPoints.where((b) {
      final pts = (b['points'] as num?)?.toInt() ?? 0;
      final stamps = (b['stamps'] as num?)?.toInt() ?? 0;
      if (_filter == 'points' && pts == 0) return false;
      if (_filter == 'stamps' && stamps == 0) return false;
      if (_search.isNotEmpty) {
        final name = (b['businessName'] as String? ?? '').toLowerCase();
        if (!name.contains(_search.toLowerCase())) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = a['lastVisit'] as String?;
        final db = b['lastVisit'] as String?;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return DateTime.parse(db).compareTo(DateTime.parse(da));
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _SkeletonView();

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    final totalPoints = _businessPoints.fold<int>(
        0, (s, b) => s + ((b['points'] as num?)?.toInt() ?? 0));
    final totalStamps = _businessPoints.fold<int>(
        0, (s, b) => s + ((b['stamps'] as num?)?.toInt() ?? 0));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  _HeroCard(
                    totalPoints: totalPoints,
                    totalStamps: totalStamps,
                    businessCount: _businessPoints.length,
                  ),
                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EDE8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(3),
                      labelColor: AppColors.textPrimary,
                      unselectedLabelColor: AppColors.textMuted,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Negocios'),
                        Tab(text: 'Historial'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _BusinessesTab(
              businesses: _filtered,
              allBusinesses: _businessPoints,
              filter: _filter,
              search: _search,
              searchController: _searchCtrl,
              onFilterChanged: (f) => setState(() => _filter = f),
              onSearchChanged: (s) => setState(() => _search = s),
              onSearchClear: () {
                _searchCtrl.clear();
                setState(() => _search = '');
              },
              onBusinessTap: (biz) => openBusinessRewardsSheet(context, biz),
            ),
            _HistorialTab(
              transactions: _transactions,
              businessLogos: _businessLogos,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loading ──────────────────────────────────────────────────────────

class _SkeletonView extends StatefulWidget {
  const _SkeletonView();

  @override
  State<_SkeletonView> createState() => _SkeletonViewState();
}

class _SkeletonViewState extends State<_SkeletonView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero skeleton
              Container(
                width: double.infinity,
                height: 130,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: _anim.value),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 16),

              // Tab skeleton
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EDE8).withValues(alpha: _anim.value),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 16),

              // Cards skeleton
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  children: List.generate(
                    4,
                    (i) => _SkeletonRow(opacity: _anim.value, last: i == 3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.opacity, required this.last});
  final double opacity;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final bg = Color.fromRGBO(0, 0, 0, 0.07 * opacity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF5F4F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 13,
                  width: 120,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 80,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                height: 22,
                width: 60,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 18,
                width: 44,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.totalPoints,
    required this.totalStamps,
    required this.businessCount,
  });

  final int totalPoints;
  final int totalStamps;
  final int businessCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            right: 30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MIS PUNTOS Y SELLOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat('#,###').format(totalPoints),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (totalStamps > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$totalStamps',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1,
                            ),
                          ),
                          Text(
                            'sellos',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'puntos acumulados',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              if (businessCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'En $businessCount negocio${businessCount != 1 ? 's' : ''} · actualizado ahora',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Businesses tab ────────────────────────────────────────────────────────────

class _BusinessesTab extends StatelessWidget {
  const _BusinessesTab({
    required this.businesses,
    required this.allBusinesses,
    required this.filter,
    required this.search,
    required this.searchController,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onBusinessTap,
  });

  final List<Map<String, dynamic>> businesses;
  final List<Map<String, dynamic>> allBusinesses;
  final String filter;
  final String search;
  final TextEditingController searchController;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final ValueChanged<Map<String, dynamic>> onBusinessTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        // Filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in [
                ('all', 'Todos'),
                ('points', 'Puntos'),
                ('stamps', 'Sellos'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onFilterChanged(f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: filter == f.$1
                            ? AppColors.primary
                            : const Color(0xFFF0EDE8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        f.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: filter == f.$1
                              ? AppColors.white
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Search with clear button
        if (allBusinesses.isNotEmpty)
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar negocio...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
              suffixIcon: search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textMuted, size: 18),
                      onPressed: onSearchClear,
                    )
                  : null,
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        const SizedBox(height: 10),

        // List
        if (allBusinesses.isEmpty)
          _EmptyState(
            icon: Icons.monetization_on_outlined,
            title: 'Sin puntos aún',
            subtitle: 'Visita un negocio afiliado y empieza a acumular',
          )
        else if (businesses.isEmpty)
          _EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Sin resultados',
            subtitle: search.isNotEmpty
                ? 'Sin resultados para "$search"'
                : 'Intenta con otro filtro',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              children: businesses
                  .map((b) => _BusinessCard(
                        biz: b,
                        filter: filter,
                        onTap: () => onBusinessTap(b),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.biz,
    required this.filter,
    required this.onTap,
  });
  final Map<String, dynamic> biz;
  final String filter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pts = (biz['points'] as num?)?.toInt() ?? 0;
    final stamps = (biz['stamps'] as num?)?.toInt() ?? 0;
    final lastVisit = biz['lastVisit'] as String?;
    String visitLabel = 'Sin visitas registradas';
    if (lastVisit != null) {
      final date = DateTime.tryParse(lastVisit);
      if (date != null) {
        visitLabel = 'Última visita ${DateFormat('d MMM', 'es').format(date)}';
      }
    }

    return InkWell(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F4F0))),
      ),
      child: Row(
        children: [
          BusinessAvatar(
            logoUrl: biz['businessLogoUrl'] as String?,
            name: biz['businessName'] as String? ?? '?',
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  biz['businessName'] as String? ?? 'Negocio',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  visitLabel,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (filter != 'stamps' && pts > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${NumberFormat('#,###').format(pts)} pts',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              if (filter != 'points' && stamps > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1F22A06B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$stamps sellos',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF22A06B),
                    ),
                  ),
                ),
              if ((filter == 'stamps' || pts == 0) && (filter == 'points' || stamps == 0))
                const Text(
                  '—',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ],
      ),
    ));
  }
}

// ── Historial tab ─────────────────────────────────────────────────────────────

class _HistorialTab extends StatelessWidget {
  const _HistorialTab({
    required this.transactions,
    required this.businessLogos,
  });
  final List<Map<String, dynamic>> transactions;
  final Map<String, String?> businessLogos;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Historial de transacciones',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Últimas 50 transacciones',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF0EDE8)),
              if (transactions.isEmpty)
                const _EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sin transacciones',
                  subtitle: 'Tus transacciones aparecerán aquí',
                )
              else
                ...transactions.map(
                  (tx) => _TransactionRow(tx: tx, businessLogos: businessLogos),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx, required this.businessLogos});
  final Map<String, dynamic> tx;
  final Map<String, String?> businessLogos;

  static String _formatRelative(String? iso) {
    if (iso == null) return '—';
    final date = DateTime.tryParse(iso);
    if (date == null) return '—';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return DateFormat('d MMM', 'es').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final type = tx['type'] as String? ?? 'add';
    final pts = (tx['totalPointsChange'] as num?)?.toInt() ?? 0;
    final stamps = (tx['totalStampsChange'] as num?)?.toInt() ?? 0;
    final bizName = tx['businessName'] as String? ?? 'Negocio';
    final bizId = tx['businessId'] as String?;
    final rewardName = tx['rewardName'] as String?;
    final createdAt = tx['createdAt'] as String?;
    final logoUrl = bizId != null ? businessLogos[bizId] : null;

    final (color, typeLabel) = switch (type) {
      'redeem' => (AppColors.primary, 'Canje'),
      'subtract' => (AppColors.textMuted, 'Ajuste'),
      _ => (const Color(0xFF22A06B), 'Compra'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0EDE8))),
      ),
      child: Row(
        children: [
          BusinessAvatar(
            logoUrl: logoUrl,
            name: bizName,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bizName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rewardName != null
                      ? '$rewardName · ${_formatRelative(createdAt)}'
                      : _formatRelative(createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (pts != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: pts > 0
                        ? AppColors.primary
                        : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${pts > 0 ? '+' : ''}$pts pts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: pts > 0 ? Colors.white : AppColors.error,
                    ),
                  ),
                ),
              if (pts != 0 && stamps != 0) const SizedBox(height: 3),
              if (stamps != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stamps > 0
                        ? const Color(0xFF22A06B)
                        : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${stamps > 0 ? '+' : ''}$stamps sellos',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: stamps > 0 ? Colors.white : AppColors.error,
                    ),
                  ),
                ),
              if (pts == 0 && stamps == 0)
                const Text(
                  '—',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
