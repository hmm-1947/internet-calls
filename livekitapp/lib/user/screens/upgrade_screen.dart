import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/billing_repository.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

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
  String? _bannerUrl;

  late final Razorpay _razorpay;
  String? _pendingOrderId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _loadFromCache();
    _load();
  }

  static const _plansCacheKey = 'user_upgrade_plans';
  static const _bannerCacheKey = 'user_upgrade_banner';
  static const _coinsCacheKey = 'user_upgrade_coins';

  /// Renders the admin-configured plans/banner and the last known coin
  /// balance from local storage instantly, so opening this screen doesn't
  /// always show a spinner (or a misleading 0) while the network round-trip
  /// completes. The displayed values only change in [_load] once a fresh
  /// fetch shows they actually differ from what's cached.
  Future<void> _loadFromCache() async {
    final cachedPlans = await HomeCache().getJson(_plansCacheKey);
    final cachedBanner = await HomeCache().getJson(_bannerCacheKey);
    final cachedCoins = await HomeCache().getJson(_coinsCacheKey);
    if (!mounted) return;
    final hasPlans = cachedPlans is List && cachedPlans.isNotEmpty;
    final hasCoins = cachedCoins is Map && cachedCoins['coins'] is num;
    if (!hasPlans && !hasCoins) return;
    setState(() {
      if (hasPlans) {
        final plans = cachedPlans.cast<Map<String, dynamic>>();
        _plans = plans;
        _bannerUrl = cachedBanner is Map
            ? cachedBanner['url'] as String?
            : null;
        _selectedPlanId =
            (plans.firstWhere(
                  (p) => p['is_featured'] == true,
                  orElse: () => plans.first,
                )['id']
                as int);
      }
      if (hasCoins) {
        _coins = (cachedCoins['coins'] as num).toInt();
      }
      _error = null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  bool _hasCachedCoins = false;

  Future<void> _load() async {
    // Only show the spinner when there is nothing on screen yet - if
    // _loadFromCache already rendered plans or a coin balance, this refresh
    // happens quietly behind them instead of blanking the screen back to a
    // spinner.
    if (_plans.isEmpty && !_hasCachedCoins) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

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
    // A cached plan list/coin balance already on screen is left alone
    // rather than being replaced with a hard error over a coins-fetch
    // failure.
    int? coins;
    try {
      final me = await _userRepository.getMe(token);
      coins = (me['coins'] as num?)?.toInt() ?? 0;
    } catch (e) {
      if (!mounted) return;
      if (_plans.isNotEmpty || _hasCachedCoins) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
      return;
    }

    // Plans are optional — if none exist yet, or the request fails for any
    // reason (empty table, transient server error, etc.), keep whatever is
    // already cached/on screen instead of clearing it to "No plan available".
    List<Map<String, dynamic>>? plans;
    try {
      plans = await _billingRepository.getPlans(token);
    } catch (_) {
      plans = null;
    }

    String? bannerUrl;
    bool bannerFetched = false;
    try {
      bannerUrl = await _billingRepository.getUpgradeBannerUrl();
      bannerFetched = true;
    } catch (_) {
      bannerFetched = false;
    }

    if (!mounted) return;
    final plansChanged = plans != null && dataChanged(_plans, plans);
    final coinsChanged = !_hasCachedCoins || dataChanged(_coins, coins);
    setState(() {
      if (coinsChanged) {
        _coins = coins!;
      }
      _hasCachedCoins = true;
      if (plansChanged) {
        _plans = plans!;
        _selectedPlanId = plans.isNotEmpty
            ? (plans.firstWhere(
                    (p) => p['is_featured'] == true,
                    orElse: () => plans!.first,
                  )['id']
                  as int)
            : null;
      }
      if (bannerFetched && dataChanged(_bannerUrl, bannerUrl)) {
        _bannerUrl = bannerUrl;
      }
      _loading = false;
    });

    if (plans != null) {
      HomeCache().setJson(_plansCacheKey, plans);
    }
    if (bannerFetched) {
      HomeCache().setJson(_bannerCacheKey, {'url': bannerUrl});
    }
    if (coinsChanged) {
      HomeCache().setJson(_coinsCacheKey, {'coins': coins});
    }
  }


  Future<void> _purchase() async {
    if (_selectedPlanId == null || _purchasing) return;
    setState(() => _purchasing = true);
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('Not logged in');
      // Step 1: ask the backend to create a Razorpay order for this plan.
      // No coins are granted yet - that only happens after a verified
      // payment (see _onPaymentSuccess).
      final order = await _billingRepository.purchasePlan(
        token,
        _selectedPlanId!,
      );
      _pendingOrderId = order['order_id'] as String?;

      final options = {
        'key': order['key_id'],
        'amount': order['amount'],
        'currency': order['currency'] ?? 'INR',
        'order_id': order['order_id'],
        'name': 'Coin Purchase',
        'description': order['plan_name'],
        'prefill': {
          'contact': order['contact'] ?? '',
          'email': order['email'] ?? '',
          'name': order['name'] ?? '',
        },
        // The app already knows the user's email/phone, so lock these
        // fields instead of making the user retype them at checkout.
        'readonly': {'contact': true, 'email': true},
        'theme': {'color': '#E11D48'},
      };

      _razorpay.open(options);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _purchasing = false);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('Not logged in');
      // Step 2: verify the payment signature on the backend. Coins are
      // credited server-side only once this succeeds.
      final result = await _billingRepository.verifyPayment(
        token,
        razorpayOrderId: response.orderId ?? _pendingOrderId ?? '',
        razorpayPaymentId: response.paymentId ?? '',
        razorpaySignature: response.signature ?? '',
      );
      final coinsPurchased = (result['coins_purchased'] as num?)?.toInt() ?? 0;
      final newBalance = (result['coins_balance'] as num?)?.toInt();
      if (!mounted) return;
      if (newBalance != null) setState(() => _coins = newBalance);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$coinsPurchased coins added to your balance'),
          backgroundColor: _AppColors.brandRed,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment received but verification failed: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      _pendingOrderId = null;
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _onPaymentError(PaymentFailureResponse response) async {
    final reason = (response.message == null || response.message == 'undefined')
        ? 'Payment failed'
        : response.message!;
    final orderId = _pendingOrderId;
    if (orderId != null) {
      final token = await _localStorage.getToken();
      if (token != null) {
        await _billingRepository.reportPaymentFailed(
          token,
          razorpayOrderId: orderId,
          reason: reason,
        );
      }
    }
    _pendingOrderId = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(reason), backgroundColor: Colors.redAccent),
    );
    setState(() => _purchasing = false);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening ${response.walletName ?? 'wallet'}...')),
    );
    setState(() => _purchasing = false);
  }

  IconData _iconForType(String? icon) {
    switch (icon) {
      case 'diamond':
        return Icons.diamond_outlined;
      case 'star':
        return Icons.star_rounded;
      case 'coin':
      default:
        return Icons.monetization_on_outlined;
    }
  }

  IconData _iconForPlan(Map<String, dynamic> plan) =>
      _iconForType(plan['icon'] as String?);

  // Icon theme follows Best Seller status, not the icon type itself:
  // gold for regular plans, red for the featured/best-seller plan.
  Color _colorForPlan(Map<String, dynamic> plan) =>
      plan['is_featured'] == true ? _AppColors.brandRed : _AppColors.gold;

  Widget _planIconGlyph(Map<String, dynamic> plan, Color color) {
    final type = plan['icon'] as String?;
    if (type == 'star') {
      // Compose a star inside a circle outline (no single Material icon
      // matches this exactly).
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.circle_outlined, color: color, size: 22),
          Icon(Icons.star_rounded, color: color, size: 12),
        ],
      );
    }
    return Icon(_iconForPlan(plan), color: color, size: 22);
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
                  disabledBackgroundColor: _AppColors.brandRed.withOpacity(0.4),
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
    final url = ApiConstants.resolveMediaUrl(_bannerUrl);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(60),
                boxShadow: [
                  BoxShadow(
                    color: _AppColors.brandRed.withOpacity(0.55),
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          url.isEmpty
              ? Icon(Icons.workspace_premium, color: _AppColors.gold, size: 72)
              : ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 220,
                    maxWidth: 260,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      cacheWidth: (260 * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.workspace_premium,
                        color: _AppColors.gold,
                        size: 72,
                      ),
                    ),
                  ),
                ),
        ],
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
            const Icon(
              Icons.payments_rounded,
              color: _AppColors.gold,
              size: 22,
            ),
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
    final coins = plan['coins'] as int? ?? 0;
    final iconColor = _colorForPlan(plan);

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
                    color: featured
                        ? _AppColors.brandRed.withOpacity(0.16)
                        : const Color(0xFF13212F),
                    shape: BoxShape.circle,
                  ),
                  child: _planIconGlyph(plan, iconColor),
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
                        '$coins Coins',
                        style: const TextStyle(
                          color: _AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '₹${plan['price']}',
                  style: TextStyle(
                    color: featured ? _AppColors.brandRed : Colors.white,
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
