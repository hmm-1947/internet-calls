import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:livekitapp/common/utils/friendly_error.dart';
import 'package:livekitapp/core/network/api_client.dart';

void main() {
  test('offline / network cases -> no internet message', () {
    expect(friendlyError(FirebaseAuthException(code: 'network-request-failed', message: 'A network error (such as timeout, interrupted connection or unreachable host) has occurred.')), kNoInternetMessage);
    expect(friendlyError(const SocketException('Failed host lookup: x')), kNoInternetMessage);
    expect(friendlyError(http.ClientException('Connection closed')), kNoInternetMessage);
    expect(friendlyError(TimeoutException('x')), kNoInternetMessage);
    expect(friendlyError(GoogleSignInException(code: GoogleSignInExceptionCode.unknownError, description: 'com.google.android.gms.common.api.ApiException: 7: NETWORK_ERROR')), kNoInternetMessage);
    expect(friendlyError(GoogleSignInException(code: GoogleSignInExceptionCode.unknownError, description: 'Unable to resolve host "www.googleapis.com"')), kNoInternetMessage);
    expect(friendlyError(PlatformException(code: 'network_error', message: 'Network is unreachable')), kNoInternetMessage);
  });

  test('server-unreachable message passes through', () {
    expect(friendlyError(const ServerUnreachableException()), contains('internet connection'));
  });

  test('plain app messages pass through untouched', () {
    expect(friendlyError(Exception('Incorrect password')), 'Incorrect password');
    expect(friendlyError(Exception('Phone number already registered')), 'Phone number already registered');
  });

  test('raw / technical text is never shown', () {
    expect(friendlyError(Exception('[{type: missing, loc: [body, phone], msg: Field required}]')), kGenericErrorMessage);
    expect(friendlyError(Exception('{code: x, msg: bad}')), kGenericErrorMessage);
    expect(friendlyError(FirebaseAuthException(code: 'internal-error', message: '[firebase_auth/internal-error] boom')), kGenericErrorMessage);
    expect(friendlyError(GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError, description: 'bad SHA-1')), 'Google sign-in failed. Please try again.');
    expect(friendlyError(StateError('Bad state: x')), kGenericErrorMessage);
    expect(friendlyError(null), kGenericErrorMessage);
  });

  test('fallback is honoured', () {
    expect(friendlyError(StateError('x'), fallback: 'Could not save the note. Please try again.'), 'Could not save the note. Please try again.');
  });
}
