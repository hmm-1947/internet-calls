import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/legal_repository.dart';
import 'package:livekitapp/common/widgets/simple_html_view.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

/// Shared full-screen viewer for the admin-authored Terms of Service or
/// Privacy Policy. Used from both the user and listener settings screens.
class LegalDocumentScreen extends StatefulWidget {
  /// Either 'terms' or 'privacy'.
  final String documentType;

  const LegalDocumentScreen({super.key, required this.documentType});

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  final LegalRepository _repository = LegalRepository();
  bool _loading = true;
  String? _error;
  String _content = '';

  /// Cached copies live under one shared key so a change made to either
  /// document while offline is still reflected once the other is opened,
  /// same shape the server response already uses.
  static const _cacheKey = 'legal_terms_privacy';
  static const _refreshTtl = Duration(days: 7);

  String get _dataKey =>
      widget.documentType == 'privacy' ? 'privacy_policy' : 'terms_of_service';

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    final fresh = await HomeCache().isFresh(_cacheKey, _refreshTtl);
    final cached = await HomeCache().getJson(_cacheKey);
    if (!mounted) return;
    if (cached is Map) {
      final text = cached[_dataKey];
      if (text is String && text.isNotEmpty) {
        setState(() {
          _content = text;
          _loading = false;
        });
      }
    }
    if (!fresh) _load();
  }

  Future<void> _load() async {
    try {
      final data = await _repository.getTermsAndPrivacy();
      if (!mounted) return;
      final fresh = data[_dataKey] ?? '';
      // Only touch state/cache when the server copy actually differs, so a
      // background refresh after the cached copy already rendered doesn't
      // cause a visible flash for the common case of unchanged content.
      if (dataChanged(_content, fresh) || _loading) {
        setState(() {
          _content = fresh;
          _loading = false;
        });
      }
      HomeCache().setJson(_cacheKey, data);
    } catch (e) {
      if (!mounted) return;
      // A cached copy is already showing - a failed refresh should not
      // replace it with an error screen.
      if (_content.isNotEmpty) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE53950);
    final title = widget.documentType == 'privacy'
        ? 'Privacy Policy'
        : 'Terms of Service';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: null,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: pink))
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SimpleHtmlView(html: _content),
              ),
      ),
    );
  }
}
