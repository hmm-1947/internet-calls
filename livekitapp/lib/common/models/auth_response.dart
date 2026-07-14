class AuthResponse {
  final String token;
  final int id;
  final String name;

  AuthResponse({required this.token, required this.id, required this.name});

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'],
      id: json['id'],
      name: json['name'],
    );
  }
}
