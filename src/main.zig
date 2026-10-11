const std = @import("std");
const net = std.net;
const Thread = std.Thread;
const log = std.log;

pub const std_options = .{
    .log_level = .info,
};

const BUFFER_SIZE = 16 * 1024; // 16 KiB

fn usage() void {
    const msg =
        \\Usage: zig-port-forward <local_port> <remote_host> <remote_port>
        \\
        \\Example:
        \\  zig-port-forward 8080 192.168.1.100 80
        \\  # Listen on 0.0.0.0:8080 and forward all TCP traffic to 192.168.1.100:80
        \\
        \\This is a simple TCP reverse proxy / port forwarder for Linux.
    ;
    std.debug.print("{s}\n", .{msg});
}

fn copyStream(src: net.Stream, dst: net.Stream, direction: []const u8) void {
    var buf: [BUFFER_SIZE]u8 = undefined;
    while (true) {
        const n = src.read(&buf) catch |err| {
            if (err != error.ConnectionResetByPeer and err != error.BrokenPipe) {
                log.err("{s} read error: {}", .{ direction, err });
            }
            break;
        };
        if (n == 0) break; // EOF

        var written: usize = 0;
        while (written < n) {
            const w = dst.write(buf[written..n]) catch |err| {
                if (err != error.ConnectionResetByPeer and err != error.BrokenPipe) {
                    log.err("{s} write error: {}", .{ direction, err });
                }
                return;
            };
            written += w;
        }
    }
    // Best-effort half-close
    dst.close();
}

fn handleConnection(client: net.Server.Connection, remote_host: []const u8, remote_port: u16) void {
    defer client.stream.close();

    const peer = client.address;
    log.info("New connection from {}", .{peer});

    // Connect to remote
    const remote_stream = net.tcpConnectToHost(std.heap.page_allocator, remote_host, remote_port) catch |err| {
        log.err("Failed to connect to {s}:{} : {}", .{ remote_host, remote_port, err });
        return;
    };
    defer remote_stream.close();

    log.info("Connected to remote {s}:{}", .{ remote_host, remote_port });

    // Bidirectional copy using two threads
    const t1 = Thread.spawn(.{}, copyStream, .{ client.stream, remote_stream, "client->remote" }) catch |err| {
        log.err("Failed to spawn thread: {}", .{err});
        return;
    };
    const t2 = Thread.spawn(.{}, copyStream, .{ remote_stream, client.stream, "remote->client" }) catch |err| {
        log.err("Failed to spawn thread: {}", .{err});
        t1.join();
        return;
    };

    t1.join();
    t2.join();

    log.info("Connection from {} closed", .{peer});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // skip program name

    const local_port_str = args.next() orelse {
        usage();
        return error.InvalidArgs;
    };
    const remote_host = args.next() orelse {
        usage();
        return error.InvalidArgs;
    };
    const remote_port_str = args.next() orelse {
        usage();
        return error.InvalidArgs;
    };

    const local_port = try std.fmt.parseInt(u16, local_port_str, 10);
    const remote_port = try std.fmt.parseInt(u16, remote_port_str, 10);

    const address = try net.Address.parseIp4("0.0.0.0", local_port);
    var server = try address.listen(.{
        .reuse_address = true,
        .kernel_backlog = 128,
    });
    defer server.deinit();

    log.info("Listening on 0.0.0.0:{} -> forwarding to {s}:{}", .{ local_port, remote_host, remote_port });

    while (true) {
        const conn = server.accept() catch |err| {
            log.err("Accept error: {}", .{err});
            continue;
        };

        // Spawn a thread for each connection so we can handle many clients
        const thread = Thread.spawn(.{}, handleConnection, .{ conn, remote_host, remote_port }) catch |err| {
            log.err("Failed to spawn handler thread: {}", .{err});
            conn.stream.close();
            continue;
        };
        // Detach so we don't accumulate joins; the thread owns the connection
        thread.detach();
    }
}
