# Rolle: Creative Tech & Supabase Architect

## Deine Aufgabe
Lies `/context/brand-identity.md` und `/concept/01-artist-benchmarks.md`. Entwirf die komplette technische Architektur und das UI/UX-System für die neue Webseite `amzeichnen.ch`.

## Fokus-Bereiche
1. **UI/UX Spezifikation (Thermodrucker-Style):**
   * Layout-Struktur (Kassenbon-Header, Filter-Tasten im Hardware-Stil, Werk-Feed als fortlaufender Beleg, Warenkorb als abreissbarer Bon am Bildschirmrand).
   * Technische Umsetzung des Dithering-Effekts (Canvas/WebGL-Shader oder CSS-Filter für den Übergang von 1-Bit-Monochrom zu Echtfarbe bei Interaktion).
2. **Supabase Datenbank-Schema (SQL):**
   * Tabellen für `artworks` (Originale, Prints, Serien), `products` (Zines, DIY-Kameras), `workshops` (Termine, freie Plätze, Ort) und `exhibitions` (Logbuch/Archiv), `translations` (Text Tabelle für alle Sprachen und Label).
   * Spezifische Metadaten-Felder für analoge Kunst (z. B. `exposure_time`, `paper_weight_gsm`, `medium`, `dimensions_mm`, `edition_size`, `edition_remaining`).
   * Supabase Storage Bucket-Struktur und Row Level Security (RLS) Policies.
3. **Admin-Dashboard (`/admin`):**
   * Spezifikation eines schlanken Backends für den Künstler: Login via Supabase Auth, Bildupload mit automatischer Komprimierung, Live-Vorschau des Kassenbon-Eintrags, Bestandsverwaltung.

## Output
1. Erstelle `/concept/02-ui-thermo-spec.md` (Design-System, Komponenten, Interaktionen).
2. Erstelle `/concept/02-database-schema.sql` (Direkt ausführbarer SQL-Code für den Supabase SQL-Editor).
