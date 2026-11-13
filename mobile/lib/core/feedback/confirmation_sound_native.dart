import 'package:flutter/services.dart';

const _channel = MethodChannel('erp/confirmation');
void prepare() {}
Future<void> play() async {
  try {
    if (await _channel.invokeMethod<bool>('success') == true) return;
  } on MissingPluginException {
    // Other native hosts retain the platform's supported feedback.
  } on PlatformException {
    // An unavailable audio device must not hide a successful sale.
  }
  await SystemSound.play(SystemSoundType.click);
}
