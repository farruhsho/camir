import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/theme_controller.dart';
import 'router.dart';
import 'theme.dart';

class CadmirApp extends ConsumerWidget {
  const CadmirApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Цадмир',
      debugShowCheckedModeBanner: false,
      theme: KozTheme.light(),
      darkTheme: KozTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
