-- Storage bucket for receipt photos.
-- Apply AFTER 20260101000002_rls.sql.
--
-- Each receipt is uploaded to:    receipts/<user_id>/<expense_id>.<ext>
-- The path prefix gates ownership: a supervisor can only put/get/delete files
-- under their own user_id; admins can do anything.

-- Create the bucket (private — clients use createSignedUrl to view)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'receipts',
    'receipts',
    false,
    5 * 1024 * 1024,   -- 5 MB max per file (a phone photo, compressed)
    array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do update set
    public            = excluded.public,
    file_size_limit   = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- ============================================================================
-- RLS policies on storage.objects scoped to the receipts bucket.
-- ============================================================================
drop policy if exists receipts_select on storage.objects;
create policy receipts_select on storage.objects
    for select to authenticated
    using (
        bucket_id = 'receipts'
        and (
            public.is_admin(auth.uid())
            or (storage.foldername(name))[1] = auth.uid()::text
        )
    );

drop policy if exists receipts_insert on storage.objects;
create policy receipts_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'receipts'
        and (
            public.is_admin(auth.uid())
            or (storage.foldername(name))[1] = auth.uid()::text
        )
    );

drop policy if exists receipts_update on storage.objects;
create policy receipts_update on storage.objects
    for update to authenticated
    using (
        bucket_id = 'receipts'
        and (
            public.is_admin(auth.uid())
            or (storage.foldername(name))[1] = auth.uid()::text
        )
    );

drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'receipts'
        and (
            public.is_admin(auth.uid())
            or (storage.foldername(name))[1] = auth.uid()::text
        )
    );
