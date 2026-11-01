part of '../main.dart';

class PcBuildApp extends StatelessWidget {
  const PcBuildApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PCBUILD LOCAL',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: mint, surface: bg),
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff0c121a),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: mint),
        ),
      ),
    ),
    home: Uri.base.queryParameters['token']?.isNotEmpty == true
        ? ResetPasswordScreen(token: Uri.base.queryParameters['token']!)
        : const WelcomeScreen(),
  );
}
