# 📂 lib/screens/onboarding/

> Ersteinrichtung: Benutzername setzen bevor die App nutzbar ist.

## Dateien

* 📄 **onboarding_screen.dart** — Onboarding-Screen (`OnboardingScreen`,
  ConsumerStatefulWidget). Eingabefeld für Benutzername, erzeugt UUID,
  speichert User in Drift-DB via `dbProvider`. Navigiert nach Abschluss
  zur Home-Seite. Branded UI mit RedPanda-Icon.
