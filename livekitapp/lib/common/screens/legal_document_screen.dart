import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/legal_repository.dart';
import 'package:livekitapp/common/widgets/simple_html_view.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _repository.getTermsAndPrivacy();
      if (!mounted) return;
      setState(() {
        _content = widget.documentType == 'privacy'
            ? data['privacy_policy'] ?? ''
            : data['terms_of_service'] ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE53950);
    final title = widget.documentType == 'privacy' ? 'Privacy Policy' : 'Terms of Service';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: pink, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.red,
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
