import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // آدرس هاب مرکزی — اولین جایی که اپ برای پیدا کردن هاست هر مرکز بهش وصل می‌شه.
  // اگه سیستم چندهاستی نمی‌خواید و فقط یه بک‌اند دارید، این رو خالی بذارید
  // و مستقیم مقدار baseUrl رو به آدرس همون بک‌اند ثابت کنید.
  static const String hubUrl = 'https://nexa-school.ir/m-f';

  static String? _resolvedBaseUrl;

  /// آدرس بک‌اندی که الان باهاش کار می‌کنیم. یا از حافظه (اگه قبلا resolve شده)
  /// یا آدرس ثابت پیش‌فرض (اگه از هاب مرکزی استفاده نمی‌کنید).
  static Future<String> get baseUrl async {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('host_url');
    if (saved != null) {
      _resolvedBaseUrl = saved;
      return saved;
    }
    // اگه هنوز resolve نشده و سیستم تک‌هاستی هست، همینجا آدرس ثابت‌تون رو بذارید:
    return hubUrl;
  }

  static Future<Map<String, dynamic>> postHub(String path, Map<String, dynamic> body, {bool auth = false}) async {
    try {
      final res = await http.post(Uri.parse('$hubUrl/$path'), headers: await _headers(auth: auth), body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': _friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> resolveClass(String classCode) async {
    try {
      final res = await http.get(Uri.parse('$hubUrl/classes/resolve?class_code=${Uri.encodeQueryComponent(classCode)}')).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final hostUrl = data['data']['host_url'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('host_url', hostUrl);
        await prefs.setString('class_code', classCode);
        if (data['data']['school_code'] != null) await prefs.setString('school_code', data['data']['school_code']);
        _resolvedBaseUrl = hostUrl;
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'اتصال به هاب مرکزی برقرار نشد'};
    }
  }

  /// از هاب مرکزی می‌پرسه «این کد مرکز مال کدوم هاسته» و نتیجه رو ذخیره می‌کنه.
  /// فقط لازمه یک‌بار (اولین ورود) صدا زده بشه؛ دفعات بعد از حافظه خونده می‌شه.
  static Future<Map<String, dynamic>> resolveSchool(String schoolCode) async {
    try {
      final res = await http.get(Uri.parse('$hubUrl/schools/resolve?school_code=$schoolCode')).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final hostUrl = data['data']['host_url'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('host_url', hostUrl);
        await prefs.setString('school_code', schoolCode);
        _resolvedBaseUrl = hostUrl;
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'اتصال به هاب مرکزی برقرار نشد'};
    }
  }

  /// کاربر می‌تونه از یه مرکز دیگه دوباره وارد بشه (کد مرکز ذخیره‌شده رو پاک می‌کنه)
  static Future<void> forgetSchool() async {
    _resolvedBaseUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('host_url');
    await prefs.remove('school_code');
  }

  static Future<String?> get savedSchoolCode async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('school_code');
  }

  /// اگه false باشه، یعنی فقط یه بک‌اند دارید (بدون هاب مرکزی) و مرحله‌ی
  /// «کد مرکز» کلا رد می‌شه؛ در اون صورت خط `return hubUrl;`
  /// بالا (تو getter باسه‌یو‌آرال) رو با آدرس بک‌اند واقعی‌تون عوض کنید.
  static const bool useHub = true;

  static Future<String?> get _token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// دسترسی عمومی به توکن خام برای سرویس‌های داخلی.
  static Future<String?> get rawToken => _token;

  static Future<void> saveRememberedLogin(String role, Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_$role', true);
    for (final entry in values.entries) {
      await prefs.setString('remember_${role}_${entry.key}', entry.value);
    }
  }

  static Future<Map<String, String>?> getRememberedLogin(String role) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('remember_$role') ?? false)) return null;
    final result = <String, String>{};
    for (final key in ['class_code', 'school_code', 'full_name', 'national_code', 'username']) {
      final value = prefs.getString('remember_${role}_$key');
      if (value != null) result[key] = value;
    }
    return result;
  }

  static Future<void> clearRememberedLogin(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remember_$role');
    for (final key in ['class_code', 'school_code', 'full_name', 'national_code', 'username']) {
      await prefs.remove('remember_${role}_$key');
    }
  }

  static Future<void> saveSession(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> get currentUser async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    return raw == null ? null : jsonDecode(raw);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    _resolvedBaseUrl = prefs.getString('host_url');
  }

  static Future<Map<String, String>> _headers({bool auth = true, bool json = true}) async {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (auth) {
      final t = await _token;
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }
    return headers;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    try {
      final base = await baseUrl;
      final res = await http
          .post(
            Uri.parse('$base/$path'),
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': _friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    try {
      final base = await baseUrl;
      final res = await http
          .get(Uri.parse('$base/$path'), headers: await _headers(auth: auth, json: false))
          .timeout(const Duration(seconds: 15));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': _friendlyError(e)};
    }
  }

  /// آپلود فرم چندبخشی (برای تکلیف، پیام عکس/ویس و ...)
  static Future<Map<String, dynamic>> uploadMultipartMany(
    String path,
    Map<String, String> fields, {
    List<String> filePaths = const [],
    String fileField = 'media_files',
  }) async {
    try {
      final base = await baseUrl;
      final uri = Uri.parse('$base/$path');
      final request = http.MultipartRequest('POST', uri);
      final t = await _token;
      if (t != null) request.headers['Authorization'] = 'Bearer $t';
      request.fields.addAll(fields);
      for (final filePath in filePaths) {
        request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': _friendlyError(e)};
    }
  }

  static Future<Map<String, dynamic>> uploadMultipart(
    String path,
    Map<String, String> fields, {
    String? filePath,
    String fileField = 'file',
  }) async {
    try {
      final base = await baseUrl;
      final uri = Uri.parse('$base/$path');
      final request = http.MultipartRequest('POST', uri);
      final t = await _token;
      if (t != null) request.headers['Authorization'] = 'Bearer $t';
      request.fields.addAll(fields);
      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': _friendlyError(e)};
    }
  }

  static Future<String> mediaUrl(String path) async {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = await baseUrl;
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  /// خطای فنی (قطعی شبکه، تایم‌اوت، آدرس غلط، JSON نامعتبر و ...) رو به یه
  /// پیام قابل‌فهم برای کاربر تبدیل می‌کنه، به‌جای اینکه کل درخواست فقط
  /// «بی‌صدا» شکست بخوره و هیچی نشون داده نشه.
  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException')) {
      return 'سرور به‌موقع جواب نداد. اتصال اینترنت یا آدرس سرور رو چک کنید';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('Connection refused')) {
      return 'اتصال به سرور برقرار نشد. اینترنت گوشی و آدرس بک‌اند (baseUrl) رو چک کنید';
    }
    if (s.contains('CleartextNotPermitted')) {
      return 'اتصال http (غیر امن) توسط اندروید مسدود شده. یا آدرس رو https کنید یا usesCleartextTraffic رو true کنید';
    }
    if (s.contains('FormatException')) {
      return 'پاسخ سرور نامعتبر بود (شاید آدرس اشتباهه یا سرور خطای PHP داده)';
    }
    return 'خطا در ارتباط با سرور: $s';
  }
}

/// تم اختصاصی هر مرکز که ادمین از پنل خودش تنظیم می‌کنه.
/// وقتی کاربر لاگین می‌کنه، از school/get-theme خونده و کل اپ با همین رنگ‌ها رنگ می‌شه.
class SchoolTheme {
  final Color primary;
  final Color secondary;
  final String? logoUrl;
  final String? iconUrl;
  final String? appName;

  SchoolTheme({required this.primary, required this.secondary, this.logoUrl, this.iconUrl, this.appName});

  static SchoolTheme get defaultTheme =>
      SchoolTheme(primary: const Color(0xFF0A5B4D), secondary: const Color(0xFFD8A12A), appName: 'مرکز قرآن و حدیث');

  static Future<SchoolTheme> fetch() async {
    try {
      final res = await ApiService.get('school/get-theme');
      if (res['success'] == true) {
        final data = res['data'];
        final base = await ApiService.baseUrl;
        return SchoolTheme(
          primary: _hexToColor(data['theme_primary_color']) ?? defaultTheme.primary,
          secondary: _hexToColor(data['theme_secondary_color']) ?? defaultTheme.secondary,
          logoUrl: data['logo_path'] != null ? '$base/${data['logo_path']}' : '$base/uploads/default_branding/fatemi_school.png',
          iconUrl: data['app_icon_path'] != null ? '$base/${data['app_icon_path']}' : '$base/uploads/default_branding/fatemi_school.png',
          appName: data['app_name']?.toString().trim().isNotEmpty == true ? data['app_name'].toString() : 'مرکز قرآن و حدیث',
        );
      }
    } catch (_) {}
    return defaultTheme;
  }

  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}
