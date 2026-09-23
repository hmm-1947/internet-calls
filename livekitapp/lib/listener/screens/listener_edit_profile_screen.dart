import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekitapp/common/utils/profile_image_crop.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

class _AppColors {
  static const bg = Color(0xFF0B0B0B);
  static const cardBg = Color(0xFF1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const brandRed = Color(0xFFE11D48);
  static const online = Color(0xFF74D8BD);
  static const textMuted = Color(0xFF9CA3AF);
}

String _memberSinceYear(String? createdAt) {
  if (createdAt == null) return '';
  try {
    return DateTime.parse(createdAt).year.toString();
  } catch (_) {
    return '';
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final String text;
  final VoidCallback? onDeleted;
  const _ProfileChip(this.text, {this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: _AppColors.cardBg,
      side: const BorderSide(color: _AppColors.cardBorder),
      onDeleted: onDeleted,
      deleteIconColor: Colors.white54,
    );
  }
}

class ListenerProfileScreen extends StatefulWidget {
  const ListenerProfileScreen({super.key});

  @override
  State<ListenerProfileScreen> createState() => ListenerProfileScreenState();
}

class ListenerProfileScreenState extends State<ListenerProfileScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  String _name = '';
  String? _photoUrl;
  bool _uploadingPhoto = false;
  String _about = '';
  List<String> _tags = [];
  List<String> _languages = [];
  int? _age;
  String _occupation = '';
  double? _avgRating;
  int _ratingCount = 0;
  int _totalCalls = 0;
  bool _isOnline = false;
  String? _createdAt;

  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  final _aboutController = TextEditingController();
  final _ageController = TextEditingController();
  final _occupationController = TextEditingController();
  final _tagController = TextEditingController();
  final _languageController = TextEditingController();
  late List<String> _editTags;
  late List<String> _editLanguages;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _aboutController.dispose();
    _ageController.dispose();
    _occupationController.dispose();
    _tagController.dispose();

    _languageController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final isFirstLoad = _createdAt == null && _name.isEmpty;
    if (isFirstLoad) setState(() => _loading = true);
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getMe(token!);
      final newSnapshot = {
        'name': data['name'] ?? '',
        'photo_url': data['photo_url'],
        'about': data['about'] ?? '',
        'tags': List<String>.from(data['tags'] ?? []),
        'languages': List<String>.from(data['languages'] ?? []),
        'age': data['age'],
        'occupation': data['occupation'] ?? '',
        'avg_rating': (data['avg_rating'] as num?)?.toDouble(),
        'rating_count': data['rating_count'] ?? 0,
        'total_calls': data['total_calls'] ?? 0,
        'is_online': data['is_online'] ?? false,
        'created_at': data['created_at'],
      };
      final oldSnapshot = {
        'name': _name,
        'photo_url': _photoUrl,
        'about': _about,
        'tags': _tags,
        'languages': _languages,
        'age': _age,
        'occupation': _occupation,
        'avg_rating': _avgRating,
        'rating_count': _ratingCount,
        'total_calls': _totalCalls,
        'is_online': _isOnline,
        'created_at': _createdAt,
      };
      if (dataChanged(oldSnapshot, newSnapshot)) {
        setState(() {
          _name = newSnapshot['name'] as String;
          _photoUrl = newSnapshot['photo_url'] as String?;
          _about = newSnapshot['about'] as String;
          _tags = newSnapshot['tags'] as List<String>;
          _languages = newSnapshot['languages'] as List<String>;
          _age = newSnapshot['age'] as int?;
          _occupation = newSnapshot['occupation'] as String;
          _avgRating = newSnapshot['avg_rating'] as double?;
          _ratingCount = newSnapshot['rating_count'] as int;
          _totalCalls = newSnapshot['total_calls'] as int;
          _isOnline = newSnapshot['is_online'] as bool;
          _createdAt = newSnapshot['created_at'] as String?;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _startEditing() {
    _aboutController.text = _about;
    _ageController.text = _age?.toString() ?? '';
    _occupationController.text = _occupation;
    _editTags = List.from(_tags);
    _editLanguages = List.from(_languages);
    setState(() => _editing = true);
  }

  Future<void> _pickAndUploadPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (picked == null) return;
    final cropped = await cropProfileImage(
      picked,
      brandColor: _AppColors.brandRed,
    );
    if (cropped == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final token = await _localStorage.getToken();
      final result = await _repository.updatePhoto(token!, cropped.path);
      ListenerDataCache().invalidateMe();
      if (mounted) setState(() => _photoUrl = result['photo_url']);
    } catch (e) {
      if (mounted) {
        PillMessage.showError(
          context,
          friendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _cancelEditing() {
    setState(() => _editing = false);
  }

  Future<void> _saveProfile() async {
    final parsedAge = int.tryParse(_ageController.text.trim());
    if (parsedAge != null && (parsedAge < 1 || parsedAge > 100)) {
      PillMessage.showError(context, 'Age must be between 1 and 100');
      return;
    }
    setState(() => _saving = true);
    try {
      final token = await _localStorage.getToken();
      await _repository.updateProfile(
        token!,
        about: _aboutController.text.trim(),
        tags: _editTags,
        languages: _editLanguages,
        age: parsedAge,
        occupation: _occupationController.text.trim(),
      );
      setState(() {
        _about = _aboutController.text.trim();
        _tags = List.from(_editTags);
        _languages = List.from(_editLanguages);
        _age = parsedAge;
        _occupation = _occupationController.text.trim();
        _editing = false;
        _saving = false;
      });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        PillMessage.showError(
          context,
          friendlyError(e),
        );
      }
    }
  }

  Widget _tagInputRow(
    TextEditingController controller,
    List<String> list,
    String hint, {
    int? maxCount,
    int? maxChars,
  }) {
    final atLimit = maxCount != null && list.length >= maxCount;
    void addFromController() {
      var t = controller.text.trim();
      if (t.isEmpty) return;
      if (maxChars != null && t.length > maxChars) {
        t = t.substring(0, maxChars);
      }
      setState(() {
        list.add(t);
        controller.clear();
      });
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !atLimit,
            maxLength: maxChars,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterText: '',
              hintText: atLimit ? 'Limit reached' : hint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: _AppColors.cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: atLimit ? null : (_) => addFromController(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add_circle, color: _AppColors.brandRed),
          onPressed: atLimit ? null : addFromController,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        actions: [
          if (!_loading)
            _editing
                ? TextButton(
                    onPressed: _saving ? null : _saveProfile,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(color: _AppColors.brandRed),
                          ),
                  )
                : IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Colors.white70,
                    ),
                    onPressed: _startEditing,
                  ),
          if (_editing)
            TextButton(
              onPressed: _saving ? null : _cancelEditing,
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  SizedBox(
                    height: 320,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenWidth = MediaQuery.sizeOf(context).width;
                        return OverflowBox(
                          minWidth: screenWidth,
                          maxWidth: screenWidth,
                          minHeight: 320,
                          maxHeight: 320,
                          child: GestureDetector(
                            onTap: _editing && !_uploadingPhoto
                                ? _pickAndUploadPhoto
                                : null,
                            child: Stack(
                              children: [
                                HeroProfileImage(
                                  photoUrl: _photoUrl,
                                  height: 320,
                                ),
                                if (_uploadingPhoto)
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(28),
                                      ),
                                      child: Container(
                                        color: Colors.black45,
                                        alignment: Alignment.center,
                                        child:
                                            const CircularProgressIndicator(),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 20,
                                  bottom: 20,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _isOnline
                                              ? _AppColors.online
                                              : _AppColors.textMuted,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _AppColors.bg,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isOnline ? 'ONLINE' : 'OFFLINE',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_editing)
                                  Positioned(
                                    right: 20,
                                    bottom: 20,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: const BoxDecoration(
                                        color: _AppColors.brandRed,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _isOnline ? 'ONLINE NOW' : 'OFFLINE',
                      style: TextStyle(
                        color: _isOnline
                            ? _AppColors.online
                            : _AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _AppColors.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _AppColors.cardBorder),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _avgRating != null
                                    ? _avgRating!.toStringAsFixed(1)
                                    : '—',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'RATING',
                                style: TextStyle(
                                  color: _AppColors.textMuted,
                                  fontSize: 11,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _AppColors.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _AppColors.cardBorder),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.call,
                                color: _AppColors.brandRed,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$_totalCalls',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'TOTAL CALLS',
                                style: TextStyle(
                                  color: _AppColors.textMuted,
                                  fontSize: 11,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const _SectionLabel('AGE & OCCUPATION'),
                  _editing
                      ? Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                maxLength: 3,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: 'Age',
                                  hintStyle: const TextStyle(
                                    color: Colors.white38,
                                  ),
                                  filled: true,
                                  fillColor: _AppColors.cardBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _occupationController,
                                maxLength: 20,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: 'Occupation',
                                  hintStyle: const TextStyle(
                                    color: Colors.white38,
                                  ),
                                  filled: true,
                                  fillColor: _AppColors.cardBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _AppColors.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _AppColors.cardBorder),
                          ),
                          child: Text(
                            '${_age?.toString() ?? '...'} · ${_occupation.isEmpty ? '...' : _occupation}',
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ),

                  const _SectionLabel('ABOUT'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AppColors.cardBorder),
                    ),
                    child: _editing
                        ? TextField(
                            controller: _aboutController,
                            maxLines: 4,
                            maxLength: 100,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Tell users about yourself...',
                              hintStyle: TextStyle(color: Colors.white38),
                            ),
                          )
                        : Text(
                            _about.isEmpty ? 'No description yet.' : _about,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                  ),
                  const _SectionLabel('GOOD TO TALK ABOUT'),
                  if (_editing) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _editTags
                          .map(
                            (t) => _ProfileChip(
                              t,
                              onDeleted: () =>
                                  setState(() => _editTags.remove(t)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    _tagInputRow(
                      _tagController,
                      _editTags,
                      'Add a topic',
                      maxCount: 5,
                      maxChars: 10,
                    ),
                  ] else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags.isEmpty
                          ? [
                              const Text(
                                'Not set',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ]
                          : _tags.map((t) => _ProfileChip(t)).toList(),
                    ),
                  const _SectionLabel('LANGUAGES'),
                  if (_editing) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _editLanguages
                          .map(
                            (t) => _ProfileChip(
                              t,
                              onDeleted: () =>
                                  setState(() => _editLanguages.remove(t)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    _tagInputRow(
                      _languageController,
                      _editLanguages,
                      'Add a language',
                      maxCount: 10,
                      maxChars: 10,
                    ),
                  ] else
                    Text(
                      _languages.isEmpty ? 'Not set' : _languages.join(' • '),
                      style: TextStyle(
                        color: _languages.isEmpty
                            ? Colors.white38
                            : _AppColors.brandRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const _SectionLabel('YOUR PRIVACY'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _AppColors.brandRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _AppColors.brandRed.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: _AppColors.brandRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '100% anonymous. Users never see your real identity. Conversations stay between the two of you.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _memberSinceYear(_createdAt).isEmpty
                          ? ''
                          : 'Member since ${_memberSinceYear(_createdAt)}',
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }
}
