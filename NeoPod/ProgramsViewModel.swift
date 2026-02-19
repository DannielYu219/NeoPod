import Foundation
import SwiftUI
internal import Combine

@MainActor
class ProgramsViewModel: ObservableObject {
    @Published var htmlFiles: [HTMLFileInfo] = []
    @Published var selectedFile: HTMLFileInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showErrorAlert = false
    @Published var showUninstallConfirm = false
    @Published var appToUninstall: HTMLFileInfo?
    @Published var uninstallingAppId: String?
    
    func loadHTMLFiles() {
        isLoading = true
        errorMessage = nil
        
        let files = FileSystemManager.htmlFilesInDevAndProgramFolders()
        
        withAnimation(.easeOut(duration: 0.28)) {
            self.htmlFiles = files
            self.isLoading = false
        }
    }
    
    func selectFile(_ file: HTMLFileInfo) {
        withAnimation(.easeOut(duration: 0.28)) {
            self.selectedFile = file
        }
    }
    
    func clearSelection() {
        withAnimation(.easeOut(duration: 0.28)) {
            self.selectedFile = nil
        }
    }
    
    func requestUninstall(_ file: HTMLFileInfo) {
        print("[ProgramsViewModel] requestUninstall called for: \(file.displayName), folder: \(file.folder)")
        guard file.folder == "program" else {
            print("[ProgramsViewModel] Cannot uninstall - not a program folder")
            return
        }
        appToUninstall = file
        showUninstallConfirm = true
        print("[ProgramsViewModel] Showing uninstall confirmation dialog")
    }
    
    func confirmUninstall() {
        guard let file = appToUninstall else {
            print("[ProgramsViewModel] confirmUninstall: no appToUninstall")
            showError("No app selected for uninstall")
            return
        }

        let appId = extractAppId(from: file)
        print("[ProgramsViewModel] confirmUninstall: appId=\(appId), file.id=\(file.id)")
        uninstallingAppId = file.id
        showUninstallConfirm = false

        Task { [weak self] in
            guard let self = self else {
                print("[ProgramsViewModel] Task: self is nil")
                return
            }
            
            print("[ProgramsViewModel] Task: Starting uninstall for appId: \(appId)")
            
            do {
                try await StoreAPI.shared.uninstallApp(appId: appId)
                print("[ProgramsViewModel] Task: Uninstall succeeded")

                await MainActor.run {
                    self.uninstallingAppId = nil
                    self.appToUninstall = nil
                    self.loadHTMLFiles()
                    print("[ProgramsViewModel] Task: UI updated after successful uninstall")
                }
            } catch {
                print("[ProgramsViewModel] Task: Uninstall failed with error: \(error)")
                let errorMsg = "Failed to uninstall \(appId): \(error.localizedDescription)"
                await MainActor.run {
                    self.showError(errorMsg)
                    self.uninstallingAppId = nil
                    self.appToUninstall = nil
                }
            }
        }
    }
    
    private func extractAppId(from file: HTMLFileInfo) -> String {
        let pathComponents = file.name.split(separator: "/")
        let appId = pathComponents.first.map(String.init) ?? file.displayName
        print("[ProgramsViewModel] extractAppId: '\(file.name)' -> '\(appId)'")
        return appId
    }
    
    private func showError(_ message: String) {
        print("[ProgramsViewModel] showError: \(message)")
        errorMessage = message
        showErrorAlert = true
    }
}
