
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// SOCKADDR_IN structure
class SockAddrIn extends Struct {
  @Int16()
  external int sin_family;

  @Uint16()
  external int sin_port;

  @Uint32()
  external int sin_addr;

  @Array(8)
  external Array<Uint8> sin_zero;
}

// WSAData structure
class WSAData extends Struct {
  @Int16()
  external int wVersion;
  @Int16()
  external int wHighVersion;
  @Array(257)
  external Array<Uint8> szDescription;
  @Array(129)
  external Array<Uint8> szSystemStatus;
  @Int16()
  external int iMaxSockets;
  @Int16()
  external int iMaxUdpDg;
  external Pointer<Uint8> lpVendorInfo;
}

// C functions
typedef WSAStartupC = Int32 Function(Int16 wVersionRequired, Pointer<WSAData> lpWSAData);
typedef WSAStartupDart = int Function(int wVersionRequired, Pointer<WSAData> lpWSAData);

typedef WSACleanupC = Int32 Function();
typedef WSACleanupDart = int Function();

typedef SocketC = IntPtr Function(Int32 af, Int32 type, Int32 protocol);
typedef SocketDart = int Function(int af, int type, int protocol);

typedef BindC = Int32 Function(IntPtr s, Pointer<SockAddrIn> name, Int32 namelen);
typedef BindDart = int Function(int s, Pointer<SockAddrIn> name, int namelen);

typedef ListenC = Int32 Function(IntPtr s, Int32 backlog);
typedef ListenDart = int Function(int s, int backlog);

typedef AcceptC = IntPtr Function(IntPtr s, Pointer<SockAddrIn> addr, Pointer<Int32> addrlen);
typedef AcceptDart = int Function(int s, Pointer<SockAddrIn> addr, Pointer<Int32> addrlen);

typedef ConnectC = Int32 Function(IntPtr s, Pointer<SockAddrIn> name, Int32 namelen);
typedef ConnectDart = int Function(int s, Pointer<SockAddrIn> name, int namelen);

typedef SendC = Int32 Function(IntPtr s, Pointer<Uint8> buf, Int32 len, Int32 flags);
typedef SendDart = int Function(int s, Pointer<Uint8> buf, int len, int flags);

typedef RecvC = Int32 Function(IntPtr s, Pointer<Uint8> buf, Int32 len, Int32 flags);
typedef RecvDart = int Function(int s, Pointer<Uint8> buf, int len, int flags);

typedef ClosesocketC = Int32 Function(IntPtr s);
typedef ClosesocketDart = int Function(int s);

typedef TransmitFileC = Int32 Function(IntPtr hSocket, IntPtr hFile, Int32 nNumberOfBytesToWrite, Int32 nNumberOfBytesPerSend, Pointer<Void> lpOverlapped, Pointer<Void> lpTransmitBuffers, Int32 dwReserved);
typedef TransmitFileDart = int Function(int hSocket, int hFile, int nNumberOfBytesToWrite, int nNumberOfBytesPerSend, Pointer<Void> lpOverlapped, Pointer<Void> lpTransmitBuffers, int dwReserved);

typedef WriteFileC = Int32 Function(IntPtr hFile, Pointer<Uint8> lpBuffer, Int32 nNumberOfBytesToWrite, Pointer<Uint32> lpNumberOfBytesWritten, Pointer<Overlapped> lpOverlapped);
typedef WriteFileDart = int Function(int hFile, Pointer<Uint8> lpBuffer, int nNumberOfBytesToWrite, Pointer<Uint32> lpNumberOfBytesWritten, Pointer<Overlapped> lpOverlapped);

typedef WSAGetLastErrorC = Int32 Function();
typedef WSAGetLastErrorDart = int Function();

typedef FormatMessageC = Int32 Function(Int32 dwFlags, Pointer<Void> lpSource, Int32 dwMessageId, Int32 dwLanguageId, Pointer<Pointer<Utf16>> lpBuffer, Int32 nSize, Pointer<Void> Arguments);
typedef FormatMessageDart = int Function(int dwFlags, Pointer<Void> lpSource, int dwMessageId, int dwLanguageId, Pointer<Pointer<Utf16>> lpBuffer, int nSize, Pointer<Void> Arguments);

class AddrInfo extends Struct {
  @Int32()
  external int ai_flags;
  @Int32()
  external int ai_family;
  @Int32()
  external int ai_socktype;
  @Int32()
  external int ai_protocol;
  @IntPtr()
  external int ai_addrlen;
  external Pointer<Utf8> ai_canonname;
  external Pointer<SockAddrIn> ai_addr;
  external Pointer<AddrInfo> ai_next;
}

typedef GetAddrInfoC = Int32 Function(Pointer<Utf8> pNodeName, Pointer<Utf8> pServiceName, Pointer<AddrInfo> pHints, Pointer<Pointer<AddrInfo>> ppResult);
typedef GetAddrInfoDart = int Function(Pointer<Utf8> pNodeName, Pointer<Utf8> pServiceName, Pointer<AddrInfo> pHints, Pointer<Pointer<AddrInfo>> ppResult);

typedef FreeAddrInfoC = Void Function(Pointer<AddrInfo> pAddrInfo);
typedef FreeAddrInfoDart = void Function(Pointer<AddrInfo> pAddrInfo);

typedef InetAddrC = Uint32 Function(Pointer<Utf8> cp);
typedef InetAddrDart = int Function(Pointer<Utf8> cp);

typedef GaiStrerrorC = Pointer<Utf8> Function(Int32 errcode);
typedef GaiStrerrorDart = Pointer<Utf8> Function(int errcode);

// OVERLAPPED structure
class Overlapped extends Struct {
  @IntPtr()
  external int Internal;
  @IntPtr()
  external int InternalHigh;
  @Int32()
  external int Offset;
  @Int32()
  external int OffsetHigh;
  @IntPtr()
  external int hEvent;
}

// Helper to load ws2_32.dll
final dylib = DynamicLibrary.open('ws2_32.dll');
final kernel32 = DynamicLibrary.open('kernel32.dll');

// Socket functions
final wsaStartup = dylib.lookupFunction<WSAStartupC, WSAStartupDart>('WSAStartup');
final wsaCleanup = dylib.lookupFunction<WSACleanupC, WSACleanupDart>('WSACleanup');
final socket = dylib.lookupFunction<SocketC, SocketDart>('socket');
final bind = dylib.lookupFunction<BindC, BindDart>('bind');
final listen = dylib.lookupFunction<ListenC, ListenDart>('listen');
final accept = dylib.lookupFunction<AcceptC, AcceptDart>('accept');
final connect = dylib.lookupFunction<ConnectC, ConnectDart>('connect');
final send = dylib.lookupFunction<SendC, SendDart>('send');
final recv = dylib.lookupFunction<RecvC, RecvDart>('recv');
final closesocket = dylib.lookupFunction<ClosesocketC, ClosesocketDart>('closesocket');
final transmitFile = dylib.lookupFunction<TransmitFileC, TransmitFileDart>('TransmitFile');
final writeFile = kernel32.lookupFunction<WriteFileC, WriteFileDart>('WriteFile');
final wsaGetLastError = dylib.lookupFunction<WSAGetLastErrorC, WSAGetLastErrorDart>('WSAGetLastError');
final formatMessage = kernel32.lookupFunction<FormatMessageC, FormatMessageDart>('FormatMessageW');
final getaddrinfo = dylib.lookupFunction<GetAddrInfoC, GetAddrInfoDart>('getaddrinfo');
final freeaddrinfo = dylib.lookupFunction<FreeAddrInfoC, FreeAddrInfoDart>('freeaddrinfo');
final inet_addr = dylib.lookupFunction<InetAddrC, InetAddrDart>('inet_addr');
final gai_strerror = dylib.lookupFunction<GaiStrerrorC, GaiStrerrorDart>('gai_strerror');

String getErrorMessage(int errorCode) {
  final buffer = calloc<Pointer<Utf16>>();
  final result = formatMessage(
    0x1300, // FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS
    nullptr,
    errorCode,
    0,
    buffer,
    0,
    nullptr,
  );

  if (result == 0) {
    calloc.free(buffer);
    return 'Unknown error';
  }

  final message = buffer.value.toDartString();
  calloc.free(buffer.value);
  calloc.free(buffer);
  return message;
}

// Constants
const AF_INET = 2;
const SOCK_STREAM = 1;
const SOMAXCONN = 128;
const INVALID_SOCKET = -1;
const SOCKET_ERROR = -1;
const O_RDONLY = 0;
const GENERIC_READ = 0x80000000;
const FILE_SHARE_READ = 1;
const OPEN_EXISTING = 3;
