-- Create attachments bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'attachments',
  'attachments',
  false,
  52428800,  -- 50MB in bytes
  ARRAY[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'application/pdf',
    'text/plain', 'text/markdown', 'text/csv',
    'application/json',
    'text/x-swift', 'text/x-python', 'text/x-javascript',
    'application/zip',
    'application/octet-stream'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- RLS: SELECT (download) — user must be session member
CREATE POLICY "session_members_can_download"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'attachments'
  AND auth.uid() IN (
    SELECT DISTINCT sm.user_id
    FROM public.session_members sm
    WHERE sm.session_id = SPLIT_PART(name, '/', 2)
  )
);

-- RLS: INSERT (upload) — authenticated users
CREATE POLICY "authenticated_can_upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'attachments'
);

-- RLS: DELETE — deny all (cleanup via backend task)
CREATE POLICY "no_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (false);
