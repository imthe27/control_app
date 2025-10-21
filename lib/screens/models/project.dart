class Project {
  final int id;
  final String name;
  final String address;
  final String status;
  final double progress;
  final String? photoUrl;
  bool isPinned;

  Project({
    required this.id,
    required this.name,
    required this.address,
    required this.status,
    required this.progress,
    this.photoUrl,
    this.isPinned = false,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      status: json['status'] ?? 'In Progress',
      progress: (json['progress'] ?? 0).toDouble(),
      photoUrl: json['photo_url'],
      isPinned: json['isPinned'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'status': status,
      'progress': progress,
      'photo_url': photoUrl,
      'isPinned': isPinned,
    };
  }
}
