import SwiftUI

struct PasswordSheet: View {
    @State private var password = ""
    @FocusState private var passwordIsFocused: Bool

    let errorMessage: String?
    let submit: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PDFのパスワードを入力")
                .font(.headline)
                .foregroundStyle(ReaderTheme.primaryText)

            SecureField("パスワード", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordIsFocused)
                .accessibilityLabel("PDFのパスワード")
                .accessibilityHint("このPDFを開くためのパスワードを入力します")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("エラー。\(errorMessage)")
            }

            HStack {
                Spacer()
                Button("キャンセル", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("開く") { submit(password) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(ReaderTheme.surface)
        .onAppear { passwordIsFocused = true }
    }
}
