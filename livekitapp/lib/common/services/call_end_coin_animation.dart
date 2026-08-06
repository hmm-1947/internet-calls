import 'package:flutter/foundation.dart';

class CallEndCoinAnimationRequest {
  final int coins;
  final int nonce;

  CallEndCoinAnimationRequest(this.coins)
      : nonce = DateTime.now().microsecondsSinceEpoch;
}

final ValueNotifier<CallEndCoinAnimationRequest?> callEndCoinAnimationNotifier =
    ValueNotifier<CallEndCoinAnimationRequest?>(null);

void triggerCallEndCoinAnimation(int coinsDeducted) {
  if (coinsDeducted <= 0) return;
  callEndCoinAnimationNotifier.value = CallEndCoinAnimationRequest(coinsDeducted);
}
