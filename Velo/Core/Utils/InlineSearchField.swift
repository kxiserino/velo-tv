import SwiftUI

struct InlineSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .submitLabel(.search)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.title2.weight(.medium))
            .accessibilityLabel(placeholder)
    }
}
