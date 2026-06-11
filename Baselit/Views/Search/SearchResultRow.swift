import SwiftUI

struct SearchResultRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)

            HStack(spacing: 8) {
                if let category = item.category {
                    Text(category.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary)
                        .clipShape(Capsule())
                }
                if let color = item.color {
                    Text(color.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary)
                        .clipShape(Capsule())
                }
            }

            BreadcrumbView(components: item.breadcrumbComponents)
        }
        .padding(.vertical, 2)
    }
}
