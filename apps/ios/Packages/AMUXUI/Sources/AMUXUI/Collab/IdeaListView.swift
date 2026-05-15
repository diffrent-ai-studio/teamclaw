import SwiftUI
import SwiftData
import AMUXCore

public struct IdeaListView: View {
    @Bindable var ideaStore: IdeaStore

    @Query(filter: #Predicate<CachedActor> { $0.actorType == "member" },
           sort: \CachedActor.displayName)
    private var members: [CachedActor]

    @Query(sort: \Workspace.displayName) private var workspaces: [Workspace]

    private var memberById: [String: CachedActor] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.actorId, $0) })
    }

    private var workspaceNameById: [String: String] {
        Dictionary(uniqueKeysWithValues: workspaces.map { ($0.workspaceId, $0.displayName) })
    }

    @Binding var showCreate: Bool
    @State private var showArchived = false

    public init(ideaStore: IdeaStore, showCreate: Binding<Bool>) {
        self.ideaStore = ideaStore
        self._showCreate = showCreate
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = ideaStore.errorMessage, ideaStore.ideas.isEmpty, !ideaStore.isLoading {
                ContentUnavailableView(
                    "Couldn’t Load Ideas",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if ideaStore.isLoading && ideaStore.ideas.isEmpty {
                ProgressView("Loading ideas…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ideaStore.ideas.isEmpty {
                ContentUnavailableView(
                    "No Ideas",
                    systemImage: IdeaUIPresentation.systemImage,
                    description: Text("Tap + to create an idea")
                )
            } else {
                List {
                    ForEach(ideaStore.ideas) { item in
                        NavigationLink(value: "idea:\(item.id)") {
                            IdeaRow(
                                item: item,
                                creator: memberById[item.createdByActorID],
                                workspaceName: workspaceNameById[item.workspaceID]
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await ideaStore.setArchived(ideaID: item.id, archived: true) }
                            } label: {
                                Label("Archive", systemImage: "archivebox.fill")
                            }
                            .tint(.gray)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await ideaStore.reload()
                }
            }
        }
        .navigationTitle(IdeaUIPresentation.pluralTitle)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            if !ideaStore.archivedIdeas.isEmpty {
                Button {
                    showArchived = true
                } label: {
                    HStack {
                        Image(systemName: "archivebox")
                        Text("Archived (\(ideaStore.archivedIdeas.count))")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateIdeaSheet(ideaStore: ideaStore) { }
        }
        .sheet(isPresented: $showArchived) {
            ArchivedIdeasView(ideaStore: ideaStore)
        }
    }

}
