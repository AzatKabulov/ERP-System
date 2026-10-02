import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo/demo_store.dart';
import 'l10n/app_localizations.dart';
import 'l10n/turkmen_localizations.dart';
import 'screens/workspace.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Inter', 'NotoSerif']) {
      final text = await rootBundle.loadString(
        'assets/fonts/$font-LICENSE.txt',
      );
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });
  final preferences = await SharedPreferences.getInstance();
  runApp(ErpApp(preferences: preferences));
}

class ErpApp extends StatefulWidget {
  const ErpApp({super.key, required this.preferences, this.store});

  final SharedPreferences preferences;
  final DemoStore? store;

  @override
  State<ErpApp> createState() => _ErpAppState();
}

class _ErpAppState extends State<ErpApp> {
  late final DemoStore _store = widget.store ?? DemoStore();
  late Locale _locale = Locale(
    widget.preferences.getString('language') == 'tk' ? 'tk' : 'ru',
  );

  void _changeLanguage(String code) {
    setState(() => _locale = Locale(code));
    widget.preferences.setString('language', code);
  }

  @override
  void dispose() {
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERP System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        TurkmenMaterialDelegate(),
        TurkmenCupertinoDelegate(),
        TurkmenWidgetsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Workspace(
        store: _store,
        languageCode: _locale.languageCode,
        onLanguageChanged: _changeLanguage,
      ),
    );
  }
}
