import SwiftUI

// 用于在弹窗和逻辑之间传递信息
struct FileInstallInfo {
    let sourceURL: URL
    let fileName: String
}

// 用于显示"关于"信息的视图
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // 使用 NSApplication 获取应用图标
            if let nsImage = NSApplication.shared.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .frame(width: 80, height: 80)
            }
            
            VStack {
                Text("Outstaller")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 0.0.1")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Link("GitHub Repo", destination: URL(string: "https://github.com/neeeeeeeeeeee/Outstaller")!)
                .font(.body)
            
            Spacer()
            
            Text("Licensed under the MIT License")
                .font(.footnote)
                .foregroundColor(.secondary)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(minWidth: 300, idealWidth: 350, minHeight: 320)
    }
}

// 安装进度视图
struct InstallProgressView: View {
    let progress: InstallProgress
    
    var body: some View {
        VStack(spacing: 16) {
            // 进度条
            VStack(spacing: 8) {
                HStack {
                    Text(progress.currentOperation)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(Int(progress.progressPercentage * 100))%")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: progress.progressPercentage, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
            
            // 详细信息
            VStack(spacing: 4) {
                HStack {
                    Text("progress_size_label")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(progress.formattedProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if progress.speed > 0 {
                    HStack {
                        Text("progress_speed_label")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(progress.formattedSpeed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("progress_time_remaining_label")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(progress.formattedTimeRemaining)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct ContentView: View {
    @State private var statusText: LocalizedStringKey = "drop_prompt"
    @AppStorage("installPath") private var installPath: String = ""
    
    // 安装进度相关状态
    @State private var isInstalling = false
    @State private var installProgress: InstallProgress?
    
    // 用于管理"覆盖"确认弹窗的状态
    @State private var showingOverwriteAlert = false
    @State private var installInfo: FileInstallInfo?
    
    // 用于控制"关于"窗口显示的状态
    @State private var showingAboutSheet = false

    var body: some View {
        VStack(spacing: 20) {
            if isInstalling, let progress = installProgress {
                // 显示进度界面
                VStack(spacing: 20) {
                    Image(systemName: "gear.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)
                        .rotationEffect(.degrees(progress.progressPercentage * 360))
                        .animation(.easeInOut(duration: 0.5), value: progress.progressPercentage)
                    
                    InstallProgressView(progress: progress)
                        .frame(maxWidth: 300)
                }
            } else {
                // 显示正常界面
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)

                Text(statusText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !installPath.isEmpty {
                    Text(
                        .init(
                            String.localizedStringWithFormat(
                                NSLocalizedString("current_install_path_label", comment: ""),
                                installPath
                            )
                        )
                    )
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !isInstalling else { return false }
            handleDrop(providers: providers)
            return true
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showingAboutSheet = true }) {
                    Label("About", systemImage: "info.circle")
                }
                .disabled(isInstalling)
                
                Button(action: selectInstallPath) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .disabled(isInstalling)
            }
        }
        .onAppear(perform: checkAndRequestPath)
        .alert(isPresented: $showingOverwriteAlert) {
            guard let info = installInfo else { return Alert(title: Text("Error")) }
            let realAppName = getRealAppName(from: info.sourceURL) ?? info.fileName
            return Alert(
                title: Text("overwrite_alert_title"),
                message: Text(.init(String.localizedStringWithFormat(NSLocalizedString("overwrite_alert_message", comment: ""), realAppName))),
                primaryButton: .destructive(Text("overwrite_button_replace")) {
                    startInstallation(for: info.sourceURL, overwrite: true)
                },
                secondaryButton: .cancel(Text("overwrite_button_cancel"))
            )
        }
        .sheet(isPresented: $showingAboutSheet) {
            AboutView()
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard !installPath.isEmpty else {
            statusText = "initial_setup_prompt"
            return
        }
        guard let provider = providers.first else { return }
        
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let sourceURL = url else { return }
            
            DispatchQueue.main.async {
                let fileManager = FileManager.default
                let originalFilename = sourceURL.lastPathComponent
                let destinationURL = URL(fileURLWithPath: self.installPath).appendingPathComponent(originalFilename)
                
                if fileManager.fileExists(atPath: destinationURL.path) {
                    self.installInfo = FileInstallInfo(sourceURL: sourceURL, fileName: originalFilename)
                    self.showingOverwriteAlert = true
                } else {
                    self.startInstallation(for: sourceURL, overwrite: false)
                }
            }
        }
    }
    
    private func startInstallation(for sourceURL: URL, overwrite: Bool) {
        isInstalling = true
        statusText = "installing_status"
        
        processDraggedFile(
            at: sourceURL,
            to: self.installPath,
            overwrite: overwrite,
            progressCallback: { progress in
                self.installProgress = progress
            },
            completion: { result in
                self.isInstalling = false
                self.installProgress = nil
                
                switch result {
                case .success(let appName):
                    self.statusText = .init(String.localizedStringWithFormat(NSLocalizedString("install_success_message", comment: ""), appName))
                    // 3秒后重置状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.statusText = "drop_prompt"
                    }
                case .failure(let error):
                    self.statusText = .init(String.localizedStringWithFormat(NSLocalizedString("install_failure_message", comment: ""), error))
                }
            }
        )
    }
    
    private func getRealAppName(from appURL: URL) -> String? {
        guard let appBundle = Bundle(url: appURL) else { return nil }
        if let displayName = appBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
            return displayName
        }
        if let bundleName = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
            return bundleName
        }
        return appURL.deletingPathExtension().lastPathComponent
    }

    private func checkAndRequestPath() {
        if installPath.isEmpty {
            statusText = "initial_setup_prompt"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectInstallPath()
            }
        }
    }

    private func selectInstallPath() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = NSLocalizedString("Select", comment: "Button title for file panel")
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true

        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                self.installPath = url.path
                statusText = "setup_success_prompt"
            }
        } else {
            if installPath.isEmpty {
                statusText = "initial_setup_prompt"
            }
        }
    }
}
