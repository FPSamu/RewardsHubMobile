import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/data/auth_service.dart';
import '../../client/data/client_service.dart';
import 'pages/client_home_page.dart';
import 'pages/client_map_page.dart';
import 'pages/client_points_page.dart';
import 'pages/client_settings_page.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell>
    with WidgetsBindingObserver {
  int _currentIndex = 1; // start on home
  Map<String, dynamic>? _user;

  final _homeKey = GlobalKey<ClientHomePageState>();
  final _pointsKey = GlobalKey<ClientPointsPageState>();
  final _mapKey = GlobalKey<ClientMapPageState>();

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadUser();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshAll(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  void _refreshAll() {
    _homeKey.currentState?.refresh();
    _pointsKey.currentState?.refresh();
    _mapKey.currentState?.refresh();
  }

  void _refreshOthers() {
    _pointsKey.currentState?.refresh();
    _mapKey.currentState?.refresh();
  }

  Future<void> _loadUser() async {
    final user = await SecureStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  // ── Redeem modal ─────────────────────────────────────────────────────────

  void _showRedeemModal() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.60),
      builder: (_) => const _RedeemCodeDialog(),
    );
  }

  // ── Profile menu ──────────────────────────────────────────────────────────

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileMenu(
        user: _user,
        onSettings: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClientSettingsPage(
                user: _user ?? {},
                onUserUpdated: (updated) {
                  setState(() => _user = updated);
                  SecureStorage.updateUser(updated);
                },
              ),
            ),
          );
        },
        onLogout: () async {
          Navigator.pop(context);
          await AuthService.logout();
          widget.onLogout();
        },
      ),
    );
  }

  // ── Pages ─────────────────────────────────────────────────────────────────

  late final _pages = [
    ClientPointsPage(key: _pointsKey),
    ClientHomePage(
      key: _homeKey,
      onVerTodos: () => setState(() => _currentIndex = 0),
      onRefreshOthers: _refreshOthers,
    ),
    ClientMapPage(key: _mapKey),
  ];

  // ── AppBar titles ─────────────────────────────────────────────────────────

  static const _titles = ['Mis Puntos', 'Inicio', 'Mapa'];

  @override
  Widget build(BuildContext context) {
    final username = _user?['username'] as String? ?? 'Usuario';
    final avatarUrl = _user?['profilePicture'] as String?
        ?? _user?['avatarUrl'] as String?
        ?? _user?['photo'] as String?;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F0),
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: _currentIndex == 1
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, $username 👋',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Text(
                    'Bienvenido a RewardsHub',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              )
            : Text(
                _titles[_currentIndex],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
        actions: [
          GestureDetector(
            onTap: _showProfileMenu,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryMuted,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      floatingActionButton: _currentIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _showRedeemModal,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              elevation: 4,
              icon: const Icon(Icons.confirmation_number_outlined, size: 20),
              label: const Text(
                'Canjear Código',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _ClientBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ── Redeem code dialog ────────────────────────────────────────────────────────

class _RedeemCodeDialog extends StatefulWidget {
  const _RedeemCodeDialog();

  @override
  State<_RedeemCodeDialog> createState() => _RedeemCodeDialogState();
}

class _RedeemCodeDialogState extends State<_RedeemCodeDialog> {
  final _controller = TextEditingController();
  String _status = 'idle'; // idle | loading | success | error
  String _error = '';
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() { _status = 'loading'; _error = ''; });
    try {
      final data = await ClientService.claimCode(code);
      setState(() { _status = 'success'; _result = data; });
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() { _status = 'error'; _error = msg.isNotEmpty ? msg : 'Código inválido o expirado'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              color: AppColors.primary,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.confirmation_number_outlined, size: 28, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Canjear Código',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ingresa el código de tu ticket',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: _status == 'loading' ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.75), size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.all(24),
              child: _status == 'success'
                  ? _SuccessBody(result: _result, onClose: () => Navigator.pop(context))
                  : _FormBody(
                      controller: _controller,
                      status: _status,
                      error: _error,
                      onSubmit: _submit,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormBody extends StatefulWidget {
  const _FormBody({
    required this.controller,
    required this.status,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String status;
  final String error;
  final VoidCallback onSubmit;

  @override
  State<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends State<_FormBody> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.status == 'loading';
    final hasText = widget.controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'CÓDIGO DEL TICKET',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: widget.controller,
          enabled: !isLoading,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          maxLength: 10,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
            color: AppColors.textPrimary,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'XXX-XXX',
            hintStyle: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              letterSpacing: 6,
              color: AppColors.border,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border, width: 2),
            ),
          ),
          onChanged: (v) => widget.controller.value = widget.controller.value.copyWith(
            text: v.toUpperCase(),
            selection: TextSelection.collapsed(offset: v.length),
          ),
          onSubmitted: (_) => widget.onSubmit(),
        ),
        if (widget.status == 'error') ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFCDD2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.error,
                    style: const TextStyle(fontSize: 13, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading || !hasText ? null : widget.onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primaryMuted,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Text('Canjear Puntos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({required this.result, required this.onClose});
  final Map<String, dynamic>? result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final pts = (result?['pointsAdded'] as num?)?.toInt();
    final stamps = (result?['stampsAdded'] as num?)?.toInt();
    final hasPoints = pts != null && pts > 0;
    final hasStamps = stamps != null && stamps > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64, height: 64,
          decoration: const BoxDecoration(
            color: Color(0xFFF0FBF6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 32, color: Color(0xFF22A06B)),
        ),
        const SizedBox(height: 16),
        const Text(
          '¡Código Canjeado!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        if (hasPoints || hasStamps) ...[
          const Text(
            'Recibiste',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasPoints)
                _RewardPill(label: '+$pts puntos', color: AppColors.primary),
              if (hasPoints && hasStamps)
                const SizedBox(width: 8),
              if (hasStamps)
                _RewardPill(label: '+$stamps sellos', color: const Color(0xFF22A06B)),
            ],
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF0EDE8),
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _RewardPill extends StatelessWidget {
  const _RewardPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

// ── Bottom navigation bar ─────────────────────────────────────────────────────

class _ClientBottomNav extends StatelessWidget {
  const _ClientBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              // Mis Puntos
              Expanded(
                child: _NavItem(
                  icon: Icons.stars_rounded,
                  label: 'Mis Puntos',
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),

              // Inicio (center — prominent)
              _HomeNavItem(
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),

              // Mapa
              Expanded(
                child: _NavItem(
                  icon: Icons.map_outlined,
                  label: 'Mapa',
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryMuted : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 22,
              color: selected ? AppColors.primary : const Color(0xFFBBB0A0),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : const Color(0xFFBBB0A0),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeNavItem extends StatelessWidget {
  const _HomeNavItem({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : const Color(0xFFF0EDE8),
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Icon(
                Icons.home_rounded,
                size: 24,
                color: selected ? AppColors.white : const Color(0xFFBBB0A0),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Inicio',
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : const Color(0xFFBBB0A0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile menu bottom sheet ─────────────────────────────────────────────────

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({
    required this.user,
    required this.onSettings,
    required this.onLogout,
  });

  final Map<String, dynamic>? user;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final username = user?['username'] as String? ?? 'Usuario';
    final email = user?['email'] as String? ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // User info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primaryMuted,
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),

            // Options
            _MenuOption(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              onTap: onSettings,
            ),
            _MenuOption(
              icon: Icons.logout_rounded,
              label: 'Cerrar Sesión',
              color: AppColors.error,
              onTap: onLogout,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuOption extends StatelessWidget {
  const _MenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
