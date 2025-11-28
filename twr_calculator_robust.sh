#!/bin/bash

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
        
        # Verificar si la respuesta es un array directo
        local response_type=$(echo "$response" | jq 'type' 2>/dev/null)
        
        if [ "$response_type" = "\"array\"" ]; then
            # Respuesta directa como array
            local activities=$(echo "$response" | jq -r '.[]' 2>/dev/null)
            if [ -n "$activities" ]; then
                type_activities="$type_activities"$'\n'"$activities"
            fi
            
            # Si tenemos menos de 100 actividades, no hay más páginas
            local count=$(echo "$response" | jq 'length' 2>/dev/null)
            echo "📄 Página $type_page_count: Encontradas $count actividades $activity_type"
            if [ "$count" -lt 100 ]; then
                echo "📄 Página $type_page_count: Solo $count actividades - no hay más páginas para $activity_type"
                break
            fi
            
            # Usar el ID de la última actividad como token para la siguiente página
            page_token=$(echo "$response" | jq -r '.[-1].id' 2>/dev/null)
            if [ "$page_token" = "null" ] || [ -z "$page_token" ]; then
                echo "📄 Página $type_page_count: No hay más token - fin de paginación para $activity_type"
                break
            fi
            echo "📄 Página $type_page_count: Continuando con token: $page_token"
        else
            # Respuesta como objeto con next_page_token
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
        
        # Límite de seguridad para evitar bucles infinitos
        if [ "$type_page_count" -gt 1000 ]; then
            echo "⚠️  Límite de páginas alcanzado (1000) para $activity_type"
            break
        fi
    done
    
    page_count=$((page_count + type_page_count))
    echo "📊 Total páginas consultadas para $activity_type: $type_page_count"
    
    # Retornar las actividades encontradas
    echo "$type_activities" | grep -v '^$' # Eliminar líneas vacías
}

# Función para calcular retorno diario de forma segura
# CORRECCIÓN IMPORTANTE: El flujo de caja se descuenta el día que se refleja en el equity,
# no el día que se registra. Esto significa que si hay un depósito el día D, se descuenta
# del equity del día D+1 para calcular el retorno del día D+1.
calculate_daily_return() {
    local prev_equity="$1"
    local current_equity="$2"
    local cash_flow="$3"
    
    # Si el equity anterior es cero o vacío, retorno = 0
    if is_zero_or_empty "$prev_equity"; then
        echo "0.0"
        return
    fi
    
    # LÓGICA CORREGIDA: El flujo de caja se descuenta del equity actual
    # porque representa el dinero que se añadió/retiró y que afecta el cálculo del retorno
    # del día actual. El equity actual ya incluye el efecto del flujo de caja.
    local adjusted_equity="$current_equity"
    if ! is_zero_or_empty "$cash_flow"; then
        # Descontar el flujo de caja del equity actual para obtener el rendimiento
        # real de la inversión existente (sin el efecto del flujo de caja)
        adjusted_equity=$(echo "$current_equity - $cash_flow" | bc -l 2>/dev/null || echo "$current_equity")
    fi
    
    # Calcular retorno: (equity_ajustado - equity_anterior) / equity_anterior
    local return=$(echo "($adjusted_equity - $prev_equity) / $prev_equity" | bc -l 2>/dev/null)
    
    # Si hay error en el cálculo, retornar 0
    if [ $? -ne 0 ] || [ -z "$return" ]; then
        echo "0.0"
    else
        echo "$return"
    fi
}

# =============================================================================
# FUNCIÓN PRINCIPAL ROBUSTA
# =============================================================================

calculate_twr_robust() {
    echo "🔍 Iniciando cálculo TWR robusto..."
    
    # =============================================================================
    # PASO 1: OBTENER DATOS DEL PORTFOLIO
    # =============================================================================
    echo "📊 Obteniendo datos del portfolio..."
    # Construir query por rango si se proveen fechas; de lo contrario period=1M
    local portfolio_url="$BASE_URL/v2/account/portfolio/history"
    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        portfolio_url="$portfolio_url?start=$START_DATE&end=$END_DATE&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"
    else
        portfolio_url="$portfolio_url?period=1M&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"
    fi

    PORTFOLIO_RESPONSE=$(curl -s "$portfolio_url" \
        -H "APCA-API-KEY-ID: $API_KEY" \
        -H "APCA-API-SECRET-KEY: $SECRET_KEY" \
        -H "Accept: application/json")
    
    # Verificar que la respuesta es válida
    if [ -z "$PORTFOLIO_RESPONSE" ] || [ "$PORTFOLIO_RESPONSE" = "null" ]; then
        echo "❌ Error: No se pudieron obtener datos del portfolio"
        return 1
    fi
    
    # =============================================================================
    # PASO 2: BUSCAR ACTIVIDADES CSD/CSW CON PAGINACIÓN
    # =============================================================================
    echo "💰 Buscando actividades CSD/CSW..."
    
    # Variables para almacenar actividades
    local all_activities=""
    local page_token=""
    local page_count=0
    
    # Buscar todas las actividades CSD/CSW con paginación CORRECTA
    while true; do
        page_count=$((page_count + 1))
        echo "📄 Consultando página $page_count..."
        
        local url="$BASE_URL/v2/account/activities?activity_type=CSD,CSW&page_size=100&direction=asc"
        if [ -n "$page_token" ]; then
            url="$url&page_token=$page_token"
        fi
        
        local response=$(curl -s "$url" \
            -H "APCA-API-KEY-ID: $API_KEY" \
            -H "APCA-API-SECRET-KEY: $SECRET_KEY" \
            -H "Accept: application/json")
        
        # Verificar si la respuesta es un array directo
        local response_type=$(echo "$response" | jq 'type' 2>/dev/null)
        echo "📄 Página $page_count: Tipo de respuesta: $response_type"
        
        if [ "$response_type" = "\"array\"" ]; then
            # Respuesta directa como array - FILTRAR SOLO CSD Y CSW
            local activities=$(echo "$response" | jq -r '.[] | select(.activity_type == "CSD" or .activity_type == "CSW")' 2>/dev/null)
            if [ -n "$activities" ]; then
                echo "📄 Página $page_count: Actividades CSD/CSW encontradas:"
                echo "$activities" | jq -r '. | "  \(.date) - \(.activity_type): \(.net_amount)"' 2>/dev/null
                all_activities="$all_activities"$'\n'"$activities"
            else
                echo "📄 Página $page_count: No se encontraron actividades CSD/CSW"
            fi
            
            # Si tenemos menos de 100 actividades, no hay más páginas
            local count=$(echo "$response" | jq 'length' 2>/dev/null)
            echo "📄 Página $page_count: Encontradas $count actividades totales"
            if [ "$count" -lt 100 ]; then
                echo "📄 Página $page_count: Solo $count actividades - no hay más páginas"
                break
            fi
            
            # Usar el ID de la última actividad como token para la siguiente página
            page_token=$(echo "$response" | jq -r '.[-1].id' 2>/dev/null)
            if [ "$page_token" = "null" ] || [ -z "$page_token" ]; then
                echo "📄 Página $page_count: No hay más token - fin de paginación"
                break
            fi
            echo "📄 Página $page_count: Continuando con token: $page_token"
        else
            # Respuesta como objeto con next_page_token
            local activities=$(echo "$response" | jq -r '.activities[]? | select(.activity_type == "CSD" or .activity_type == "CSW")' 2>/dev/null)
            if [ -n "$activities" ]; then
                all_activities="$all_activities"$'\n'"$activities"
            fi
            
            page_token=$(echo "$response" | jq -r '.next_page_token' 2>/dev/null)
            if [ "$page_token" = "null" ] || [ -z "$page_token" ]; then
                echo "📄 Página $page_count: No hay next_page_token - fin de paginación"
                break
            fi
            echo "📄 Página $page_count: Continuando con next_page_token: $page_token"
        fi
        
        # Límite de seguridad para evitar bucles infinitos
        if [ "$page_count" -gt 1000 ]; then
            echo "⚠️  Límite de páginas alcanzado (1000)"
            break
        fi
    done
    
    echo "📊 Total de páginas consultadas: $page_count"
    
    # =============================================================================
    # PASO 3: GENERAR TABLA TWR
    # =============================================================================
    echo ""
    echo "=================================================================================="
    echo "📊 TABLA TWR CON DATOS REALES Y FLUJOS DE CAJA"
    echo "=================================================================================="
    echo ""
    echo "📈 TABLA DIARIA CON DATOS REALES Y TWR CORRECTO:"
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
    printf "%-12s %-12s %-12s %-12s %-12s %-12s %-15s %-15s %-15s\n" \
        "Date" "Equity" "PnL" "PnL%" "Deposits" "Withdrawals" "Net Cash Flow" "Daily Return" "Cumulative TWR"
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
    
    # Variables para cálculo TWR
    local prev_equity=""
    local cumulative_twr=1.0
    local trading_started=false
    
    # Procesar datos del portfolio
    local timestamps=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.timestamp[]')
    local equities=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.equity[]')
    local pnls=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.profit_loss[]')
    local pnl_pcts=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.profit_loss_pct[]')
    
    # Convertir a arrays
    local timestamp_array=($timestamps)
    local equity_array=($equities)
    local pnl_array=($pnls)
    local pnl_pct_array=($pnl_pcts)
    
    # Procesar cada día
    for i in "${!timestamp_array[@]}"; do
        local timestamp="${timestamp_array[$i]}"
        local equity="${equity_array[$i]}"
        local pnl="${pnl_array[$i]}"
        local pnl_pct="${pnl_pct_array[$i]}"
        
        # Convertir timestamp a fecha
        local date=$(convert_timestamp "$timestamp")
        
        # =============================================================================
        # PASO 4: BUSCAR ACTIVIDADES PARA ESTA FECHA Y LA ANTERIOR
        # =============================================================================
        local deposits_today=0
        local withdrawals_today=0
        local deposits_yesterday=0
        local withdrawals_yesterday=0
        
        # Buscar actividades CSD/CSW para esta fecha (para mostrar en la tabla)
        if [ -n "$all_activities" ]; then
            local day_activities=$(echo "$all_activities" | jq -r --arg date "$date" 'select(.date == $date)' 2>/dev/null)
            if [ -n "$day_activities" ]; then
                deposits_today=$(echo "$day_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' 2>/dev/null | awk '{sum += $1} END {print sum+0}')
                withdrawals_today=$(echo "$day_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' 2>/dev/null | awk '{sum += $1} END {print sum+0}')
            fi
        fi
        
        # Buscar actividades CSD/CSW del día anterior (para el cálculo TWR)
        # CORRECCIÓN: El flujo de caja se aplica al día que se refleja en el equity
        if [ -n "$all_activities" ] && [ "$i" -gt 0 ]; then
            local prev_timestamp="${timestamp_array[$((i-1))]}"
            local prev_date=$(convert_timestamp "$prev_timestamp")
            
            # Buscar actividades del día anterior de trading
            local prev_day_activities=$(echo "$all_activities" | jq -r --arg date "$prev_date" 'select(.date == $date)' 2>/dev/null)
            
            # Si no hay actividades en el día anterior de trading, buscar actividades
            # que ocurrieron entre el día anterior y el día actual
            if [ -z "$prev_day_activities" ]; then
                # Convertir fechas a formato comparable
                local prev_date_num=$(date -j -f "%Y-%m-%d" "$prev_date" "+%Y%m%d" 2>/dev/null || echo "0")
                local current_date_num=$(date -j -f "%Y-%m-%d" "$date" "+%Y%m%d" 2>/dev/null || echo "0")
                
                # Buscar actividades entre estas fechas
                prev_day_activities=$(echo "$all_activities" | jq -r --arg prev_num "$prev_date_num" --arg curr_num "$current_date_num" '
                    select(.date != null) | 
                    select((.date | gsub("-"; "") | tonumber) > ($prev_num | tonumber) and 
                           (.date | gsub("-"; "") | tonumber) < ($curr_num | tonumber))
                ' 2>/dev/null)
                
                if [ -n "$prev_day_activities" ]; then
                    echo "📄 Aplicando flujo de caja entre $prev_date y $date"
                fi
            fi
            
            if [ -n "$prev_day_activities" ]; then
                deposits_yesterday=$(echo "$prev_day_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' 2>/dev/null | awk '{sum += $1} END {print sum+0}')
                withdrawals_yesterday=$(echo "$prev_day_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' 2>/dev/null | awk '{sum += $1} END {print sum+0}')
            fi
        fi
        
        local net_cash_flow_today=$(echo "$deposits_today - $withdrawals_today" | bc -l 2>/dev/null || echo "0")
        local net_cash_flow_yesterday=$(echo "$deposits_yesterday - $withdrawals_yesterday" | bc -l 2>/dev/null || echo "0")
        
        # =============================================================================
        # PASO 5: CALCULAR RETORNO DIARIO Y TWR DE FORMA ROBUSTA
        # =============================================================================
        local daily_return=0.0
        
        # Si es el primer día o el equity anterior es cero/vacío
        if [ -z "$prev_equity" ] || is_zero_or_empty "$prev_equity"; then
            daily_return=0.0
            
            # Si el equity actual es mayor que cero, empezar el cálculo TWR
            if ! is_zero_or_empty "$equity"; then
                cumulative_twr=1.0
                trading_started=true
            fi
        else
            # Solo calcular retorno si el trading ya empezó
            if [ "$trading_started" = true ]; then
                # CORRECCIÓN: Usar el flujo de caja del día anterior para el cálculo TWR
                daily_return=$(calculate_daily_return "$prev_equity" "$equity" "$net_cash_flow_yesterday")
                cumulative_twr=$(echo "$cumulative_twr * (1 + $daily_return)" | bc -l 2>/dev/null || echo "$cumulative_twr")
            fi
        fi
        
        # =============================================================================
        # PASO 6: FORMATEAR Y MOSTRAR RESULTADO
        # =============================================================================
        printf "%-12s $%-11.2f $%-11.2f %-11.4f%% $%-11.2f $%-11.2f $%-14.2f %-14.4f%% %-14.4f%%\n" \
            "$date" "$equity" "$pnl" "$pnl_pct" "$deposits_today" "$withdrawals_today" "$net_cash_flow_today" \
            "$(echo "$daily_return * 100" | bc -l 2>/dev/null || echo "0.0")" \
            "$(echo "($cumulative_twr - 1) * 100" | bc -l 2>/dev/null || echo "0.0")"
        
        prev_equity="$equity"
    done
    
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
    
    # =============================================================================
    # PASO 7: CALCULAR TWR FINAL Y MOSTRAR RESUMEN
    # =============================================================================
    local final_twr=$(echo "$cumulative_twr - 1" | bc -l 2>/dev/null || echo "0.0")
    local total_days=$(echo "$PORTFOLIO_RESPONSE" | jq '.timestamp | length')
    local base_value=$(echo "$PORTFOLIO_RESPONSE" | jq '.base_value')
    local base_date=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.base_value_asof')
    
    echo ""
    echo "📊 RESUMEN EJECUTIVO FINAL:"
    echo "============================"
    echo "• TWR Total: $(printf "%.4f" "$(echo "$final_twr * 100" | bc -l 2>/dev/null || echo "0.0")")%"
    echo "• Días de trading analizados: $total_days"
    echo "• Base Value: \$$base_value"
    echo "• Base Value Date: $base_date"
    
    echo ""
    echo "💰 FLUJOS DE CAJA ENCONTRADOS:"
    echo "==============================="
    if [ -n "$all_activities" ]; then
        local total_deposits=$(echo "$all_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        local total_withdrawals=$(echo "$all_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        echo "• Total Depósitos: \$$(printf "%.2f" "$total_deposits")"
        echo "• Total Retiros: \$$(printf "%.2f" "$total_withdrawals")"
        echo "• Net Cash Flow: \$$(printf "%.2f" "$(echo "$total_deposits - $total_withdrawals" | bc -l 2>/dev/null || echo "0.0")")"
    else
        echo "• No se encontraron actividades CSD/CSW"
    fi
    
    echo ""
    echo "🔧 METODOLOGÍA TWR APLICADA:"
    echo "============================="
    echo "• Time-Weighted Return elimina el efecto distorsionador de los flujos de caja"
    echo "• Cada subperíodo se calcula independientemente"
    echo "• TWR Final = (1 + r1) × (1 + r2) × ... × (1 + rn) - 1"
    echo "• Mide el rendimiento real por dólar invertido"
    echo "• Manejo robusto de casos especiales (equity $0.00, períodos inactivos)"
    
    echo ""
    echo "⚠️  NOTA IMPORTANTE:"
    echo "===================="
    echo "Esta tabla combina:"
    echo "• Datos REALES del portfolio de la API de Alpaca"
    echo "• Actividades REALES CSD/CSW con paginación completa"
    echo "• Metodología TWR correcta con ajuste por flujos de caja"
    echo "• Manejo robusto de casos especiales para cualquier cuenta"
}

# =============================================================================
# FUNCIÓN PRINCIPAL - PUNTO DE ENTRADA
# =============================================================================

json_output() {
    # Igual que calculate_twr_robust pero emite un JSON con un array de objetos
    # para facilitar el parseo desde la app.
    # Reutilizamos las mismas variables y lógica, pero acumulamos objetos JSON.
    calculate_prep || true
}

# Preparación compartida para JSON (envuelve el cálculo e imprime JSON)
calculate_prep() {
    # Reutilizar la obtención de portfolio y actividades de calculate_twr_robust
    # Ejecutamos la función original pero capturando datos necesarios línea a línea.
    # Para simplicidad y coherencia, repetimos la parte mínima aquí.

    local portfolio_url="$BASE_URL/v2/account/portfolio/history"
    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        portfolio_url="$portfolio_url?start=$START_DATE&end=$END_DATE&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"
    else
        portfolio_url="$portfolio_url?period=1M&timeframe=$TIMEFRAME&extended_hours=$EXTENDED_HOURS"
    fi

    PORTFOLIO_RESPONSE=$(curl -s "$portfolio_url" \
        -H "APCA-API-KEY-ID: $API_KEY" \
        -H "APCA-API-SECRET-KEY: $SECRET_KEY" \
        -H "Accept: application/json")

    if [ -z "$PORTFOLIO_RESPONSE" ] || [ "$PORTFOLIO_RESPONSE" = "null" ]; then
        echo '{"error":"no_portfolio_data"}'
        return 1
    fi

    # Buscar actividades CSD/CSW
    local all_activities=""
    local page_token=""
    local page_count=0
    while true; do
        page_count=$((page_count + 1))
        local url="$BASE_URL/v2/account/activities?activity_type=CSD,CSW&page_size=100&direction=asc"
        if [ -n "$page_token" ]; then
            url="$url&page_token=$page_token"
        fi
        local response=$(curl -s "$url" \
            -H "APCA-API-KEY-ID: $API_KEY" \
            -H "APCA-API-SECRET-KEY: $SECRET_KEY" \
            -H "Accept: application/json")
        local response_type=$(echo "$response" | jq 'type' 2>/dev/null)
        if [ "$response_type" = "\"array\"" ]; then
            local activities=$(echo "$response" | jq -r '.[] | select(.activity_type == "CSD" or .activity_type == "CSW")' 2>/dev/null)
            [ -n "$activities" ] && all_activities="$all_activities"$'\n'"$activities"
            local count=$(echo "$response" | jq 'length' 2>/dev/null)
            [ "$count" -lt 100 ] && break
            page_token=$(echo "$response" | jq -r '.[-1].id' 2>/dev/null)
            [ -z "$page_token" ] || [ "$page_token" = "null" ] && break
        else
            local activities=$(echo "$response" | jq -r '.activities[]? | select(.activity_type == "CSD" or .activity_type == "CSW")' 2>/dev/null)
            [ -n "$activities" ] && all_activities="$all_activities"$'\n'"$activities"
            page_token=$(echo "$response" | jq -r '.next_page_token' 2>/dev/null)
            [ -z "$page_token" ] || [ "$page_token" = "null" ] && break
        fi
        [ "$page_count" -gt 1000 ] && break
    done

    # Variables para cálculo TWR
    local prev_equity=""
    local cumulative_twr=1.0
    local trading_started=false

    local timestamps=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.timestamp[]')
    local equities=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.equity[]')
    local pnls=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.profit_loss[]')
    local pnl_pcts=$(echo "$PORTFOLIO_RESPONSE" | jq -r '.profit_loss_pct[]')

    local timestamp_array=($timestamps)
    local equity_array=($equities)
    local pnl_array=($pnls)
    local pnl_pct_array=($pnl_pcts)

    echo '['
    local first_item=true
    for i in "${!timestamp_array[@]}"; do
        local timestamp="${timestamp_array[$i]}"
        local equity="${equity_array[$i]}"
        local pnl="${pnl_array[$i]}"
        local pnl_pct="${pnl_pct_array[$i]}"
        local date=$(convert_timestamp "$timestamp")

        local deposits_today=0
        local withdrawals_today=0
        local deposits_yesterday=0
        local withdrawals_yesterday=0

        if [ -n "$all_activities" ]; then
            local day_activities=$(echo "$all_activities" | jq -r --arg date "$date" 'select(.date == $date)')
            [ -n "$day_activities" ] && deposits_today=$(echo "$day_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' | awk '{sum += $1} END {print sum+0}')
            [ -n "$day_activities" ] && withdrawals_today=$(echo "$day_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' | awk '{sum += $1} END {print sum+0}')
        fi

        if [ -n "$all_activities" ] && [ "$i" -gt 0 ]; then
            local prev_timestamp="${timestamp_array[$((i-1))]}"
            local prev_date=$(convert_timestamp "$prev_timestamp")
            local prev_day_activities=$(echo "$all_activities" | jq -r --arg date "$prev_date" 'select(.date == $date)')
            if [ -z "$prev_day_activities" ]; then
                local prev_date_num=$(date -j -f "%Y-%m-%d" "$prev_date" "+%Y%m%d" 2>/dev/null || echo "0")
                local current_date_num=$(date -j -f "%Y-%m-%d" "$date" "+%Y%m%d" 2>/dev/null || echo "0")
                prev_day_activities=$(echo "$all_activities" | jq -r --arg prev_num "$prev_date_num" --arg curr_num "$current_date_num" '
                    select(.date != null) |
                    select((.date | gsub("-"; "") | tonumber) > ($prev_num | tonumber) and
                           (.date | gsub("-"; "") | tonumber) < ($curr_num | tonumber))')
            fi
            [ -n "$prev_day_activities" ] && deposits_yesterday=$(echo "$prev_day_activities" | jq -r 'select(.activity_type == "CSD") | .net_amount' | awk '{sum += $1} END {print sum+0}')
            [ -n "$prev_day_activities" ] && withdrawals_yesterday=$(echo "$prev_day_activities" | jq -r 'select(.activity_type == "CSW") | .net_amount' | awk '{sum += $1} END {print sum+0}')
        fi

        local net_cash_flow_today=$(echo "$deposits_today - $withdrawals_today" | bc -l 2>/dev/null || echo "0")
        local net_cash_flow_yesterday=$(echo "$deposits_yesterday - $withdrawals_yesterday" | bc -l 2>/dev/null || echo "0")

        local daily_return=0.0
        if [ -z "$prev_equity" ] || is_zero_or_empty "$prev_equity"; then
            daily_return=0.0
            if ! is_zero_or_empty "$equity"; then
                cumulative_twr=1.0
                trading_started=true
            fi
        else
            if [ "$trading_started" = true ]; then
                daily_return=$(calculate_daily_return "$prev_equity" "$equity" "$net_cash_flow_yesterday")
                cumulative_twr=$(echo "$cumulative_twr * (1 + $daily_return)" | bc -l 2>/dev/null || echo "$cumulative_twr")
            fi
        fi

        $first_item || echo ','
        first_item=false
        printf '{"date":"%s","equity":%.4f,"pnl":%.4f,"pnl_pct":%.6f,"deposits":%.4f,"withdrawals":%.4f,"net_cash_flow":%.4f,"daily_return":%.8f,"cumulative_twr":%.8f}' \
            "$date" "$equity" "$pnl" "$pnl_pct" "$deposits_today" "$withdrawals_today" "$net_cash_flow_today" \
            "$(echo "$daily_return" | bc -l 2>/dev/null || echo "0.0")" \
            "$(echo "($cumulative_twr - 1)" | bc -l 2>/dev/null || echo "0.0")"

        prev_equity="$equity"
    done
    echo ']'
}

main() {
    case "${1:-full}" in
        "full")
            calculate_twr_robust
            ;;
        "json")
            json_output
            ;;
        "help"|"-h"|"--help")
            echo "Uso: $0 [full|json|help]"
            echo ""
            echo "Variables de entorno: API_KEY, SECRET_KEY, START_DATE, END_DATE, TIMEFRAME (1D|1Min), EXTENDED_HOURS (true|false)"
            echo ""
            echo "Opciones:"
            echo "  full      - Imprime tabla humana + resumen"
            echo "  json      - Imprime JSON con los puntos diarios"
            echo "  help      - Muestra esta ayuda"
            ;;
        *)
            echo "Opción no válida. Usa '$0 help' para ver las opciones disponibles."
            exit 1
            ;;
    esac
}

# =============================================================================
# EJECUTAR SCRIPT
# =============================================================================

# Verificar dependencias
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq no está instalado. Instálalo con: brew install jq"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "❌ Error: bc no está instalado. Instálalo con: brew install bc"
    exit 1
fi

# Ejecutar función principal
main "$@"
