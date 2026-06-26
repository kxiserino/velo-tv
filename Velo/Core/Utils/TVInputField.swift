import SwiftUI

struct TVInputField: View {
    let placeholder: String
    let systemImage: String
    @Binding var text: String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(focused ? .white : .secondary)
                .frame(width: 26)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(.tertiary)
            )
            .focused($focused)
            .textFieldStyle(.plain)
            .submitLabel(.search)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white)
            .focusEffectDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(.leading, 18)
        .padding(.trailing, text.isEmpty ? 18 : 6)
        .padding(.vertical, 8)
        .background(fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? .white.opacity(0.70) : .white.opacity(0.12), lineWidth: focused ? 2 : 1)
        )
        .shadow(color: focused ? .black.opacity(0.28) : .clear, radius: 18, y: 10)
        .animation(.easeInOut(duration: 0.16), value: focused)
        .animation(.easeInOut(duration: 0.12), value: text.isEmpty)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(focused ? 0.14 : 0.075))
    }
}
