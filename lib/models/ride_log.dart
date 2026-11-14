class RideLog {
  final String id;
  final String trainId;
  final String originCode;
  final String originName;
  final String destinationCode;
  final String destinationName;
  final String? track;
  final DateTime boardedAt;
  final DateTime? arrivedAt;
  final int totalStops;
  final String statusSummary;

  const RideLog({
    required this.id,
    required this.trainId,
    required this.originCode,
    required this.originName,
    required this.destinationCode,
    required this.destinationName,
    this.track,
    required this.boardedAt,
    this.arrivedAt,
    required this.totalStops,
    required this.statusSummary,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'trainId': trainId,
        'originCode': originCode,
        'originName': originName,
        'destinationCode': destinationCode,
        'destinationName': destinationName,
        'track': track,
        'boardedAt': boardedAt.toIso8601String(),
        'arrivedAt': arrivedAt?.toIso8601String(),
        'totalStops': totalStops,
        'statusSummary': statusSummary,
      };

  factory RideLog.fromJson(Map<String, dynamic> json) {
    return RideLog(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString(),
      trainId: (json['trainId'] ?? '3800').toString(),
      originCode: (json['originCode'] ?? 'NY').toString(),
      originName: (json['originName'] ?? 'New York Penn Station').toString(),
      destinationCode: (json['destinationCode'] ?? 'MP').toString(),
      destinationName: (json['destinationName'] ?? 'Metropark').toString(),
      track: json['track']?.toString(),
      boardedAt: DateTime.tryParse((json['boardedAt'] ?? '').toString()) ?? DateTime.now(),
      arrivedAt: json['arrivedAt'] != null
          ? DateTime.tryParse(json['arrivedAt'].toString())
          : null,
      totalStops: (json['totalStops'] as num?)?.toInt() ?? 5,
      statusSummary: (json['statusSummary'] ?? 'On Time').toString(),
    );
  }
}
