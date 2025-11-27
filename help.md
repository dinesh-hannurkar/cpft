ping dineshs-pixel.local

nslookup dineshs-pixel.local

ping 192.168.1.188

dns-sd -B _http._tcp

ps aux | grep dns-sd

dns-sd -G v4 dineshs-pixel.local

ping dineshs-pixel.local

curl -I http://dineshs-pixel.local:8080/

curl -I http://192.168.1.188:8080/

dns-sd -L "dineshs-pixel" _http._tcp local.

dig @224.0.0.251 -p 5353 dineshs-pixel.local A