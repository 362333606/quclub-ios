import UIKit
import WebKit
import Network

/// 趣club 原生壳：WKWebView 承载 https://best.qiuyu8.cn
/// - 登录态/缓存走持久化 store，重装不丢
/// - 支付 H5（拉卡拉/汇付/支付宝网页收银台）在壳内完成，跳回后仍在原地
/// - 微信/支付宝 App scheme 拉起系统应用，失败则留在当前页
final class ViewController: UIViewController {

    private static let homeURL = URL(string: "https://best.qiuyu8.cn")!

    /// 允许在壳内直接打开的域名以外的 App scheme（拉起失败自动忽略）
    private static let externalSchemes: Set<String> = [
        "weixin", "weixinULAPI", "wechat", "alipay", "alipays", "mqq", "qq",
        "baiduboxapp", "snssdk1128", "dingtalk", "tmall",
    ]

    private var webView: WKWebView!
    private var progressView: UIProgressView!
    private var errorPane: UIView?

    private let monitor = NWPathMonitor()
    private var hasLoadedOnce = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupWebView()
        startObservingNetwork()
        loadHome()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // 持久化：登录态/localStorage
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true

        // 原生感CSS：禁长按系统菜单/禁选词放大镜（输入框保留）；注入到全部frame
        // （智能问答跑在 /qa/ iframe 里，forMainFrameOnly=false 才盖得住）。
        // 注：WebKit 无公开 CSS 注入 API（WKUserStyleSheet 不存在），走 UserScript 插 style
        let nativeFeelCSS = """
        (function(){
          var s=document.createElement('style');
          s.textContent='html{-webkit-touch-callout:none!important;-webkit-user-select:none!important;user-select:none!important}'
          +'input,textarea,select{-webkit-user-select:text!important;user-select:text!important;-webkit-touch-callout:default}';
          (document.head||document.documentElement).appendChild(s);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: nativeFeelCSS, injectionTime: .atDocumentStart,
                         forMainFrameOnly: false)
        )

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // 原生感：钉死缩放=1（禁捏合/双击放大），关链接3D预览
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = true          // 边缘右滑返回上一页
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress),
                            options: .new, context: nil)

        // 原生下拉刷新（品牌青色调）
        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(red: 0.25, green: 0.88, blue: 0.82, alpha: 1)
        refresh.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        view.addSubview(webView)
        // 顶部收进安全区：网页从状态栏下沿开始渲染（Safari 同款行为）。
        // 底部必须铺满到屏幕物理底边：H5 的 uni-tabbar 自带
        // padding-bottom:env(safe-area-inset-bottom)，webView 伸进 Home 条区域后
        // 该 env 值生效，tabbar 会自己把内容抬到 Home 条之上——收进 safeArea 反而
        // 会在 tabbar 下露出一条原生白底（V1.0.1 实测问题）
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 顶部进度条
        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.tintColor = UIColor(red: 0.25, green: 0.88, blue: 0.82, alpha: 1)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func loadHome() {
        hideErrorPane()
        webView.load(URLRequest(url: Self.homeURL, cachePolicy: .useProtocolCachePolicy))
    }

    // MARK: - 网络监控 + 断网遮罩

    private func startObservingNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                if path.status == .unsatisfied && self.hasLoadedOnce {
                    self.showErrorPane(title: "网络连接已断开", message: "请检查网络后重试")
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.qiuyu.monitor"))
    }

    private func showErrorPane(title: String, message: String) {
        guard errorPane == nil else { return }
        let pane = UIView(frame: view.bounds)
        pane.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pane.backgroundColor = .white

        let icon = UILabel()
        icon.text = "⚽️"
        icon.font = .systemFont(ofSize: 56)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = UIColor(white: 0.1, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let msgLabel = UILabel()
        msgLabel.text = message
        msgLabel.textColor = UIColor(white: 0.45, alpha: 1)
        msgLabel.font = .systemFont(ofSize: 14)
        msgLabel.textAlignment = .center
        msgLabel.numberOfLines = 0
        msgLabel.translatesAutoresizingMaskIntoConstraints = false

        let retry = UIButton(type: .system)
        retry.setTitle("重新加载", for: .normal)
        retry.setTitleColor(UIColor(red: 0.03, green: 0.10, blue: 0.09, alpha: 1), for: .normal)
        retry.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retry.backgroundColor = UIColor(red: 0.25, green: 0.88, blue: 0.82, alpha: 1)
        retry.layer.cornerRadius = 22
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retry.translatesAutoresizingMaskIntoConstraints = false

        pane.addSubview(icon)
        pane.addSubview(titleLabel)
        pane.addSubview(msgLabel)
        pane.addSubview(retry)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: pane.centerYAnchor, constant: -110),
            titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            titleLabel.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            msgLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            msgLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 48),
            msgLabel.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -48),
            retry.topAnchor.constraint(equalTo: msgLabel.bottomAnchor, constant: 32),
            retry.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            retry.widthAnchor.constraint(equalToConstant: 168),
            retry.heightAnchor.constraint(equalToConstant: 44),
        ])
        view.addSubview(pane)
        errorPane = pane
    }

    private func hideErrorPane() {
        errorPane?.removeFromSuperview()
        errorPane = nil
    }

    @objc private func retryTapped() { loadHome() }

    /// 下拉刷新：重载当前页；页面 ondidFinish 后统一收起菊花
    @objc private func refreshPulled() {
        if webView.url != nil {
            webView.reload()
        } else {
            loadHome()
        }
    }

    private func endRefreshing() {
        if let refresh = webView.scrollView.refreshControl, refresh.isRefreshing {
            refresh.endRefreshing()
        }
    }
}

// MARK: - WKNavigationDelegate

extension ViewController: WKNavigationDelegate {

    /// 拦截导航：壳内放行业务/支付 H5；第三方 App scheme 拉起后取消网页跳转
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "http", "https":
            decisionHandler(.allow)          // 站内 + 支付收银台 H5 全部壳内打开
        case "tel", "sms", "mailto":
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        case "itms-apps", "itms-services":
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        default:
            if Self.externalSchemes.contains(scheme) {
                UIApplication.shared.open(url) { _ in }   // 拉不起微信/支付宝就留原地
            }
            decisionHandler(.cancel)
        }
    }

    /// 服务器重定向同上处理
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hideErrorPane()
        progressView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedOnce = true
        progressView.isHidden = true
        endRefreshing()
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        progressView.isHidden = true
        endRefreshing()
        showErrorPane(title: "页面加载失败", message: "网络似乎不太顺畅，请重试一次。")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        progressView.isHidden = true
        endRefreshing()
        showErrorPane(title: "无法打开趣club", message: "网络似乎不太顺畅，请重试一次。")
    }

    /// 页面里 location.href 跳到 App Store 等外部站点时留壳（V1 站内无此需求，兜底放行）
    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {}
}

// MARK: - WKUIDelegate（新窗口/JS弹窗）

extension ViewController: WKUIDelegate {

    /// target=_blank / window.open → 壳内当前页加载，不弹新窗
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        present(alert, animated: true)
    }
}

// MARK: - 进度条

extension ViewController {
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == #keyPath(WKWebView.estimatedProgress) {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress >= 1
        }
    }
}
