// Client-side copies of the sign-up rules the backend enforces.
//
// These exist so the user gets instant feedback while typing instead of a
// round trip and a snackbar. The backend still validates everything; if the
// two ever disagree, the backend wins.

/// True when the text looks like an attempt at an email rather than a phone
/// number. Mirrors the backend, which treats anything containing "@" as an
/// email so a typo reports an email error, not a phone-number one.
bool looksLikeEmail(String value) => value.contains('@');

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$');

/// Returns null when [value] is a usable email address, otherwise the message
/// to show under the field.
String? emailFormatError(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'Enter your email address';
  if (email.length > 254 || !_emailPattern.hasMatch(email)) {
    return 'Enter a valid email address';
  }
  return null;
}

/// Validates the combined email-or-phone field used on the sign-up and login
/// screens. [normalizedPhone] is the digits-only phone number produced by
/// `PhoneAuthService.normalize`, passed in so this file stays free of Firebase
/// imports.
String? identifierError(String value, {required String normalizedPhone}) {
  final input = value.trim();
  if (input.isEmpty) return 'Enter your email or phone number';
  if (looksLikeEmail(input)) return emailFormatError(input);
  if (normalizedPhone.length != 10 ||
      !RegExp(r'^[6-9]').hasMatch(normalizedPhone)) {
    return 'Enter a valid email or 10-digit phone number';
  }
  return null;
}

const int usernameMinLength = 3;
const int usernameMaxLength = 20;

/// Returns null when the handle is well formed, otherwise the message to show.
/// Uniqueness is a separate, server-side check.
String? usernameFormatError(String username) {
  final value = username.trim();
  if (value.isEmpty) return 'Choose a username';
  if (value.length < usernameMinLength) {
    return 'Username must be at least $usernameMinLength characters long';
  }
  if (value.length > usernameMaxLength) {
    return 'Username must be at most $usernameMaxLength characters long';
  }
  if (!RegExp(r'^[A-Za-z0-9._]+$').hasMatch(value)) {
    return 'Only letters, numbers, dots and underscores are allowed';
  }
  if (!RegExp(r'[A-Za-z]').hasMatch(value)) {
    return 'Username must contain at least one letter';
  }
  if (value.startsWith('.') || value.endsWith('.')) {
    return 'Username cannot start or end with a dot';
  }
  return null;
}

const int displayNameMaxLength = 30;

/// The name other people see. Unlike the username it does not have to be
/// unique, but it cannot be blank.
String? displayNameError(String name) {
  final value = name.trim();
  if (value.length < 2) return 'Display name must be at least 2 characters long';
  if (value.length > displayNameMaxLength) {
    return 'Display name must be at most $displayNameMaxLength characters long';
  }
  return null;
}
