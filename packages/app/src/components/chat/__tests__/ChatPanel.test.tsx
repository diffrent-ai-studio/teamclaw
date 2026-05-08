import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fireEvent, render, waitFor } from '@testing-library/react';

// ── Browser API polyfills ──────────────────────────────────────────────

// jsdom does not implement ResizeObserver; provide a no-op stub
global.ResizeObserver = class ResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
};

if (!HTMLElement.prototype.scrollTo) {
  HTMLElement.prototype.scrollTo = () => {};
}

// ── Mocks ──────────────────────────────────────────────────────────────

vi.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key: string, fallback?: string) => fallback ?? key,
  }),
  initReactI18next: { type: '3rdParty', init: () => {} },
}));

vi.mock('@/lib/i18n', () => ({
  default: { t: (key: string) => key },
}));

vi.mock('@tauri-apps/plugin-fs', () => ({
  readFile: vi.fn(),
  mkdir: vi.fn(),
  writeFile: vi.fn(),
}));

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

vi.mock('@tauri-apps/api/event', () => ({
  listen: vi.fn(() => Promise.resolve(() => {})),
}));

vi.mock('@tauri-apps/api/window', () => ({
  getCurrentWindow: vi.fn(() => ({ setFocus: vi.fn() })),
}));

// Mock Supabase-backed actor components to prevent module evaluation errors
// and avoid render-loop issues with the real Supabase client in test env.
vi.mock('../ActorChatInput', () => ({
  ActorChatInput: vi.fn(() => null),
}));
vi.mock('../ActorMessageList', () => ({
  ActorMessageList: vi.fn(() => null),
}));
vi.mock('@/lib/supabase-client', () => ({
  supabase: {
    channel: vi.fn(() => ({ on: vi.fn().mockReturnThis(), subscribe: vi.fn().mockReturnThis(), unsubscribe: vi.fn() })),
    from: vi.fn(() => ({ select: vi.fn().mockReturnThis(), order: vi.fn().mockReturnThis(), limit: vi.fn().mockResolvedValue({ data: [], error: null }) })),
    auth: { getUser: vi.fn().mockResolvedValue({ data: { user: null }, error: null }) },
  },
}));

// Session store state — mutated per test
const sessionState = {
  activeSessionId: null as string | null,
  viewingChildSessionId: null as string | null,
  childSessionMessages: {} as Record<string, unknown[]>,
  isLoadingChildMessages: false,
  archivedSessions: [] as Array<{
    id: string;
    title: string;
    messages: unknown[];
    createdAt: Date;
    updatedAt: Date;
    directory?: string;
    isArchived?: boolean;
    archivedAt?: Date;
  }>,
  viewingArchivedSessionId: null as string | null,
  archivedSessionMessages: {} as Record<string, unknown[]>,
  archivedSessionError: null as string | null,
  isLoadingArchivedSessions: false,
  sessions: [] as unknown[],
  error: null as string | null,
  isConnected: true,
  messageQueue: [] as unknown[],
  sessionError: null,
  inactivityWarning: false,
  draftInput: '',
  isLoading: false,
  pendingPermissions: [],
  pendingQuestions: [],
  todos: [],
  sessionDiff: [],
  sessionStatus: null,
  highlightedSessionIds: [],
  isLoadingMore: false,
  hasMoreSessions: false,
  visibleSessionCount: 50,
  selectedModel: null,
  sendMessage: vi.fn(),
  abortSession: vi.fn(),
  removeFromQueue: vi.fn(),
  loadSessions: vi.fn(() => Promise.resolve()),
  resetSessions: vi.fn(),
  clearSessionError: vi.fn(),
  setError: vi.fn(),
  setSelectedModel: vi.fn(),
  setDraftInput: vi.fn(),
  pollPermissions: vi.fn(),
  createSession: vi.fn(),
  setActiveSession: vi.fn(),
  setViewingChildSession: vi.fn(),
  archiveSession: vi.fn(),
  closeArchivedSession: vi.fn(),
  restoreSession: vi.fn(() => Promise.resolve()),
  updateSessionTitle: vi.fn(),
  loadMoreSessions: vi.fn(),
  replyPermission: vi.fn(),
  answerQuestion: vi.fn(),
};

vi.mock('@/stores/session', () => {
  const useSessionStore = (selector: (s: typeof sessionState) => unknown) =>
    selector(sessionState);
  Object.assign(useSessionStore, {
    getState: () => sessionState,
    setState: (partial: Partial<typeof sessionState>) => Object.assign(sessionState, partial),
  });
  return {
    useSessionStore,
    sessionLookupCache: new Map(),
    getSessionById: vi.fn(() => null),
  };
});

const streamingState = {
  streamingMessageId: null as string | null,
  streamingContent: '',
  streamingUpdateTrigger: 0,
  childSessionStreaming: {} as Record<string, unknown>,
};

vi.mock('@/stores/streaming', () => {
  const useStreamingStore = (selector: (s: typeof streamingState) => unknown) =>
    selector(streamingState);
  Object.assign(useStreamingStore, {
    getState: () => streamingState,
    setState: (partial: Partial<typeof streamingState>) => Object.assign(streamingState, partial),
  });
  return { useStreamingStore };
});

const workspaceState = {
  workspacePath: '/test/workspace',
  openCodeReady: true,
};

vi.mock('@/stores/workspace', () => {
  const useWorkspaceStore = (selector: (s: typeof workspaceState) => unknown) =>
    selector(workspaceState);
  Object.assign(useWorkspaceStore, {
    getState: () => workspaceState,
    setState: (partial: Partial<typeof workspaceState>) => Object.assign(workspaceState, partial),
  });
  return { useWorkspaceStore };
});

const providerState = {
  models: [] as unknown[],
  configuredProvidersLoading: false,
  currentModelKey: null as string | null,
  initAll: vi.fn(),
};

vi.mock('@/stores/provider', () => {
  const useProviderStore = (selector: (s: typeof providerState) => unknown) =>
    selector(providerState);
  Object.assign(useProviderStore, {
    getState: () => providerState,
    setState: vi.fn(),
  });
  return {
    useProviderStore,
    getSelectedModelOption: () => null,
  };
});

const teamModeState = {
  teamMode: false,
  teamModelConfig: null,
  loadTeamConfig: vi.fn(() => Promise.resolve()),
  applyTeamModelToOpenCode: vi.fn(() => Promise.resolve()),
};

vi.mock('@/stores/team-mode', () => {
  const useTeamModeStore = (selector: (s: typeof teamModeState) => unknown) =>
    selector(teamModeState);
  Object.assign(useTeamModeStore, {
    getState: () => teamModeState,
    setState: vi.fn(),
  });
  return { useTeamModeStore };
});

const voiceInputState = {
  registerInsertToChatHandler: vi.fn(() => () => {}),
};

vi.mock('@/stores/voice-input', () => {
  const useVoiceInputStore = (selector: (s: typeof voiceInputState) => unknown) =>
    selector(voiceInputState);
  Object.assign(useVoiceInputStore, {
    getState: () => voiceInputState,
    setState: vi.fn(),
  });
  return { useVoiceInputStore };
});

vi.mock('@/stores/suggestions', () => ({
  useSuggestionsStore: (selector: (s: { customSuggestions: string[] }) => unknown) =>
    selector({ customSuggestions: [] }),
}));

vi.mock('@/lib/opencode/sdk-client', () => ({
  getOpenCodeClient: () => ({
    executeCommand: vi.fn(),
  }),
}));

// ── Import component after mocks ───────────────────────────────────────

import { ChatPanel } from '../ChatPanel';

// ── Tests ──────────────────────────────────────────────────────────────

describe('ChatPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessionState.activeSessionId = null;
    sessionState.viewingChildSessionId = null;
    sessionState.childSessionMessages = {};
    sessionState.isLoadingChildMessages = false;
    sessionState.archivedSessions = [];
    sessionState.viewingArchivedSessionId = null;
    sessionState.archivedSessionMessages = {};
    sessionState.archivedSessionError = null;
    sessionState.isLoadingArchivedSessions = false;
    sessionState.isConnected = true;
    sessionState.error = null;
    sessionState.sessionError = null;
    sessionState.draftInput = '';
    sessionState.messageQueue = [];
    sessionState.sessions = [];
    streamingState.streamingMessageId = null;
    streamingState.childSessionStreaming = {};
    workspaceState.openCodeReady = true;
    voiceInputState.registerInsertToChatHandler = vi.fn(() => () => {});
    sessionState.loadSessions = vi.fn(() => Promise.resolve());
    sessionState.resetSessions = vi.fn();
    sessionState.clearSessionError = vi.fn();
    sessionState.setError = vi.fn();
    sessionState.setSelectedModel = vi.fn();
    sessionState.setDraftInput = vi.fn();
    sessionState.pollPermissions = vi.fn();
    sessionState.setViewingChildSession = vi.fn();
    sessionState.closeArchivedSession = vi.fn();
    sessionState.restoreSession = vi.fn(() => Promise.resolve());
    providerState.initAll = vi.fn();
    teamModeState.loadTeamConfig = vi.fn(() => Promise.resolve());
    teamModeState.applyTeamModelToOpenCode = vi.fn(() => Promise.resolve());
  });

  it('renders child components when session is active', () => {
    sessionState.activeSessionId = 'sess-1';
    sessionState.sessions = [
      { id: 'sess-1', title: 'Test session', messages: [], createdAt: new Date(), updatedAt: new Date() },
    ];

    const { container } = render(<ChatPanel />);
    expect(container.children.length).toBeGreaterThan(0);
    expect(container.firstChild).not.toBeNull();
  });

  it('does not render the transient connection badge inside the message area', () => {
    sessionState.isConnected = false;
    sessionState.activeSessionId = 'sess-1';

    const { container } = render(<ChatPanel />);
    expect(container.textContent).not.toContain('Connecting');
  });

  it('renders streaming child session content before child messages finish loading', () => {
    // Phase 1E/v2: ActorMessageList handles child session rendering via Supabase.
    // The "Back to main session" navigation bar is still rendered by ChatPanel.
    sessionState.activeSessionId = 'sess-parent';
    sessionState.viewingChildSessionId = 'child-1';
    sessionState.childSessionMessages = {
      'child-1': [],
    };
    streamingState.childSessionStreaming = {
      'child-1': {
        sessionId: 'child-1',
        text: 'Child stream in progress',
        reasoning: '',
        isStreaming: true,
      },
    };

    const { container } = render(<ChatPanel />);

    // Navigation bar is still rendered by ChatPanel itself
    expect(container.textContent).toContain('Back to main session');
    // Message content is now rendered by ActorMessageList (mocked to null in tests)
  });

  it('renders archived messages in read-only mode', () => {
    // Phase 1E/v2: ActorMessageList handles archived session rendering via Supabase.
    // ChatPanel still renders the archived session navigation bar.
    sessionState.viewingArchivedSessionId = 'archived-1';
    sessionState.archivedSessions = [
      {
        id: 'archived-1',
        title: 'Archived Todo Chat',
        messages: [],
        createdAt: new Date('2026-05-01T10:00:00.000Z'),
        updatedAt: new Date('2026-05-01T11:00:00.000Z'),
        isArchived: true,
        archivedAt: new Date('2026-05-02T10:00:00.000Z'),
      },
    ];
    sessionState.archivedSessionMessages = {
      'archived-1': [
        {
          id: 'msg-1',
          sessionId: 'archived-1',
          role: 'user',
          content: 'Archived hello',
          parts: [],
          timestamp: new Date('2026-05-01T10:05:00.000Z'),
        },
      ],
    };

    const { container } = render(<ChatPanel />);

    expect(container.textContent).toContain('Archived Todo Chat');
    expect(container.textContent).toContain('Restore');
    // Message content (Archived hello) is rendered by ActorMessageList (mocked to null in tests)
  });

  it('prioritizes archived view over child session view', () => {
    sessionState.viewingArchivedSessionId = 'archived-1';
    sessionState.viewingChildSessionId = 'child-1';
    sessionState.archivedSessions = [
      {
        id: 'archived-1',
        title: 'Archived Todo Chat',
        messages: [],
        createdAt: new Date(),
        updatedAt: new Date(),
        isArchived: true,
        archivedAt: new Date(),
      },
    ];
    sessionState.archivedSessionMessages = {
      'archived-1': [
        {
          id: 'archived-msg',
          sessionId: 'archived-1',
          role: 'user',
          content: 'Archived message wins',
          parts: [],
          timestamp: new Date(),
        },
      ],
    };
    sessionState.childSessionMessages = {
      'child-1': [
        {
          id: 'child-msg',
          sessionId: 'child-1',
          role: 'assistant',
          content: 'Child message should be hidden',
          parts: [],
          timestamp: new Date(),
        },
      ],
    };
    streamingState.childSessionStreaming = {
      'child-1': {
        sessionId: 'child-1',
        text: 'Child stream should be hidden',
        reasoning: '',
        isStreaming: true,
      },
    };

    const { container, getByText } = render(<ChatPanel />);

    expect(container.textContent).toContain('Archived Todo Chat');
    // Archived message content is rendered by ActorMessageList (mocked to null in tests)
    // Child session bars should not be shown when viewing an archived session
    expect(container.textContent).not.toContain('Back to main session');
    expect(container.textContent).not.toContain('Sub-agent');

    fireEvent.click(getByText('Back to active session'));

    expect(sessionState.closeArchivedSession).toHaveBeenCalled();
    expect(sessionState.setViewingChildSession).toHaveBeenCalledWith(null);
  });

  it('restores archived session from the read-only bar', async () => {
    sessionState.viewingArchivedSessionId = 'archived-1';
    sessionState.archivedSessions = [
      {
        id: 'archived-1',
        title: 'Archived Todo Chat',
        messages: [],
        createdAt: new Date(),
        updatedAt: new Date(),
        isArchived: true,
        archivedAt: new Date(),
      },
    ];

    const { findByText } = render(<ChatPanel />);

    fireEvent.click(await findByText('Restore'));

    await waitFor(() => {
      expect(sessionState.restoreSession).toHaveBeenCalledWith('archived-1');
    });
  });

  it('shows archived session navigation bar with title when viewing an archived session', () => {
    // Phase 1E/v2: Error display from archivedSessionError is no longer rendered
    // by ChatPanel directly — error handling is managed by ActorMessageList.
    // This test verifies the archived navigation bar is still shown.
    sessionState.viewingArchivedSessionId = 'archived-1';
    sessionState.archivedSessionError = 'OpenCode API Error: unavailable';
    sessionState.archivedSessions = [
      {
        id: 'archived-1',
        title: 'Archived Todo Chat',
        messages: [],
        createdAt: new Date(),
        updatedAt: new Date(),
        isArchived: true,
        archivedAt: new Date(),
      },
    ];

    const { container } = render(<ChatPanel />);

    expect(container.textContent).toContain('Archived Todo Chat');
    expect(container.textContent).toContain('Restore');
  });

  it('ignores duplicate restore clicks while restore is pending', async () => {
    let resolveRestore: () => void = () => {};
    sessionState.restoreSession = vi.fn(
      () =>
        new Promise<void>((resolve) => {
          resolveRestore = resolve;
        }),
    );
    sessionState.viewingArchivedSessionId = 'archived-1';
    sessionState.archivedSessions = [
      {
        id: 'archived-1',
        title: 'Archived Todo Chat',
        messages: [],
        createdAt: new Date(),
        updatedAt: new Date(),
        isArchived: true,
        archivedAt: new Date(),
      },
    ];

    const { findByRole } = render(<ChatPanel />);
    const restoreButton = await findByRole('button', { name: /restore/i });

    fireEvent.click(restoreButton);
    fireEvent.click(restoreButton);

    expect(sessionState.restoreSession).toHaveBeenCalledTimes(1);
    expect((restoreButton as HTMLButtonElement).disabled).toBe(true);

    resolveRestore();
    await waitFor(() => {
      expect((restoreButton as HTMLButtonElement).disabled).toBe(false);
    });
  });
});
