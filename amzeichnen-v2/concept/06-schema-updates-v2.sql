-- ============================================================================
-- AMZEICHNEN.CH – SCHEMA UPDATES V2 (Kategorien, Erstellungsdatum, Material-Freitext, Rahmung)
-- Ausführung: Direkt im Supabase SQL-Editor ausführbar (Idempotent)
-- ============================================================================

-- 1. NEUE TABELLE: public.categories (Dynamische Werk-Kategorien inkl. Präfix & Print)
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT NOT NULL UNIQUE,           -- Technischer Schlüssel, z.B. 'drawing', 'print', 'cyanotype'
  prefix TEXT NOT NULL,                -- Kürzel für automatische Werk-ID, z.B. 'Z', 'PRT', 'CYA'
  name_de TEXT NOT NULL,               -- Anzeigename Deutsch
  name_en TEXT,                        -- Anzeigename Englisch
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_categories_updated_at ON public.categories;
CREATE TRIGGER trg_categories_updated_at
  BEFORE UPDATE ON public.categories
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can read active categories" ON public.categories;
CREATE POLICY "Public can read active categories"
  ON public.categories FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS "Admins have full access to categories" ON public.categories;
CREATE POLICY "Admins have full access to categories"
  ON public.categories FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Standard-Kategorien inkl. Print einfügen
INSERT INTO public.categories (slug, prefix, name_de, name_en, sort_order, is_active)
VALUES
  ('drawing',     'Z',   'Farbstift-Original',     'Colored Pencil Original', 10, true),
  ('print',       'PRT', 'Print / Fine-Art-Print', 'Fine Art Print',          20, true),
  ('cyanotype',   'CYA', 'Cyanotypie',             'Cyanotype',               30, true),
  ('solargraphy', 'SOL', 'Solargraphie',           'Solargraphy',             40, true),
  ('pinhole',     'PIN', 'Pinhole-Fotografie',     'Pinhole Photography',     50, true),
  ('relief_3d',   'REL', '3D-Relief & Blattgold',  '3D Relief & Gold Leaf',   60, true),
  ('mixed_media', 'MIX', 'Mixed Media / Hybrid',   'Mixed Media / Hybrid',    70, true)
ON CONFLICT (slug) DO NOTHING;

-- 2. TABELLE public.artworks ERWEITERN & FLEXIBILISIEREN
-- Fixe Kategorie-Check-Einschränkung entfernen, damit neue Admin-Kategorien funktionieren
ALTER TABLE public.artworks
  DROP CONSTRAINT IF EXISTS artworks_category_check;

-- Fixe Rahmungs-Check-Einschränkung entfernen, damit auch Freitext möglich ist
ALTER TABLE public.artworks
  DROP CONSTRAINT IF EXISTS artworks_framing_status_check;

-- Neue Spalten für Erstellungsdatum und globales Material/Gewicht (Freitext)
ALTER TABLE public.artworks
  ADD COLUMN IF NOT EXISTS created_date DATE NOT NULL DEFAULT CURRENT_DATE,
  ADD COLUMN IF NOT EXISTS material_spec TEXT;

-- Bestehende Datensätze sinnvoll auffüllen (falls noch leer)
UPDATE public.artworks
SET
  created_date = COALESCE(created_date, make_date(created_year, 1, 1)),
  material_spec = COALESCE(
    material_spec,
    TRIM(CONCAT_WS(' ', NULLIF(paper_weight_gsm::TEXT || ' g/m²', ' g/m²'), paper_type))
  ),
  framing_status = COALESCE(NULLIF(framing_status, ''), 'Ohne Rahmen')
WHERE material_spec IS NULL OR framing_status IS NULL;
