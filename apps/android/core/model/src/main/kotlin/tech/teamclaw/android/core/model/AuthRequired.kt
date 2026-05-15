package tech.teamclaw.android.core.model

/** Thrown by OnboardingStore.ensureSession() when no Supabase session exists. */
class AuthRequired : RuntimeException("Not authenticated")
