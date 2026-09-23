import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:livekitapp/core/network/api_client.dart';

const String kNoInternetMessage =
    'No internet connection. Please check your network and try again.';
const String kGenericErrorMessage =
    'Something went wrong. Please try again.';

/// Turns any thrown object into a short message that is safe to show a user.
///
/// Raw exception text (Firebase codes, stack-ish strings, platform details)
/// must never reach the UI. Anything this does not recognise falls back to a
/// generic message instead of leaking `e.toString()`.
///
/// Errors the app throws on purpose (`Exception('...')` from repositories and
/// [ServerUnreachableException]) already carry a user-facing message, so those
/// pass through unchanged.
String friendlyError(Object? error, {String? fallback}) {
  final generic = fallback ?? kGenericErrorMessage;

  if (error is ServerUnreachableException) return error.message;

  if (error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return kNoInternetMessage;
  }

  if (error is FirebaseAuthException) return _firebaseAuthMessage(error, generic);

  if (error is FirebaseException) {
    return _isNetworkText(error.code) || _isNetworkText(error.message)
        ? kNoInternetMessage
        : generic;
  }

  if (error is GoogleSignInException) return _googleMessage(error, generic);

  if (error is PlatformException) {
    return _isNetworkText(error.code) || _isNetworkText(error.message)
        ? kNoInternetMessage
        : generic;
  }

  // App-thrown `Exception('message')`: toString() is "Exception: message".
  // Only trust it when it is a plain Exception (not a library error type),
  // and when the text does not look like a technical dump.
  if (error is Exception) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty || _looksTechnical(text)) {
      return _isNetworkText(text) ? kNoInternetMessage : generic;
    }
    return text;
  }

  return generic;
}

String _firebaseAuthMessage(FirebaseAuthException e, String generic) {
  switch (e.code) {
    case 'network-request-failed':
      return kNoInternetMessage;
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'account-exists-with-different-credential':
      return 'An account already exists with a different sign-in method.';
    case 'invalid-credential':
    case 'invalid-verification-code':
    case 'expired-action-code':
      return 'Sign-in failed. Please try again.';
    case 'operation-not-allowed':
    case 'internal-error':
    default:
      return _isNetworkText(e.message) ? kNoInternetMessage : generic;
  }
}

String _googleMessage(GoogleSignInException e, String generic) {
  // Google Sign-In does not raise a dedicated "offline" code; with no
  // connection it usually surfaces as a generic/unknown failure whose
  // description mentions the network, so check the text as well.
  if (_isNetworkText(e.description)) return kNoInternetMessage;
  switch (e.code) {
    case GoogleSignInExceptionCode.interrupted:
      return 'Sign-in was interrupted. Please try again.';
    default:
      return 'Google sign-in failed. Please try again.';
  }
}

bool _isNetworkText(String? text) {
  if (text == null) return false;
  final t = text.toLowerCase();
  return t.contains('network') ||
      t.contains('socket') ||
      t.contains('unreachable') ||
      t.contains('timed out') ||
      t.contains('timeout') ||
      t.contains('connection') && (t.contains('fail') || t.contains('refused') || t.contains('reset') || t.contains('closed')) ||
      t.contains('unable to resolve host') ||
      t.contains('no address associated') ||
      t.contains('failed host lookup') ||
      t.contains('offline') ||
      t.contains('no internet');
}

/// Detects strings that are clearly developer output rather than a message
/// meant for a person: class names, stack traces, error codes, file paths.
bool _looksTechnical(String text) {
  // A server validation error (FastAPI returns `detail` as a list of objects)
  // that was stringified straight into an Exception, e.g.
  // "[{type: missing, loc: [body, phone], msg: Field required}]".
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) return true;

  return RegExp(
    r'(Exception|Error|firebase|\[[a-z_\-]+/[a-z_\-]+\]|package:|dart:|'
    r'^\s*at\s|StackTrace|null check|type .* is not a subtype|'
    r'RangeError|FormatException|PlatformException|SocketException|'
    r'com\.google|java\.|kotlin\.)',
    caseSensitive: false,
  ).hasMatch(text);
}
