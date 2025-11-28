import SwiftUI

struct IndexCard: View {
    let index: Index
    @State private var currentValue: Double = 0.0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var dailyChangePercentage: Double? = nil
    @State private var isLoadingDailyChange = false
    @StateObject private var indexDataManager = IndexDataManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header con nombre y símbolo del índice
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(index.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Indicador de tipo de índice
                        Text("INDEX")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // Icono de índice
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Información de valor actual
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading value...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            Text(EuropeanNumberFormatter.shared.format(currentValue))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            
                            if isLoadingDailyChange {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else if let dailyChange = dailyChangePercentage {
                                HStack(spacing: 4) {
                                    Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                    
                                    Text("\(dailyChange >= 0 ? "+" : "")\(EuropeanNumberFormatter.shared.format(dailyChange))%")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill((dailyChange >= 0 ? Color.green : Color.red).opacity(0.1))
                                )
                            } else {
                                // Hide stale info: show loader placeholder until daily change is computed
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Last update time (original position)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Last update")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    if let lastUpdate = indexDataManager.lastUpdateTimes[index.id] {
                        Text(formatLastUpdateTime(lastUpdate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(ColorCompatibility.controlBackground())
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            // Start in loading state and hide stale daily change until computed
            isLoadingDailyChange = true
            dailyChangePercentage = nil
            loadIndexData()
        }
    }
    
    private func loadIndexData() {
        // Obtener datos del índice para los últimos 30 días
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate
        
        indexDataManager.fetchIndexHistory(
            index: index,
            startDate: startDate,
            endDate: endDate
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let history):
                    if let lastDataPoint = history.dataPoints.last {
                        self.currentValue = lastDataPoint.value
                        self.isLoading = false
                        self.errorMessage = nil
                        
                        // Calcular cambio diario
                        self.calculateDailyChange(history: history)
                    } else {
                        self.isLoading = false
                        self.errorMessage = "No data available"
                        self.isLoadingDailyChange = false
                        self.dailyChangePercentage = nil
                    }
                case .failure(let error):
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.isLoadingDailyChange = false
                    self.dailyChangePercentage = nil
                }
            }
        }
    }
    
    private func calculateDailyChange(history: IndexHistory) {
        guard history.dataPoints.count >= 2 else {
            self.dailyChangePercentage = nil
            self.isLoadingDailyChange = false
            return
        }
        
        let lastDataPoint = history.dataPoints[history.dataPoints.count - 1]
        let previousDataPoint = history.dataPoints[history.dataPoints.count - 2]
        
        let change = lastDataPoint.value - previousDataPoint.value
        let changePercentage = (change / previousDataPoint.value) * 100
        
        self.dailyChangePercentage = changePercentage
        self.isLoadingDailyChange = false
    }
    
    private func formatLastUpdateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
