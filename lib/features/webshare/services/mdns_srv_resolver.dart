import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart' as mdns;

/// Resolver to get actual .local hostname from mDNS SRV records
/// This extracts the SRV target hostname that NSD doesn't expose
class MdnsSrvResolver {
  /// Resolve the actual .local hostname for a discovered service
  /// Returns the SRV target hostname (e.g., "Android_CPH2FXOW.local")
  static Future<String?> resolveHostnameForService({
    required String serviceName,
    required String serviceType,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    debugPrint('[MdnsSrvResolver] Resolving SRV hostname for: $serviceName.$serviceType.local');
    
    final client = mdns.MDnsClient();
    String? resolvedHostname;
    
    try {
      await client.start();
      debugPrint('[MdnsSrvResolver] mDNS client started');
      
      // Query for SRV record for the specific service instance
      final fullServiceName = '$serviceName.$serviceType.local';
      debugPrint('[MdnsSrvResolver] Querying SRV record: $fullServiceName');
      
      // Use timeout to prevent hanging
      bool found = false;
      await for (final mdns.SrvResourceRecord srv in client.lookup<mdns.SrvResourceRecord>(
        mdns.ResourceRecordQuery.service(fullServiceName),
        timeout: timeout,
      )) {
        // The SRV target is the actual hostname where the service is reachable!
        resolvedHostname = srv.target;
        debugPrint('[MdnsSrvResolver] ✅ Found SRV target hostname: $resolvedHostname');
        debugPrint('[MdnsSrvResolver]   - Priority: ${srv.priority}');
        debugPrint('[MdnsSrvResolver]   - Weight: ${srv.weight}');
        debugPrint('[MdnsSrvResolver]   - Port: ${srv.port}');
        found = true;
        break; // Got what we need
      }
      
      if (!found) {
        debugPrint('[MdnsSrvResolver] ⚠️ No SRV record found within timeout (${timeout.inSeconds}s)');
      }
      
    } catch (e) {
      debugPrint('[MdnsSrvResolver] ❌ Error resolving hostname: $e');
    } finally {
      try {
        client.stop();
        debugPrint('[MdnsSrvResolver] mDNS client stopped');
      } catch (e) {
        debugPrint('[MdnsSrvResolver] Error stopping client: $e');
      }
    }
    
    return resolvedHostname;
  }
  
  /// Discover all services with their actual hostnames from SRV records
  /// This is more comprehensive than NSD as it directly reads mDNS packets
  static Future<List<ServiceInfo>> discoverServicesWithHostnames({
    required String serviceType,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    debugPrint('[MdnsSrvResolver] Discovering services: $serviceType');
    
    final client = mdns.MDnsClient();
    final List<ServiceInfo> services = [];
    final Set<String> processedServices = {}; // Avoid duplicates
    
    try {
      await client.start();
      
      // Browse for services using PTR query
      await for (final mdns.PtrResourceRecord ptr in client.lookup<mdns.PtrResourceRecord>(
        mdns.ResourceRecordQuery.serverPointer(serviceType),
        timeout: timeout,
      )) {
        final serviceName = ptr.domainName;
        
        // Skip if we've already processed this service
        if (processedServices.contains(serviceName)) {
          continue;
        }
        processedServices.add(serviceName);
        
        debugPrint('[MdnsSrvResolver] Found service: $serviceName');
        
        // Get SRV record for this service instance
        await for (final mdns.SrvResourceRecord srv in client.lookup<mdns.SrvResourceRecord>(
          mdns.ResourceRecordQuery.service(serviceName),
          timeout: const Duration(seconds: 2),
        )) {
          debugPrint('[MdnsSrvResolver]   - SRV target: ${srv.target}');
          debugPrint('[MdnsSrvResolver]   - Port: ${srv.port}');
          
          // Get IP address from A record for the SRV target hostname
          String? ipAddress;
          await for (final mdns.IPAddressResourceRecord ip in client.lookup<mdns.IPAddressResourceRecord>(
            mdns.ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 1),
          )) {
            ipAddress = ip.address.address;
            debugPrint('[MdnsSrvResolver]   - IPv4: $ipAddress');
            break; // First IP is enough
          }
          
          // Get TXT records for additional metadata
          String? txtRecords;
          await for (final mdns.TxtResourceRecord txt in client.lookup<mdns.TxtResourceRecord>(
            mdns.ResourceRecordQuery.text(serviceName),
            timeout: const Duration(seconds: 1),
          )) {
            txtRecords = txt.text;
            debugPrint('[MdnsSrvResolver]   - TXT: $txtRecords');
            break;
          }
          
          services.add(ServiceInfo(
            name: serviceName,
            hostname: srv.target,  // ← The actual .local hostname!
            port: srv.port,
            ipAddress: ipAddress,
            txtRecords: txtRecords,
          ));
          
          break; // First SRV record is enough
        }
      }
      
      debugPrint('[MdnsSrvResolver] ✅ Discovery complete: ${services.length} services found');
      
    } catch (e) {
      debugPrint('[MdnsSrvResolver] ❌ Error discovering services: $e');
    } finally {
      client.stop();
    }
    
    return services;
  }
  
  /// Get our own service's actual hostname by discovering ourselves
  static Future<String?> getOwnHostname({
    required String serviceName,
    required String serviceType,
  }) async {
    debugPrint('[MdnsSrvResolver] Getting own hostname for: $serviceName.$serviceType');
    
    final hostname = await resolveHostnameForService(
      serviceName: serviceName,
      serviceType: serviceType,
      timeout: const Duration(seconds: 3),
    );
    
    if (hostname != null) {
      debugPrint('[MdnsSrvResolver] ✅ Own hostname resolved: $hostname');
      
      // Remove .local suffix for storage
      if (hostname.endsWith('.local')) {
        return hostname.substring(0, hostname.length - 6);
      }
      return hostname;
    }
    
    debugPrint('[MdnsSrvResolver] ⚠️ Could not resolve own hostname');
    return null;
  }
}

/// Service information with actual hostname from SRV records
class ServiceInfo {
  final String name;           // Full service name (e.g., "dinesh._http._tcp.local")
  final String hostname;       // Actual .local hostname (e.g., "Android_CPH2FXOW.local")
  final int port;             // Service port
  final String? ipAddress;    // IPv4 address (if resolved)
  final String? txtRecords; // TXT record metadata
  
  ServiceInfo({
    required this.name,
    required this.hostname,
    required this.port,
    this.ipAddress,
    this.txtRecords,
  });
  
  /// Get the URL using the actual hostname
  String get hostnameUrl => 'http://$hostname:$port';
  
  /// Get the URL using IP address (fallback)
  String? get ipUrl => ipAddress != null ? 'http://$ipAddress:$port' : null;
  
  /// Get hostname without .local suffix
  String get hostnameWithoutSuffix {
    if (hostname.endsWith('.local')) {
      return hostname.substring(0, hostname.length - 6);
    }
    return hostname;
  }
  
  @override
  String toString() {
    return 'ServiceInfo(name: $name, hostname: $hostname, port: $port, ip: $ipAddress)';
  }
}
