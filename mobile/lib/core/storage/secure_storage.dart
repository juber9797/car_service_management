import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/domain/models/models.dart';

class SecureStorageService {
  const SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  static const _opts = AndroidOptions(encryptedSharedPreferences: true);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.tokenKey,        value: accessToken,   aOptions: _opts),
      _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken,  aOptions: _opts),
    ]);
  }

  Future<String?> getAccessToken() =>
      _storage.read(key: AppConstants.tokenKey, aOptions: _opts);

  Future<String?> getRefreshToken() =>
      _storage.read(key: AppConstants.refreshTokenKey, aOptions: _opts);

  Future<void> saveGarageId(String id) =>
      _storage.write(key: AppConstants.garageIdKey, value: id, aOptions: _opts);

  Future<String?> getGarageId() =>
      _storage.read(key: AppConstants.garageIdKey, aOptions: _opts);

  Future<void> saveUser(AppUser user) =>
      _storage.write(key: AppConstants.userKey, value: jsonEncode(user.toJson()), aOptions: _opts);

  Future<AppUser?> getUser() async {
    final raw = await _storage.read(key: AppConstants.userKey, aOptions: _opts);
    if (raw == null) return null;
    return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clearAll() => _storage.deleteAll(aOptions: _opts);

  Future<bool> get isLoggedIn async => (await getAccessToken()) != null;
}
