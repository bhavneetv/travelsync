class TravelGroup {
  final String id;
  final String ownerId;
  final String name;
  final String? inviteCode;
  final String? destination;
  final DateTime? tripStart;
  final DateTime? tripEnd;
  final double? budget;
  final DateTime? createdAt;
  final int memberCount;

  TravelGroup({
    required this.id,
    required this.ownerId,
    required this.name,
    this.inviteCode,
    this.destination,
    this.tripStart,
    this.tripEnd,
    this.budget,
    this.createdAt,
    this.memberCount = 0,
  });

  factory TravelGroup.fromJson(Map<String, dynamic> json) {
    return TravelGroup(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String?,
      destination: json['destination'] as String?,
      tripStart: json['trip_start'] != null
          ? DateTime.parse(json['trip_start'] as String)
          : null,
      tripEnd: json['trip_end'] != null
          ? DateTime.parse(json['trip_end'] as String)
          : null,
      budget: (json['budget'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      memberCount: json['member_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'owner_id': ownerId,
      'name': name,
      'invite_code': inviteCode,
      'destination': destination,
      'trip_start': tripStart?.toIso8601String().split('T').first,
      'trip_end': tripEnd?.toIso8601String().split('T').first,
      'budget': budget,
    };
  }
}

class GroupTodo {
  final int? id;
  final String groupId;
  final String createdBy;
  final String text;
  final bool isDone;
  final String? assignedTo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  GroupTodo({
    this.id,
    required this.groupId,
    required this.createdBy,
    required this.text,
    this.isDone = false,
    this.assignedTo,
    this.createdAt,
    this.updatedAt,
  });

  factory GroupTodo.fromJson(Map<String, dynamic> json) {
    return GroupTodo(
      id: json['id'] as int?,
      groupId: json['group_id'] as String,
      createdBy: json['created_by'] as String,
      text: json['text'] as String,
      isDone: json['is_done'] as bool? ?? false,
      assignedTo: json['assigned_to'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'group_id': groupId,
      'created_by': createdBy,
      'text': text,
      'is_done': isDone,
      'assigned_to': assignedTo,
    };
  }

  GroupTodo copyWith({bool? isDone, String? assignedTo}) {
    return GroupTodo(
      id: id,
      groupId: groupId,
      createdBy: createdBy,
      text: text,
      isDone: isDone ?? this.isDone,
      assignedTo: assignedTo ?? this.assignedTo,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
