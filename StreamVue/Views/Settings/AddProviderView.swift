import SwiftUI
import SwiftData

struct AddProviderView: View {
    var providerManager: ProviderManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Use AppStorage to remember last used values
    @AppStorage("lastProviderType") private var lastProviderType = "Xtream Codes"
    @AppStorage("lastXtreamURL") private var lastXtreamURL = ""
    @AppStorage("lastXtreamUsername") private var lastXtreamUsername = ""
    @AppStorage("lastXtreamPassword") private var lastXtreamPassword = ""
    @AppStorage("lastM3UURL") private var lastM3UURL = ""
    @AppStorage("lastEPGURL") private var lastEPGURL = ""

    @State private var name = ""
    @State private var type: ProviderType = .xtream
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var epgURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Provider")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Type", selection: $type) {
                        ForEach(ProviderType.allCases, id: \.self) { providerType in
                            Text(providerType.rawValue).tag(providerType)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("My IPTV Provider", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(type == .m3u ? "M3U/M3U8 URL" : "Server URL")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField(
                            type == .m3u
                                ? "http://example.com/playlist.m3u"
                                : "http://example.com:8080",
                            text: $url
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    if type == .xtream {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("Username", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Password")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("EPG URL (optional)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("http://example.com/epg.xml", text: $epgURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: addProvider) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Add Provider")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || url.isEmpty || isLoading)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 480)
        .onAppear {
            // Restore saved credentials
            if lastProviderType == ProviderType.xtream.rawValue {
                type = .xtream
                url = lastXtreamURL
                username = lastXtreamUsername
                password = lastXtreamPassword
            } else {
                type = .m3u
                url = lastM3UURL
            }
            epgURL = lastEPGURL
        }
        .onChange(of: type) { _, newType in
            // Switch between saved values
            if newType == .xtream {
                url = lastXtreamURL
                username = lastXtreamUsername
                password = lastXtreamPassword
            } else {
                url = lastM3UURL
            }
        }
    }

    private func addProvider() {
        isLoading = true
        errorMessage = nil

        // Save credentials for next time
        lastProviderType = type.rawValue
        if type == .xtream {
            lastXtreamURL = url
            lastXtreamUsername = username
            lastXtreamPassword = password
        } else {
            lastM3UURL = url
        }
        lastEPGURL = epgURL

        let provider = Provider(
            name: name,
            type: type,
            url: url,
            username: username,
            password: password,
            epgURL: epgURL
        )
        modelContext.insert(provider)

        Task {
            providerManager.setModelContext(modelContext)
            await providerManager.loadChannels(for: provider)
            if let error = providerManager.errorMessage {
                errorMessage = error
                modelContext.delete(provider)
            } else {
                dismiss()
            }
            isLoading = false
        }
    }
}
