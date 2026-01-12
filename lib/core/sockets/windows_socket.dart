
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'native_socket.dart';
import 'windows_ffi.dart' as ffi;
import 'windows_socket_manager.dart';

class WindowsSocket implements NativeSocket {
  int _socket = ffi.INVALID_SOCKET;

  WindowsSocket() {
    // Ensure the manager is initialized.
    WindowsSocketManager();
    _socket = ffi.socket(ffi.AF_INET, ffi.SOCK_STREAM, 0);
    if (_socket == ffi.INVALID_SOCKET) {
      final error = ffi.wsaGetLastError();
      throw 'Failed to create socket: ${ffi.getErrorMessage(error)} (error = $error)';
    }
  }

  WindowsSocket._fromSocket(this._socket);

  @override
  Future<void> bind(SocketAddress address) async {
    await Isolate.run((int fd) {
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
      final bindResult = ffi.bind(fd, result.ref.ai_addr, result.ref.ai_addrlen);

      ffi.freeaddrinfo(result);
      calloc.free(hints);
      calloc.free(resultPointer);
      calloc.free(service);

      if (bindResult == ffi.SOCKET_ERROR) {
        final error = ffi.wsaGetLastError();
        throw 'Failed to bind socket: ${ffi.getErrorMessage(error)} (error = $error)';
      }
    }, _socket);
  }

  @override
  Future<void> listen(int backlog) async {
    await Isolate.run((int fd) {
      final result = ffi.listen(fd, backlog);
      if (result == ffi.SOCKET_ERROR) {
        final error = ffi.wsaGetLastError();
        throw 'Failed to listen on socket: ${ffi.getErrorMessage(error)} (error = $error)';
      }
    }, _socket);
  }

  @override
  Future<NativeSocket> accept() async {
    return await Isolate.run((int fd) {
      final sockaddr = calloc<ffi.SockAddrIn>();
      final addrlen = calloc<Int32>()..value = sizeOf<ffi.SockAddrIn>();
      final clientSocket = ffi.accept(fd, sockaddr, addrlen);
      calloc.free(sockaddr);
      calloc.free(addrlen);
      if (clientSocket == ffi.INVALID_SOCKET) {
        final error = ffi.wsaGetLastError();
        throw 'Failed to accept connection: ${ffi.getErrorMessage(error)} (error = $error)';
      }
      return WindowsSocket._fromSocket(clientSocket);
    }, _socket);
  }

  @override
  Future<void> connect(SocketAddress address) async {
    await Isolate.run((int fd) {
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
      final connectResult = ffi.connect(fd, result.ref.ai_addr, result.ref.ai_addrlen);

      ffi.freeaddrinfo(result);
      calloc.free(hints);
      calloc.free(resultPointer);
      calloc.free(service);
      calloc.free(host);

      if (connectResult == ffi.SOCKET_ERROR) {
        final error = ffi.wsaGetLastError();
        throw 'Failed to connect to socket: ${ffi.getErrorMessage(error)} (error = $error)';
      }
    }, _socket);
  }

  @override
  Future<int> write(List<int> data) async {
    return await Isolate.run((int fd) {
      final buffer = calloc<Uint8>(data.length);
      buffer.asTypedList(data.length).setAll(0, data);
      final result = ffi.send(fd, buffer, data.length, 0);
      calloc.free(buffer);
      return result;
    }, _socket);
  }

  @override
  Future<List<int>> read(int length) async {
    return await Isolate.run((int fd) {
      final buffer = calloc<Uint8>(length);
      final result = ffi.recv(fd, buffer, length, 0);
      if (result == ffi.SOCKET_ERROR) {
        calloc.free(buffer);
        final error = ffi.wsaGetLastError();
        throw 'Failed to read from socket: ${ffi.getErrorMessage(error)} (error = $error)';
      }
      final data = buffer.asTypedList(result).toList();
      calloc.free(buffer);
      return data;
    }, _socket);
  }

  @override
  Future<void> close() async {
    await Isolate.run((int fd) => ffi.closesocket(fd), _socket);
  }

  @override
  Future<void> sendFile(File file, {void Function(int bytesSent)? onProgress}) async {
    await Isolate.run((int fd) async {
      final fileAccess = await file.open(mode: FileMode.read);
      final fileFd = (fileAccess as dynamic).fd;
      final fileSize = await file.length();

      final result = ffi.transmitFile(
        fd,
        fileFd,
        0, // Setting this to 0 sends the entire file.
        0,
        nullptr,
        nullptr,
        0,
      );

      await fileAccess.close();

      if (result == 0) {
        final error = ffi.wsaGetLastError();
        throw 'Failed to send file: ${ffi.getErrorMessage(error)} (error = $error)';
      }
      onProgress?.call(fileSize);
    }, _socket);
  }
}
