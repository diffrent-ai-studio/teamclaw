import { useEffect } from "react";
import { useAuthStore } from "@/stores/auth-store";
import { LoginScreen } from "./LoginScreen";
import { LobsterLoader } from "./LobsterLoader";

interface AuthGateProps {
  children: React.ReactNode;
}

export function AuthGate({ children }: AuthGateProps) {
  const { session, loading, hydrate } = useAuthStore();

  useEffect(() => {
    hydrate();
  }, [hydrate]);

  useEffect(() => {
    document.getElementById("skeleton")?.remove();
  }, []);

  if (loading && !session) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-5 bg-background">
        <LobsterLoader size={120} />
        <p className="text-[13px] text-muted-foreground">Loading…</p>
      </div>
    );
  }

  if (!session) {
    return <LoginScreen />;
  }

  return <>{children}</>;
}
