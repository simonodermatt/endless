# Brand Identity & Projekt-Kontext: amZeichnen.ch

## 1. Künstlerisches Profil & Portfolio
* **Brand / Domain:** amZeichnen.ch (Instagram: `@simon.amZeichnen`)
* **Standort & Fokus:** Schweiz (Raum Luzern / Bern).
* **Medien & Techniken:**
  * Physische Originalzeichnungen mit Farbstiften (teils montiert auf Holzpanels, teils gerahmt, teils ohne).
  * Experimentelle analoge Fotografie: Pinhole-Fotografie (Lochkameras aus Dosen, Karton/Origami-Konstruktionens Projekt), Langzeitbelichtungen (Solargraphie) "map.solargrafie.ch".
  * Alternative Edeldruckverfahren: Cyanotypie (bis hin zu lebensgrossen Papier-Installationen).
  * Audio-visuelle und generative Experimente an der Schnittstelle von analogem Handwerk und Web-Technologie.

## 2. Design-Vision: "Thermal Printer / Receipt Brutalism"
* **Ästhetische Inspiration:** Thermodrucker-Kassenbons, Teenage Engineering Hardware-Design, monochromer Brutalismus, technische Datenblätter.
* **Visuelle Mechanik der Webseite:**
  * Endlos-Papierrollen-Gefühl (Single-Page Continuous Scroll) auf hellem Thermopapier-Hintergrund (`#F4F4F0`) oder invertiertem Dark-Mode, kombiniert mit harten `1px solid` Rahmen und gestrichelten Trennlinien (`---`).
  * Typografie: Strikte Monospace-Schriften (z. B. JetBrains Mono, Space Mono, VT323).
  * Bilddarstellung: Kunstwerke erscheinen im Feed zunächst im 1-Bit-Dithering-Look (Halbton-Raster wie auf einem echten Thermodrucker). Erst bei Hover oder Klick "entwickelt" sich das hochauflösende, farbige Originalbild (wichtig für das tiefe Preussischblau der Cyanotypien und die Textur der Farbstifte).
  * Metadaten-Fokus: Jedes Werk wird wie ein technischer Beleg gelistet (Werk-ID, Zeitstempel, Technik, Belichtungszeit, Papiergewicht, Dimension, Preis, Barcode/QR-Code).
  * Gezackte Abrisskanten (SVG/CSS) am oberen/unteren Rand von Sektionen und beim Checkout-Bon.

## 3. Technische Anforderungen
* **Ablösung:** Kompletter Ersatz der bestehenden Seite `amzeichnen.ch`.
* **Datenbank & Backend:** Supabase (PostgreSQL Datenbank + Supabase Storage für hochauflösende Bilder + Supabase Auth).
* **Admin-Workflow:** Geschütztes `/admin`-Interface direkt auf der Webseite, um Bilder per Drag-and-Drop hochzuladen, Metadaten zu pflegen, Bestände/Preise anzupassen und die Sichtbarkeit zu steuern.

## 4. Business-Ziele
* Aufbau eines tragfähigen Kunst- und Kreativ-Business über einen reinen Portfolio-Auftritt hinaus.
* **Säulen:** Direktverkauf von Originalen & Prints, Vertrieb von DIY-Kits/Zines (z. B. faltbare Lochkameras, Cyanotypie-Anleitungen, Solarografie Set), Buchung von Workshops sowie Konzeption von Pop-up-Ausstellungen.
