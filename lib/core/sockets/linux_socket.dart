
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'native_socket.dart';
import 'linux_ffi.dart' as ffi;

class LinuxSocket implements NativeSocket {
  int _socketFd = -1;

  LinuxSocket() {
    _socketFd = ffi.socket(ffi.AF_INET, ffi.SOCK_STREAM, 0);
    if (_socketFd < 0) {
      final errno = ffi.get_errno();
      throw 'Failed to create socket: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
    }
  }

  LinuxSocket._fromFd(this._socketFd);

  @override
  Future<void> bind(SocketAddress address) async {
    await Isolate.run(() {
      final hints = calloc<ffi.AddrInfo>();
      hints.ref.ai_family = ffi.AF_INET;
      hints.ref.ai_socktype = ffi.SOCK_STREAM;
      hints.ref.ai_flags = 1; // AI_PASSIVE
      final resultPointer = calloc<Pointer<ffi.AddrInfo>>();
      final service = address.port.toString().toNativeUtf8();

      final ret = ffi.getaddrinfo(nullptr, service, hints, resultPointer);

      if (ret != 0) {
        calloc.free(hints);
        calloc.free(resultPointer);
        calloc.free(service);
        throw 'Failed to resolve host: ${ffi.gai_strerror(ret).toDartString()}';
      }

      final result = resultPointer.value;
      final bindResult = ffi.bind(_socketFd, result.ref.ai_addr, result.ref.ai_addrlen);

      ffi.freeaddrinfo(result);
      calloc.free(hints);
      calloc.free(resultPointer);
      calloc.free(service);

      if (bindResult < 0) {
        final errno = ffi.get_errno();
        throw 'Failed to bind socket: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
      }
    });
  }

  @override
  Future<void> listen(int backlog) async {
    await Isolate.run(() {
      final result = ffi.listen(_socketFd, backlog);
      if (result < 0) {
        final errno = ffi.get_errno();
        throw 'Failed to listen on socket: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
      }
    });
  }

  @override
  Future<NativeSocket> accept() async {
    return await Isolate.run(() {
      final sockaddr = calloc<ffi.SockAddrIn>();
      final addrlen = calloc<Int32>()..value = sizeOf<ffi.SockAddrIn>();
      final clientFd = ffi.accept(_socketFd, sockaddr, addrlen);
      calloc.free(sockaddr);
      calloc.free(addrlen);
      if (clientFd < 0) {
        final errno = ffi.get_errno();
        throw 'Failed to accept connection: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
      }
      return LinuxSocket._fromFd(clientFd);
    });
  }

  @override
  Future<void> connect(SocketAddress address) async {
    await Isolate.run(() {
      final hints = calloc<ffi.AddrInfo>();
      hints.ref.ai_family = ffi.AF_INET;
      hints.ref.ai_socktype = ffi.SOCK_STREAM;
      final resultPointer = calloc<Pointer<ffi.AddrInfo>>();
      final service = address.port.toString().toNativeUtf8();
      final host = address.host.toNativeUtf8();

      final ret = ffi.getaddrinfo(host, service, hints, resultPointer);

      if (ret != 0) {
        calloc.free(host);
        calloc.free(hints);
        calloc.free(resultPointer);
        calloc.free(service);
        throw 'Failed to resolve host: ${ffi.gai_strerror(ret).toDartString()}';
      }

      final result = resultPointer.value;
      final connectResult = ffi.connect(_socketFd, result.ref.ai_addr, result.ref.ai_addrlen);

      ffi.freeaddrinfo(result);
      calloc.free(hints);
      calloc.free(resultPointer);
      calloc.free(service);
      calloc.free(host);

      if (connectResult < 0) {
        final errno = ffi.get_errno();
        throw 'Failed to connect to socket: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
      }
    });
  }

  @override
  Future<int> write(List<int> data) async {
    return await Isolate.run(() {
      final buffer = calloc<Uint8>(data.length);
      buffer.asTypedList(data.length).setAll(0, data);
      final result = ffi.send(_socketFd, buffer.cast(), data.length, 0);
      calloc.free(buffer);
      return result;
    });
  }

  @override
  Future<List<int>> read(int length) async {
    return await Isolate.run(() {
      final buffer = calloc<Uint8>(length);
      final result = ffi.recv(_socketFd, buffer.cast(), length, 0);
      if (result < 0) {
        calloc.free(buffer);
        final errno = ffi.get_errno();
        throw 'Failed to read from socket: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
      }
      final data = buffer.asTypedList(result).toList();
      calloc.free(buffer);
      return data;
    });
  }

  @override
  Future<void> close() async {
    await Isolate.run(() => ffi.close(_socketFd));
  }

  @override
  Future<void> sendFile(File file, {void Function(int bytesSent)? onProgress}) async {
    await Isolate.run(() async {
      final fileAccess = await file.open(mode: FileMode.read);
      final fileFd = (fileAccess as dynamic).fd;
      final fileSize = await file.length();
      final offset = calloc<Int64>();

      try {
        offset.value = 0;
        while (offset.value < fileSize) {
          final result = ffi.sendfile(_socketFd, fileFd, offset, fileSize - offset.value);
          if (result < 0) {
            final errno = ffi.get_errno();
            throw 'Failed to send file: ${ffi.strerror(errno).toDartString()} (errno = $errno)';
          }
          onProgress?.call(offset.value);
        }
      } finally {
        calloc.free(offset);
        await fileAccess.close();
      }
    });
  }
}
