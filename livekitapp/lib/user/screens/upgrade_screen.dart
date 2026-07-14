import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/billing_repository.dart';
import 'package:livekitapp/user/repository/user_repository.dart';

class _AppColors {
  static const bg = Color(0xFF0B0B0B);
  static const cardBg = Color(0xCC1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const brandRed = Color(0xFFE11D48);
  static const textSecondary = Color(0xFFD4E4FA);
  static const textMuted = Color(0xFF9C8484);
  static const gold = Color(0xFFE8B93A);
}

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  final _billingRepository = BillingRepository();
  final _userRepository = UserRepository();
  final _localStorage = LocalStorage();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = [];
  int _coins = 0;
  int? _selectedPlanId;
  bool _purchasing = false;

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

    final token = await _localStorage.getToken();
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _error = 'Not logged in';
        _loading = false;
      });
      return;
    }

    // Balance is essential info for this screen — if it fails, show the
    // error state since something is genuinely wrong (e.g. bad session).
    int coins;
    try {
      final me = await _userRepository.getMe(token);
      coins = (me['coins'] as num?)?.toInt() ?? 0;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
      return;
    }

    // Plans are optional — if none exist yet, or the request fails for any
    // reason (empty table, transient server error, etc.), just fall back to
    // an empty list so the screen still renders with "No plan available"
    // instead of showing a hard error.
    List<Map<String, dynamic>> plans = [];
    try {
      plans = await _billingRepository.getPlans(token);
    } catch (_) {
      plans = [];
    }

    if (!mounted) return;
    setState(() {
      _coins = coins;
      _plans = plans;
      _selectedPlanId = plans.isNotEmpty
          ? (plans.firstWhere(
                  (p) => p['is_featured'] == true,
                  orElse: () => plans.first,
                )['id']
                as int)
          : null;
      _loading = false;
    });
  }

  Future<void> _purchase() async {
    if (_selectedPlanId == null || _purchasing) return;
    setState(() => _purchasing = true);
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('Not logged in');
      await _billingRepository.purchasePlan(token, _selectedPlanId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan purchased successfully'),
          backgroundColor: _AppColors.brandRed,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  IconData _iconForPlan(Map<String, dynamic> plan) {
    final type = plan['plan_type'] as String? ?? 'monthly';
    switch (type) {
      case 'yearly':
        return Icons.diamond_outlined;
      case 'quarterly':
        return Icons.star_outline;
      default:
        return Icons.monetization_on_outlined;
    }
  }

  String _cycleLabel(Map<String, dynamic> plan) {
    final type = plan['plan_type'] as String? ?? 'monthly';
    final validity = plan['validity_value'] ?? 1;
    final unit = type == 'monthly'
        ? 'month'
        : type == 'quarterly'
        ? 'quarter'
        : 'year';
    final plural = validity == 1 ? unit : '${unit}s';
    return '$validity $plural';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Upgrade',
          style: TextStyle(
            color: _AppColors.brandRed,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _AppColors.brandRed),
              )
            : _error != null
            ? _buildError()
            : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: _AppColors.brandRed,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final hasPlans = _plans.isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            children: [
              _buildBanner(),
              const SizedBox(height: 20),
              _buildBalance(),
              const SizedBox(height: 20),
              if (!hasPlans)
                _buildNoPlansState()
              else
                ..._plans.map(_buildPlanCard),
            ],
          ),
        ),
        if (hasPlans)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_selectedPlanId == null || _purchasing)
                    ? null
                    : _purchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _AppColors.brandRed,
                  disabledBackgroundColor: _AppColors.brandRed.withOpacity(
                    0.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _purchasing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'PURCHASE NOW',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoPlansState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              color: _AppColors.textMuted.withOpacity(0.6),
              size: 36,
            ),
            const SizedBox(height: 12),
            const Text(
              'No plans currently available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please check back later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            _AppColors.gold.withOpacity(0.35),
            const Color(0xFF1A1410),
          ],
        ),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      child: const Center(
        child: Icon(Icons.workspace_premium, color: _AppColors.gold, size: 72),
      ),
    );
  }

  Widget _buildBalance() {
    return Column(
      children: [
        const Text(
          'MY BALANCE',
          style: TextStyle(
            color: _AppColors.textMuted,
            fontSize: 12,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.savings_outlined, color: _AppColors.gold, size: 22),
            const SizedBox(width: 8),
            Text(
              '$_coins Coins',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final id = plan['id'] as int;
    final selected = _selectedPlanId == id;
    final featured = plan['is_featured'] == true;
    final description = (plan['description'] as String?)?.trim();

    return GestureDetector(
      onTap: () => setState(() => _selectedPlanId = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _AppColors.brandRed : _AppColors.cardBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconForPlan(plan),
                    color: _AppColors.gold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name'] as String? ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Valid for ${_cycleLabel(plan)}',
                        style: const TextStyle(
                          color: _AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(
                            color: _AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '₹${plan['price']}',
                  style: const TextStyle(
                    color: _AppColors.brandRed,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (featured)
              Positioned(
                top: -16,
                right: -16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _AppColors.brandRed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'BEST SELLER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
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
