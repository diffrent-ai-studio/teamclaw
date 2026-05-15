import SwiftUI
import SwiftData
import AMUXCore

public struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: SessionListViewModel
    let teamclawService: TeamclawService
    let targetDeviceID: String

    public init(viewModel: SessionListViewModel, teamclawService: TeamclawService, targetDeviceID: String) {
        self.viewModel = viewModel
        self.teamclawService = teamclawService
        self.targetDeviceID = targetDeviceID
    }

    public var body: some View {
        NavigationStack {
            WorkspaceManagementView(viewModel: viewModel, teamclawService: teamclawService, targetDeviceID: targetDeviceID)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.title3).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
        }
    }
}
