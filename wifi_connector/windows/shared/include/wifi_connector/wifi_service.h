#ifndef WIFI_SERVICE_H_
#define WIFI_SERVICE_H_

#include <string>
#include <vector>

class WifiService {
public:
    WifiService();
    ~WifiService();

    std::vector<std::wstring> ScanNetworks();
    bool Connect(const std::wstring& ssid, const std::wstring& password);
    void Disconnect();

private:
    void* client_handle_ = nullptr;
    static const unsigned long wlan_version_;
};

#endif  // WIFI_SERVICE_H_
