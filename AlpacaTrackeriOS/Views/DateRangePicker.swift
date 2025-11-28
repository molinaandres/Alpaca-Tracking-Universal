import SwiftUI

struct DateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let firstTradeDate: Date?
    @State private var showingDatePicker = false
    
    init(startDate: Binding<Date>, endDate: Binding<Date>, firstTradeDate: Date? = nil) {
        self._startDate = startDate
        self._endDate = endDate
        self.firstTradeDate = firstTradeDate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rango de fechas")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                // Fecha de inicio
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desde")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingDatePicker = true
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 12))
                            
                            Text(formatDate(startDate))
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorCompatibility.systemBackground())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Fecha de fin
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hasta")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingDatePicker = true
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 12))
                            
                            Text(formatDate(endDate))
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ColorCompatibility.systemBackground())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            DateRangeSelectionView(
                startDate: $startDate,
                endDate: $endDate,
                isPresented: $showingDatePicker,
                firstTradeDate: firstTradeDate
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: date)
    }
}

struct DateRangeSelectionView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var isPresented: Bool
    let firstTradeDate: Date?
    
    @State private var tempStartDate: Date
    @State private var tempEndDate: Date
    
    init(startDate: Binding<Date>, endDate: Binding<Date>, isPresented: Binding<Bool>, firstTradeDate: Date? = nil) {
        self._startDate = startDate
        self._endDate = endDate
        self._isPresented = isPresented
        self.firstTradeDate = firstTradeDate
        self._tempStartDate = State(initialValue: startDate.wrappedValue)
        self._tempEndDate = State(initialValue: endDate.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select date range")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("✕") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.title3)
            }
            .padding()
                        .background(ColorCompatibility.systemBackground())
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Date pickers section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rango de fechas")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Start date")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                DatePicker(
                                    "Start date",
                                    selection: $tempStartDate,
                                    in: (firstTradeDate ?? Date.distantPast)...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(CompactDatePickerStyle())
                                .labelsHidden()
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("End date")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                DatePicker(
                                    "End date",
                                    selection: $tempEndDate,
                                    in: tempStartDate...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(CompactDatePickerStyle())
                                .labelsHidden()
                            }
                        }
                        
                        // Validation message
                        if tempStartDate > tempEndDate {
                            Text("Start date must be before end date")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        // Duration info
                        if tempStartDate <= tempEndDate {
                            let duration = Calendar.current.dateComponents([.day], from: tempStartDate, to: tempEndDate)
                            if let days = duration.day {
                                Text("Duration: \(days) day\(days == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                        .background(ColorCompatibility.systemBackground())
                    .cornerRadius(12)
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancelar") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Aplicar") {
                    startDate = tempStartDate
                    endDate = tempEndDate
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(tempStartDate > tempEndDate)
            }
            .padding()
        }
        .frame(width: 500, height: 300)
        .background(ColorCompatibility.systemBackground())
    }
}

struct InlineDateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let firstTradeDate: Date?
    let onConfirm: () -> Void
    
    @State private var tempStartDate: Date
    @State private var tempEndDate: Date
    @State private var hasChanges = false
    
    // Calendar con timezone de Nueva York para alinearse con Alpaca
    private var nyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }
    
    init(startDate: Binding<Date>, endDate: Binding<Date>, firstTradeDate: Date? = nil, onConfirm: @escaping () -> Void) {
        self._startDate = startDate
        self._endDate = endDate
        self.firstTradeDate = firstTradeDate
        self.onConfirm = onConfirm
        self._tempStartDate = State(initialValue: startDate.wrappedValue)
        self._tempEndDate = State(initialValue: endDate.wrappedValue)
    }
    
    var body: some View {
        HStack(spacing: 1) {
            // Fecha de inicio
            DatePicker(
                "Start date",
                selection: $tempStartDate,
                in: (firstTradeDate ?? Date.distantPast)...tempEndDate,
                displayedComponents: .date
            )
            .datePickerStyle(CompactDatePickerStyle())
            .font(.caption2)
            .environment(\.sizeCategory, .small)
            .scaleEffect(0.85)
            .labelsHidden()
            .frame(minWidth: 110)
            .frame(height: 28)
            .environment(\.calendar, nyCalendar)
            .onChange(of: tempStartDate) { _, _ in
                checkForChanges()
            }
            
            Text("→")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Fecha de fin
            DatePicker(
                "End date",
                selection: $tempEndDate,
                in: tempStartDate...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(CompactDatePickerStyle())
            .font(.caption2)
            .environment(\.sizeCategory, .small)
            .scaleEffect(0.85)
            .labelsHidden()
            .frame(minWidth: 110)
            .frame(height: 28)
            .environment(\.calendar, nyCalendar)
            .onChange(of: tempEndDate) { _, _ in
                checkForChanges()
            }
            
            // Botón de confirmación (siempre visible, cambia de estado)
            Button(action: {
                if hasChanges {
                    // Convertir fechas al timezone de Nueva York antes de guardarlas
                    let nyTimeZone = TimeZone(identifier: "America/New_York") ?? .current
                    let nyCalendar = Calendar(identifier: .gregorian)
                    var calendar = nyCalendar
                    calendar.timeZone = nyTimeZone
                    
                    // Convertir las fechas seleccionadas al timezone de Nueva York
                    let startComponents = calendar.dateComponents([.year, .month, .day], from: tempStartDate)
                    let endComponents = calendar.dateComponents([.year, .month, .day], from: tempEndDate)
                    
                    if let nyStartDate = calendar.date(from: startComponents),
                       let nyEndDate = calendar.date(from: endComponents) {
                        startDate = nyStartDate
                        endDate = nyEndDate
                    } else {
                        // Fallback a las fechas originales si la conversión falla
                        startDate = tempStartDate
                        endDate = tempEndDate
                    }
                    hasChanges = false
                    onConfirm()
                }
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(hasChanges ? .accentColor : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!hasChanges)
            .opacity(hasChanges ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.2), value: hasChanges)
            .padding(.trailing, 2)
        }
        .frame(height: 32)
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ColorCompatibility.systemBackground())
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(hasChanges ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: hasChanges ? 2 : 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
    }
    
    private func checkForChanges() {
        hasChanges = (tempStartDate != startDate) || (tempEndDate != endDate)
    }
}

struct CompactDateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let firstTradeDate: Date?
    @State private var showingStartDatePicker = false
    @State private var showingEndDatePicker = false
    
    init(startDate: Binding<Date>, endDate: Binding<Date>, firstTradeDate: Date? = nil) {
        self._startDate = startDate
        self._endDate = endDate
        self.firstTradeDate = firstTradeDate
    }
    
    var body: some View {
        HStack(spacing: 1) {
            // Fecha de inicio compacta
            Button(action: {
                showingStartDatePicker = true
            }) {
                HStack(spacing: 1) {
                    Image(systemName: "calendar")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 10))
                    
                    Text(formatDate(startDate))
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorCompatibility.systemBackground())
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Text("→")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Fecha de fin compacta
            Button(action: {
                showingEndDatePicker = true
            }) {
                HStack(spacing: 1) {
                    Image(systemName: "calendar")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 10))
                    
                    Text(formatDate(endDate))
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ColorCompatibility.systemBackground())
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showingStartDatePicker) {
            CompactDateSelectionView(
                title: "Start date",
                selectedDate: $startDate,
                isPresented: $showingStartDatePicker,
                minDate: firstTradeDate,
                maxDate: endDate
            )
        }
        .sheet(isPresented: $showingEndDatePicker) {
            CompactDateSelectionView(
                title: "End date",
                selectedDate: $endDate,
                isPresented: $showingEndDatePicker,
                minDate: startDate
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}

struct CompactDateSelectionView: View {
    let title: String
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    let minDate: Date?
    let maxDate: Date?
    
    @State private var tempDate: Date
    
    init(title: String, selectedDate: Binding<Date>, isPresented: Binding<Bool>, minDate: Date? = nil, maxDate: Date? = nil) {
        self.title = title
        self._selectedDate = selectedDate
        self._isPresented = isPresented
        self.minDate = minDate
        self.maxDate = maxDate
        self._tempDate = State(initialValue: selectedDate.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancelar") {
                    isPresented = false
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Date picker
            DatePicker(
                title,
                selection: $tempDate,
                in: (minDate ?? Date.distantPast)...(maxDate ?? Date()),
                displayedComponents: .date
            )
            .datePickerStyle(GraphicalDatePickerStyle())
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancelar") {
                    isPresented = false
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Aplicar") {
                    selectedDate = tempDate
                    isPresented = false
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.accentColor)
                .fontWeight(.medium)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 350)
        .background(ColorCompatibility.systemBackground())
    }
}

#Preview {
    VStack {
        DateRangePicker(
            startDate: .constant(Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()),
            endDate: .constant(Date()),
            firstTradeDate: Calendar.current.date(byAdding: .day, value: -60, to: Date())
        )
        .padding()
        
        InlineDateRangePicker(
            startDate: .constant(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()),
            endDate: .constant(Date()),
            firstTradeDate: Calendar.current.date(byAdding: .day, value: -60, to: Date()),
            onConfirm: {}
        )
        .padding()
        
        CompactDateRangePicker(
            startDate: .constant(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()),
            endDate: .constant(Date()),
            firstTradeDate: Calendar.current.date(byAdding: .day, value: -60, to: Date())
        )
        .padding()
    }
}
