import 'package:flutter/material.dart';

class UserProvider with ChangeNotifier {
  String _email = '';
  bool _isAdmin = false;

  // Getters (para leer)
  String get email => _email;
  bool get isAdmin => _isAdmin;

  // Setters (para actualizar)
  void setUser(String email, bool isAdmin) {
    _email = email;
    _isAdmin = isAdmin;

    notifyListeners();
  }

  void clear() {
    _email = '';
    _isAdmin = false;
    notifyListeners();
  }
}
