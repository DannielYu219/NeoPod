import Foundation
import SwiftUI
internal import Combine

@MainActor
class DevViewModel: ObservableObject {
    @Published var htmlFiles: [HTMLFileInfo] = []
    @Published var selectedFile: HTMLFileInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func loadHTMLFiles() {
        isLoading = true
        errorMessage = nil
        
        let files = FileSystemManager.htmlFilesInDevFolder()
        
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
}
