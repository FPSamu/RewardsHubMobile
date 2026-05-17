import 'package:flutter/services.dart';

class WalletChannel {
  static const _channel = MethodChannel('rewardshub/wallet');

  static Future<void> addPassToWallet(List<int> passData) async {
    await _channel.invokeMethod(
      'addPassToWallet',
      Uint8List.fromList(passData),
    );
  }
}
