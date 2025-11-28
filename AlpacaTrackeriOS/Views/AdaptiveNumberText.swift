import SwiftUI

struct AdaptiveNumberText: View {
    let value: Double
    let specifier: String
    let maxWidth: CGFloat
    let minFontSize: CGFloat
    let maxFontSize: CGFloat
    
    @State private var fontSize: CGFloat = 0
    
    init(
        value: Double,
        specifier: String = "%.2f",
        maxWidth: CGFloat = 200,
        minFontSize: CGFloat = 12,
        maxFontSize: CGFloat = 28
    ) {
        self.value = value
        self.specifier = specifier
        self.maxWidth = maxWidth
        self.minFontSize = minFontSize
        self.maxFontSize = maxFontSize
        self._fontSize = State(initialValue: maxFontSize)
    }
    
    var body: some View {
        Text(String(format: specifier, value))
            .font(.system(size: fontSize, weight: .bold, design: .default))
            .foregroundColor(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.1)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            adjustFontSize(for: geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            adjustFontSize(for: newWidth)
                        }
                }
            )
    }
    
    private func adjustFontSize(for availableWidth: CGFloat) {
        let testString = String(format: specifier, value)
        var testFontSize = maxFontSize
        
        // Binary search to find the optimal font size
        while testFontSize > minFontSize {
            let testSize = testString.size(withAttributes: [.font: UIFont.systemFont(ofSize: testFontSize, weight: .bold)])
            
            if testSize.width <= availableWidth {
                break
            }
            
            testFontSize -= 1
        }
        
        fontSize = max(testFontSize, minFontSize)
    }
}

// Extension to calculate text size
extension String {
    func size(withAttributes attributes: [NSAttributedString.Key: Any]) -> CGSize {
        return (self as NSString).size(withAttributes: attributes)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Test with different number lengths
        AdaptiveNumberText(value: 1234567.89, specifier: "%.2f", maxWidth: 150)
        AdaptiveNumberText(value: 123456789.12, specifier: "%.2f", maxWidth: 150)
        AdaptiveNumberText(value: 1234567890.34, specifier: "%.2f", maxWidth: 150)
    }
    .padding()
}
