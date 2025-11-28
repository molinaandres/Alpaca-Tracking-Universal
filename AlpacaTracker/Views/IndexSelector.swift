import SwiftUI

struct IndexSelector: View {
    @Binding var selectedIndices: Set<String>
    let availableIndices: [Index]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(availableIndices, id: \.id) { index in
                IndexSelectionCard(
                    index: index,
                    isSelected: selectedIndices.contains(index.id),
                    onToggle: {
                        if selectedIndices.contains(index.id) {
                            selectedIndices.remove(index.id)
                        } else {
                            selectedIndices.insert(index.id)
                        }
                    }
                )
            }
        }
    }
}

struct IndexSelectionCard: View {
    let index: Index
    let isSelected: Bool
    let onToggle: () -> Void
    
    private var indexColor: Color {
        switch index.id {
        case "sp500":
            return .red
        case "nasdaq":
            return .yellow
        case "msci_world":
            return .purple
        default:
            return .gray
        }
    }
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? indexColor : .secondary)
                    .font(.system(size: 14))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(index.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    
                    Text(index.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? indexColor.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? indexColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct IndexComparisonSummary: View {
    let comparisons: [IndexComparison]
    
    // Ordenar comparaciones: SP500, NASDAQ, MSCI World
    private var sortedComparisons: [IndexComparison] {
        let order: [String] = ["sp500", "nasdaq", "msci_world"]
        return comparisons.sorted { comparison1, comparison2 in
            let index1 = order.firstIndex(of: comparison1.index.id) ?? Int.max
            let index2 = order.firstIndex(of: comparison2.index.id) ?? Int.max
            return index1 < index2
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if comparisons.isEmpty {
                Text("No comparisons available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(comparisons.count, 3)), spacing: 12) {
                    ForEach(sortedComparisons) { comparison in
                        UnifiedComparisonCard(comparison: comparison)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
}

struct QuickComparisonButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.compare")
                    .font(.system(size: 14, weight: .medium))
                Text("Compare with Indices")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(8)
            .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct UnifiedComparisonCard: View {
    let comparison: IndexComparison
    
    // Color del índice basado en el ID
    private var indexColor: Color {
        switch comparison.index.id {
        case "sp500":
            return .red
        case "nasdaq":
            return .yellow
        case "msci_world":
            return .purple
        default:
            return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header con nombre del índice y outperformance
            HStack {
                Text(comparison.index.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Outperformance")
                        .font(.caption2)
                        .foregroundColor(comparison.outperformance >= 0 ? .green : .red)
                    
                    HStack(spacing: 4) {
                        Image(systemName: comparison.outperformance >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text("\(comparison.outperformance, specifier: "%.2f")%")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(comparison.outperformance >= 0 ? .green : .red)
                }
            }
            
            // Métricas principales
            VStack(spacing: 8) {
                // Retornos
                HStack {
                    Text("Portfolio Return:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(comparison.portfolioReturn, specifier: "%.2f")%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue) // Azul para el portfolio
                }
                
                HStack {
                    Text("Index Return:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(comparison.indexReturn, specifier: "%.2f")%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(indexColor) // Color del índice
                }
                
                Divider()
                
                // Correlación
                HStack {
                    Text("Correlation:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(comparison.correlation, specifier: "%.3f")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(indexColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(indexColor, lineWidth: 1.5)
                )
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        IndexSelector(
            selectedIndices: .constant(["sp500", "nasdaq"]),
            availableIndices: Index.allIndices
        )
        
        IndexComparisonSummary(comparisons: [])
        
        QuickComparisonButton(action: {})
    }
    .padding()
}
