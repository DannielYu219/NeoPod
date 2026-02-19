import Foundation
import SwiftUI
internal import Combine

@MainActor
class ProgramsViewModel: ObservableObject {
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

        let appId = extractAppId(from: file)
        guard let appFolderURL = FileSystemManager.programFolderURL()?.appendingPathComponent(appId, isDirectory: true) else {
            errorMessage = "Failed to get app folder URL"
            appToUninstall = nil
            return
        }

        uninstallingAppId = file.id

        Task { [weak self] in
            guard let self = self else { return }
            do {
                if FileManager.default.fileExists(atPath: appFolderURL.path) {
                    try await self.removeItemOffMainThread(at: appFolderURL)
                } else {
                    print("App folder not found for \(appId) at \(appFolderURL.path)")
                    throw StoreError.installFailed
                }

                await MainActor.run {
                    self.uninstallingAppId = nil
                    self.appToUninstall = nil
                    self.loadHTMLFiles()
                }
            } catch {
                print("Uninstall failed: \(error)")
                await MainActor.run {
                    self.errorMessage = "Failed to uninstall: \(error.localizedDescription)"
                    self.uninstallingAppId = nil
                    self.appToUninstall = nil
                }
            }
        }
    }
    
    private func extractAppId(from file: HTMLFileInfo) -> String {
        let pathComponents = file.name.split(separator: "/")
        let appId = pathComponents.first.map(String.init) ?? file.displayName
        print("Extracting appId from '\(file.name)' -> '\(appId)'")
        return appId
    }

    private func removeItemOffMainThread(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.removeItem(at: url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
