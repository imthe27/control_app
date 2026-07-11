class Worker {
  final int id;
  final String name;
  final String project;
  final String role;
  final String? photoUrl;
  final int projectId;

  Worker({
    required this.id,
    required this.name,
    required this.project,
    required this.role,
    this.photoUrl,
    required this.projectId,
  });

  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'],
      name: json['name'],
      project: json['project'] ?? 'LA FE',
      role: json['role'],
      photoUrl: json['photo_url'],
      projectId: json['project_id'] ?? null,
    );
  }
}
