import SwiftUI

struct AccountPickerView: View {
    let accounts: [AlpacaAccount]
    @Binding var selectedAccount: UUID?
    @ObservedObject var accountManager: AccountManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(accounts, id: \.id) { account in
                    Button(action: {
                        selectedAccount = account.id
                        dismiss()
                    }) {
                        HStack {
                            if selectedAccount == account.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                // Remove Alpaca ID to prioritize relevant indicators (space reclaimed)
                                if account.name == "Total Accounts" {
                                    Text("Sum of all accounts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            // Daily change chip
                            let isTotal = account.name == "Total Accounts"
                            let dailyChange: Double? = isTotal ? accountManager.totalAccountsDailyChangeNew : accountManager.dailyChangePercentages[account.id]
                            if let dailyChange = dailyChange {
                                HStack(spacing: 4) {
                                    Image(systemName: dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption2)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                    Text("\(String(format: "%.2f", dailyChange))%")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(dailyChange >= 0 ? .green : .red)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background((dailyChange >= 0 ? Color.green : Color.red).opacity(0.12))
                                .cornerRadius(4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}