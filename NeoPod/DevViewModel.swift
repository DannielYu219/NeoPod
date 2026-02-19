import Foundation
import SwiftUI
internal import Combine

@MainActor
class DevViewModel: ObservableObject {
    @Published var htmlFiles: [HTMLFileInfo] = []
    @Published var selectedFile: HTMLFileInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
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
        guard file.folder == "program" else { return }
        appToUninstall = file
        showUninstallConfirm = true
    }
    
    func confirmUninstall() {
        guard let file = appToUninstall else { return }
        
        uninstallingAppId = file.id
        
        Task {
            do {
                let appId = extractAppId(from: file)
                try await StoreAPI.shared.uninstallApp(appId: appId)
                
                await MainActor.run {
                    uninstallingAppId = nil
                    appToUninstall = nil
                    loadHTMLFiles()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to uninstall: \(error.localizedDescription)"
                    uninstallingAppId = nil
                    appToUninstall = nil
                }
            }
        }
    }
    
    private func extractAppId(from file: HTMLFileInfo) -> String {
        let pathComponents = file.name.split(separator: "/")
        return pathComponents.first.map(String.init) ?? file.displayName
    }
}