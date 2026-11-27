import 'package:uuid/uuid.dart';

const localUserId = 'local-user';
const recognitionMode = 'recognition';

String newReviewEventId() => const Uuid().v7();
