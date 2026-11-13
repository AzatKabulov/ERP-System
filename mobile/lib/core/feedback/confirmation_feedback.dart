import 'package:flutter/services.dart';
import 'confirmation_sound_native.dart'
    if (dart.library.js_interop) 'confirmation_sound_web.dart'
    as sound;

/// Called directly from the confirmation tap, before awaiting the network.
void prepareSaleConfirmation() => sound.prepare();

/// Feedback failures must never change or obscure a committed sale.
Future<void> playSaleConfirmation() async {
  await Future.wait([
    HapticFeedback.mediumImpact().catchError((Object _) {}),
    sound.play().catchError((Object _) {}),
  ]);
}
