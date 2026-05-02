import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/screens/auth/login_screen.dart';
import 'package:car_workshop/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:car_workshop/presentation/screens/job_cards/job_card_screen.dart';
import 'package:car_workshop/presentation/screens/tasks/task_detail_screen.dart';
import 'package:car_workshop/presentation/screens/tasks/add_task_screen.dart';
import 'package:car_workshop/presentation/screens/billing/billing_screen.dart';
import 'package:car_workshop/presentation/screens/technician/technician_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final user = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (ctx, state) {
      final isLoggedIn  = user != null;
      final isLoginPage = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginPage) return '/login';
      if (isLoggedIn  && isLoginPage)  return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/technician',
        builder: (_, __) => const TechnicianScreen(),
      ),
      GoRoute(
        path: '/job-cards/:id',
        builder: (_, state) => JobCardScreen(id: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'add-task',
            builder: (_, state) =>
                AddTaskScreen(jobCardId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'billing',
            builder: (_, state) =>
                BillingScreen(jobCardId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/tasks/:id',
        builder: (_, state) => TaskDetailScreen(taskId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.error}')),
    ),
  );
});
