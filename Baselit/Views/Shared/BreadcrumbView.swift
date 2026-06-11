import SwiftUI

struct BreadcrumbView: View {
    let components: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(component)
                    .font(.caption)
                    .foregroundStyle(index == components.count - 1 ? .primary : .secondary)
            }
        }
    }
}
