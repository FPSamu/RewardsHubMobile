import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/client_service.dart';
import '../widgets/shared/business_avatar.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

LatLng? _extractLatLng(Map<String, dynamic> b) {
  // Nested location object (most common from API)
  final loc = b['location'] as Map<String, dynamic>?;
  if (loc != null) {
    final lat = (loc['latitude'] ?? loc['lat']) as num?;
    final lng = (loc['longitude'] ?? loc['lng'] ?? loc['lon']) as num?;
    if (lat != null && lng != null) return LatLng(lat.toDouble(), lng.toDouble());

    // GeoJSON: { type: "Point", coordinates: [lng, lat] }
    final coords = loc['coordinates'] as List?;
    if (coords != null && coords.length >= 2) {
      return LatLng((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
    }
  }
  // Top-level lat/lng fields
  final lat = (b['latitude'] ?? b['lat']) as num?;
  final lng = (b['longitude'] ?? b['lng'] ?? b['lon']) as num?;
  if (lat != null && lng != null) return LatLng(lat.toDouble(), lng.toDouble());
  return null;
}

// ── Main page ─────────────────────────────────────────────────────────────────

class ClientMapPage extends StatefulWidget {
  const ClientMapPage({super.key});

  @override
  State<ClientMapPage> createState() => _ClientMapPageState();
}

class _ClientMapPageState extends State<ClientMapPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _mapCtrl = MapController();

  LatLng? _userLocation;
  String? _locationError;
  bool _gettingLoc = true;

  List<Map<String, dynamic>> _businesses = [];
  Map<String, Map<String, int>> _userPointsMap = {};
  Map<String, List<dynamic>> _rewardsMap = {};
  bool _loading = true;

  String _filter = 'all';
  Map<String, dynamic>? _selected;

  static const _fallback = LatLng(20.6597, -103.3496); // Guadalajara

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  // ── Init ────────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _gettingLoc = true;
    });
    await _locateUser();
    await _loadData();
  }

  Future<void> _locateUser() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _userLocation = _fallback;
            _locationError = 'Ubicación no disponible. Mostrando Guadalajara.';
            _gettingLoc = false;
          });
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _userLocation = ll;
          _gettingLoc = false;
        });
        try { _mapCtrl.move(ll, 14); } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _userLocation = _fallback;
          _locationError = 'Ubicación no disponible. Mostrando Guadalajara.';
          _gettingLoc = false;
        });
      }
    }
  }

  Future<void> _loadData() async {
    try {
      setState(() => _loading = true);
      final loc = _userLocation ?? _fallback;

      final results = await Future.wait([
        ClientService.getUserPoints(),
        ClientService.getNearbyBusinesses(loc.latitude, loc.longitude, radius: 50),
      ]);

      final pointsData = results[0] as Map<String, dynamic>;
      final nearbyData = results[1] as Map<String, dynamic>;

      // Build userPoints map
      final ptsMap = <String, Map<String, int>>{};
      for (final bp in (pointsData['businessPoints'] as List? ?? [])) {
        final m = bp as Map<String, dynamic>;
        ptsMap[m['businessId'] as String] = {
          'points': (m['points'] as num?)?.toInt() ?? 0,
          'stamps': (m['stamps'] as num?)?.toInt() ?? 0,
        };
      }

      final rawList = (nearbyData['businesses'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      // Deduplicate by id, keep closest
      final deduped = <String, Map<String, dynamic>>{};
      for (final b in rawList) {
        final id = b['id'] as String? ?? b['_id'] as String? ?? '';
        final dist = (b['distance'] as num?)?.toDouble() ?? 9999.0;
        final prev = deduped[id];
        if (prev == null ||
            dist < ((prev['distance'] as num?)?.toDouble() ?? 9999.0)) {
          deduped[id] = {...b, 'id': id};
        }
      }
      final unique = deduped.values.toList();

      // Fetch redeemable rewards only for businesses the user has visited
      final rMap = <String, List<dynamic>>{};
      await Future.wait(unique.map((b) async {
        final id = b['id'] as String;
        final userPts = ptsMap[id];
        if (userPts == null) {
          rMap[id] = [];
          return;
        }
        try {
          final allRewards = await ClientService.getBusinessRewards(id);
          rMap[id] = allRewards.where((r) {
            final rm = r as Map<String, dynamic>;
            if (rm['isActive'] == false) return false;
            final pointsReq = (rm['pointsRequired'] as num?)?.toInt();
            final stampsReq = (rm['stampsRequired'] as num?)?.toInt();
            if (pointsReq != null) return userPts['points']! >= pointsReq;
            if (stampsReq != null) return userPts['stamps']! >= stampsReq;
            return false;
          }).toList();
        } catch (_) {
          rMap[id] = [];
        }
      }));

      // Enrich businesses
      final enriched = unique.map((b) {
        final id = b['id'] as String;
        final userPts = ptsMap[id];
        final hasVisited =
            userPts != null && ((userPts['points']! > 0) || (userPts['stamps']! > 0));
        final dist = (b['distance'] as num?)?.toDouble();
        return {
          ...b,
          'name': b['username'] ?? b['name'] ?? 'Negocio',
          'logoUrl': b['logoUrl'] as String?,
          'distanceRaw': dist ?? 9999.0,
          'distanceLabel': dist != null
              ? (dist < 1 ? '${(dist * 1000).round()} m' : '${dist.toStringAsFixed(1)} km')
              : '— km',
          'status': hasVisited ? 'visited' : 'not_visited',
          'hasRewards': (rMap[id]?.length ?? 0) > 0,
        };
      }).toList()
        ..sort((a, b) =>
            (a['distanceRaw'] as double).compareTo(b['distanceRaw'] as double));

      if (mounted) {
        setState(() {
          _businesses = enriched;
          _userPointsMap = ptsMap;
          _rewardsMap = rMap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recenter() async {
    await _locateUser();
    if (_userLocation != null) {
      _mapCtrl.move(_userLocation!, 14);
    }
  }

  // ── Filtering ────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'rewards':
        return _businesses.where((b) => b['hasRewards'] == true).toList();
      case 'visited':
        return _businesses.where((b) => b['status'] == 'visited').toList();
      case 'not_visited':
        return _businesses.where((b) => b['status'] != 'visited').toList();
      default:
        return _businesses;
    }
  }

  Map<String, int> get _counts => {
        'all': _businesses.length,
        'rewards': _businesses.where((b) => b['hasRewards'] == true).length,
        'visited': _businesses.where((b) => b['status'] == 'visited').length,
        'not_visited': _businesses.where((b) => b['status'] != 'visited').length,
      };

  Color _pinColor(Map<String, dynamic> b) {
    if (b['hasRewards'] == true) return const Color(0xFF10B981);
    if (b['status'] == 'visited') return const Color(0xFF6366F1);
    return const Color(0xFF9CA3AF);
  }

  void _selectBusiness(Map<String, dynamic> biz) {
    setState(() => _selected = biz);
    final ll = _extractLatLng(biz);
    if (ll != null) _mapCtrl.move(ll, 15);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mapHeight = MediaQuery.of(context).size.height * 0.45;
    final center = _userLocation ?? _fallback;
    final filtered = _filtered;
    final counts = _counts;

    return Column(
      children: [
        // ── Map section ─────────────────────────────────────────────────────
        SizedBox(
          height: mapHeight,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapCtrl,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 13,
                  onTap: (_, __) => setState(() => _selected = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.rewardshub.mobile',
                  ),
                  MarkerLayer(
                    markers: [
                      // User location
                      if (_userLocation != null)
                        Marker(
                          point: _userLocation!,
                          width: 22,
                          height: 22,
                          child: _UserMarker(),
                        ),
                      // Business markers (all, not just filtered — same as web)
                      ..._businesses.map((b) {
                        final ll = _extractLatLng(b);
                        if (ll == null) return null;
                        return Marker(
                          point: ll,
                          width: 40,
                          height: 46,
                          child: GestureDetector(
                            onTap: () => _selectBusiness(b),
                            child: _BusinessPin(
                              color: _pinColor(b),
                              logoUrl: b['logoUrl'] as String?,
                              name: b['name'] as String? ?? '?',
                              hasRewards: b['hasRewards'] == true,
                            ),
                          ),
                        );
                      }).whereType<Marker>(),
                    ],
                  ),
                ],
              ),

              // Loading overlay
              if (_gettingLoc || _loading)
                _MapLoadingOverlay(
                  label: _gettingLoc
                      ? 'Obteniendo tu ubicación…'
                      : 'Cargando negocios…',
                ),

              // Recenter button
              Positioned(
                right: 12,
                bottom: _selected != null ? 200 : 12,
                child: _RecenterButton(onTap: _recenter),
              ),

              // Location error banner
              if (_locationError != null && _selected == null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _LocationBanner(message: _locationError!),
                ),

              // Selected business card
              if (_selected != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BusinessBottomCard(
                    biz: _selected!,
                    userPointsMap: _userPointsMap,
                    rewardsMap: _rewardsMap,
                    onClose: () => setState(() => _selected = null),
                  ),
                ),
            ],
          ),
        ),

        // ── Scrollable content below map ─────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats strip
                _StatsStrip(
                  total: counts['all']!,
                  withRewards: counts['rewards']!,
                  visited: counts['visited']!,
                ),
                const SizedBox(height: 14),

                // Filter pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in [
                        ('all', 'Todos'),
                        ('rewards', 'Recompensas'),
                        ('visited', 'Visitados'),
                        ('not_visited', 'Sin visitar'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterPill(
                            label: f.$2,
                            count: _filter != f.$1 ? counts[f.$1] : null,
                            selected: _filter == f.$1,
                            onTap: () => setState(() => _filter = f.$1),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Business list card
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
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Negocios cercanos',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Radio de 50 km desde tu ubicación',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${filtered.length} negocios',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF0EDE8)),

                      // Rows
                      if (_loading)
                        ..._buildSkeletonRows()
                      else if (filtered.isEmpty)
                        const _EmptyState()
                      else
                        ...filtered.map(
                          (biz) => _BusinessRow(
                            biz: biz,
                            userPointsMap: _userPointsMap,
                            rewardsMap: _rewardsMap,
                            onTap: () => _selectBusiness(biz),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSkeletonRows() {
    return List.generate(
      3,
      (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
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
                      color: Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 70,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── User marker ───────────────────────────────────────────────────────────────

class _UserMarker extends StatefulWidget {
  @override
  State<_UserMarker> createState() => _UserMarkerState();
}

class _UserMarkerState extends State<_UserMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _scale = Tween(begin: 1.0, end: 2.4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x406366F1).withValues(alpha: _opacity.value),
              ),
            ),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6366F1),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Business pin marker ───────────────────────────────────────────────────────

class _BusinessPin extends StatelessWidget {
  const _BusinessPin({
    required this.color,
    required this.logoUrl,
    required this.name,
    required this.hasRewards,
  });
  final Color color;
  final String? logoUrl;
  final String name;
  final bool hasRewards;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: color,
              width: hasRewards ? 2.5 : 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: hasRewards ? 0.4 : 0.2),
                blurRadius: hasRewards ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: BusinessAvatar(logoUrl: logoUrl, name: name, size: 36),
          ),
        ),
        CustomPaint(
          size: const Size(8, 5),
          painter: _TrianglePainter(color: color),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// ── Map overlays ──────────────────────────────────────────────────────────────

class _MapLoadingOverlay extends StatelessWidget {
  const _MapLoadingOverlay({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F5).withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location_rounded,
          size: 20,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Business bottom card (shows on map when selected) ─────────────────────────

class _BusinessBottomCard extends StatelessWidget {
  const _BusinessBottomCard({
    required this.biz,
    required this.userPointsMap,
    required this.rewardsMap,
    required this.onClose,
  });
  final Map<String, dynamic> biz;
  final Map<String, Map<String, int>> userPointsMap;
  final Map<String, List<dynamic>> rewardsMap;
  final VoidCallback onClose;

  Future<void> _openMaps() async {
    final ll = _extractLatLng(biz);
    if (ll == null) return;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${ll.latitude},${ll.longitude}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final id = biz['id'] as String? ?? '';
    final name = biz['name'] as String? ?? 'Negocio';
    final logoUrl = biz['logoUrl'] as String?;
    final distance = biz['distanceLabel'] as String? ?? '— km';
    final userPts = userPointsMap[id];
    final rewards = rewardsMap[id] ?? [];
    final isVisited = biz['status'] == 'visited';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16)],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header row
            Row(
              children: [
                BusinessAvatar(logoUrl: logoUrl, name: name, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$distance de distancia',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Status badges
            Row(
              children: [
                if (rewards.isNotEmpty)
                  _MapBadge(
                    label:
                        '${rewards.length} recompensa${rewards.length > 1 ? 's' : ''}',
                    bgColor: const Color(0xFFD1FAE5),
                    textColor: const Color(0xFF065F46),
                  ),
                if (isVisited) ...[
                  if (rewards.isNotEmpty) const SizedBox(width: 6),
                  _MapBadge(
                    label: 'Visitado',
                    bgColor: AppColors.primaryMuted,
                    textColor: AppColors.primary,
                  ),
                ] else ...[
                  if (rewards.isNotEmpty) const SizedBox(width: 6),
                  _MapBadge(
                    label: 'Sin visitar',
                    bgColor: const Color(0xFFF0EDE8),
                    textColor: AppColors.textMuted,
                  ),
                ],
              ],
            ),

            // Points / stamps tiles
            if (userPts != null &&
                ((userPts['points'] ?? 0) > 0 || (userPts['stamps'] ?? 0) > 0)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if ((userPts['points'] ?? 0) > 0)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${userPts['points']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            const Text(
                              'PUNTOS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if ((userPts['points'] ?? 0) > 0 && (userPts['stamps'] ?? 0) > 0)
                    const SizedBox(width: 8),
                  if ((userPts['stamps'] ?? 0) > 0)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${userPts['stamps']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF065F46),
                              ),
                            ),
                            const Text(
                              'SELLOS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF065F46),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // CTA
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _openMaps,
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text(
                  'Cómo llegar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBadge extends StatelessWidget {
  const _MapBadge({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });
  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Stats strip ───────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.total,
    required this.withRewards,
    required this.visited,
  });
  final int total;
  final int withRewards;
  final int visited;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          label: 'Cercanos',
          value: total,
          valueColor: AppColors.primary,
          bgColor: AppColors.primaryMuted,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Recompensas',
          value: withRewards,
          valueColor: const Color(0xFF065F46),
          bgColor: const Color(0xFFD1FAE5),
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Visitados',
          value: visited,
          valueColor: const Color(0xFF6366F1),
          bgColor: const Color(0xFFEEF2FF),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.bgColor,
  });
  final String label;
  final int value;
  final Color valueColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: valueColor,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter pill ───────────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF0EDE8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.white : AppColors.textMuted,
              ),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? AppColors.white.withValues(alpha: 0.7)
                      : AppColors.textMuted.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Business row (in list) ────────────────────────────────────────────────────

class _BusinessRow extends StatelessWidget {
  const _BusinessRow({
    required this.biz,
    required this.userPointsMap,
    required this.rewardsMap,
    required this.onTap,
  });
  final Map<String, dynamic> biz;
  final Map<String, Map<String, int>> userPointsMap;
  final Map<String, List<dynamic>> rewardsMap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = biz['id'] as String? ?? '';
    final name = biz['name'] as String? ?? 'Negocio';
    final logoUrl = biz['logoUrl'] as String?;
    final distance = biz['distanceLabel'] as String? ?? '';
    final userPts = userPointsMap[id];
    final rewards = rewardsMap[id] ?? [];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            BusinessAvatar(logoUrl: logoUrl, name: name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distance,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (rewards.isNotEmpty ||
                      (userPts?['points'] ?? 0) > 0 ||
                      (userPts?['stamps'] ?? 0) > 0) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (rewards.isNotEmpty)
                          _RowBadge(
                            label:
                                '${rewards.length} recompensa${rewards.length > 1 ? 's' : ''}',
                            bgColor: const Color(0xFFD1FAE5),
                            textColor: const Color(0xFF065F46),
                          ),
                        if ((userPts?['points'] ?? 0) > 0)
                          _RowBadge(
                            label: '${userPts!['points']} pts',
                            bgColor: AppColors.primaryMuted,
                            textColor: AppColors.primary,
                          ),
                        if ((userPts?['stamps'] ?? 0) > 0)
                          _RowBadge(
                            label: '${userPts!['stamps']} sellos',
                            bgColor: const Color(0xFFF0EDE8),
                            textColor: AppColors.textMuted,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowBadge extends StatelessWidget {
  const _RowBadge({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });
  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EDE8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.store_outlined,
              size: 24,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sin negocios en esta categoría',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prueba con otro filtro',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
