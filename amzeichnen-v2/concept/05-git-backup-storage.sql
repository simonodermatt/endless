-- ============================================================================
-- AMZEICHNEN.CH – SUPABASE STORAGE BUCKET FÜR TÄGLICHE GITHUB-BACKUPS
-- Ausführung: Optional im Supabase SQL-Editor (wird ansonsten auch automatisch
-- vom GitHub Actions Workflow über den Service-Role-Key angelegt)
-- ============================================================================

-- 1. Privaten Storage Bucket 'git-backups' erstellen
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'git-backups',
  'git-backups',
  false,       -- Privat: Nur über Service-Role-Key (GitHub Action) oder eingeloggten Admin lesbar
  52428800,    -- 50 MB Limit pro Backup-Archiv
  NULL         -- Erlaubt .bundle, .tar.gz und .json Dateien
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- 2. RLS Policy: Eingeloggte Admins dürfen die Git-Backups im Dashboard / Admin herunterladen
DROP POLICY IF EXISTS "Admin full access for git-backups" ON storage.objects;
CREATE POLICY "Admin full access for git-backups"
  ON storage.objects FOR ALL
  TO authenticated
  USING (bucket_id = 'git-backups' AND public.is_admin())
  WITH CHECK (bucket_id = 'git-backups' AND public.is_admin());
