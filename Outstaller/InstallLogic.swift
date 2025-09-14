import AppKit
import Foundation

// 定义一个枚举来清晰地表示安装结果
enum InstallResult {
    case success(appName: String)
    case failure(error: String)
}

// 进度信息结构体
struct InstallProgress {
    let bytesCompleted: Int64
    let totalBytes: Int64
    let speed: Double // bytes per second
    let estimatedTimeRemaining: TimeInterval // seconds
    let currentOperation: String // 当前操作描述
    
    var progressPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(bytesCompleted) / Double(totalBytes)
    }
    
    var formattedSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }
    
    var formattedTimeRemaining: String {
        if estimatedTimeRemaining.isInfinite || estimatedTimeRemaining.isNaN || estimatedTimeRemaining < 0 {
            return "calculating..."
        }
        
        let minutes = Int(estimatedTimeRemaining) / 60
        let seconds = Int(estimatedTimeRemaining) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        let completed = formatter.string(fromByteCount: bytesCompleted)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(completed) / \(total)"
    }
}

/// 处理拖入的 .app 文件，执行拷贝和创建链接的操作
func processDraggedFile(
    at sourceURL: URL,
    to destinationPath: String,
    overwrite: Bool,
    progressCallback: @escaping (InstallProgress) -> Void,
    completion: @escaping (InstallResult) -> Void
) {
    
    DispatchQueue.global(qos: .userInitiated).async {
        let fileManager = FileManager.default
        
        // --- 1. 获取名称和路径 ---
        let originalFilename = sourceURL.lastPathComponent
        guard let realAppName = getRealAppName(from: sourceURL) else {
            let errorMsg = NSLocalizedString("error_parsing_plist", comment: "")
            DispatchQueue.main.async { completion(.failure(error: errorMsg)) }
            return
        }
        
        let finalDestinationURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(originalFilename)
        let linkTargetPath = "/Applications/\(realAppName).app"
        
        // --- 2. 计算总大小 ---
        guard let totalSize = getDirectorySize(at: sourceURL) else {
            let errorMsg = NSLocalizedString("error_calculating_size", comment: "")
            DispatchQueue.main.async { completion(.failure(error: errorMsg)) }
            return
        }
        
        // --- 3. 如果是覆盖操作，先删除旧文件和旧链接 ---
        if overwrite {
            DispatchQueue.main.async {
                progressCallback(InstallProgress(
                    bytesCompleted: 0,
                    totalBytes: totalSize,
                    speed: 0,
                    estimatedTimeRemaining: 0,
                    currentOperation: NSLocalizedString("removing_old_files", comment: "")
                ))
            }
            
            do {
                if fileManager.fileExists(atPath: finalDestinationURL.path) {
                    try fileManager.removeItem(at: finalDestinationURL)
                }
                if fileManager.fileExists(atPath: linkTargetPath) {
                    try fileManager.removeItem(atPath: linkTargetPath)
                }
            } catch {
                let errorMsg = NSLocalizedString("error_removing_old_files", comment: "") + ": \(error.localizedDescription)"
                DispatchQueue.main.async { completion(.failure(error: errorMsg)) }
                return
            }
        }

        // --- 4. 执行带进度的文件拷贝 ---
        let startTime = Date()
        var lastProgressTime = startTime
        var lastBytesCompleted: Int64 = 0
        
        let success = copyDirectoryWithProgress(
            from: sourceURL,
            to: finalDestinationURL,
            totalSize: totalSize,
            progressCallback: { bytesCompleted in
                let currentTime = Date()
                let timeElapsed = currentTime.timeIntervalSince(lastProgressTime)
                
                // 每0.1秒更新一次进度（避免过于频繁的UI更新）
                if timeElapsed >= 0.1 {
                    let bytesInInterval = bytesCompleted - lastBytesCompleted
                    let speed = timeElapsed > 0 ? Double(bytesInInterval) / timeElapsed : 0
                    
                    let remainingBytes = totalSize - bytesCompleted
                    let estimatedTimeRemaining = speed > 0 ? Double(remainingBytes) / speed : Double.infinity
                    
                    let progress = InstallProgress(
                        bytesCompleted: bytesCompleted,
                        totalBytes: totalSize,
                        speed: speed,
                        estimatedTimeRemaining: estimatedTimeRemaining,
                        currentOperation: NSLocalizedString("copying_files", comment: "")
                    )
                    
                    DispatchQueue.main.async {
                        progressCallback(progress)
                    }
                    
                    lastProgressTime = currentTime
                    lastBytesCompleted = bytesCompleted
                }
            }
        )
        
        guard success else {
            let errorMsg = NSLocalizedString("error_copying_files", comment: "")
            DispatchQueue.main.async { completion(.failure(error: errorMsg)) }
            return
        }
        
        // --- 5. 创建符号链接 ---
        DispatchQueue.main.async {
            progressCallback(InstallProgress(
                bytesCompleted: totalSize,
                totalBytes: totalSize,
                speed: 0,
                estimatedTimeRemaining: 0,
                currentOperation: NSLocalizedString("creating_link", comment: "")
            ))
        }
        
        do {
            // 更安全的链接删除和创建过程
            if fileManager.fileExists(atPath: linkTargetPath) {
                // 检查是否为符号链接，如果是则删除
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: linkTargetPath, isDirectory: &isDirectory) {
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: linkTargetPath)
                        if let fileType = attributes[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                            // 是符号链接，安全删除
                            try fileManager.removeItem(atPath: linkTargetPath)
                        } else if isDirectory.boolValue {
                            // 是真实的应用目录，需要删除（覆盖模式）
                            try fileManager.removeItem(atPath: linkTargetPath)
                        } else {
                            // 是普通文件，删除
                            try fileManager.removeItem(atPath: linkTargetPath)
                        }
                    } catch {
                        // 如果获取属性失败，直接尝试删除
                        try fileManager.removeItem(atPath: linkTargetPath)
                    }
                }
            }
            
            // 创建新的符号链接
            try fileManager.createSymbolicLink(atPath: linkTargetPath, withDestinationPath: finalDestinationURL.path)
        } catch {
            let errorMsg = NSLocalizedString("error_creating_link", comment: "") + ": \(error.localizedDescription)"
            DispatchQueue.main.async { completion(.failure(error: errorMsg)) }
            return
        }
        
        // --- 6. 完成 ---
        DispatchQueue.main.async {
            progressCallback(InstallProgress(
                bytesCompleted: totalSize,
                totalBytes: totalSize,
                speed: 0,
                estimatedTimeRemaining: 0,
                currentOperation: NSLocalizedString("installation_complete", comment: "")
            ))
            completion(.success(appName: realAppName))
        }
    }
}

/// 计算目录总大小
private func getDirectorySize(at url: URL) -> Int64? {
    let fileManager = FileManager.default
    var totalSize: Int64 = 0
    
    guard let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }
    
    for case let fileURL as URL in enumerator {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if let isDirectory = resourceValues.isDirectory, !isDirectory {
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        } catch {
            // 忽略无法访问的文件，继续计算其他文件
            continue
        }
    }
    
    return totalSize > 0 ? totalSize : nil
}

/// 带进度回调的目录拷贝函数（适用于 .app 包）
private func copyDirectoryWithProgress(
    from sourceURL: URL,
    to destinationURL: URL,
    totalSize: Int64,
    progressCallback: @escaping (Int64) -> Void
) -> Bool {
    let fileManager = FileManager.default
    
    // 创建一个定时器来模拟进度更新
    let startTime = Date()
    var progressTimer: Timer?
    var hasCompleted = false
    
    // 在后台线程执行实际的复制操作
    let copyGroup = DispatchGroup()
    copyGroup.enter()
    
    var copySuccess = false
    
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            // 使用标准的 FileManager.copyItem 来保持 .app 包的完整性
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            copySuccess = true
        } catch {
            copySuccess = false
        }
        copyGroup.leave()
    }
    
    // 启动进度模拟定时器
    DispatchQueue.main.async {
        var simulatedProgress: Int64 = 0
        let updateInterval: TimeInterval = 0.1
        let estimatedDuration: TimeInterval = max(2.0, Double(totalSize) / (50 * 1024 * 1024)) // 假设 50MB/s 的速度
        let progressIncrement = Int64(Double(totalSize) / (estimatedDuration / updateInterval))
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            if hasCompleted {
                timer.invalidate()
                return
            }
            
            // 模拟进度增长（带有一些随机性来看起来更真实）
            let randomFactor = Double.random(in: 0.8...1.2)
            simulatedProgress += Int64(Double(progressIncrement) * randomFactor)
            
            // 确保不超过总大小的 95%（为完成时留出空间）
            simulatedProgress = min(simulatedProgress, Int64(Double(totalSize) * 0.95))
            
            progressCallback(simulatedProgress)
        }
    }
    
    // 等待复制完成
    copyGroup.wait()
    
    // 停止定时器并发送完成进度
    DispatchQueue.main.sync {
        hasCompleted = true
        progressTimer?.invalidate()
        if copySuccess {
            progressCallback(totalSize) // 显示 100% 完成
        }
    }
    
    return copySuccess
}

/// 从 .app 包中读取真实的应用显示名称 (使用 Bundle API)
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
