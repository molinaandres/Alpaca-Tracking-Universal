import Foundation

final class TWREmbeddedRunner {
    static let script: String = """
#!/bin/bash
API_KEY="${API_KEY:-}"; SECRET_KEY="${SECRET_KEY:-}"; BASE_URL="https://api.alpaca.markets"; START_DATE="${START_DATE:-}"; END_DATE="${END_DATE:-}"; TIMEFRAME="${TIMEFRAME:-1D}"; EXTENDED_HOURS="${EXTENDED_HOURS:-false}";
if [ -z "$API_KEY" ] || [ -z "$SECRET_KEY" ]; then echo '{"error":"missing_keys"}'; exit 1; fi
if ! command -v jq >/dev/null; then echo '{"error":"missing_jq"}'; exit 1; fi
if ! command -v bc >/dev/null; then echo '{"error":"missing_bc"}'; exit 1; fi
convert_ts(){ date -r "$1" +"%Y-%m-%d" 2>/dev/null || echo "N/A"; }
is_zero(){ v="$1"; [ -z "$v" ] || [ "$v" = 0 ] || [ "$v" = 0.0 ] || [ "$v" = 0.00 ]; }
calc_ret(){ pe="$1"; ce="$2"; cf="$3"; if is_zero "$pe"; then echo 0.0; return; fi; ae="$ce"; if ! is_zero "$cf"; then ae=$(echo "$ce - $cf" | bc -l 2>/dev/null || echo "$ce"); fi; echo "($ae - $pe)/$pe" | bc -l 2>/dev/null || echo 0.0; }
ph_url="$BASE_URL/v2/account/portfolio/history"; if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then ph_url="$ph_url?start=$START_DATE&end=$END_DATE&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"; else ph_url="$ph_url?period=1M&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"; fi
PH=$(curl -s "$ph_url" -H "APCA-API-KEY-ID: $API_KEY" -H "APCA-API-SECRET-KEY: $SECRET_KEY" -H "Accept: application/json"); if [ -z "$PH" ] || [ "$PH" = null ]; then echo '{"error":"no_portfolio_data"}'; exit 0; fi
ACT=""; for typ in CSD CSW; do tok=""; pc=0; while true; do pc=$((pc+1)); url="$BASE_URL/v2/account/activities/$typ?after=$START_DATE&until=$END_DATE&page_size=100&direction=asc"; [ -n "$tok" ] && url="$url&page_token=$tok"; R=$(curl -s "$url" -H "APCA-API-KEY-ID: $API_KEY" -H "APCA-API-SECRET-KEY: $SECRET_KEY" -H "Accept: application/json"); t=$(echo "$R"|jq 'type'); if [ "$t" = '"array"' ]; then A=$(echo "$R"|jq -r '.[]'); [ -n "$A" ] && ACT="$ACT"$'\n'"$A"; c=$(echo "$R"|jq 'length'); [ "$c" -lt 100 ] && break; tok=$(echo "$R"|jq -r '.[-1].id'); [ -z "$tok" ] || [ "$tok" = null ] && break; else A=$(echo "$R"|jq -r '.activities[]?'); [ -n "$A" ] && ACT="$ACT"$'\n'"$A"; tok=$(echo "$R"|jq -r '.next_page_token'); [ -z "$tok" ] || [ "$tok" = null ] && break; fi; [ "$pc" -gt 1000 ] && break; done; done
prev=""; twr=1.0; started=false
TS=($(echo "$PH"|jq -r '.timestamp[]')); EQ=($(echo "$PH"|jq -r '.equity[]')); PNL=($(echo "$PH"|jq -r '.profit_loss[]')); PPC=($(echo "$PH"|jq -r '.profit_loss_pct[]'))
echo '['; first=1; for i in "${!TS[@]}"; do ts="${TS[$i]}"; eq="${EQ[$i]}"; pnl="${PNL[$i]}"; ppc="${PPC[$i]}"; d=$(convert_ts "$ts"); depT=0; wdrT=0; depY=0; wdrY=0; if [ -n "$ACT" ]; then day=$(echo "$ACT"|jq -r --arg d "$d" 'select(.date==$d)'); [ -n "$day" ] && depT=$(echo "$day"|jq -r 'select(.activity_type=="CSD")|.net_amount'|awk '{s+=$1} END{print s+0}'); [ -n "$day" ] && wdrT=$(echo "$day"|jq -r 'select(.activity_type=="CSW")|.net_amount'|awk '{s+=$1} END{print s+0}'); fi
if [ -n "$ACT" ] && [ "$i" -gt 0 ]; then pts="${TS[$((i-1))]}"; pd=$(convert_ts "$pts"); prevA=$(echo "$ACT"|jq -r --arg d "$pd" 'select(.date==$d)'); if [ -z "$prevA" ]; then pn=$(date -j -f "%Y-%m-%d" "$pd" "+%Y%m%d" 2>/dev/null||echo 0); cn=$(date -j -f "%Y-%m-%d" "$d" "+%Y%m%d" 2>/dev/null||echo 0); prevA=$(echo "$ACT"|jq -r --arg pn "$pn" --arg cn "$cn" 'select(.date!=null) | select((.date|gsub("-";"")|tonumber) > ($pn|tonumber) and (.date|gsub("-";"")|tonumber) < ($cn|tonumber))'); fi; [ -n "$prevA" ] && depY=$(echo "$prevA"|jq -r 'select(.activity_type=="CSD")|.net_amount'|awk '{s+=$1} END{print s+0}'); [ -n "$prevA" ] && withdrawalsY=$(echo "$prevA"|jq -r 'select(.activity_type=="CSW")|.net_amount'|awk '{s+=$1} END{print s+0}'); wdrY=${withdrawalsY:-0}; fi
ncT=$(echo "$depT - $wdrT"|bc -l 2>/dev/null||echo 0); ncY=$(echo "$depY - $wdrY"|bc -l 2>/dev/null||echo 0); dr=0.0; if [ -z "$prev" ] || is_zero "$prev"; then dr=0.0; if ! is_zero "$eq"; then twr=1.0; started=true; fi; else if [ "$started" = true ]; then dr=$(calc_ret "$prev" "$eq" "$ncY"); twr=$(echo "$twr*(1+$dr)"|bc -l 2>/dev/null||echo "$twr"); fi; fi; [ $first -eq 1 ] || echo ','; first=0; printf '{"date":"%s","equity":%.4f,"pnl":%.4f,"pnl_pct":%.6f,"deposits":%.4f,"withdrawals":%.4f,"net_cash_flow":%.4f,"daily_return":%.8f,"cumulative_twr":%.8f}' "$d" "$eq" "$pnl" "$ppc" "$depT" "$wdrT" "$ncT" "$(echo "$dr"|bc -l 2>/dev/null||echo 0.0)" "$(echo "($twr-1)"|bc -l 2>/dev/null||echo 0.0)"; prev="$eq"; done; echo ']'
"""

    static func run(apiKey: String, secretKey: String, startDate: Date, endDate: Date, timeframe: PortfolioHistoryTimeframe, extendedHours: Bool) throws -> Data {
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory()
        let path = (tmp as NSString).appendingPathComponent("twr_embed.sh")
        if fm.fileExists(atPath: path) { try? fm.removeItem(atPath: path) }
        try Self.script.data(using: .utf8)!.write(to: URL(fileURLWithPath: path), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [path, "json"]
        var env = ProcessInfo.processInfo.environment
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York")
        env["API_KEY"] = apiKey; env["SECRET_KEY"] = secretKey; env["START_DATE"] = f.string(from: startDate); env["END_DATE"] = f.string(from: endDate); env["TIMEFRAME"] = (timeframe == .oneMinute) ? "1Min" : "1D"; env["EXTENDED_HOURS"] = extendedHours ? "true" : "false"; p.environment = env
        let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err; try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "error"; throw NSError(domain: "TWR", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: e]) }
        return out.fileHandleForReading.readDataToEndOfFile()
    }
}


