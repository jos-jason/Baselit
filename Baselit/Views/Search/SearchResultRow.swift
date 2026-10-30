import SwiftUI

struct SearchResultRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: item.photos, placeholderIcon: "shippingbox")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                BreadcrumbView(components: item.breadcrumbComponents)
            }
        }
        .padding(.vertical, 2)
    }
}
