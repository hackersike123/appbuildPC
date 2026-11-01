part of '../api_client.dart';

extension ApiClientAuthEndpoints on ApiClient {
  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/login',
        body: {'email': email, 'password': password},
      ),
    );
    token = data['accessToken'] as String?;
    currentUser = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : null;
    return data;
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String areaId = 'hcm',
  }) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/register',
        body: {
          'name': name,
          'email': email,
          'password': password,
          'areaId': areaId,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/forgot-password',
        body: {'email': email},
      ),
    );
  }

  Future<Map<String, dynamic>> resetPassword(
    String token,
    String password,
  ) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/reset-password',
        body: {'token': token, 'password': password},
      ),
    );
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _request(
      'POST',
      '/api/v1/auth/change-password',
      auth: true,
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<Map<String, dynamic>> me() async {
    final data = await _request('GET', '/api/v1/auth/me', auth: true);
    currentUser = Map<String, dynamic>.from(data as Map);
    return currentUser!;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? areaId,
    String? avatarUrl,
    bool? pricePreference,
    bool? priceNotifications,
  }) async {
    final data = Map<String, dynamic>.from(
      await _request(
        'PUT',
        '/api/v1/auth/me',
        auth: true,
        body: {
          ...?name == null ? null : {'name': name},
          ...?areaId == null ? null : {'areaId': areaId},
          ...?avatarUrl == null ? null : {'avatarUrl': avatarUrl},
          ...?(pricePreference == null && priceNotifications == null)
              ? null
              : {
                  'preferences': {
                    ...?pricePreference == null
                        ? null
                        : {'pricePreference': pricePreference},
                    ...?priceNotifications == null
                        ? null
                        : {'priceNotifications': priceNotifications},
                  },
                },
        },
      ),
    );
    currentUser = data;
    return data;
  }

  void logout() {
    token = null;
    currentUser = null;
    buildId = null;
  }
}
