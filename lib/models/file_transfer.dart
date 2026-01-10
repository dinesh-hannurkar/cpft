/// High-level file transfer state and metadata
class FileOffer {
  final String transferId; // unique per transfer
  final String fileName;
  final int fileSize; // bytes
  final String mimeType; // best-effort
  final String? sha256; // optional integrity hash

  FileOffer({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.sha256,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'fileName': fileName,
    'fileSize': fileSize,
    'mimeType': mimeType,
    if (sha256 != null) 'sha256': sha256,
  };

  factory FileOffer.fromJson(Map<String, dynamic> json) => FileOffer(
    transferId: json['transferId'] as String,
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int,
    mimeType: json['mimeType'] as String,
    sha256: json['sha256'] as String?,
  );
}

/// Represents a chunk of file data (Base64 encoded for JSON transport)
class FileChunk {
  final String transferId;
  final int index; // zero-based chunk index
  final String dataBase64; // chunk payload
  final bool isLast; // marks final chunk

  FileChunk({
    required this.transferId,
    required this.index,
    required this.dataBase64,
    required this.isLast,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'index': index,
    'data': dataBase64,
    'isLast': isLast,
  };

  factory FileChunk.fromJson(Map<String, dynamic> json) => FileChunk(
    transferId: json['transferId'] as String,
    index: json['index'] as int,
    dataBase64: json['data'] as String,
    isLast: json['isLast'] as bool,
  );
}

/// Acknowledgement for control flow/backpressure
class FileAck {
  final String transferId;
  final int nextExpectedIndex; // receiver expects this chunk next
  final bool completed;
  final String? error; // present if failed

  FileAck({
    required this.transferId,
    required this.nextExpectedIndex,
    required this.completed,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'nextExpectedIndex': nextExpectedIndex,
    'completed': completed,
    if (error != null) 'error': error,
  };

  factory FileAck.fromJson(Map<String, dynamic> json) => FileAck(
    transferId: json['transferId'] as String,
    nextExpectedIndex: json['nextExpectedIndex'] as int,
    completed: json['completed'] as bool,
    error: json['error'] as String?,
  );
}

/// Cancellation message
class FileCancel {
  final String transferId;
  final String reason;

  FileCancel({required this.transferId, required this.reason});

  Map<String, dynamic> toJson() => {'transferId': transferId, 'reason': reason};

  factory FileCancel.fromJson(Map<String, dynamic> json) => FileCancel(
    transferId: json['transferId'] as String,
    reason: json['reason'] as String,
  );
}

/// Helper to generate transfer IDs
String generateTransferId() => DateTime.now().microsecondsSinceEpoch.toString();
