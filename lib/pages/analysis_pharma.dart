// 🔹 Età Biologica (normalizzata su base 25–75)
final double etaReale = (resultData["marketing"]?["Età Biologica"] ?? 40).toDouble();
final double etaNorm = (1.0 - ((etaReale - 25.0) / 50.0)).clamp(0.0, 1.0);

_buildParamCard(
  "Età Biologica della Pelle",
  etaNorm,
  etaReale: etaReale,
),
