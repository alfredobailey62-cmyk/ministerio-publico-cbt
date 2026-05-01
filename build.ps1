cd C:\Users\aeman\Documents\FlutterProjects\ministerio_publico_cbt
flutter clean
flutter pub get
flutter build apk --release


firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk `
--app 1:166195661856:android:5e22920ffaf36f32730045 `
--project ministerio-publico-cbt `
--testers alfredobailey62@gmail.com,guillermo246jm@gmail.com `
--release-notes "Nueva versión con cambios en login, usuarios y recorridos"
