import Foundation
import Supabase

// Single shared Supabase client for the entire app
let supabase = SupabaseClient(
    supabaseURL: Constants.Supabase.url,
    supabaseKey: Constants.Supabase.anonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            // Opt in to the new behavior: always emit the locally stored session
            // as the initial session (avoids the deprecation warning from the SDK).
            emitLocalSessionAsInitialSession: true
        )
    )
)
