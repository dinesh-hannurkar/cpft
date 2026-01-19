
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// sockaddr_in structure
final class SockAddrIn extends Struct {
  @Int16()
  external int sin_family;

  @Uint16()
  external int sin_port;

  @Uint32()
  external int sin_addr;

  @Array(8)
  external Array<Uint8> sin_zero;
}

// C functions
typedef SocketC = Int32 Function(Int32 domain, Int32 type, Int32 protocol);
typedef SocketDart = int Function(int domain, int type, int protocol);

typedef BindC = Int32 Function(Int32 sockfd, Pointer<SockAddrIn> addr, Int32 addrlen);
typedef BindDart = int Function(int sockfd, Pointer<SockAddrIn> addr, int addrlen);

typedef ListenC = Int32 Function(Int32 sockfd, Int32 backlog);
typedef ListenDart = int Function(int sockfd, int backlog);

typedef AcceptC = Int32 Function(Int32 sockfd, Pointer<SockAddrIn> addr, Pointer<Int32> addrlen);
typedef AcceptDart = int Function(int sockfd, Pointer<SockAddrIn> addr, Pointer<Int32> addrlen);

typedef ConnectC = Int32 Function(Int32 sockfd, Pointer<SockAddrIn> addr, Int32 addrlen);
typedef ConnectDart = int Function(int sockfd, Pointer<SockAddrIn> addr, int addrlen);

typedef SendC = Int64 Function(Int32 sockfd, Pointer<Void> buf, Int64 len, Int32 flags);
typedef SendDart = int Function(int sockfd, Pointer<Void> buf, int len, int flags);

typedef RecvC = Int64 Function(Int32 sockfd, Pointer<Void> buf, Int64 len, Int32 flags);
typedef RecvDart = int Function(int sockfd, Pointer<Void> buf, int len, int flags);

typedef CloseC = Int32 Function(Int32 fd);
typedef CloseDart = int Function(int fd);

typedef SendfileC = Int64 Function(Int32 out_fd, Int32 in_fd, Pointer<Int64> offset, Int64 count);
typedef SendfileDart = int Function(int out_fd, int in_fd, Pointer<Int64> offset, int count);

typedef ErrnoLocationC = Pointer<Int32> Function();
typedef ErrnoLocationDart = Pointer<Int32> Function();

typedef StrerrorC = Pointer<Utf8> Function(Int32 errnum);
typedef StrerrorDart = Pointer<Utf8> Function(int errnum);

final class AddrInfo extends Struct {
  @Int32()
  external int ai_flags;
  @Int32()
  external int ai_family;
  @Int32()
  external int ai_socktype;
  @Int32()
  external int ai_protocol;
  @Int32()
  external int ai_addrlen;
  external Pointer<SockAddrIn> ai_addr;
  external Pointer<Utf8> ai_canonname;
  external Pointer<AddrInfo> ai_next;
}

typedef GetAddrInfoC = Int32 Function(Pointer<Utf8> node, Pointer<Utf8> service, Pointer<AddrInfo> hints, Pointer<Pointer<AddrInfo>> res);
typedef GetAddrInfoDart = int Function(Pointer<Utf8> node, Pointer<Utf8> service, Pointer<AddrInfo> hints, Pointer<Pointer<AddrInfo>> res);

typedef FreeAddrInfoC = Void Function(Pointer<AddrInfo> res);
typedef FreeAddrInfoDart = void Function(Pointer<AddrInfo> res);

typedef GaiStrerrorC = Pointer<Utf8> Function(Int32 errcode);
typedef GaiStrerrorDart = Pointer<Utf8> Function(int errcode);

typedef InetAddrC = Uint32 Function(Pointer<Utf8> cp);
typedef InetAddrDart = int Function(Pointer<Utf8> cp);

// Helper to load libc
final dylib = DynamicLibrary.open('libc.so.6');

// Socket functions
final socket = dylib.lookupFunction<SocketC, SocketDart>('socket');
final bind = dylib.lookupFunction<BindC, BindDart>('bind');
final listen = dylib.lookupFunction<ListenC, ListenDart>('listen');
final accept = dylib.lookupFunction<AcceptC, AcceptDart>('accept');
final connect = dylib.lookupFunction<ConnectC, ConnectDart>('connect');
final send = dylib.lookupFunction<SendC, SendDart>('send');
final recv = dylib.lookupFunction<RecvC, RecvDart>('recv');
final close = dylib.lookupFunction<CloseC, CloseDart>('close');
final sendfile = dylib.lookupFunction<SendfileC, SendfileDart>('sendfile');
final strerror = dylib.lookupFunction<StrerrorC, StrerrorDart>('strerror');
final errno_location = dylib.lookupFunction<ErrnoLocationC, ErrnoLocationDart>('__errno_location');
final getaddrinfo = dylib.lookupFunction<GetAddrInfoC, GetAddrInfoDart>('getaddrinfo');
final freeaddrinfo = dylib.lookupFunction<FreeAddrInfoC, FreeAddrInfoDart>('freeaddrinfo');
final gai_strerror = dylib.lookupFunction<GaiStrerrorC, GaiStrerrorDart>('gai_strerror');
final inet_addr = dylib.lookupFunction<InetAddrC, InetAddrDart>('inet_addr');

int get_errno() => errno_location().value;

// Constants
const AF_INET = 2;
const SOCK_STREAM = 1;
const SOMAXCONN = 128;
const O_RDONLY = 0;
