import os
from supabase import create_client

supabase_url = 'https://mardeektaxigbxlckwzv.supabase.co'
supabase_key = 'sb_publishable_4JqOykRfsu6xjCQ3KegCbw_oVfEj5DK'

supabase = create_client(supabase_url, supabase_key)

school_id = '02467563-d81a-4fb3-a426-66c0a37e3dff'

print("Testing admin_audit_logs table...")
try:
    # 1. Insert test audit log
    insert_res = supabase.table('admin_audit_logs').insert({
        'school_id': school_id,
        'admin_email': 'admin_test@school.edu',
        'action_type': 'VERIFY_AUDIT_LOG',
        'target_entity': 'test_suite',
        'target_id': 'test-123',
        'details': 'Verification of audit log creation and read capability.',
    }).execute()
    print("Insert result:", insert_res.data)

    # 2. Select recent audit logs
    select_res = supabase.table('admin_audit_logs').select('*').eq('school_id', school_id).order('created_at', desc=True).limit(5).execute()
    print("Read audit logs count:", len(select_res.data))
    for log in select_res.data:
        print(f" - [{log['created_at']}] {log['admin_email']} | {log['action_type']} | {log['details']}")
except Exception as e:
    print("Audit log verification error:", e)
