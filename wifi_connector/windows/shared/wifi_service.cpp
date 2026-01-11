#include "include/wifi_connector/wifi_service.h"
#include <windows.h>
#include <wlanapi.h>
#include <stdexcept>
#include <iostream>

#pragma comment(lib, "wlanapi.lib")

const unsigned long WifiService::wlan_version_ = 2;

WifiService::WifiService() {
    DWORD result = WlanOpenHandle(wlan_version_, nullptr, &result, &client_handle_);
    if (result != ERROR_SUCCESS) {
        throw std::runtime_error("Failed to open WLAN handle.");
    }
}

WifiService::~WifiService() {
    if (client_handle_) {
        WlanCloseHandle(client_handle_, nullptr);
    }
}

std::vector<std::wstring> WifiService::ScanNetworks() {
    std::vector<std::wstring> ssids;
    PWLAN_INTERFACE_INFO_LIST interface_list = nullptr;
    DWORD result = WlanEnumInterfaces(client_handle_, nullptr, &interface_list);

    if (result != ERROR_SUCCESS) {
        return ssids;
    }

    for (DWORD i = 0; i < interface_list->dwNumberOfItems; ++i) {
        PWLAN_AVAILABLE_NETWORK_LIST network_list = nullptr;
        result = WlanGetAvailableNetworkList(client_handle_, &interface_list->InterfaceInfo[i].InterfaceGuid, 0, nullptr, &network_list);

        if (result == ERROR_SUCCESS) {
            for (DWORD j = 0; j < network_list->dwNumberOfItems; ++j) {
                ssids.push_back(std::wstring(reinterpret_cast<const wchar_t*>(network_list->Network[j].dot11Ssid.ucSSID), network_list->Network[j].dot11Ssid.uSSIDLength));
            }
            WlanFreeMemory(network_list);
        }
    }

    WlanFreeMemory(interface_list);
    return ssids;
}

bool WifiService::Connect(const std::wstring& ssid, const std::wstring& password) {
    PWLAN_INTERFACE_INFO_LIST interface_list = nullptr;
    DWORD result = WlanEnumInterfaces(client_handle_, nullptr, &interface_list);

    if (result != ERROR_SUCCESS) {
        return false;
    }

    if (interface_list->dwNumberOfItems == 0) {
        WlanFreeMemory(interface_list);
        return false;
    }

    const GUID* interface_guid = &interface_list->InterfaceInfo[0].InterfaceGuid;

    std::string profile_content =
        "<?xml version=\"1.0\"?>"
        "<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">"
        "    <name>" + std::string(ssid.begin(), ssid.end()) + "</name>"
        "    <SSIDConfig>"
        "        <SSID>"
        "            <name>" + std::string(ssid.begin(), ssid.end()) + "</name>"
        "        </SSID>"
        "    </SSIDConfig>"
        "    <connectionType>ESS</connectionType>"
        "    <connectionMode>auto</connectionMode>"
        "    <MSM>"
        "        <security>"
        "            <authEncryption>"
        "                <authentication>WPA2PSK</authentication>"
        "                <encryption>AES</encryption>"
        "                <useOneX>false</useOneX>"
        "            </authEncryption>"
        "            <sharedKey>"
        "                <keyType>passPhrase</keyType>"
        "                <protected>false</protected>"
        "                <keyMaterial>" + std::string(password.begin(), password.end()) + "</keyMaterial>"
        "            </sharedKey>"
        "        </security>"
        "    </MSM>"
        "</WLANProfile>";

    DWORD profile_result;
    result = WlanSetProfile(client_handle_, interface_guid, 0, std::wstring(profile_content.begin(), profile_content.end()).c_str(), nullptr, TRUE, nullptr, &profile_result);

    if (result != ERROR_SUCCESS) {
        WlanFreeMemory(interface_list);
        return false;
    }

    WLAN_CONNECTION_PARAMETERS conn_params;
    conn_params.wlanConnectionMode = wlan_connection_mode_profile;
    conn_params.strProfile = ssid.c_str();
    conn_params.pDot11Ssid = nullptr;
    conn_params.pDesiredBssidList = nullptr;
    conn_params.dwFlags = 0;

    result = WlanConnect(client_handle_, interface_guid, &conn_params, nullptr);

    WlanFreeMemory(interface_list);
    return result == ERROR_SUCCESS;
}

void WifiService::Disconnect() {
    PWLAN_INTERFACE_INFO_LIST interface_list = nullptr;
    DWORD result = WlanEnumInterfaces(client_handle_, nullptr, &interface_list);

    if (result == ERROR_SUCCESS && interface_list->dwNumberOfItems > 0) {
        WlanDisconnect(client_handle_, &interface_list->InterfaceInfo[0].InterfaceGuid, nullptr);
    }

    if (interface_list) {
        WlanFreeMemory(interface_list);
    }
}
