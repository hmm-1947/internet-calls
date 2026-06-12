class AppConfig {
  // Server IP — change this one value to update everywhere
  static const String _host = '192.168.42.83';

  static const String baseUrl = 'http://$_host:8000';

  static const String livekitUrl = 'ws://$_host:7880';
  static const String wsBaseUrl = 'ws://$_host:8000';
}
