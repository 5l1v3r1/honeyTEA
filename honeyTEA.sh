#!/usr/bin/env bash

# Sazan avlamaya ne dersiniz?
# http://www.teakolik.com
# TEAkolik@TEAkolik.com
# @TEAkolik
# Version 2.0.2

###
### AYARLAR
###

## IP Bloke Süresi Dakika Cinsinden
BANNED_TIME=90

## Cloudflare Üyeliği E-posta Adresi
USER="CLOUDFLARE@EXAMPLE.COM"

## Cloudflare Public Api Key Giriyoruz
TOKEN="CLOUDFLAREPUBLICAPIKEY"

## IP Ayar Dosyalarınızın Lokasyonları
LINE_FILE="/var/www/html/HoneyTEA/line.dat"
BLACKLIST_FILE="/var/www/html/HoneyTEA/blacklist.dat"

## Nginx veya Apache Access Log Dosyanızın Lokasyonu ve Dosya Adı
LOG_FILE="/var/log/httpd/access.log"

###
### AYARLAR BURADA BITTI! BUNDAN SONRASI HoneyTEA Scripti Başlıyor
###

# Config Dosyası Kontrolü Yapıyoruz
if [ ! $# -eq 1 ]
then
    	echo "Usage: $0 <config.txt>"
        exit 1
fi

config="$1"

if [ ! -f "$config"  ]
then
    	echo "File: $config Ayar dosyasını belirtiniz! Kullanım ./honeyTEA.sh config.txt"
        exit 1
fi

# Config Dosyasını Okuyoruz Sazanları Avlıyoruz
function get_config_line() {
        line_count=$(wc -l $config | awk '{print $1}')

        count=1
        cat "$config" | while read -r config_file
        do
          	if [ $count -eq $line_count ]
                then
                    	echo -n "$config_file"
                else
                    	echo -n "$config_file|"
                fi

                count=$((count + 1))
        done
}

# Ip Blacklist Kontrolü Yapıyoruz
function is_ip_in_blacklist() {

        ip="$1"

        grep -Eq "^$ip" $BLACKLIST_FILE
        return $?
}

# Önce Blokeliyse ve Süresi Dolduysa Blokeyi Açıyoruz
function accept_cloudflare() {

        ip="$1"
	JSON=$(curl -sSX GET "https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules?mode=block&configuration_target=ip&configuration_value=$ip" -H "X-Auth-Email: $USER" -H "X-Auth-Key: $TOKEN") 
	ID=$(echo $JSON | jq -r '.result[].id')
	echo $JSON

# Önceki Blokeleri Temizliyoruz
	curl -X DELETE "https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules/$ID" \
     		-H "X-Auth-Email: $USER" \
     		-H "X-Auth-Key: $TOKEN" \
     		-H "Content-Type: application/json" \
     		--data '{"cascade":"none"}'
}
# Bloke Ediyoruz Cloudflare Üzerinden
function block_cloudflare() {
        ip="$1"
        curl -ssX POST "https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules" -H "X-Auth-Email: $USER" -H "X-Auth-Key: $TOKEN" -H "Content-Type: application/json" --data "{\"mode\":\"block\",\"configuration\":{\"target\":\"ip\",\"value\":\"$ip\"},\"notes\":\"Block honeyTEA Project\"}"
}
# Black List Dosyası İçeriğinden Blokesi Kaldırılan IPyi kaldırıyoruz.
function clear_out_file() {
        ip="$1"
        tmp_out_file="`mktemp /tmp/$USER.XXXXXX`"
        grep -Ev "^$ip$" $BLACKLIST_FILE > $tmp_out_file
        rm -f $BLACKLIST_FILE
        mv "$tmp_out_file" "$BLACKLIST_FILE"
}
function run() {
        now=$(date +%s)
        cat $BLACKLIST_FILE | grep -Ev "^$" | while read -r line
        do
          	timestamp=$(echo "$line" | cut -d ":" -f1)
                ip=$(echo "$line" | cut -d ":" -f2)
                seconds=$(echo "$BANNED_TIME * 60" | bc -l )
                time_diff=$(echo "$now-$timestamp" | bc -l)
                if [  $time_diff -gt $seconds ]
                then
                    	accept_cloudflare "$ip"
                        clear_out_file "$ip"
                else
                    	block_cloudflare "$ip"
                fi
        done
}
# Line Dosyasını Okuyoruz, Kaldığımız Yerden Devam Ediyoruz.
function main() {
        line=0
	if [ -f $LINE_FILE ]
        then
            	line=$(cat $LINE_FILE)
        fi
	log_file_line=$(wc -l $LOG_FILE | cut -d " " -f1)
        if [ $line -gt $log_file_line ]
        then
            	line=0
        fi
	echo "$log_file_line" > $LINE_FILE
        result=$(get_config_line)
        diff=$(echo "$log_file_line - $line"| bc -l)
        cat "$LOG_FILE" | tail -"$diff" |  grep -E "$result" | while read -r line
        do
          	echo -n "$line" | cut -d " " -f1
        done | sort -nu | while read -r ip
        do
          	if ! is_ip_in_blacklist "$ip"
                then
                    	timestamp=$(date +%s)
                        echo "$timestamp:$ip" >> $BLACKLIST_FILE
                fi
        done
	run
}
#
##
###
#### Main Döngüsü 
###
##
#
main
