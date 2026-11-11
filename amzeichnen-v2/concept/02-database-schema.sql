-- ============================================================================
-- AMZEICHNEN.CH – SUPABASE DATABASE SCHEMA & STORAGE SETUP
-- Rolle: Creative Tech & Supabase Architect
-- Ausführung: Direkt im Supabase SQL-Editor ausführbar (Idempotent / Clean Setup)
-- ============================================================================

-- 1. EXTENSIONS AKTIVIEREN
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 2. HILFSFUNKTIONEN & ADMIN-ZUGRIFFSSTEUERUNG
-- ============================================================================

-- Automatischer Timestamp-Trigger für updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Tabelle für autorisierte Admin-Benutzer (verknüpft mit auth.users)
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'admin',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Sicherheitsfunktion: Prüft, ob der aktuell eingeloggte User ein Admin ist
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.admin_users
    WHERE user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin darf die admin_users Tabelle lesen
DROP POLICY IF EXISTS "Admins can view admin_users" ON public.admin_users;
CREATE POLICY "Admins can view admin_users"
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- ============================================================================
-- 3. TABELLE: translations (Mehrsprachige UI-Labels & Kassenbon-Textbausteine)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.translations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  translation_key TEXT NOT NULL UNIQUE,          -- z.B. 'header.status.ready', 'receipt.label.exposure'
  namespace TEXT NOT NULL DEFAULT 'ui',          -- 'ui', 'receipt', 'checkout', 'categories', 'admin'
  de TEXT NOT NULL,                              -- Schweizerdeutsch / Hochdeutsch (Standard)
  en TEXT NOT NULL,                              -- Englisch (Internationale Sammler)
  fr TEXT,                                       -- Optional: Französisch (Westschweiz)
  context_note TEXT,                             -- Hinweis für das Admin-Interface
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_translations_namespace ON public.translations(namespace);
CREATE INDEX IF NOT EXISTS idx_translations_key ON public.translations(translation_key);

DROP TRIGGER IF EXISTS trg_translations_updated_at ON public.translations;
CREATE TRIGGER trg_translations_updated_at
  BEFORE UPDATE ON public.translations
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 4. TABELLE: artworks (Originale, Fine-Art-Prints, Cyanotypien, Solargraphien)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.artworks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artwork_code TEXT NOT NULL UNIQUE,             -- Maschinenlesbare Werk-ID, z.B. 'K0064', 'CYA-2026-01'
  slug TEXT NOT NULL UNIQUE,                     -- URL-Slug, z.B. 'k0064-goldader-im-preussischblau'
  
  -- Mehrsprachige Kerndaten
  title_de TEXT NOT NULL,
  title_en TEXT,
  description_de TEXT,
  description_en TEXT,
  
  -- Klassifizierung & Serie
  category TEXT NOT NULL CHECK (category IN (
    'drawing',       -- Farbstift-Originale (Papier / Holzpanel)
    'cyanotype',     -- Cyanotypie & Edeldruckverfahren
    'pinhole',       -- Lochkamera-Fotografie
    'solargraphy',   -- Langzeitbelichtungen (Solargraphie)
    'relief_3d',     -- 3D-Papierrelief & Blattgold-Objekte
    'mixed_media'    -- Audio-visuelle & hybride Experimente
  )),
  series_code TEXT,                              -- z.B. 'SER-01', 'SER-12'
  series_name TEXT,                              -- z.B. 'Cyanotypie & Experimentell', 'Organische Formstudien'
  created_year INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM NOW())::INTEGER,
  
  -- Spezifische analoge & technische Metadaten (für den Kassenbon-Druck)
  medium TEXT NOT NULL,                          -- z.B. 'Polychromos auf Bütten', 'Cyanotypie + 24k Blattgold'
  paper_type TEXT,                               -- z.B. 'Arches Aquarelle Bütten', 'Birkenholz-Panel', 'Ilford RC'
  paper_weight_gsm INTEGER,                      -- Papiergewicht in g/m², z.B. 250, 300
  dimensions_mm TEXT NOT NULL,                   -- Exaktes Mass in mm, z.B. '148 x 210 mm' oder '650 x 2000 mm'
  format_label TEXT,                             -- Kurzform, z.B. 'A6', 'A5', 'A4', 'Lebensgross (2m)'
  framing_status TEXT DEFAULT 'unframed' CHECK (framing_status IN (
    'unframed', 'mounted_on_wood', 'framed_oak', 'framed_black', 'installation_scroll'
  )),
  
  -- Foto- & Belichtungsparameter (für Cyanotypie, Pinhole & Solargraphie)
  exposure_time TEXT,                            -- Freitext für Bon, z.B. '16 Min 40 Sek' oder '182 Tage (Wintersonnenwende)'
  exposure_seconds INTEGER,                      -- Numerischer Wert für Sortierung/Filterung
  uv_source TEXT,                                -- z.B. 'Alpensonne Luzern (UV-Index 7)', 'Halogen-UV-Röhre'
  aperture TEXT,                                 -- z.B. 'f/138 (0.25mm Pinhole)'
  coordinates TEXT,                              -- z.B. '47.0502° N, 8.3093° E (Luzern)'
  solargraphy_map_id TEXT,                       -- Referenz-ID zu map.solargrafie.ch
  color_mood TEXT,                               -- z.B. 'Preussischblau & Feingold', 'Ultramarin & Ocker'
  
  -- Editions- & Bestands-Logik
  edition_type TEXT NOT NULL DEFAULT 'original' CHECK (edition_type IN (
    'original',          -- 1/1 Unikat
    'limited_edition',   -- Nummerierte Kleinedition
    'open_print',        -- Offene Print-Serie
    'drop_bundle'        -- Kuratiertes Themen-Set
  )),
  edition_size INTEGER NOT NULL DEFAULT 1 CHECK (edition_size >= 1),
  edition_remaining INTEGER NOT NULL DEFAULT 1 CHECK (edition_remaining >= 0),
  
  -- Preis & Verkaufsstatus (Schweizer Franken CHF)
  price_chf NUMERIC(10, 2) NOT NULL CHECK (price_chf >= 0),
  shipping_category TEXT NOT NULL DEFAULT 'flat_a5' CHECK (shipping_category IN (
    'flat_a5', 'flat_a3', 'tube_oversize', 'wood_crate', 'pickup_only'
  )),
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN (
    'available',     -- Käuflich im Feed
    'reserved',      -- Reserviert (z.B. während laufender Ausstellung)
    'sold',          -- Verkauft (bleibt im Werkverzeichnis mit [ ARCHIVIERT ]-Stempel)
    'not_for_sale',  -- Reines Ausstellungs-/Archivstück
    'draft'          -- Nur im /admin sichtbar
  )),
  
  -- Bild-Pipeline (1-Bit Dither + Echtfarbe)
  image_dither_url TEXT NOT NULL,                -- 384px 1-Bit PNG für schnellen Thermo-Feed
  image_color_url TEXT NOT NULL,                 -- 800px WebP für Hover/Tap-Entwicklung
  image_hd_url TEXT,                             -- 2000px WebP für Vollbild-Leuchtkasten
  dither_config JSONB DEFAULT '{"algorithm": "atkinson", "threshold": 128, "contrast": 1.1}'::JSONB,
  
  -- Steuerung & Sortierung
  is_published BOOLEAN NOT NULL DEFAULT false,
  is_featured BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL DEFAULT 0,
  printed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- Zeitstempel auf dem Kassenbon
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artworks_category ON public.artworks(category);
CREATE INDEX IF NOT EXISTS idx_artworks_status ON public.artworks(status);
CREATE INDEX IF NOT EXISTS idx_artworks_published ON public.artworks(is_published, sort_order DESC, printed_at DESC);
CREATE INDEX IF NOT EXISTS idx_artworks_series ON public.artworks(series_code);

DROP TRIGGER IF EXISTS trg_artworks_updated_at ON public.artworks;
CREATE TRIGGER trg_artworks_updated_at
  BEFORE UPDATE ON public.artworks
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 5. TABELLE: products (DIY-Lochkamera-Kits, Cyanotypie-Sets, Zines, Postkarten)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku TEXT NOT NULL UNIQUE,                      -- z.B. 'KIT-PIN-A6', 'KIT-SOL-01', 'ZINE-001'
  slug TEXT NOT NULL UNIQUE,
  
  title_de TEXT NOT NULL,
  title_en TEXT,
  subtitle_de TEXT,
  subtitle_en TEXT,
  description_de TEXT NOT NULL,
  description_en TEXT,
  
  product_type TEXT NOT NULL CHECK (product_type IN (
    'diy_camera_kit',    -- Faltbare Lochkameras (Origami/Karton) & Solargraphie-Dosen-Sets
    'cyanotype_kit',     -- Cyanotypie-Starter-Sets & Papier-Packs
    'zine',              -- Gedruckte Mini-Zines & Werkkataloge
    'postcard_set',      -- Postkarten- & Kleinprint-Bögen
    'merch_tool'         -- Spezielles Atelier-Zubehör (z.B. Belichtungsrahmen)
  )),
  
  -- Technische Spezifikationen für das Kassenbon-Datenblatt
  dimensions_mm TEXT,                            -- z.B. '105 x 148 x 12 mm (Gefaltet)'
  weight_grams INTEGER,                          -- Für Schweizer Post Versandberechnung (Brief vs. Paket)
  difficulty_level TEXT,                         -- z.B. 'Einsteiger / Ab 10 J.', 'Labor-Erfahrung'
  contents_list TEXT[],                          -- Array der enthaltenen Bauteile auf dem Beleg
  technical_specs JSONB DEFAULT '{}'::JSONB,     -- z.B. {"focal_length_mm": 35, "pinhole_mm": 0.22, "f_stop": "f/159"}
  
  -- Preis & Lagerbestand
  price_chf NUMERIC(10, 2) NOT NULL CHECK (price_chf >= 0),
  stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  is_published BOOLEAN NOT NULL DEFAULT false,
  
  -- Medien
  image_dither_url TEXT NOT NULL,
  image_color_url TEXT NOT NULL,
  gallery_urls TEXT[] DEFAULT '{}',
  manual_pdf_url TEXT,                           -- Link zur digitalen Bau-/Belichtungsanleitung
  
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_type ON public.products(product_type);
CREATE INDEX IF NOT EXISTS idx_products_published ON public.products(is_published, sort_order ASC);

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 6. TABELLE: workshops (Analoge Kreativ-Workshops in Luzern, Bern & Outdoor)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.workshops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_code TEXT NOT NULL UNIQUE,            -- z.B. 'WS-LU-2026-01', 'WS-BE-2026-02'
  slug TEXT NOT NULL UNIQUE,
  
  title_de TEXT NOT NULL,
  title_en TEXT,
  subtitle_de TEXT,
  subtitle_en TEXT,
  description_de TEXT NOT NULL,
  description_en TEXT,
  
  workshop_topic TEXT NOT NULL CHECK (workshop_topic IN (
    'pinhole_build',     -- Lochkamera-Bau & Dunkelkammer-Entwicklung
    'cyanotype_outdoor', -- Cyanotypie-Belichtung im Freien
    'solargraphy_lab',   -- Solargraphie: Bau, Montage & digitale Auswertung
    'drawing_intensive'  -- Farbstift-Schichttechnik & Werkstudien
  )),
  
  -- Ort & Zeit
  location_city TEXT NOT NULL,                   -- z.B. 'Luzern', 'Bern'
  location_venue TEXT NOT NULL,                  -- z.B. 'Atelier / Neubad Luzern', 'PROGR Bern (Gast-Labor)'
  location_address TEXT,
  coordinates TEXT,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  duration_hours NUMERIC(4, 1) NOT NULL,         -- z.B. 4.0 Stunden (Halbtages-Workshop)
  
  -- Kapazität & Buchungsstatus
  max_participants INTEGER NOT NULL DEFAULT 8 CHECK (max_participants > 0),
  seats_remaining INTEGER NOT NULL DEFAULT 8 CHECK (seats_remaining >= 0),
  price_chf NUMERIC(10, 2) NOT NULL CHECK (price_chf >= 0),
  materials_included TEXT[],                     -- z.B. ARRAY['Vorbeschichtetes Büttenpapier', 'Chemie & Wasserbad', '3 eigene Prints zum Mitnehmen']
  
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
    'open',          -- Buchbar
    'almost_full',   -- Nur noch 1-2 Plätze
    'sold_out',      -- Ausgebucht (Warteliste möglich)
    'completed',     -- Vergangener Workshop (bleibt als Referenz im Logbuch)
    'cancelled'
  )),
  
  image_dither_url TEXT,
  image_color_url TEXT,
  is_published BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workshops_start_time ON public.workshops(start_time ASC);
CREATE INDEX IF NOT EXISTS idx_workshops_published ON public.workshops(is_published, start_time ASC);

DROP TRIGGER IF EXISTS trg_workshops_updated_at ON public.workshops;
CREATE TRIGGER trg_workshops_updated_at
  BEFORE UPDATE ON public.workshops
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 7. TABELLE: exhibitions (Ausstellungs-Logbuch, Pop-ups & Projekt-Archiv)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.exhibitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exhibition_code TEXT NOT NULL UNIQUE,          -- z.B. 'LOG-2026-01', 'EXH-LU-2025'
  slug TEXT NOT NULL UNIQUE,
  
  title_de TEXT NOT NULL,
  title_en TEXT,
  entry_type TEXT NOT NULL DEFAULT 'popup' CHECK (entry_type IN (
    'solo_exhibition',   -- Einzelausstellung
    'group_exhibition',  -- Gruppenausstellung
    'popup_event',       -- Zwischennutzung / Pop-up-Labor
    'installation',      -- Grossformatige 2m-Cyanotypie-Installation
    'field_log'          -- Feld-Experiment (z.B. map.solargrafie.ch Auswertung)
  )),
  
  venue_name TEXT NOT NULL,                      -- z.B. 'Zwischennutzung Industriestrasse', 'Kulturzentrum'
  city TEXT NOT NULL,                            -- z.B. 'Luzern', 'Bern', 'Zürich'
  start_date DATE NOT NULL,
  end_date DATE,
  vernissage_info TEXT,                          -- z.B. 'Freitag, 19:00 Uhr – Live-Belichtung & Sound'
  
  description_de TEXT NOT NULL,
  description_en TEXT,
  
  -- Verknüpfung mit gezeigten Werken (Array von artwork_codes)
  featured_artwork_codes TEXT[] DEFAULT '{}',
  external_link_url TEXT,                        -- z.B. 'https://map.solargrafie.ch'
  
  image_dither_url TEXT,
  image_color_url TEXT,
  gallery_urls TEXT[] DEFAULT '{}',
  
  is_published BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exhibitions_dates ON public.exhibitions(start_date DESC);

DROP TRIGGER IF EXISTS trg_exhibitions_updated_at ON public.exhibitions;
CREATE TRIGGER trg_exhibitions_updated_at
  BEFORE UPDATE ON public.exhibitions
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 8. TABELLE: receipt_orders (Kassenbon-Bestellungen & Dual-Receipt CoA Archiv)
-- ============================================================================

CREATE SEQUENCE IF NOT EXISTS public.receipt_number_seq START 1001;

CREATE TABLE IF NOT EXISTS public.receipt_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_number TEXT NOT NULL UNIQUE DEFAULT ('BON-' || EXTRACT(YEAR FROM NOW())::TEXT || '-' || LPAD(nextval('public.receipt_number_seq')::TEXT, 4, '0')),
  stripe_session_id TEXT UNIQUE,
  payment_method TEXT DEFAULT 'twint_or_card',   -- 'twint', 'card', 'invoice'
  payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN (
    'pending', 'paid', 'shipped', 'completed', 'cancelled'
  )),
  
  customer_name TEXT,
  customer_email TEXT,
  shipping_address JSONB,
  
  items_json JSONB NOT NULL,                     -- Gekaufte Positionen (Werk-ID, SKU, Workshop-Ticket, Einzelpreis)
  subtotal_chf NUMERIC(10, 2) NOT NULL,
  shipping_chf NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
  total_chf NUMERIC(10, 2) NOT NULL,
  
  coa_verification_hash TEXT UNIQUE DEFAULT encode(gen_random_bytes(8), 'hex'),
  physical_bon_printed BOOLEAN NOT NULL DEFAULT false,
  tracking_number TEXT,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_receipt_orders_updated_at ON public.receipt_orders;
CREATE TRIGGER trg_receipt_orders_updated_at
  BEFORE UPDATE ON public.receipt_orders
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================================
-- 9. ROW LEVEL SECURITY (RLS) POLICIES FÜR ALLE TABELLEN
-- ============================================================================

ALTER TABLE public.translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.artworks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workshops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exhibitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_orders ENABLE ROW LEVEL SECURITY;

-- 9.1 Policies für translations (Jeder darf lesen, nur Admin darf schreiben)
DROP POLICY IF EXISTS "Public can read translations" ON public.translations;
CREATE POLICY "Public can read translations"
  ON public.translations FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Admins have full access to translations" ON public.translations;
CREATE POLICY "Admins have full access to translations"
  ON public.translations FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 9.2 Policies für artworks (Öffentlich nur wenn is_published = true)
DROP POLICY IF EXISTS "Public can view published artworks" ON public.artworks;
CREATE POLICY "Public can view published artworks"
  ON public.artworks FOR SELECT
  TO anon, authenticated
  USING (is_published = true AND status <> 'draft');

DROP POLICY IF EXISTS "Admins have full access to artworks" ON public.artworks;
CREATE POLICY "Admins have full access to artworks"
  ON public.artworks FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 9.3 Policies für products
DROP POLICY IF EXISTS "Public can view published products" ON public.products;
CREATE POLICY "Public can view published products"
  ON public.products FOR SELECT
  TO anon, authenticated
  USING (is_published = true);

DROP POLICY IF EXISTS "Admins have full access to products" ON public.products;
CREATE POLICY "Admins have full access to products"
  ON public.products FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 9.4 Policies für workshops
DROP POLICY IF EXISTS "Public can view published workshops" ON public.workshops;
CREATE POLICY "Public can view published workshops"
  ON public.workshops FOR SELECT
  TO anon, authenticated
  USING (is_published = true);

DROP POLICY IF EXISTS "Admins have full access to workshops" ON public.workshops;
CREATE POLICY "Admins have full access to workshops"
  ON public.workshops FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 9.5 Policies für exhibitions
DROP POLICY IF EXISTS "Public can view published exhibitions" ON public.exhibitions;
CREATE POLICY "Public can view published exhibitions"
  ON public.exhibitions FOR SELECT
  TO anon, authenticated
  USING (is_published = true);

DROP POLICY IF EXISTS "Admins have full access to exhibitions" ON public.exhibitions;
CREATE POLICY "Admins have full access to exhibitions"
  ON public.exhibitions FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 9.6 Policies für receipt_orders (Nur Admin sieht alle Bestellungen)
DROP POLICY IF EXISTS "Admins have full access to receipt_orders" ON public.receipt_orders;
CREATE POLICY "Admins have full access to receipt_orders"
  ON public.receipt_orders FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- 10. SUPABASE STORAGE BUCKETS & STORAGE RLS POLICIES
-- ============================================================================

-- Öffentlicher Bucket für 1-Bit-Dither-PNGs & WebP-Vorschaubilder
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'public-artworks',
  'public-artworks',
  true,
  10485760, -- 10 MB Limit pro Datei
  ARRAY['image/png', 'image/webp', 'image/jpeg', 'image/svg+xml']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Privater Bucket für Druck-Master, DIY-Schnittbögen (PDF) und Kassenbon-Zertifikate
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'private-print-masters',
  'private-print-masters',
  false,
  52428800, -- 50 MB Limit pro Datei
  ARRAY['image/tiff', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage RLS: Öffentlicher Lesezugriff auf 'public-artworks'
DROP POLICY IF EXISTS "Public read access for public-artworks" ON storage.objects;
CREATE POLICY "Public read access for public-artworks"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'public-artworks');

-- Storage RLS: Admin Schreib-/Löschzugriff auf 'public-artworks'
DROP POLICY IF EXISTS "Admin full access for public-artworks" ON storage.objects;
CREATE POLICY "Admin full access for public-artworks"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'public-artworks' AND public.is_admin())
  WITH CHECK (bucket_id = 'public-artworks' AND public.is_admin());

-- Storage RLS: Admin Vollzugriff auf 'private-print-masters'
DROP POLICY IF EXISTS "Admin full access for private-print-masters" ON storage.objects;
CREATE POLICY "Admin full access for private-print-masters"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'private-print-masters' AND public.is_admin())
  WITH CHECK (bucket_id = 'private-print-masters' AND public.is_admin());

-- ============================================================================
-- 11. INITIALER SEED-DATENSATZ (TRANSLATIONS, BEISPIEL-WERKE, KITS, WORKSHOPS)
-- ============================================================================

INSERT INTO public.translations (translation_key, namespace, de, en, context_note)
VALUES
  ('terminal.model_name', 'ui', 'TP-652 CONTINUOUS // ATELIER SIMON', 'TP-652 CONTINUOUS // STUDIO SIMON', 'Geräte-Header links'),
  ('terminal.status_ready', 'ui', 'BEREIT // ROLLE EINGEFÄDELT', 'READY // ROLL LOADED', 'OLED Display Status'),
  ('filter.all', 'ui', '00 // ALLE BELEGE', '00 // ALL RECEIPTS', 'Filtertaste 0'),
  ('filter.drawings', 'ui', '01 // FARBSTIFT', '01 // COLORED PENCIL', 'Filtertaste 1'),
  ('filter.cyanotype', 'ui', '02 // CYANOTYPIE', '02 // CYANOTYPE', 'Filtertaste 2'),
  ('filter.pinhole', 'ui', '03 // PINHOLE & SOLAR', '03 // PINHOLE & SOLAR', 'Filtertaste 3'),
  ('filter.kits', 'ui', '04 // DIY-KITS & ZINES', '04 // DIY KITS & ZINES', 'Filtertaste 4'),
  ('filter.workshops', 'ui', '05 // WORKSHOPS & LOG', '05 // WORKSHOPS & LOG', 'Filtertaste 5'),
  ('receipt.develop_btn', 'receipt', '[ ◐ IN ECHTFARBE BELICHTEN ]', '[ ◐ DEVELOP FULL COLOR ]', 'Interaktions-Button auf 1-Bit-Bild'),
  ('receipt.add_to_bon', 'receipt', '[ + AUF DEN BON DRUCKEN ]', '[ + PRINT TO RECEIPT ]', 'Warenkorb-Button'),
  ('receipt.sold_stamp', 'receipt', 'VERGRIFFEN // IM ARCHIV', 'SOLD // ARCHIVED', 'Stempel für verkaufte Werke'),
  ('checkout.tear_and_pay', 'checkout', '[ ✂ BON ABREISSEN & BEZAHLEN (TWINT / KARTE) ]', '[ ✂ TEAR RECEIPT & PAY (TWINT / CARD) ]', 'Checkout CTA')
ON CONFLICT (translation_key) DO NOTHING;

-- Beispiel-Kunstwerke aus Simons Portfolio
INSERT INTO public.artworks (
  artwork_code, slug, title_de, title_en, description_de, category, series_code, series_name,
  medium, paper_type, paper_weight_gsm, dimensions_mm, format_label, framing_status,
  exposure_time, exposure_seconds, uv_source, color_mood, edition_type, edition_size, edition_remaining,
  price_chf, shipping_category, status, image_dither_url, image_color_url, is_published, is_featured, sort_order
)
VALUES
  (
    'K0064',
    'k0064-goldader-im-preussischblau',
    'Goldader im Preussischblau',
    'Gold Vein in Prussian Blue',
    'Organischer Cyanotypie-Sonnendruck, veredelt mit einer feinen Kintsugi-Spur aus 24-karätigem Blattgold.',
    'cyanotype',
    'SER-12',
    'Cyanotypie & Experimentell',
    'Cyanotypie-Sonnendruck mit Kintsugi-Blattgold',
    'Arches Aquarelle Bütten',
    300,
    '148 x 210 mm',
    'A5',
    'unframed',
    '16 Min 40 Sek',
    1000,
    'Alpensonne Luzern (UV-Index 7)',
    'Preussischblau & Feingold',
    'original',
    1,
    1,
    290.00,
    'flat_a5',
    'available',
    '/storage/v1/object/public/public-artworks/artworks/K0064/dither_384.png',
    '/storage/v1/object/public/public-artworks/artworks/K0064/color_feed_800.webp',
    true,
    true,
    100
  ),
  (
    'K0018',
    'k0018-schleife-der-wandlung',
    'Schleife der Wandlung',
    'Loop of Transformation',
    'Dreidimensional geformtes Papierrelief mit dichter Polychromos-Schichtung und echter Blattgold-Auflage.',
    'relief_3d',
    'SER-11',
    '3D-Serie & Relief-Objekte',
    'Geformtes Büttenpapier, Farbstift & Blattgold auf Holzpanel',
    'Hahnemühle Bütten auf Birkenholz',
    350,
    '148 x 210 x 28 mm',
    'A5 Relief',
    'mounted_on_wood',
    NULL,
    NULL,
    NULL,
    'Goldblatt & Tiefschwarz',
    'original',
    1,
    1,
    420.00,
    'flat_a3',
    'available',
    '/storage/v1/object/public/public-artworks/artworks/K0018/dither_384.png',
    '/storage/v1/object/public/public-artworks/artworks/K0018/color_feed_800.webp',
    true,
    true,
    90
  ),
  (
    'SOL-2026-01',
    'sol-2026-01-halbjahresbogen-pilatus',
    'Halbjahresbogen über dem Vierwaldstättersee',
    'Six-Month Solar Arc over Lake Lucerne',
    '182 Tage ununterbrochene Langzeitbelichtung von der Wintersonnenwende bis zur Sommersonnenwende in einer handgefertigten Aluminium-Lochkamera.',
    'solargraphy',
    'SER-SOL',
    'Solargraphie Schweiz (map.solargrafie.ch)',
    'Fine-Art-Pigmentdruck ab Direkt-Papiernegativ',
    'Hahnemühle Photo Rag',
    308,
    '210 x 297 mm',
    'A4 Edition',
    'unframed',
    '182 Tage (21.12.2025 – 21.06.2026)',
    15724800,
    'Direkte Sonnenbahn (Luzern)',
    'Kupferrot, Cyan & Nachtblau',
    'limited_edition',
    10,
    7,
    180.00,
    'flat_a3',
    'available',
    '/storage/v1/object/public/public-artworks/artworks/SOL-2026-01/dither_384.png',
    '/storage/v1/object/public/public-artworks/artworks/SOL-2026-01/color_feed_800.webp',
    true,
    true,
    80
  )
ON CONFLICT (artwork_code) DO NOTHING;

-- Beispiel-DIY-Kit
INSERT INTO public.products (
  sku, slug, title_de, title_en, subtitle_de, description_de, product_type,
  dimensions_mm, weight_grams, difficulty_level, contents_list, technical_specs,
  price_chf, stock_quantity, image_dither_url, image_color_url, is_published, sort_order
)
VALUES
  (
    'KIT-PIN-ORIGAMI',
    'faltbares-origami-lochkamera-kit-a6',
    'Faltbares Origami-Lochkamera-Kit (Modell PK-01)',
    'Foldable Origami Pinhole Camera Kit (Model PK-01)',
    'Komplettes Selbstbau-Set inkl. Präzisions-Lochblende & Fotopapier',
    'Gestanzter, lichtdichter 350g/m² Schwarzkarton im technischen Datenblatt-Design. Ohne Klebstoff in 15 Minuten faltbar. Inklusive Zugangscode für den Upload auf map.solargrafie.ch.',
    'diy_camera_kit',
    '148 x 210 x 8 mm (Flachpackung)',
    180,
    'Einsteiger & Fortgeschrittene (Ohne Dunkelkammer nutzbar im Solargraphie-Modus)',
    ARRAY[
      '1x Vorgestanzter Faltbogen (350 g/m² Lichtschutz-Karton)',
      '1x Laser-gebohrte Messing-Lochblende (0.22 mm / f/159)',
      '6x Blatt Ilford Multigrade RC Fotopapier in Lichtschutz-Beutel',
      '1x Technische Falt- & Belichtungstabelle auf Thermopapier',
      '1x QR-Upload-Token für map.solargrafie.ch'
    ],
    '{"aperture_mm": 0.22, "focal_length_mm": 35, "f_stop": "f/159", "negative_size": "A6 (105x148mm)"}'::JSONB,
    45.00,
    25,
    '/storage/v1/object/public/public-artworks/products/KIT-PIN-ORIGAMI/dither_384.png',
    '/storage/v1/object/public/public-artworks/products/KIT-PIN-ORIGAMI/color_feed_800.webp',
    true,
    10
  )
ON CONFLICT (sku) DO NOTHING;

-- Beispiel-Workshop
INSERT INTO public.workshops (
  workshop_code, slug, title_de, subtitle_de, description_de, workshop_topic,
  location_city, location_venue, start_time, end_time, duration_hours,
  max_participants, seats_remaining, price_chf, materials_included, status, is_published
)
VALUES
  (
    'WS-LU-2026-CYA',
    'cyanotypie-im-freien-luzern',
    'LABOR 01 // Cyanotypie & Sonnendruck im Freien',
    'Analoge Edeldruckverfahren mit UV-Licht, Pflanzen & Negativen (4 Std.)',
    'Wir mischen die historische Eisen-Chemie von 1842 selbst an, beschichten schweres Aquarell-Büttenpapier und belichten in der Sonne eigene grossformatige Preussischblau-Unikate.',
    'cyanotype_outdoor',
    'Luzern',
    'Atelier & Werkhof Raum Luzern',
    '2026-05-16 13:30:00+02',
    '2026-05-16 17:30:00+02',
    4.0,
    8,
    5,
    165.00,
    ARRAY[
      'Sämtliche Rohchemikalien & Schutzmaterial',
      '5 Bögen Arches / Hahnemühle Büttenpapier (A5 bis A3)',
      'Digitale Negativ-Aufbereitung für 1 eigenes Foto vorab',
      '100ml angesetzte Cyanotypie-Lösung für zuhause',
      'Gedrucktes Rezept-Zine & Atelier-Kaffee'
    ],
    'open',
    true
  )
ON CONFLICT (workshop_code) DO NOTHING;
