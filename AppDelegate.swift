import UIKit
import Darwin

// MARK: - 安全日志写入
func writeLog(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
    let logLine = "[\(timestamp)] \(message)\n"
    let docsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    let logPath = (docsPath as NSString).appendingPathComponent("exploit.log")
    
    do {
        if FileManager.default.fileExists(atPath: logPath) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
            handle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    } catch {
        print("日志写入失败: \(error)")
    }
}

func setupExceptionHandler() {
    NSSetUncaughtExceptionHandler { exception in
        let log = "[FATAL] Uncaught exception: \(exception)\nReason: \(exception.reason ?? "unknown")\nCall stack: \(exception.callStackSymbols.joined(separator: "\n"))"
        writeLog(log)
    }
}

// MARK: - Sysctl 工具
func getSysctlString(_ name: String, default defaultValue: String = "N/A") -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return defaultValue
    }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
        return defaultValue
    }
    let result = String(cString: value)
    return result.isEmpty ? defaultValue : result
}

func getSysctlInt(_ name: String, default defaultValue: Int = 0) -> Int {
    var value: Int = 0
    var size = MemoryLayout<Int>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
        return defaultValue
    }
    return value
}

// MARK: - ViewController
class ViewController: UIViewController {
    private let logTextView = UITextView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()
    private let exploitButton = UIButton(type: .system)
    private let footerLabel = UILabel()
    private let deviceInfoTextView = UITextView()

    private var isExecuting = false
    private var timer: Timer?
    private var remainingSeconds = 25  // 改为 25 秒
    private let totalWaitingTime = 25

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadDeviceInfo()
        appendLog("应用已启动")
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        appendLog("系统版本: iOS \(versionString)")
        if version.majorVersion > 27 || (version.majorVersion == 27 && version.minorVersion >= 6) {
            appendLog("⚠️ 系统版本 >= 27.0b4，漏洞已修复，此应用可能无效")
        }
    }

    private func setupUI() {
        view.backgroundColor = .white

        statusLabel.text = "准备就绪"
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.boldSystemFont(ofSize: 16)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        deviceInfoTextView.isEditable = false
        deviceInfoTextView.isSelectable = false
        deviceInfoTextView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        deviceInfoTextView.backgroundColor = UIColor.systemGray5
        deviceInfoTextView.layer.cornerRadius = 6
        deviceInfoTextView.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        deviceInfoTextView.translatesAutoresizingMaskIntoConstraints = false
        deviceInfoTextView.text = "加载设备信息中..."
        view.addSubview(deviceInfoTextView)

        progressView.progress = 0.0
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        logTextView.isEditable = false
        logTextView.isSelectable = false
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.backgroundColor = UIColor.systemGray6
        logTextView.layer.cornerRadius = 8
        logTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logTextView)

        exploitButton.setTitle("开始执行漏洞利用+MDM移除", for: .normal)
        exploitButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        exploitButton.backgroundColor = .systemRed
        exploitButton.setTitleColor(.white, for: .normal)
        exploitButton.layer.cornerRadius = 8
        exploitButton.translatesAutoresizingMaskIntoConstraints = false
        exploitButton.addTarget(self, action: #selector(exploitTapped), for: .touchUpInside)
        view.addSubview(exploitButton)

        footerLabel.text = "本软件由Cow科技开发，支持iOS26.0-27.0b4，仅供学习研究，不得用于违法用途，可能需要重启生效"
        footerLabel.textAlignment = .center
        footerLabel.font = UIFont.systemFont(ofSize: 11, weight: .light)
        footerLabel.textColor = .darkGray
        footerLabel.numberOfLines = 0
        footerLabel.lineBreakMode = .byWordWrapping
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            deviceInfoTextView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            deviceInfoTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            deviceInfoTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            deviceInfoTextView.heightAnchor.constraint(equalToConstant: 100),

            progressView.topAnchor.constraint(equalTo: deviceInfoTextView.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            progressView.heightAnchor.constraint(equalToConstant: 8),

            logTextView.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTextView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35),

            exploitButton.topAnchor.constraint(equalTo: logTextView.bottomAnchor, constant: 12),
            exploitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exploitButton.widthAnchor.constraint(equalToConstant: 220),
            exploitButton.heightAnchor.constraint(equalToConstant: 44),

            footerLabel.topAnchor.constraint(equalTo: exploitButton.bottomAnchor, constant: 12),
            footerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            footerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            footerLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    private func loadDeviceInfo() {
        DispatchQueue.global(qos: .userInitiated).async {
            let machine = getSysctlString("hw.machine")
            let model = getSysctlString("hw.model")
            let kernelVersion = getSysctlString("kern.version").components(separatedBy: "\n").first ?? "N/A"
            let pageSize = getSysctlInt("hw.pagesize")
            let pageSizeHex = String(format: "0x%X", pageSize)
            var processor = getSysctlString("hw.processor")
            if processor == "N/A" { processor = model }
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion
            let osVersionString = "iOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

            let infoText = """
            [*] Machine Name: \(machine)
            [*] Model Name: \(model)
            [*] Kernel Version: \(kernelVersion)
            [*] Processor Version: \(processor)
            [*] Kernel Page Size: \(pageSizeHex)
            [*] System Version: \(osVersionString)
            """
            DispatchQueue.main.async {
                self.deviceInfoTextView.text = infoText
            }
        }
    }

    private func appendLog(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logTextView.text += "[\(timestamp)] \(message)\n"
            let range = NSRange(location: self.logTextView.text.count - 1, length: 1)
            self.logTextView.scrollRangeToVisible(range)
        }
        writeLog(message)
    }

    private func updateProgress(_ value: Float) {
        DispatchQueue.main.async {
            self.progressView.setProgress(value, animated: true)
        }
    }

    @objc private func exploitTapped() {
        guard !isExecuting else { return }
        isExecuting = true
        exploitButton.isEnabled = false
        exploitButton.backgroundColor = .systemGray
        progressView.progress = 0.0
        logTextView.text = ""
        appendLog("开始执行流程...")
        remainingSeconds = totalWaitingTime
        updateProgress(0.0)
        // 立即输出第一条模拟日志
        appendLog("🔧 正在初始化内核服务...")
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    @objc private func tick() {
        remainingSeconds -= 1
        let progress = Float(totalWaitingTime - remainingSeconds) / Float(totalWaitingTime)
        updateProgress(progress)
        statusLabel.text = "冷却中... \(remainingSeconds)秒"

        // 每隔5秒输出模拟工作日志
        if remainingSeconds == 20 {
            appendLog("🔍正在解析驱动地址...")
        } else if remainingSeconds == 15 {
            appendLog("正在建立IOKit连接...")
        } else if remainingSeconds == 13 {
            appendLog("正在检测进程状态...")
        } else if remainingSeconds == 10 {
            appendLog("正在分配内存...")
        } else if remainingSeconds == 5 {
            appendLog("⏳准备执行漏洞利用...")
        } else if remainingSeconds == 0 {
            timer?.invalidate()
            timer = nil
            appendLog("冷却结束，开始执行漏洞利用...")
            statusLabel.text = "正在执行..."
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.performExploit()
            }
        }
    }

    private func performExploit() {
        DispatchQueue.main.async {
            self.statusLabel.text = "正在触发漏洞..."
            self.updateProgress(0.3)
        }
        let (success, message) = KernelExploit.runExploitAndDeleteProfiles()
        DispatchQueue.main.async {
            self.appendLog("执行结果: \(message)")
            self.updateProgress(1.0)
            if success {
                self.statusLabel.text = "✅ 漏洞利用成功！配置文件已删除。"
                self.exploitButton.setTitle("操作完成", for: .normal)
                self.exploitButton.backgroundColor = .systemGreen
            } else {
                self.statusLabel.text = "❌ 执行失败，请查看日志"
                self.exploitButton.setTitle("重试", for: .normal)
                self.exploitButton.backgroundColor = .systemRed
            }
            self.isExecuting = false
            self.exploitButton.isEnabled = true
        }
    }
}

// MARK: - AppDelegate
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupExceptionHandler()
        writeLog("应用启动")
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        return true
    }
}