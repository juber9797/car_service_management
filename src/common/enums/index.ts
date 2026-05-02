export enum UserRole {
  ADMIN = 'admin',
  TECHNICIAN = 'technician',
  RECEPTIONIST = 'receptionist',
}

export enum JobCardStatus {
  PENDING = 'pending',
  IN_PROGRESS = 'in_progress',
  ON_HOLD = 'on_hold',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
}

export enum TaskStatus {
  PENDING = 'pending',
  IN_PROGRESS = 'in_progress',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
}

export enum InvoiceStatus {
  DRAFT = 'draft',
  ISSUED = 'issued',
  PAID = 'paid',
  OVERDUE = 'overdue',
  VOID = 'void',
}

export enum SyncOperation {
  CREATE = 'create',
  UPDATE = 'update',
  DELETE = 'delete',
}

export enum LineItemType {
  LABOR = 'labor',
  PART = 'part',
  MISC = 'misc',
}
