#!/bin/bash

show() {
    local color=$1
    local message=$2
    case $color in
        "blue") echo -e "\033[1;34m$message\033[0m" ;;
        "green") echo -e "\033[1;32m$message\033[0m" ;;
        "yellow") echo -e "\033[1;33m$message\033[0m" ;;
        "red") echo -e "\033[1;31m$message\033[0m" ;;
        "purple") echo -e "\033[1;35m$message\033[0m" ;;
        "cyan") echo -e "\033[1;36m$message\033[0m" ;;
        *) echo -e "\033[1;37m$message\033[0m" ;; # белый по умолчанию
    esac
}

get_proxy() {
    show "blue" "Введите данные прокси в формате protocol://ip:port"
    show "blue" "Примеры:"
    show "blue" "  socks5://11.22.33.44:1080"
    show "blue" "  http://11.22.33.44:8080"
    show "blue" "  socks5://user:pass@11.22.33.44:1080"
    read -p "Прокси: " proxy
    echo "$proxy"
}

install_browser() {
    local container_name=$1
    local proxy_url=$2
    
    USERNAME=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 5; echo)
    PASSWORD=$(< /dev/urandom tr -dc 'A-Za-z0-9@#$&' | head -c 10; echo)
    CREDENTIALS_FILE="$HOME/vps-browser-credentials-$container_name.json"
    
    mkdir -p "$HOME/chromium/$container_name/config"
    
    CHROME_ARGS=""
    
    # Применяем усиленные настройки безопасности только для браузера с прокси
    if [ ! -z "$proxy_url" ]; then
        # Базовые аргументы безопасности
        CHROME_ARGS="--disable-webrtc-multiple-routes --disable-webrtc-hide-local-ips-with-mdns --disable-webrtc-hw-encoding --disable-webrtc-hw-decoding"
        
        # Дополнительные настройки безопасности
        CHROME_ARGS="$CHROME_ARGS --disable-reading-from-canvas --disable-background-networking --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-breakpad --disable-client-side-phishing-detection --disable-default-apps --disable-dev-shm-usage --disable-translate"
        
        # Настройки прокси
        CHROME_ARGS="$CHROME_ARGS --proxy-server=$proxy_url --proxy-bypass-list=<-loopback>"
        
        # Создаем файл политик безопасности только для прокси-браузера
        mkdir -p "$HOME/chromium/$container_name/config/policies"
        cat <<EOL > "$HOME/chromium/$container_name/config/policies/managed_policies.json"
{
    "WebRtcIPHandlingPolicy": "disable_non_proxied_udp",
    "AudioCaptureAllowed": false,
    "VideoCaptureAllowed": false,
    "DefaultGeolocationSetting": 2,
    "AutofillAddressEnabled": false,
    "AutofillCreditCardEnabled": false,
    "PasswordManagerEnabled": false,
    "SafeBrowsingEnabled": false,
    "SearchSuggestEnabled": false,
    "MetricsReportingEnabled": false,
    "NetworkPredictionEnabled": false
}
EOL
    fi
    
    IP=$(curl -s ifconfig.me)
    
    # Разные рматы файла credentials в зависимости от типа браузера
    if [ ! -z "$proxy_url" ]; then
        cat <<EOL > "$CREDENTIALS_FILE"
{
    "browser": "$container_name",
    "username": "$USERNAME",
    "password": "$PASSWORD",
    "proxy": "$proxy_url",
    "security_settings": {
        "webrtc_disabled": true,
        "canvas_fingerprinting_disabled": true,
        "proxy_bypass_disabled": true
    }
}
EOL
    else
        cat <<EOL > "$CREDENTIALS_FILE"
{
    "browser": "$container_name",
    "username": "$USERNAME",
    "password": "$PASSWORD"
}
EOL
    fi
    
    sudo docker run -d \
        --name $container_name \
        -e TITLE=$container_name \
        -e DISPLAY=:1 \
        -e PUID=1000 \
        -e PGID=1000 \
        -e CUSTOM_USER="$USERNAME" \
        -e PASSWORD="$PASSWORD" \
        -e LANGUAGE=en_US.UTF-8 \
        -e CHROME_ARGS="$CHROME_ARGS --no-sandbox --enable-extensions --enable-features=VizDisplayCompositor,UseOzonePlatform --ozone-platform=wayland --enable-clipboard-read --enable-clipboard-write" \
        -e ENABLE_CLIPBOARD=true \
        -e GUACD_DISABLE_CLIPBOARD=false \
        -e ENABLE_WEBRTC=true \
        -e GUACD_CLIPBOARD_MAX_LENGTH=10485760 \
        -v "$HOME/chromium/$container_name/config:/config" \
        -v /dev/shm:/dev/shm \
        -v /etc/localtime:/etc/localtime:ro \
        -p 3000:3000 \
        -p 3001:3001 \
        --shm-size="2gb" \
        --security-opt seccomp=unconfined \
        --restart unless-stopped \
        lscr.io/linuxserver/chromium:latest
        
    show "green" "Браузер установлен!"
    show "cyan" "Доступ: http://$IP:3000/ или https://$IP:3001/"
    show "cyan" "Имя пользователя: $USERNAME"
    show "cyan" "Пароль: $PASSWORD"
    show "cyan" "Учетные данные сохранены в $CREDENTIALS_FILE"
    
    # Показываем информацию о безпасности только для прокси-браузера
    if [ ! -z "$proxy_url" ]; then
        show "cyan" "\nВажные настройки безопасности:"
        show "cyan" "✓ WebRTC отключен"
        show "cyan" "✓ Canvas fingerprinting отключен"
        show "cyan" "✓ Геолокация отключена"
        show "cyan" "✓ Обход прокси заблокирован"
        show "cyan" "✓ Сбор метрик отключен"
        show "cyan" "✓ Предсказание сети отключено"
    fi
}

check_requirements() {
    # Проверка и обновление системы
    show "yellow" "Проверка обновлений системы..."
    sudo apt-get update
    
    # Проверка необходимых пакетов
    if ! [ -x "$(command -v curl)" ]; then
        show "yellow" "curl не установлен. Установка..."
        sudo apt-get install -y curl
    fi
    
    if ! [ -x "$(command -v unzip)" ]; then
        show "yellow" "unzip не установлен. Установка..."
        sudo apt-get install -y unzip
    fi
    
    if ! [ -x "$(command -v docker)" ]; then
        show "yellow" "Docker не установлен. Установка..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
    fi
    
    show "cyan" "Загрузка образа Chromium..."
    sudo docker pull linuxserver/chromium:latest
}

remove_browser() {
    show "yellow" "╔═══ Список установленных браузеров ═══╗"
    
    # Получаем список браузеров
    browsers=($(docker ps -a --filter "ancestor=lscr.io/linuxserver/chromium" --format "{{.Names}}"))
    
    if [ ${#browsers[@]} -eq 0 ]; then
        show "red" "Установленных браузеров не найдено!"
        return
    fi
    
    # Показываем список с нумерацией и статусом
    for i in "${!browsers[@]}"; do
        status=$(docker ps -f "name=${browsers[$i]}" --format "{{.Status}}" | grep -q "Up" && echo "🟢 Работает" || echo "🔴 Остановлен")
        show "cyan" "[$((i+1))] ${browsers[$i]} - $status"
    done
    
    echo
    show "green" "Введите номер браузера для удаления (или 'q' для отмены):"
    read -p "> " choice
    
    # Проверка на отмену
    if [[ "$choice" == "q" ]]; then
        show "yellow" "Операция отменена"
        return
    fi
    
    # Проверка корректности ввода
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#browsers[@]} ]; then
        show "red" "⚠ Неверный выбор!"
        return
    fi
    
    browser_name=${browsers[$((choice-1))]}
    show "yellow" "Удаление браузера $browser_name..."
    
    sudo docker stop $browser_name
    sudo docker rm $browser_name
    rm -f "$HOME/vps-browser-credentials-$browser_name.json"
    rm -rf "$HOME/chromium/$browser_name"
    show "green" "✓ Браузер $browser_name успешно удален"
}

restart_browser() {
    show "yellow" "╔═══ Список установленных браузеров ═══╗"
    
    browsers=($(docker ps -a --filter "ancestor=lscr.io/linuxserver/chromium" --format "{{.Names}}"))
    
    if [ ${#browsers[@]} -eq 0 ]; then
        show "red" "Установленных браузеров не найдено!"
        return
    fi
    
    for i in "${!browsers[@]}"; do
        status=$(docker ps -f "name=${browsers[$i]}" --format "{{.Status}}" | grep -q "Up" && echo "🟢 Работает" || echo "🔴 Остановлен")
        show "cyan" "[$((i+1))] ${browsers[$i]} - $status"
    done
    
    echo
    show "green" "Введите номер браузера для перезапуска (или 'q' для отмены):"
    read -p "> " choice
    
    if [[ "$choice" == "q" ]]; then
        show "yellow" "Операция отменена"
        return
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#browsers[@]} ]; then
        show "red" "⚠ Неверный выбор!"
        return
    fi
    
    browser_name=${browsers[$((choice-1))]}
    show "yellow" "Перезапуск браузера $browser_name..."
    
    sudo docker restart $browser_name
    
    if [ $? -eq 0 ]; then
        show "green" "✓ Браузер $browser_name успешно перезапущен"
        
        # Показываем данные для входа
        credentials_file="$HOME/vps-browser-credentials-$browser_name.json"
        if [ -f "$credentials_file" ]; then
            IP=$(curl -s ifconfig.me)
            show "cyan" "Данные для входа:"
            show "cyan" "URL: http://$IP:3000/ или https://$IP:3001/"
            show "cyan" "Учетные данные сохранены в $credentials_file"
        fi
    else
        show "red" "✗ Ошибка при перезапуске браузера $browser_name"
    fi
}

view_logs() {
    show "yellow" "╔═══ Список установленных браузеров ═╗"
    
    browsers=($(docker ps -a --filter "ancestor=lscr.io/linuxserver/chromium" --format "{{.Names}}"))
    
    if [ ${#browsers[@]} -eq 0 ]; then
        show "red" "Установленных браузеров не найдно!"
        return
    fi
    
    for i in "${!browsers[@]}"; do
        status=$(docker ps -f "name=${browsers[$i]}" --format "{{.Status}}" | grep -q "Up" && echo "🟢 Работает" || echo "🔴 Остановлен")
        show "cyan" "[$((i+1))] ${browsers[$i]} - $status"
    done
    
    echo
    show "green" "Введите номер браузера для просмотра логов (или 'q' для отмены):"
    read -p "> " choice
    
    if [[ "$choice" == "q" ]]; then
        show "yellow" "Операция отменена"
        return
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#browsers[@]} ]; then
        show "red" "⚠ Неверный во!"
        return
    fi
    
    browser_name=${browsers[$((choice-1))]}
    show "yellow" "Последние логи браузера $browser_name:"
    echo
    sudo docker logs --tail 50 $browser_name
    echo
    show "green" "Нажмите Enter для возврата в меню..."
    read
}

view_browsers() {
    show "yellow" "╔═══ Список установленных браузеров ═══╗"
    
    browsers=($(docker ps -a --filter "ancestor=lscr.io/linuxserver/chromium" --format "{{.Names}}"))
    
    if [ ${#browsers[@]} -eq 0 ]; then
        show "red" "Установленных браузеров не найдено!"
        return
    fi
    
    IP=$(curl -s ifconfig.me)
    
    for i in "${!browsers[@]}"; do
        status=$(docker ps -f "name=${browsers[$i]}" --format "{{.Status}}" | grep -q "Up" && echo "🟢 Работает" || echo "🔴 Остановлен")
        credentials_file="$HOME/vps-browser-credentials-${browsers[$i]}.json"
        
        show "yellow" "╔═══ Браузер #$((i+1)) ═══╗"
        show "cyan" "Имя: ${browsers[$i]}"
        show "cyan" "Статус: $status"
        show "cyan" "URL: http://$IP:3000/ или https://$IP:3001/"
        
        if [ -f "$credentials_file" ]; then
            show "green" "=== Учетные данные ==="
            username=$(grep -o '"username": "[^"]*' "$credentials_file" | cut -d'"' -f4)
            password=$(grep -o '"password": "[^"]*' "$credentials_file" | cut -d'"' -f4)
            proxy=$(grep -o '"proxy": "[^"]*' "$credentials_file" | cut -d'"' -f4)
            
            show "blue" "Логин: $username"
            show "blue" "Пароль: $password"
            [ ! -z "$proxy" ] && show "blue" "Прокси: $proxy"
        else
            show "red" "Файл с учетными данными не найден!"
        fi
        echo
    done
}

main_menu() {
    while true; do
        clear
        echo -e "\033[1;34m+-----------------------------------+\033[0m"
        echo -e "\033[1;34m|\033[0m     \033[1;33mУправление браузером VPS\033[0m    \033[1;34m|\033[0m"
        echo -e "\033[1;34m+-----------------------------------+\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;32m1.\033[0m Установить браузер               \033[1;34m|\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;32m2.\033[0m Установить браузер с прокси      \033[1;34m|\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;32m3.\033[0m Просмотр установленных браузеров \033[1;34m|\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;32m4.\033[0m Перезапустить браузер            \033[1;34m|\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;32m5.\033[0m Просмотр огов браузера          \033[1;34m|\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;32m6.\033[0m Удалить браузер                  \033[1;34m|\033[0m"
        echo -e "\033[1;34m|\033[0m \033[1;31m7.\033[0m Выход                            \033[1;34m|\033[0m"
        echo -e "\033[1;34m+-----------------------------------+\033[0m"
        echo
        show "blue" "Введите номер выбранного пункта:"
        read -p "> " choice
        
        case $choice in
            1)
                clear
                show "yellow" "╔═══ Установка браузера ═══╗"
                check_requirements
                install_browser "browser" ""
                show "cyan" "Нажмите Enter для продолжения..."
                read
                ;;
            2)
                clear
                show "yellow" "╔═══ Установка браузера с прокси ═══╗"
                proxy_url=$(get_proxy)
                check_requirements
                install_browser "browser-proxy" "$proxy_url"
                show "cyan" "Нажмите Enter для продолжения..."
                read
                ;;
            3)
                clear
                show "yellow" "╔═══ Просмотр браузеров ═══╗"
                view_browsers
                show "cyan" "Нажмите Enter для продолженя..."
                read
                ;;
            4)
                clear
                show "yellow" "╔═══ Перезапуск браузера ═══╗"
                restart_browser
                show "cyan" "Нажмите Enter для продолжения..."
                read
                ;;
            5)
                clear
                show "yellow" "╔═══ Просмотр логов ═══╗"
                view_logs
                show "cyan" "Нажмите Enter для продолжения..."
                read
                ;;
            6)
                clear
                show "yellow" "╔═══ Удаление браузера ═══╗"
                remove_browser
                show "cyan" "Нажмите Enter для продолжения..."
                read
                ;;
            7)
                clear
                show "yellow" "╔═══ Завершение работы ═══╗"
                show "green" "Спасибо за использование! До свидания!"
                exit 0
                ;;
            *)
                show "red" "⚠ Неверный выбор! Попробуйте снова."
                sleep 2
                ;;
        esac
    done
}

main_menu