onPressed: () async {
  try {
    final auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    final adminEmail = currentUser?.email;

    // ⚠️ Aquí debes tener la contraseña del admin
    final adminPassword = "TU_PASSWORD_ADMIN"; // ⚠️ mejor pedirla en UI

    // Crear nuevo usuario
    final credencial = await auth.createUserWithEmailAndPassword(
      email: _correoController.text.trim(),
      password: _passwordController.text.trim(),
    );

    // Guardar en Firestore
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(credencial.user!.uid)
        .set({
      'nombre': _nombreController.text.trim(),
      'cedula': _cedulaController.text.trim(),
      'correo': _correoController.text.trim(),
      'rol': _rolSeleccionado,
      'fecha_registro': DateTime.now(),
    });

    // 🔁 Volver a loguear al admin
    await auth.signOut();

    await auth.signInWithEmailAndPassword(
      email: adminEmail!,
      password: adminPassword,
    );

    _limpiarFormulario();
    if (context.mounted) Navigator.pop(context);

  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}