import SwiftUI

public struct FindOnPageView: View {
    @Binding public var isPresented: Bool
    @State private var query: String = ""
    @State private var matchIndex: Int = 0
    @State private var totalMatches: Int = 0
    
    public let onFindText: (String, Bool) -> Void // (query, forward)
    public let onDismiss: () -> Void

    public init(
        isPresented: Binding<Bool>,
        onFindText: @escaping (String, Bool) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.onFindText = onFindText
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Find in Page", text: $query)
                    .shiftNoAutocapitalization()
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .onChange(of: query) { newQuery in
                        onFindText(newQuery, true)
                    }
                    .onSubmit {
                        onFindText(query, true)
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        onFindText("", true)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.tertiarySystemFillColor)
            .cornerRadius(10)

            // Step Navigation
            HStack(spacing: 2) {
                Button {
                    onFindText(query, false)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .disabled(query.isEmpty)

                Button {
                    onFindText(query, true)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .disabled(query.isEmpty)
            }

            Button("Done") {
                isPresented = false
                onDismiss()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
