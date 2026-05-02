import 'package:car_workshop/core/constants/app_constants.dart';

// ─────────────────────────────────────────────
// Immutable domain models (plain Dart classes)
// These are decoupled from DB rows and API JSON.
// ─────────────────────────────────────────────

class AppUser {
  const AppUser({
    required this.id,
    required this.garageId,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
  });

  final String id;
  final String garageId;
  final String email;
  final String fullName;
  final UserRole role;
  final String? phone;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id:        j['id'] as String,
    garageId:  j['garageId'] as String,
    email:     j['email'] as String,
    fullName:  j['fullName'] as String,
    role:      UserRole.values.firstWhere(
                 (r) => r.name == (j['role'] as String),
                 orElse: () => UserRole.technician),
    phone:     j['phone'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'garageId': garageId, 'email': email,
    'fullName': fullName, 'role': role.name, 'phone': phone,
  };
}

class Customer {
  const Customer({
    required this.id, required this.garageId,
    required this.fullName, required this.phone,
    this.email, this.address,
  });
  final String id, garageId, fullName, phone;
  final String? email, address;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] as String, garageId: j['garageId'] as String,
    fullName: j['fullName'] as String, phone: j['phone'] as String,
    email: j['email'] as String?, address: j['address'] as String?,
  );
}

class Vehicle {
  const Vehicle({
    required this.id, required this.garageId, required this.customerId,
    required this.make, required this.model, required this.year,
    required this.licensePlate, this.color, this.mileage,
  });
  final String id, garageId, customerId, make, model, licensePlate;
  final int year;
  final String? color;
  final int? mileage;

  String get displayName => '$make $model ($licensePlate)';

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
    id: j['id'] as String, garageId: j['garageId'] as String,
    customerId: j['customerId'] as String,
    make: j['make'] as String, model: j['model'] as String,
    year: j['year'] as int, licensePlate: j['licensePlate'] as String,
    color: j['color'] as String?,
    mileage: j['mileage'] as int?,
  );
}

class JobCard {
  const JobCard({
    required this.id, required this.garageId, required this.jobNumber,
    required this.vehicleId, required this.customerId,
    required this.status, required this.description,
    required this.version, required this.createdAt,
    this.assignedToId, this.estimatedHours, this.mileageIn,
    this.promisedAt, this.startedAt, this.completedAt, this.notes,
    // Joined fields (populated from local DB joins)
    this.vehicle, this.customer, this.tasks,
  });

  final String id, garageId, jobNumber, vehicleId, customerId, description;
  final String? assignedToId, notes;
  final JobCardStatus status;
  final double? estimatedHours;
  final int? mileageIn;
  final DateTime? promisedAt, startedAt, completedAt;
  final DateTime createdAt;
  final int version;

  final Vehicle? vehicle;
  final Customer? customer;
  final List<Task>? tasks;

  int get totalTasks => tasks?.length ?? 0;
  int get completedTasks => tasks?.where((t) => t.status == TaskStatus.completed).length ?? 0;
  double get progress => totalTasks == 0 ? 0 : completedTasks / totalTasks;

  factory JobCard.fromJson(Map<String, dynamic> j) => JobCard(
    id: j['id'] as String, garageId: j['garageId'] as String,
    jobNumber: j['jobNumber'] as String, vehicleId: j['vehicleId'] as String,
    customerId: j['customerId'] as String, description: j['description'] as String,
    status: JobCardStatusX.fromApi(j['status'] as String),
    version: j['version'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
    assignedToId: j['assignedToId'] as String?,
    estimatedHours: (j['estimatedHours'] as num?)?.toDouble(),
    mileageIn: j['mileageIn'] as int?,
    notes: j['notes'] as String?,
    promisedAt: j['promisedAt'] != null ? DateTime.parse(j['promisedAt'] as String) : null,
    startedAt:  j['startedAt']  != null ? DateTime.parse(j['startedAt']  as String) : null,
    completedAt:j['completedAt']!= null ? DateTime.parse(j['completedAt'] as String) : null,
  );
}

class Task {
  const Task({
    required this.id, required this.garageId, required this.jobCardId,
    required this.title, required this.status, required this.version,
    required this.createdAt, this.description, this.assignedToId,
    this.estimatedHours, this.actualHours, this.laborRate,
    this.startedAt, this.completedAt, this.sortOrder = 0,
    this.assignedTo,
  });

  final String id, garageId, jobCardId, title;
  final String? description, assignedToId;
  final TaskStatus status;
  final double? estimatedHours, actualHours, laborRate;
  final DateTime? startedAt, completedAt;
  final DateTime createdAt;
  final int version, sortOrder;
  final AppUser? assignedTo;

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String, garageId: j['garageId'] as String,
    jobCardId: j['jobCardId'] as String, title: j['title'] as String,
    status: TaskStatusX.fromApi(j['status'] as String),
    version: j['version'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
    description: j['description'] as String?,
    assignedToId: j['assignedToId'] as String?,
    estimatedHours: (j['estimatedHours'] as num?)?.toDouble(),
    actualHours: (j['actualHours'] as num?)?.toDouble(),
    laborRate: (j['laborRate'] as num?)?.toDouble(),
    sortOrder: j['sortOrder'] as int? ?? 0,
    startedAt:  j['startedAt']  != null ? DateTime.parse(j['startedAt']  as String) : null,
    completedAt:j['completedAt']!= null ? DateTime.parse(j['completedAt'] as String) : null,
  );
}

class Invoice {
  const Invoice({
    required this.id, required this.garageId, required this.invoiceNumber,
    required this.jobCardId, required this.customerId,
    required this.status, required this.subtotal, required this.total,
    required this.discountPct, required this.taxPct,
    required this.discountAmount, required this.taxAmount,
    required this.version, required this.createdAt,
    this.notes, this.issuedAt, this.dueAt, this.paidAt,
    this.lineItems = const [],
  });

  final String id, garageId, invoiceNumber, jobCardId, customerId;
  final InvoiceStatus status;
  final double subtotal, total, discountPct, taxPct, discountAmount, taxAmount;
  final DateTime? issuedAt, dueAt, paidAt;
  final DateTime createdAt;
  final String? notes;
  final int version;
  final List<InvoiceLineItem> lineItems;
}

class InvoiceLineItem {
  const InvoiceLineItem({
    required this.id, required this.invoiceId, required this.description,
    required this.quantity, required this.unitPrice, required this.itemType,
    this.taskId, this.sortOrder = 0,
  });

  final String id, invoiceId, description, itemType;
  final String? taskId;
  final double quantity, unitPrice;
  final int sortOrder;

  double get totalPrice => quantity * unitPrice;
}
