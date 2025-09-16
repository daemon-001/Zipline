import 'package:json_annotation/json_annotation.dart';

// part 'transfer_item.g.dart';

enum TransferType { file, folder, text }

enum TransferStatus { pending, inProgress, completed, failed, cancelled }

@JsonSerializable()
class TransferItem {
  final String id;
  final String name;
  final String? path;
  final int size;
  final TransferType type;
  final TransferStatus status;
  final int progress;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? error;
  final String? textContent; // For text transfers

  const TransferItem({
    required this.id,
    required this.name,
    this.path,
    required this.size,
    required this.type,
    required this.status,
    this.progress = 0,
    required this.createdAt,
    this.completedAt,
    this.error,
    this.textContent,
  });

  // factory TransferItem.fromJson(Map<String, dynamic> json) => _$TransferItemFromJson(json);
  // Map<String, dynamic> toJson() => _$TransferItemToJson(this);

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String?,
      size: json['size'] as int,
      type: TransferType.values.byName(json['type'] as String),
      status: TransferStatus.values.byName(json['status'] as String),
      progress: json['progress'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null 
          ? DateTime.parse(json['completedAt'] as String) 
          : null,
      error: json['error'] as String?,
      textContent: json['textContent'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'type': type.name,
      'status': status.name,
      'progress': progress,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'error': error,
      'textContent': textContent,
    };
  }

  TransferItem copyWith({
    String? id,
    String? name,
    String? path,
    int? size,
    TransferType? type,
    TransferStatus? status,
    int? progress,
    DateTime? createdAt,
    DateTime? completedAt,
    String? error,
    String? textContent,
  }) {
    return TransferItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      type: type ?? this.type,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
      textContent: textContent ?? this.textContent,
    );
  }

  String get displaySize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double bytes = size.toDouble();
    int unitIndex = 0;
    
    while (bytes >= 1024 && unitIndex < units.length - 1) {
      bytes /= 1024;
      unitIndex++;
    }
    
    return '${bytes.toStringAsFixed(bytes < 10 ? 1 : 0)} ${units[unitIndex]}';
  }

  String get iconPath {
    switch (type) {
      case TransferType.folder:
        return 'assets/images/OpenFolderIcon.png';
      case TransferType.text:
        return 'assets/images/RecentText.png';
      case TransferType.file:
      default:
        return 'assets/images/RecentFile.png';
    }
  }

  bool get isCompleted => status == TransferStatus.completed;
  bool get isFailed => status == TransferStatus.failed;
  bool get isInProgress => status == TransferStatus.inProgress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'TransferItem{name: $name, status: $status, progress: $progress%}';
}