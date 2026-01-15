# Step Counter

**Step Counter** to aplikacja mobilna na Androida służąca do lokalnego monitorowania aktywności fizycznej użytkownika na podstawie liczby kroków Aplikacja działa w pełni offline, bez backendu i bez kont użytkownika, dając pełną kontrolę nad danymi.

Projekt został zrealizowany w **Flutterze** z wykorzystaniem **natywnego Androida (Kotlin)** do obsługi sensora kroków i pracy w tle.

---

## Główne funkcjonalności

- liczenie kroków w tle (Android `TYPE_STEP_COUNTER`)
- historia dzienna aktywności
- wykres aktywności godzinowej
- cele dzienne + streaki
- czas trwania aktywności
- pokonany dystans
- spalone kalorie
- eksport danych do pliku JSON
- import danych (scalanie lub zastąpienie historii)
- automatyczne czyszczenie starych danych (retention policy)
- brak chmury, brak logowania, brak internetu

---

## Jak działa aplikacja

- Kroki są zliczane przez **natywny serwis Androida**, który działa w tle.
- Dane zapisywane są **lokalnie w pamięci telefonu**.
- Flutter odpowiada za:
  - interfejs użytkownika,
  - logikę prezentacji danych,
  - ustawienia i dialogi.
- Komunikacja Fluttera i Androida odbywa się przez **MethodChannel**.

---

## Struktura projektu (najważniejsze elementy)

### 🔹 Android (Kotlin)

| Plik | Rola |
|----|----|
| `StepTrackingService.kt` | Serwis działający w tle – zliczanie kroków, zapis danych, retention policy |
| `StepCounterChannel.kt` | Kanał komunikacji Flutter ↔ Android (pobieranie danych, import/eksport, ustawienia) |
| `BootReceiver.kt` | Wznawianie śledzenia po restarcie telefonu |
| `MainActivity.kt` | Główna aktywność aplikacji Android |

**Odpowiedzialność Androida:**
- dostęp do sensora kroków,
- praca w tle,
- trwałe przechowywanie danych,
- import / eksport danych,
- automatyczne czyszczenie historii.

---

### 🔹 Flutter (Dart)

| Plik | Rola |
|----|----|
| `main.dart` | Punkt startowy aplikacji |
| `pages.dart` | Główne ekrany: Kroki, Ustawienia |
| `step_counter_repository.dart` | Repozytorium danych (most między Flutterem a Androidem) |
| `step_counter_android.dart` | Implementacja repozytorium po stronie Androida |
| `goal_store.dart` | Zarządzanie celem dziennym |
| `body_params_store.dart` | Parametry ciała (waga, długość kroku) |
| `activity_recognition_permission.dart` | Obsługa uprawnień Androida |
| `app_theme.dart` | Motyw aplikacji |

**Odpowiedzialność Fluttera:**
- UI i UX aplikacji,
- prezentacja danych,
- dialogi ustawień,
- nawigacja,
- walidacja danych użytkownika.

---

## Kroki (ekran główny)

Na ekranie głównym użytkownik znajdzie:
- liczbę kroków dla wybranego dnia,
- postęp realizacji celu dziennego,
- wykres aktywności godzinowej,
- czas aktywności, dystans i spalone kalorie,
- oznaczenie osiągnięcia celu i streak.

Można:
- przełączać dni (gestem lub kalendarzem),
- edytować cel dzienny,
- przeglądać historię.

---

## ⚙️ Ustawienia

### Ogólne
- włączanie / wyłączanie śledzenia kroków w tle,
- powiadomienia o osiągnięciu celu,
- **automatyczne czyszczenie danych (retention policy)**:
  - codziennie,
  - raz w tygodniu,
  - raz w miesiącu,
  - raz w roku,
  - własna liczba dni.

Retention działa jako **okno przechowywania danych** – aplikacja zawsze trzyma ostatnie *N* dni historii.

---

### Dystans
- domyślna długość kroku,
- własna długość kroku,
- automatyczne wyliczenie z wzrostu i płci.

---

### Kalorie
- domyślna waga,
- własna waga użytkownika.

---

## Import / eksport danych

### Eksport
- zapis całej historii do pliku JSON,
- dane czytelne i możliwe do analizy (np. Excel, Python),
- zawiera:
  - dni,
  - histogramy godzinowe,
  - cele,
  - ustawienia,
  - metadane techniczne.

### Import
- możliwość:
  - scalania danych (z pominięciem lub nadpisaniem dni),
  - zastąpienia całej historii,
- opcjonalny import ustawień,
- walidacja formatu i wersji pliku.

---

## Prywatność i dane

- brak backendu,
- brak kont użytkownika,
- brak wysyłania danych,
- wszystkie informacje przechowywane są **lokalnie na urządzeniu**,
- użytkownik ma pełną kontrolę nad danymi (eksport / import / czyszczenie).

---

## Ograniczenia

- dokładność zależna od sensora telefonu,
- system Android może ograniczać pracę w tle,
- dane nie są synchronizowane między urządzeniami automatycznie.