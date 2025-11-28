import SwiftUI

struct TooltipView: View {
    let content: AnyView
    let isVisible: Bool
    let position: CGPoint
    let maxWidth: CGFloat
    @State private var contentSize: CGSize = .zero
    
    init<Content: View>(
        isVisible: Bool,
        position: CGPoint,
        maxWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) {
        self.isVisible = isVisible
        self.position = position
        self.maxWidth = maxWidth
        self.content = AnyView(content())
    }
    
    var body: some View {
        if isVisible {
            GeometryReader { container in
                let containerSize = container.size
                content
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .frame(maxWidth: maxWidth)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    contentSize = geometry.size
                                }
                            .onChange(of: geometry.size) { _, newSize in
                                contentSize = newSize
                            }
                        }
                    )
                    .position(
                        x: min(
                            max(position.x, (contentSize.width / 2) + 8),
                            containerSize.width - ((contentSize.width / 2) + 8)
                        ),
                        y: {
                            let verticalOffset: CGFloat = 80
                            let topPosition = position.y - verticalOffset
                            let bottomPosition = position.y + verticalOffset
                            let minY = (contentSize.height / 2) + 8
                            let maxY = containerSize.height - ((contentSize.height / 2) + 8)
                            // Si no cabe arriba, colocarlo abajo
                            if topPosition < minY {
                                return min(max(bottomPosition, minY), maxY)
                            } else {
                                return min(max(topPosition, minY), maxY)
                            }
                        }()
                    )
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
            }
        }
    }
}

// MARK: - Tooltip Modifier

struct TooltipModifier: ViewModifier {
    @State private var isTooltipVisible = false
    @State private var tooltipPosition: CGPoint = .zero
    let tooltipContent: AnyView
    let maxWidth: CGFloat
    
    init<Content: View>(
        maxWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.tooltipContent = AnyView(content())
    }
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .onLongPressGesture(minimumDuration: 0.5) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isTooltipVisible = true
                    }
                } onPressingChanged: { pressing in
                    if !pressing {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isTooltipVisible = false
                        }
                    }
                }
            
            TooltipView(
                isVisible: isTooltipVisible,
                position: tooltipPosition,
                maxWidth: maxWidth
            ) {
                tooltipContent
            }
        }
    }
}

extension View {
    func tooltip<Content: View>(
        maxWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) -> some View {
        self.modifier(TooltipModifier(maxWidth: maxWidth, content: content))
    }
}

// MARK: - Chart Tooltip Modifier

struct ChartTooltipModifier: ViewModifier {
    @Binding var isTooltipVisible: Bool
    @Binding var tooltipPosition: CGPoint
    let tooltipContent: AnyView
    let maxWidth: CGFloat
    
    init<Content: View>(
        isVisible: Binding<Bool>,
        position: Binding<CGPoint>,
        maxWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) {
        self._isTooltipVisible = isVisible
        self._tooltipPosition = position
        self.maxWidth = maxWidth
        self.tooltipContent = AnyView(content())
    }
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .onLongPressGesture(minimumDuration: 0.3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isTooltipVisible = true
                    }
                } onPressingChanged: { pressing in
                    if !pressing {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isTooltipVisible = false
                        }
                    }
                }
            
            TooltipView(
                isVisible: isTooltipVisible,
                position: tooltipPosition,
                maxWidth: maxWidth
            ) {
                tooltipContent
            }
        }
    }
}

extension View {
    func chartTooltip<Content: View>(
        isVisible: Binding<Bool>,
        position: Binding<CGPoint>,
        maxWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) -> some View {
        self.modifier(ChartTooltipModifier(
            isVisible: isVisible,
            position: position,
            maxWidth: maxWidth,
            content: content
        ))
    }
}

// MARK: - Performance Tooltip Content

struct PerformanceTooltipContent: View {
    let timestamp: Date
    let equity: Double
    let changeAmount: Double
    let changePercentage: Double
    let isTotalAccounts: Bool
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: timestamp)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatTimestamp(timestamp))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if isTotalAccounts {
                Text("\(String(format: "%.2f", equity))%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            } else {
                Text("$\(String(format: "%.2f", equity))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                HStack {
                    Text("Change:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("$\(String(format: "%.2f", changeAmount))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(changeAmount >= 0 ? .green : .red)
                    
                    Text("(\(String(format: "%.2f", changePercentage))%)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(changeAmount >= 0 ? .green : .red)
                }
            }
        }
    }
}

// MARK: - Comparison Tooltip Content

struct ComparisonTooltipContent: View {
    let timestamp: Date
    let portfolioValue: Double
    let indexValues: [(String, Double, Color)]
    
    private func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: timestamp)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatTimestamp(timestamp))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Portfolio
            HStack(spacing: 8) {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                Text("Portfolio:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(String(format: "%.2f", portfolioValue))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            
            // Indices
            ForEach(indexValues, id: \.0) { indexName, value, color in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text("\(indexName):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.2f", value))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
            }
        }
    }
}

// MARK: - Position Tooltip Content

struct PositionTooltipContent: View {
    let position: Position
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(position.symbol)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(position.assetClass.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quantity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(String(format: "%.2f", position.quantity))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Side:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(position.side.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(position.side.lowercased() == "long" ? .green : .red)
                }
                
                HStack {
                    Text("Current Price:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", position.currentPriceDouble))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Entry Price:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", Double(position.avgEntryPrice) ?? 0.0))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Unrealized P&L:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", position.unrealizedPLDouble))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(position.isProfitable ? .green : .red)
                }
                
                HStack {
                    Text("P&L %:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(String(format: "%.2f", Double(position.unrealizedPlpc) ?? 0.0))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(position.isProfitable ? .green : .red)
                }
                
                HStack {
                    Text("Market Value:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", position.marketValueDouble))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
    }
}
