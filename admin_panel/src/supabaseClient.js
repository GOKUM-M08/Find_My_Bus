import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://mardeektaxigbxlckwzv.supabase.co'
const supabaseKey = 'sb_publishable_4JqOykRfsu6xjCQ3KegCbw_oVfEj5DK'

export const supabase = createClient(supabaseUrl, supabaseKey)