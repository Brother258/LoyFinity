import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

class AppState extends ChangeNotifier {
  AppState(this.api) {
    api.setRefreshHandler(_refreshAccessToken);
  }

  final ApiClient api;
  static const _storage = FlutterSecureStorage();
  Map<String, dynamic>? user;
  bool initialized = false;
  bool busy = false;
  String? lastMessage;
  String? debugVerificationToken;
  Future<String?>? _refreshing;

  bool get signedIn => user != null && api.accessToken != null;
  String get role => (user?['role'] ?? '').toString();
  String get displayName => (user?['fullName'] ?? 'there').toString();

  Future<void> restore() async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh != null && refresh.isNotEmpty) {
        final result = await api.post('/auth/refresh', data: {'refreshToken': refresh});
        await _saveSession(result);
      }
    } catch (_) {
      await _clearSession();
    } finally {
      initialized = true;
      notifyListeners();
    }
  }


  Future<String?> _refreshAccessToken() {
    final existing = _refreshing;
    if (existing != null) return existing;
    final pending = _performRefresh();
    _refreshing = pending;
    return pending.whenComplete(() => _refreshing = null);
  }

  Future<String?> _performRefresh() async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh == null || refresh.isEmpty) return null;
      final result = await api.post('/auth/refresh', data: {'refreshToken': refresh});
      await _saveSession(result);
      return api.accessToken;
    } catch (_) {
      await _clearSession();
      notifyListeners();
      return null;
    }
  }

  Future<bool> login(String email, String password) async {
    busy = true;
    lastMessage = null;
    notifyListeners();
    try {
      final result = await api.post('/auth/login', data: {'email': email.trim(), 'password': password});
      await _saveSession(result);
      return true;
    } catch (error) {
      lastMessage = api.messageFrom(error);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> register({required String fullName, required String email, required String password, required String role, String? businessName, String? businessCategory}) async {
    busy = true;
    lastMessage = null;
    debugVerificationToken = null;
    notifyListeners();
    try {
      final body = <String, dynamic>{
        'fullName': fullName.trim(), 'email': email.trim(), 'password': password, 'role': role,
      };
      if (role == 'business_owner') {
        body['businessName'] = businessName?.trim();
        body['businessCategory'] = businessCategory?.trim();
      }
      final result = await api.post('/auth/register', data: body);
      final token = result['developmentVerificationToken']?.toString();
      if (token != null && token.isNotEmpty) {
        debugVerificationToken = token;
        await api.post('/auth/verify-email', data: {'token': token});
        lastMessage = 'Email verified in local development. Sign in to continue.';
      } else {
        lastMessage = 'Account created. Check your email for the verification link before signing in.';
      }
      return true;
    } catch (error) {
      lastMessage = api.messageFrom(error);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _saveSession(Map<String, dynamic> result) async {
    final access = result['accessToken']?.toString();
    final refresh = result['refreshToken']?.toString();
    final profile = result['user'];
    if (access == null || refresh == null || profile is! Map) throw Exception('Invalid session response');
    api.accessToken = access;
    await _storage.write(key: 'refresh_token', value: refresh);
    user = profile.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> logout() async {
    final refresh = await _storage.read(key: 'refresh_token');
    try {
      if (refresh != null && refresh.isNotEmpty) await api.post('/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {
      // Local credentials are still cleared if the device is offline.
    }
    await _clearSession();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await api.delete('/auth/me');
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    api.accessToken = null;
    user = null;
    await _storage.delete(key: 'refresh_token');
  }
}
