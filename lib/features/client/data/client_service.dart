import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/wallet_channel.dart';

class ClientService {
  ClientService._();

  static Future<Map<String, dynamic>> getUserPoints() async {
    final res = await ApiClient.instance.get('/user-points');
    return res.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getBusinessById(String id) async {
    final res = await ApiClient.instance.get('/business/$id');
    final data = res.data as Map<String, dynamic>;
    return {...data, 'name': data['username'] ?? data['name'] ?? 'Negocio'};
  }

  static Future<Map<String, dynamic>> getNearbyBusinesses(
    double lat,
    double lng, {
    double radius = 50,
  }) async {
    final res = await ApiClient.instance.get(
      '/business/nearby',
      queryParameters: {'latitude': lat, 'longitude': lng, 'maxDistanceKm': radius},
    );
    return res.data as Map<String, dynamic>;
  }

  static Future<List<dynamic>> getBusinessRewards(String businessId) async {
    final res = await ApiClient.instance
        .get('/rewards/business/$businessId', queryParameters: {'includeInactive': false});
    final data = res.data;
    if (data is List) return data;
    return (data as Map<String, dynamic>)['rewards'] as List? ?? [];
  }

  static Future<List<dynamic>> getUserTransactions({int limit = 50, int offset = 0}) async {
    final res = await ApiClient.instance
        .get('/transactions', queryParameters: {'limit': limit, 'offset': offset});
    final data = res.data;
    if (data is List) return data;
    return (data as Map<String, dynamic>)['transactions'] as List? ?? [];
  }

  static Future<List<dynamic>> getMyMemberships() async {
    final res = await ApiClient.instance.get('/memberships/my');
    final data = res.data;
    if (data is List) return data;
    return [];
  }

  static Future<Map<String, dynamic>> claimCode(String code) async {
    final res = await ApiClient.instance.post('/delivery/claim', data: {'code': code});
    return res.data as Map<String, dynamic>;
  }

  static Future<void> addToAppleWallet() async {
    final res = await ApiClient.instance.get(
      '/passes/apple',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data as List<int>;
    await WalletChannel.addPassToWallet(bytes);
  }

  static Future<void> openGoogleWallet() async {
    final res = await ApiClient.instance.get('/passes/google');
    final url = (res.data as Map<String, dynamic>)['url'] as String;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
