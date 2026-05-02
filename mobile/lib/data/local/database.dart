import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// ─────────────────────────────────────────────────────────────
// TABLE DEFINITIONS
// ─────────────────────────────────────────────────────────────

class UsersTable extends Table {
  @override
  String get tableName => 'users';

  TextColumn get id          => text()();
  TextColumn get garageId    => text()();
  TextColumn get email       => text()();
  TextColumn get fullName    => text()();
  TextColumn get role        => text()();
  TextColumn get phone       => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class CustomersTable extends Table {
  @override
  String get tableName => 'customers';

  TextColumn get id        => text()();
  TextColumn get garageId  => text()();
  TextColumn get fullName  => text()();
  TextColumn get phone     => text()();
  TextColumn get email     => text().nullable()();
  TextColumn get address   => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class VehiclesTable extends Table {
  @override
  String get tableName => 'vehicles';

  TextColumn get id           => text()();
  TextColumn get garageId     => text()();
  TextColumn get customerId   => text()();
  TextColumn get make         => text()();
  TextColumn get model        => text()();
  IntColumn  get year         => integer()();
  TextColumn get licensePlate => text()();
  TextColumn get color        => text().nullable()();
  IntColumn  get mileage      => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class JobCardsTable extends Table {
  @override
  String get tableName => 'job_cards';

  TextColumn  get id             => text()();
  TextColumn  get garageId       => text()();
  TextColumn  get jobNumber      => text()();
  TextColumn  get vehicleId      => text()();
  TextColumn  get customerId     => text()();
  TextColumn  get assignedToId   => text().nullable()();
  TextColumn  get status         => text()();
  TextColumn  get description    => text()();
  RealColumn  get estimatedHours => real().nullable()();
  RealColumn  get actualHours    => real().nullable()();
  IntColumn   get mileageIn      => integer().nullable()();
  TextColumn  get notes          => text().nullable()();
  DateTimeColumn get promisedAt  => dateTime().nullable()();
  DateTimeColumn get startedAt   => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn   get version        => integer().withDefault(const Constant(1))();
  TextColumn  get clientId       => text().nullable()();
  DateTimeColumn get createdAt   => dateTime()();
  DateTimeColumn get updatedAt   => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class TasksTable extends Table {
  @override
  String get tableName => 'tasks';

  TextColumn  get id             => text()();
  TextColumn  get garageId       => text()();
  TextColumn  get jobCardId      => text().references(JobCardsTable, #id)();
  TextColumn  get assignedToId   => text().nullable()();
  TextColumn  get title          => text()();
  TextColumn  get description    => text().nullable()();
  TextColumn  get status         => text()();
  RealColumn  get estimatedHours => real().nullable()();
  RealColumn  get actualHours    => real().nullable()();
  RealColumn  get laborRate      => real().nullable()();
  IntColumn   get sortOrder      => integer().withDefault(const Constant(0))();
  DateTimeColumn get startedAt   => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn   get version        => integer().withDefault(const Constant(1))();
  TextColumn  get clientId       => text().nullable()();
  DateTimeColumn get createdAt   => dateTime()();
  DateTimeColumn get updatedAt   => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class InvoicesTable extends Table {
  @override
  String get tableName => 'invoices';

  TextColumn  get id             => text()();
  TextColumn  get garageId       => text()();
  TextColumn  get invoiceNumber  => text()();
  TextColumn  get jobCardId      => text()();
  TextColumn  get customerId     => text()();
  TextColumn  get status         => text()();
  RealColumn  get subtotal       => real().withDefault(const Constant(0.0))();
  RealColumn  get discountPct    => real().withDefault(const Constant(0.0))();
  RealColumn  get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn  get taxPct         => real().withDefault(const Constant(0.0))();
  RealColumn  get taxAmount      => real().withDefault(const Constant(0.0))();
  RealColumn  get total          => real().withDefault(const Constant(0.0))();
  TextColumn  get notes          => text().nullable()();
  DateTimeColumn get issuedAt    => dateTime().nullable()();
  DateTimeColumn get dueAt       => dateTime().nullable()();
  DateTimeColumn get paidAt      => dateTime().nullable()();
  IntColumn   get version        => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt   => dateTime()();
  DateTimeColumn get updatedAt   => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class InvoiceLineItemsTable extends Table {
  @override
  String get tableName => 'invoice_line_items';

  TextColumn get id          => text()();
  TextColumn get invoiceId   => text().references(InvoicesTable, #id)();
  TextColumn get garageId    => text()();
  TextColumn get taskId      => text().nullable()();
  TextColumn get sparePartId => text().nullable()();
  TextColumn get itemType    => text()();
  TextColumn get description => text()();
  RealColumn get quantity    => real()();
  RealColumn get unitPrice   => real()();
  IntColumn  get sortOrder   => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending offline changes waiting to be pushed to server
class SyncQueueTable extends Table {
  @override
  String get tableName => 'sync_queue';

  TextColumn  get changeId      => text()();                  // client UUID, idempotency key
  TextColumn  get entityType    => text()();                  // 'job_cards' | 'tasks'
  TextColumn  get entityId      => text()();
  TextColumn  get operation     => text()();                  // 'create' | 'update' | 'delete'
  TextColumn  get payload       => text()();                  // JSON string
  IntColumn   get baseVersion   => integer()();
  TextColumn  get localTimestamp => text()();                 // ISO-8601
  TextColumn  get syncStatus    => text().withDefault(const Constant('pending'))();
  IntColumn   get retryCount    => integer().withDefault(const Constant(0))();
  TextColumn  get errorMessage  => text().nullable()();
  DateTimeColumn get createdAt  => dateTime()();
  DateTimeColumn get updatedAt  => dateTime()();

  @override
  Set<Column> get primaryKey => {changeId};
}

// ─────────────────────────────────────────────────────────────
// DATABASE
// ─────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  UsersTable,
  CustomersTable,
  VehiclesTable,
  JobCardsTable,
  TasksTable,
  InvoicesTable,
  InvoiceLineItemsTable,
  SyncQueueTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Future migrations go here
    },
  );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'car_workshop');
}
