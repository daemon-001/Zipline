import 'package:json_annotation/json_annotation.dart';
import 'peer.dart';
import 'transfer_item.dart';

// part 'transfer_session.g.dart';

enum TransferDirection { sending, receiving, outgoing, incoming }
enum TransferStatus { pending, inProgress, completed, failed, cancelled }

@JsonSerializable()
class TransferSession {
  final String id;
  final Peer peer;
  final List<TransferItem> items;
  final TransferDirection direction;
  final TransferStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int totalSize;
  final int transferredSize;
  final String? error;
  final String? currentFileName;
  final int totalFiles;
  final int completedFiles;

  const TransferSession({
    required this.id,
    required this.peer,
    required this.items,
    required this.direction,
    required this.status,
    required this.startedAt,
    this.completedAt,
    required this.totalSize,
    this.transferredSize = 0,
    this.error,
    this.currentFileName,
    this.totalFiles = 0,
    this.completedFiles = 0,
  });

  // factory TransferSession.fromJson(Map<String, dynamic> json) => _$TransferSessionFromJson(json);
  // Map<String, dynamic> toJson() => _$TransferSessionToJson(this);

  factory TransferSession.fromJson(Map<String, dynamic> json) {
    return TransferSession(
      id: json['id'] as String,
      peer: Peer.fromJson(json['peer'] as Map<String, dynamic>),
      items: (json['items'] as List<dynamic>)
          .map((item) => TransferItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      direction: TransferDirection.values.byName(json['direction'] as String),
      status: TransferStatus.values.byName(json['status'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null 
          ? DateTime.parse(json['completedAt'] as String) 
          : null,
      totalSize: json['totalSize'] as int,
      transferredSize: json['transferredSize'] as int? ?? 0,
      error: json['error'] as String?,
      currentFileName: json['currentFileName'] as String?,
      totalFiles: json['totalFiles'] as int? ?? 0,
      completedFiles: json['completedFiles'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'peer': peer.toJson(),
      'items': items.map((item) => item.toJson()).toList(),
      'direction': direction.name,
      'status': status.name,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'totalSize': totalSize,
      'transferredSize': transferredSize,
      'error': error,
      'currentFileName': currentFileName,
      'totalFiles': totalFiles,
      'completedFiles': completedFiles,
    };
  }

  TransferSession copyWith({
    String? id,
    Peer? peer,
    List<TransferItem>? items,
    TransferDirection? direction,
    TransferStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    int? totalSize,
    int? transferredSize,
    String? error,
    String? currentFileName,
    int? totalFiles,
    int? completedFiles,
  }) {
    return TransferSession(
      id: id ?? this.id,
      peer: peer ?? this.peer,
      items: items ?? this.items,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      totalSize: totalSize ?? this.totalSize,
      transferredSize: transferredSize ?? this.transferredSize,
      error: error ?? this.error,
      currentFileName: currentFileName ?? this.currentFileName,
      totalFiles: totalFiles ?? this.totalFiles,
      completedFiles: completedFiles ?? this.completedFiles,
    );
  }

  double get progressPercentage {
    if (totalSize == 0) return 0.0;
    return (transferredSize / totalSize * 100).clamp(0.0, 100.0);
  }

  String get displayTotalSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double bytes = totalSize.toDouble();
    int unitIndex = 0;
    
    while (bytes >= 1024 && unitIndex < units.length - 1) {
      bytes /= 1024;
      unitIndex++;
    }
    
    return '${bytes.toStringAsFixed(bytes < 10 ? 1 : 0)} ${units[unitIndex]}';
  }

  String get displayTransferredSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double bytes = transferredSize.toDouble();
    int unitIndex = 0;
    
    while (bytes >= 1024 && unitIndex < units.length - 1) {
      bytes /= 1024;
      unitIndex++;
    }
    
    return '${bytes.toStringAsFixed(bytes < 10 ? 1 : 0)} ${units[unitIndex]}';
  }

  Duration get duration {
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  String get statusText {
    switch (status) {
      case TransferStatus.pending:
        return 'Pending';
      case TransferStatus.inProgress:
        return 'In Progress';
      case TransferStatus.completed:
        return 'Completed';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get directionText {
    switch (direction) {
      case TransferDirection.sending:
      case TransferDirection.outgoing: // Handle both enum values
        return 'Sending to ${peer.displayName}';
      case TransferDirection.receiving:
      case TransferDirection.incoming: // Handle both enum values
        return 'Receiving from ${peer.displayName}';
    }
  }

  // Compatibility getter for old code that uses createdAt
  DateTime get createdAt => startedAt;

  bool get isCompleted => status == TransferStatus.completed;
  bool get isFailed => status == TransferStatus.failed;
  bool get isInProgress => status == TransferStatus.inProgress;
  bool get canCancel => status == TransferStatus.pending || status == TransferStatus.inProgress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferSession && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TransferSession{peer: ${peer.name}, direction: $direction, status: $status}';
}