import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://fqnsmvkxsuujahhmpzuk.supabase.co'
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZxbnNtdmt4c3V1amFoaG1wenVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg1NTE1ODUsImV4cCI6MjA5NDEyNzU4NX0.bF8MzHJXpIja7I5sMV58tLulTlZgiscNsTwGQ9DhjzE'

export const supabase = createClient(supabaseUrl, supabaseKey)
