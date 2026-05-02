import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';
import 'package:car_workshop/routing/app_router.dart';

class CarWorkshopApp extends ConsumerStatefulWidget {
  const CarWorkshopApp({super.key});

  @override
  ConsumerState<CarWorkshopApp> createState() => _CarWorkshopAppState();
}

class _CarWorkshopAppState extends ConsumerState<CarWorkshopApp> {
  @override
  void initState() {
    super.initState();
    // Attempt to restore previous session on cold start
    Future.microtask(
      () => ref.read(authProvider.notifier).tryRestoreSession(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Car Workshop',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
