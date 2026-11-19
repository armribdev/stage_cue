import 'dart:math' as math;

/// Plage du gain d'un son réglable dans la fiche de la bibliothèque, en dB
/// ([décision 0045]). 0 dB = le fichier tel quel.
///
/// Le bas est une atténuation franche (−24 dB ≈ 6 %), le haut le relèvement
/// maximal que le lecteur du casque sait rendre (`volume-max` de mpv, voir
/// `cue_audio_service.dart`).
const double kGainMinDb = -24;
const double kGainMaxDb = 12;

/// Facteur linéaire d'un gain de [db] décibels.
double dbToGain(double db) => math.pow(10, db / 20).toDouble();

/// Gain de [gain] (facteur linéaire) en dB, ramené dans la plage du curseur :
/// un gain nul (son muet) ou hors plage s'affiche à la borne la plus proche.
double gainToDb(double gain) {
  if (gain <= 0) return kGainMinDb;
  return (20 * math.log(gain) / math.ln10).clamp(kGainMinDb, kGainMaxDb);
}
