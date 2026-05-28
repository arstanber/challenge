import Foundation
import Supabase

// Single shared Supabase client for the entire app
let supabase = SupabaseClient(
    supabaseURL: Constants.Supabase.url,
    supabaseKey: Constants.Supabase.anonKey
)
