# zig-port-forward

A simple, lightweight **TCP port forwarding / reverse proxy** written in [Zig](https://ziglang.org/), designed for Linux.

It listens on a local port and transparently forwards all TCP traffic to a remote host:port.

## Features

- Pure Zig, no external dependencies
- Multi-threaded: each client connection is handled in its own thread
- Bidirectional data copying
- `SO_REUSEADDR` enabled
- Works as a classic reverse proxy / local port forwarder

## Requirements

- Zig 0.11+ (tested with recent stable versions)
- Linux (uses standard POSIX sockets)

## Build

```bash
git clone https://github.com/aasszz77d/zig-port-forward.git
cd zig-port-forward
zig build -Doptimize=ReleaseSafe
```

Binary will be at `zig-out/bin/zig-port-forward`.

For smaller binary size:

```bash
zig build -Doptimize=ReleaseSmall
```

## Usage

```bash
./zig-out/bin/zig-port-forward <local_port> <remote_host> <remote_port>
```

### Examples

Forward local port 8080 to a web server:

```bash
./zig-out/bin/zig-port-forward 8080 192.168.1.100 80
```

Forward local 2222 to a remote SSH server:

```bash
./zig-out/bin/zig-port-forward 2222 example.com 22
```

Then connect with:

```bash
ssh -p 2222 user@localhost
```

Listen on all interfaces (default is `0.0.0.0`).

## How it works

1. Binds and listens on `0.0.0.0:<local_port>`
2. Accepts incoming TCP connections
3. For each connection, opens a new TCP connection to `<remote_host>:<remote_port>`
4. Spawns two threads that copy data in both directions until either side closes

## License

MIT
