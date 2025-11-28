import Foundation

struct TWRPoint: Identifiable, Decodable {
    var id = UUID()
    let timestamp: Date
    let date: String
    let equity: Double
    let pnl: Double
    let pnl_pct: Double
    let deposits: Double
    let withdrawals: Double
    let net_cash_flow: Double
    let daily_return: Double
    let cumulative_twr: Double

    enum CodingKeys: String, CodingKey {
        case timestamp, date, equity, pnl, pnl_pct, deposits, withdrawals, net_cash_flow, daily_return, cumulative_twr
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Script emits date as string; construct timestamp from date
        self.date = try container.decode(String.self, forKey: .date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        self.timestamp = formatter.date(from: self.date) ?? Date()
        self.equity = try container.decode(Double.self, forKey: .equity)
        self.pnl = try container.decode(Double.self, forKey: .pnl)
        self.pnl_pct = try container.decode(Double.self, forKey: .pnl_pct)
        self.deposits = try container.decode(Double.self, forKey: .deposits)
        self.withdrawals = try container.decode(Double.self, forKey: .withdrawals)
        self.net_cash_flow = try container.decode(Double.self, forKey: .net_cash_flow)
        self.daily_return = try container.decode(Double.self, forKey: .daily_return)
        self.cumulative_twr = try container.decode(Double.self, forKey: .cumulative_twr)
    }
}

enum TWRRunnerError: Error, LocalizedError {
    case scriptNotFound(String)
    case executionFailed(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let path): return "TWR script not found: \(path)"
        case .executionFailed(let msg): return "TWR script failed: \(msg)"
        case .decodingFailed(let msg): return "Failed to decode TWR JSON: \(msg)"
        }
    }
}

final class TWRRunner {
    // Embedded bash script to avoid filesystem permission issues. This is written to a
    // temporary location at runtime and executed from there.
    static let embeddedScript: String = """#!/bin/bash

# =============================================================================
# SCRIPT ROBUSTO PARA CÁLCULO TWR CON DATOS REALES DE ALPACA API
# =============================================================================
# 
# DESCRIPCIÓN:
# Este script calcula Time-Weighted Returns (TWR) usando datos reales de la API
# de Alpaca, con manejo robusto de casos especiales como equity $0.00, depósitos,
# retiros, y diferentes períodos de actividad.
#
# CORRECCIÓN IMPORTANTE (v2.1):
# El flujo de caja se descuenta el día que se refleja en el equity, no el día
# que se registra. Esto significa que si hay un depósito el día D, se descuenta
# del equity del día D+1 para calcular el retorno del día D+1.
# 
# Ejemplo: Depósito $10,000 el 25/09 → Se descuenta del equity del 26/09
# para calcular el retorno del 26/09, no del 25/09.
#
# AUTOR: Asistente AI
# FECHA: 2025-01-01
# VERSIÓN: 2.1 (Corrección Flujo de Caja)
# =============================================================================

# =============================================================================
# CONFIGURACIÓN DE LA API
# =============================================================================
# Permite sobreescribir por variables de entorno o flags
API_KEY="${API_KEY:-}"
SECRET_KEY="${SECRET_KEY:-}"
BASE_URL="https://api.alpaca.markets"

# Parámetros dinámicos
START_DATE="${START_DATE:-}"
END_DATE="${END_DATE:-}"
TIMEFRAME="${TIMEFRAME:-1D}"
EXTENDED_HOURS="${EXTENDED_HOURS:-false}"

# Validación mínima de credenciales
if [ -z "$API_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo "❌ Error: API_KEY y SECRET_KEY deben proporcionarse (variables de entorno)." 1>&2
    exit 1
fi

# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

# Función para convertir timestamp Unix a fecha YYYY-MM-DD
convert_timestamp() {
    date -r "$1" +"%Y-%m-%d" 2>/dev/null || echo "N/A"
}

# Función para verificar si un valor es cero o vacío
is_zero_or_empty() {
    local value="$1"
    [ -z "$value" ] || [ "$value" = "0" ] || [ "$value" = "0.00" ] || [ "$value" = "0.0" ]
}

# Función para buscar actividades por tipo específico con paginación completa
fetch_activities_by_type() {
    local activity_type="$1"
    local page_token=""
    local type_page_count=0
    local type_activities=""
    echo "🔍 Buscando actividades $activity_type..."
    while true; do
        type_page_count=$((type_page_count + 1))
        echo "📄 Consultando página $type_page_count para $activity_type..."
        local url="$BASE_URL/v2/account/activities?activity_type=$activity_type&page_size=100&direction=asc"
        if [ -n "$page_token" ]; then
            url="$url&page_token=$page_token"
        fi
        local response=$(curl -s "$url" \
            -H "APCA-API-KEY-ID: $API_KEY" \
            -H "APCA-API-SECRET-KEY: $SECRET_KEY" \
            -H "Accept: application/json")
        local response_type=$(echo "$response" | jq 'type' 2>/dev/null)
        if [ "$response_type" = "\"array\"" ]; then
            local activities=$(echo "$response" | jq -r '.[]' 2>/dev/null)
            if [ -n "$activities" ]; then
                type_activities="$type_activities"$'\n'"$activities"
            fi
            local count=$(echo "$response" | jq 'length' 2>/dev/null)
            echo "📄 Página $type_page_count: Encontradas $count actividades $activity_type"
            if [ "$count" -lt 100 ]; then
                echo "📄 Página $type_page_count: Solo $count actividades - no hay más páginas para $activity_type"
                break
            fi
            page_token=$(echo "$response" | jq -r '.[-1].id' 2>/dev/null)
            if [ "$page_token" = "null" ] || [ -z "$page_token" ]; then
                echo "📄 Página $type_page_count: No hay más token - fin de paginación para $activity_type"
                break
            fi
            echo "📄 Página $type_page_count: Continuando con token: $page_token"
        else
            local activities=$(echo "$response" | jq -r '.activities[]?' 2>/dev/null)
            if [ -n "$activities" ]; then
                type_activities="$type_activities"$'\n'"$activities"
            fi
            page_token=$(echo "$response" | jq -r '.next_page_token' 2>/dev/null)
            if [ "$page_token" = "null" ] || [ -z "$page_token" ]; then
                echo "📄 Página $type_page_count: No hay next_page_token - fin de paginación para $activity_type"
                break
            fi
            echo "📄 Página $type_page_count: Continuando con next_page_token: $page_token"
        fi
        if [ "$type_page_count" -gt 1000 ]; then
            echo "⚠️  Límite de páginas alcanzado (1000) para $activity_type"
            break
        fi
    done
    page_count=$((page_count + type_page_count))
    echo "📊 Total páginas consultadas para $activity_type: $type_page_count"
    echo "$type_activities" | grep -v '^$'
}

# Función para calcular retorno diario
calculate_daily_return() {
    local prev_equity="$1"
    local current_equity="$2"
    local cash_flow="$3"
    if is_zero_or_empty "$prev_equity"; then
        echo "0.0"; return
    fi
    local adjusted_equity="$current_equity"
    if ! is_zero_or_empty "$cash_flow"; then
        adjusted_equity=$(echo "$current_equity - $cash_flow" | bc -l 2>/dev/null || echo "$current_equity")
    fi
    local return=$(echo "($adjusted_equity - $prev_equity) / $prev_equity" | bc -l 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$return" ]; then echo "0.0"; else echo "$return"; fi
}

# === JSON OUTPUT (compacto para embed) ===
json_output() {
    local portfolio_url="$BASE_URL/v2/account/portfolio/history"
    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        portfolio_url="$portfolio_url?start=$START_DATE&end=$END_DATE&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"
    else
        portfolio_url="$portfolio_url?period=1M&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"
    fi
    PORTFOLIO_RESPONSE=$(curl -s "$portfolio_url" -H "APCA-API-KEY-ID: $API_KEY" -H "APCA-API-SECRET-KEY: $SECRET_KEY" -H "Accept: application/json")
    if [ -z "$PORTFOLIO_RESPONSE" ] || [ "$PORTFOLIO_RESPONSE" = "null" ]; then echo '{"error":"no_portfolio_data"}'; return 1; fi
    local all_activities=""; local page_token=""; local page_count=0
    while true; do
        page_count=$((page_count+1)); local url="$BASE_URL/v2/account/activities?activity_type=CSD,CSW&page_size=100&direction=asc"; [ -n "$page_token" ] && url="$url&page_token=$page_token"
        local response=$(curl -s "$url" -H "APCA-API-KEY-ID: $API_KEY" -H "APCA-API-SECRET-KEY: $SECRET_KEY" -H "Accept: application/json")
        local response_type=$(echo "$response" | jq 'type' 2>/dev/null)
        if [ "$response_type" = "\"array\"" ]; then
            local activities=$(echo "$response" | jq -r '.[] | select(.activity_type == "CSD" or .activity_type == "CSW")' 2>/dev/null); [ -n "$activities" ] && all_activities="$all_activities"$'\n'"$activities"; local count=$(echo "$response" | jq 'length' 2>/dev/null); [ "$count" -lt 100 ] && break; page_token=$(echo "$response" | jq -r '.[-1].id' 2>/dev/null); [ -z "$page_token" ] || [ "$page_token" = "null" ] && break
        else
            local activities=$(echo "$response" | jq -r '.activities[]? | select(.activity_type == "CSD" or .activity_type == "CSW")' 2>/dev/null); [ -n "$activities" ] && all_activities="$all_activities"$'\n'"$activities"; page_token=$(echo "$response" | jq -r '.next_page_token' 2>/dev/null); [ -z "$page_token" ] || [ "$page_token" = "null" ] && break
        fi
        [ "$page_count" -gt 1000 ] && break
    done
    local prev_equity=""; local cumulative_twr=1.0; local trading_started=false
    local timestamps=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.timestamp[]'); local equities=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.equity[]'); local pnls=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.profit_loss[]'); local pnl_pcts=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.profit_loss_pct[]')
    local timestamp_array=($timestamps); local equity_array=($equities); local pnl_array=($pnls); local pnl_pct_array=($pnl_pcts)
    echo '['; local first_item=true
    for i in "${!timestamp_array[@]}"; do
        local timestamp="${timestamp_array[$i]}"; local equity="${equity_array[$i]}"; local pnl="${pnl_array[$i]}"; local pnl_pct="${pnl_pct_array[$i]}"; local date=$(convert_timestamp "$timestamp")
        local deposits_today=0; local withdrawals_today=0; local deposits_yesterday=0; local withdrawals_yesterday=0
        if [ -n "$all_activities" ]; then
            local day_activities=$(echo "$all_activities" | jq -r --arg date "$date" 'select(.date == $date)'); [ -n "$day_activities" ] && deposits_today=$(echo "$day_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' | awk '{sum += $1} END {print sum+0}'); [ -n "$day_activities" ] && withdrawals_today=$(echo "$day_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' | awk '{sum += $1} END {print sum+0}')
        fi
        if [ -n "$all_activities" ] && [ "$i" -gt 0 ]; then
            local prev_timestamp="${timestamp_array[$((i-1))]}"; local prev_date=$(convert_timestamp "$prev_timestamp"); local prev_day_activities=$(echo "$all_activities" | jq -r --arg date "$prev_date" 'select(.date == $date)'); if [ -z "$prev_day_activities" ]; then local prev_date_num=$(date -j -f "%Y-%m-%d" "$prev_date" "+%Y%m%d" 2>/dev/null || echo "0"); local current_date_num=$(date -j -f "%Y-%m-%d" "$date" "+%Y%m%d" 2>/dev/null || echo "0"); prev_day_activities=$(echo "$all_activities" | jq -r --arg prev_num "$prev_date_num" --arg curr_num "$current_date_num" 'select(.date != null) | select((.date | gsub("-"; "") | tonumber) > ($prev_num | tonumber) and (.date | gsub("-"; "") | tonumber) < ($curr_num | tonumber))'); fi; [ -n "$prev_day_activities" ] && deposits_yesterday=$(echo "$prev_day_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' | awk '{sum += $1} END {print sum+0}'); [ -n "$prev_day_activities" ] && withdrawals_yesterday=$(echo "$prev_day_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' | awk '{sum += $1} END {print sum+0}')
        fi
        local net_cash_flow_today=$(echo "$deposits_today - $withdrawals_today" | bc -l 2>/dev/null || echo "0"); local net_cash_flow_yesterday=$(echo "$deposits_yesterday - $withdrawals_yesterday" | bc -l 2>/dev/null || echo "0")
        local daily_return=0.0; if [ -z "$prev_equity" ] || is_zero_or_empty "$prev_equity"; then daily_return=0.0; if ! is_zero_or_empty "$equity"; then cumulative_twr=1.0; trading_started=true; fi; else if [ "$trading_started" = true ]; then daily_return=$(calculate_daily_return "$prev_equity" "$equity" "$net_cash_flow_yesterday"); cumulative_twr=$(echo "$cumulative_twr * (1 + $daily_return)" | bc -l 2>/dev/null || echo "$cumulative_twr"); fi; fi
        $first_item || echo ','; first_item=false
        printf '{"date":"%s","equity":%.4f,"pnl":%.4f,"pnl_pct":%.6f,"deposits":%.4f,"withdrawals":%.4f,"net_cash_flow":%.4f,"daily_return":%.8f,"cumulative_twr":%.8f}' "$date" "$equity" "$pnl" "$pnl_pct" "$deposits_today" "$withdrawals_today" "$net_cash_flow_today" "$(echo "$daily_return" | bc -l 2>/dev/null || echo "0.0")" "$(echo "($cumulative_twr - 1)" | bc -l 2>/dev/null || echo "0.0")"
        prev_equity="$equity"
    done; echo ']'
}

main() { case "${1:-json}" in json) json_output ;; *) json_output ;; esac }

# Deps check
if ! command -v jq &> /dev/null; then echo "{\"error\":\"missing_jq\"}"; exit 1; fi
if ! command -v bc &> /dev/null; then echo "{\"error\":\"missing_bc\"}"; exit 1; fi

main "$@"
"""

    static func run(
        scriptAbsolutePath: String,
        apiKey: String,
        secretKey: String,
        startDate: Date,
        endDate: Date,
        timeframe: PortfolioHistoryTimeframe,
        extendedHours: Bool
    ) throws -> [TWRPoint] {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let tf: String = (timeframe == .oneMinute || timeframe == .oneMin) ? "1Min" : "1D"
        let ext = extendedHours ? "true" : "false"

        // Stage the embedded script into a sandbox-friendly temporary location and make it executable
        let temporaryDirectory = NSTemporaryDirectory()
        let stagedScriptPath = (temporaryDirectory as NSString).appendingPathComponent("twr_calculator_staged.sh")
        do {
            // Remove any previous staged script
            if fileManager.fileExists(atPath: stagedScriptPath) {
                try? fileManager.removeItem(atPath: stagedScriptPath)
            }
            // Write embedded script content to tmp
            let scriptData: Data
            if let data = TWRRunner.embeddedScript.data(using: .utf8), data.count > 0 {
                scriptData = data
            } else {
                // Fallback to reading from provided path if embedded content missing
                scriptData = try Data(contentsOf: URL(fileURLWithPath: scriptAbsolutePath))
            }
            try scriptData.write(to: URL(fileURLWithPath: stagedScriptPath), options: .atomic)
            // Ensure executable permissions (rwxr-xr-x)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedScriptPath)
        } catch {
            throw TWRRunnerError.executionFailed("Failed to stage script into temporary directory: \(error.localizedDescription)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [stagedScriptPath, "json"]

        var env = ProcessInfo.processInfo.environment
        env["API_KEY"] = apiKey
        env["SECRET_KEY"] = secretKey
        env["START_DATE"] = start
        env["END_DATE"] = end
        env["TIMEFRAME"] = tf
        env["EXTENDED_HOURS"] = ext
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
            throw TWRRunnerError.executionFailed(err)
        }

        do {
            let points = try JSONDecoder().decode([TWRPoint].self, from: data)
            return points.sorted { $0.timestamp < $1.timestamp }
        } catch {
            throw TWRRunnerError.decodingFailed(error.localizedDescription)
        }
    }
}


