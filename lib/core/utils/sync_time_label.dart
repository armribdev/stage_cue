/// En dessous de cet âge, une synchro s'exprime en durée relative.
const Duration kRelativeSyncWindow = Duration(hours: 1);

/// Âge d'une synchro, pour qu'une ligne puisse se rafraîchir au bon moment.
/// Négatif (horloge réglée en arrière) : traité comme « à l'instant ».
Duration syncAge(DateTime syncedAt, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(syncedAt);
  return age.isNegative ? Duration.zero : age;
}

/// Date d'une synchro, lisible après « Synchronisé » : relative pendant la
/// dernière heure (« à l'instant », « il y a 3 min »), absolue au-delà
/// (« aujourd'hui à 14:32 », « hier à … », « le 09/11 à … »).
///
/// L'absolu garde sa valeur passé une heure : « il y a 190 min » se lit plus mal
/// qu'une heure, et ne dit pas à quel moment de la journée c'était.
String formatDriveSyncTimestamp(DateTime syncedAt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final age = syncAge(syncedAt, now: reference);
  if (age < kRelativeSyncWindow) {
    if (age < const Duration(minutes: 1)) return "à l'instant";
    return 'il y a ${age.inMinutes} min';
  }

  final local = syncedAt.toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final syncDay = DateTime(local.year, local.month, local.day);
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';

  if (syncDay == today) return "aujourd'hui à $time";
  if (syncDay == today.subtract(const Duration(days: 1))) return 'hier à $time';
  return 'le ${two(local.day)}/${two(local.month)} à $time';
}
