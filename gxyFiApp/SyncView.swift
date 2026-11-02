import SwiftUI

struct SyncView: View {
    @Environment(AppModel.self) private var model
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var askUpload = false
    @State private var confirmLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.storageLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(FiColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let user = model.cloudUser, !model.cloudExpired {
                    connected(user)
                } else {
                    loginForm
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FiColor.background)
        .navigationTitle("网页同步")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if server.isEmpty { server = model.cloudServer }
            if username.isEmpty { username = model.cloudUser ?? "" }
        }
        .confirmationDialog(
            "手机上已有 \(model.ledger.recordCount()) 条记录",
            isPresented: $askUpload,
            titleVisibility: .visible
        ) {
            Button("上传到网页账号") { login(upload: true) }
            Button("不上传，改用网页上的账", role: .destructive) { login(upload: false) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("上传会把这些记录追加到网页账号里。两种选择都会先把手机上的账备份到「文件」App 的 gxyFi 文件夹。")
        }
        .confirmationDialog("退出网页账号？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出并清空手机缓存", role: .destructive) {
                Task { await model.disconnect() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账仍保存在网页端，下次登录会重新下载。")
        }
    }

    private func connected(_ user: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("网页端", model.cloudServer)
            infoRow("账号", user)
            infoRow("上次同步", model.lastSync.isEmpty ? "—" : model.lastSync)
            HStack(spacing: 8) {
                FiButton(title: model.syncing ? "同步中…" : "立即同步", kind: .primary, disabled: model.syncing) {
                    Task { await model.pull() }
                }
                FiButton(title: "退出登录", kind: .danger) { confirmLogout = true }
            }
            Text("登录后，记账、修改、删除都会直接存到网页端，再下载回手机显示。没有网络时只能查看，不能记账。")
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("网页端地址") {
                TextField("例如 https://fi.example.com", text: $server)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field("用户名") {
                TextField("", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field("密码") {
                SecureField("", text: $password)
                    .textContentType(.password)
            }
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(FiColor.up)
            }
            FiButton(title: working ? "登录中…" : "登录并同步", kind: .primary, disabled: working) { start() }
            Text("使用网页版的同一个账号。网页端不开放注册，账号由管理员在 Cloudflare 里配置。")
                .font(.system(size: 12))
                .foregroundStyle(FiColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func start() {
        error = nil
        let firstTime = model.ledger.setting("cloud_user")?.isEmpty != false
        if firstTime, model.ledger.recordCount() > 0 {
            askUpload = true
        } else {
            login(upload: false)
        }
    }

    private func login(upload: Bool) {
        working = true
        Task {
            defer { working = false }
            do {
                try await model.connect(server: server, username: username, password: password, upload: upload)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(FiColor.muted)
            content().textFieldStyle(.plain).foregroundStyle(FiColor.cream)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FiColor.field)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(FiColor.line))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13)).foregroundStyle(FiColor.muted).frame(width: 72, alignment: .leading)
            Text(value).font(.system(size: 15)).foregroundStyle(FiColor.cream).textSelection(.enabled)
        }
    }
}
