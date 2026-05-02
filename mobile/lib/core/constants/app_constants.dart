abstract class AppConstants {
  // Set via --dart-define=API_BASE_URL=https://your-server.com/api/v1 at build time.
  // Falls back to the Android emulator address for local debug builds.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
  static const String tokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String garageIdKey = 'garage_id';
  static const String userKey = 'current_user';

  static const Duration syncInterval = Duration(seconds: 30);
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  static const int syncBatchSize = 50;
  static const int maxRetryAttempts = 3;
}

enum JobCardStatus { pending, inProgress, onHold, completed, cancelled }
enum TaskStatus { pending, inProgress, completed, cancelled }
enum InvoiceStatus { draft, issued, paid, overdue, void_ }
enum UserRole { admin, technician, receptionist }
enum SyncOperation { create, update, delete }
enum SyncStatus { pending, syncing, synced, failed }

extension JobCardStatusX on JobCardStatus {
  String get apiValue => switch (this) {
    JobCardStatus.pending    => 'pending',
    JobCardStatus.inProgress => 'in_progress',
    JobCardStatus.onHold     => 'on_hold',
    JobCardStatus.completed  => 'completed',
    JobCardStatus.cancelled  => 'cancelled',
  };

  static JobCardStatus fromApi(String v) => switch (v) {
    'pending'     => JobCardStatus.pending,
    'in_progress' => JobCardStatus.inProgress,
    'on_hold'     => JobCardStatus.onHold,
    'completed'   => JobCardStatus.completed,
    _             => JobCardStatus.cancelled,
  };
}

extension TaskStatusX on TaskStatus {
  String get apiValue => switch (this) {
    TaskStatus.pending    => 'pending',
    TaskStatus.inProgress => 'in_progress',
    TaskStatus.completed  => 'completed',
    TaskStatus.cancelled  => 'cancelled',
  };

  static TaskStatus fromApi(String v) => switch (v) {
    'in_progress' => TaskStatus.inProgress,
    'completed'   => TaskStatus.completed,
    'cancelled'   => TaskStatus.cancelled,
    _             => TaskStatus.pending,
  };
}
