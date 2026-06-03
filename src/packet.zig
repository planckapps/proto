const std = @import("std");
const Type = std.builtin.Type;
const Operation = @import("operation.zig").Operation;
const Status = @import("operation.zig").Status;
const ValueType = @import("operation.zig").ValueType;
const Attribute = @import("operation.zig").Attribute;
const DocType = @import("operation.zig").DocType;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Buffer = @import("utils").Buffer;

pub const Packet = struct {
    checksum: u64,
    packet_length: u32,
    packet_id: u32,
    timestamp: i64,
    op: Operation,

    pub fn calcMsgSize(pck: *const Packet) usize {
        var size: usize = 0;
        size += @sizeOf(u64);
        size += @sizeOf(u32);
        size += @sizeOf(u32);
        size += @sizeOf(i64);
        size += 1;
        switch (pck.op) {
            .Authenticate => |data| {
                size += 4 + @as(u32, @intCast(data.uid.len));
                size += 4 + @as(u32, @intCast(data.key.len));
            },
            .Logout => {},
            .Insert => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 4 + @as(u32, @intCast(data.payload.len));
                size += 1;
            },
            .BatchInsert => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 4;
                for (data.values) |value| {
                    size += 4 + @as(u32, @intCast(value.len));
                }
            },
            .Read => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 16;
            },
            .Update => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 16;
                size += 4 + @as(u32, @intCast(data.payload.len));
            },
            .Delete => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 1;
                if (data.id) |_| {
                    size += 16;
                }
                size += 1;
                if (data.query_json) |qj| {
                    size += 4 + @as(u32, @intCast(qj.len));
                }
            },
            .Query => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 4 + @as(u32, @intCast(data.query_json.len));
            },
            .Aggregate => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 4 + @as(u32, @intCast(data.aggregate_json.len));
            },
            .Scan => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 1;
                if (data.start_key) |_| {
                    size += 16;
                }
                size += 4;
                size += 4;
            },
            .Range => |data| {
                size += 4 + @as(u32, @intCast(data.store_ns.len));
                size += 16;
                size += 16;
            },
            .List => |data| {
                size += 1;
                size += 1;
                if (data.ns) |ns| {
                    size += 4 + @as(u32, @intCast(ns.len));
                }
                size += 1;
                if (data.limit) |_| {
                    size += 4;
                }
                size += 1;
                if (data.offset) |_| {
                    size += 4;
                }
            },
            .NextSequence => |data| {
                size += 4 + @as(u32, @intCast(data.name.len)); // name string
            },
            .Watch => |data| {
                size += 4;
                for (data.stores) |s| {
                    size += 4 + @as(u32, @intCast(s.len));
                }
                size += 8;
                size += 4;
                size += 4;
            },
            .WatchReply => |data| {
                size += 1;
                size += 8;
                size += 4;
                for (data.records) |r| {
                    size += 4 + @as(u32, @intCast(r.len));
                }
            },
            .Reply => |data| {
                size += 1;
                size += 1;
                if (data.data) |d| {
                    size += 4 + @as(u32, @intCast(d.len));
                }
            },
            .BatchReply => |data| {
                size += 1;
                size += 4;
                for (data.results) |result| {
                    size += 4 + @as(u32, @intCast(result.len));
                }
            },
            .Create => |data| {
                size += 1;
                size += 4 + @as(u32, @intCast(data.ns.len));
                size += 4 + @as(u32, @intCast(data.payload.len));
                size += 1;
                size += 1;
                if (data.metadata) |meta| {
                    size += 4 + @as(u32, @intCast(meta.len));
                }
            },
            .Drop => |data| {
                size += 1;
                size += 4 + @as(u32, @intCast(data.name.len));
            },
            .Flush => {},
        }
        return size;
    }

    pub fn serialize(self: Packet, buf: *Buffer) ![]u8 {
        const w = buf.writer();
        try w.writeInt(u64, self.checksum, .little);
        try w.writeInt(u32, self.packet_length, .little);
        try w.writeInt(u32, self.packet_id, .little);
        try w.writeInt(i64, self.timestamp, .little);
        try Packet.serializeOperation(w, self.op);
        return buf.slice();
    }

    pub fn deserialize(allocator: Allocator, data: []const u8) !Packet {
        var offset: usize = 0;
        const checksum = try Packet.readBytes(data, &offset, u64);
        const packet_length = try Packet.readBytes(data, &offset, u32);
        const packet_id = try Packet.readBytes(data, &offset, u32);
        const timestamp = try Packet.readBytes(data, &offset, i64);
        const op = try Packet.deserializeOperation(allocator, data, &offset);
        return Packet{
            .checksum = checksum,
            .packet_length = packet_length,
            .packet_id = packet_id,
            .timestamp = timestamp,
            .op = op,
        };
    }

    pub fn free(allocator: Allocator, pck: Packet) void {
        switch (pck.op) {
            .BatchInsert => |data| {
                allocator.free(data.values);
            },
            .BatchReply => |data| {
                for (data.results) |result| {
                    allocator.free(result);
                }
                allocator.free(data.results);
            },
            .Watch => |data| {
                if (data.stores.len > 0) allocator.free(data.stores);
            },
            .WatchReply => |data| {
                if (data.records.len > 0) allocator.free(data.records);
            },
            else => {},
        }
    }

    fn serializeAttribute(w: Buffer.Writer, attr: Attribute) !void {
        const tag = @intFromEnum(attr);
        try w.writeInt(u8, tag, .little);
        switch (attr) {
            .I8 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i8, data.value, .little);
            },
            .I16 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i16, data.value, .little);
            },
            .I32 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i32, data.value, .little);
            },
            .I64 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i64, data.value, .little);
            },
            .I128 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i128, data.value, .little);
            },
            .U8 => |data| {
                try w.writeString(data.name);
                try w.writeInt(u8, data.value, .little);
            },
            .U16 => |data| {
                try w.writeString(data.name);
                try w.writeInt(u16, data.value, .little);
            },
            .U32 => |data| {
                try w.writeString(data.name);
                try w.writeInt(u32, data.value, .little);
            },
            .U64 => |data| {
                try w.writeString(data.name);
                try w.writeInt(u64, data.value, .little);
            },
            .U128 => |data| {
                try w.writeString(data.name);
                try w.writeInt(u128, data.value, .little);
            },
            .F32 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i32, @bitCast(data.value), .little);
            },
            .F64 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i64, @bitCast(data.value), .little);
            },
            .F128 => |data| {
                try w.writeString(data.name);
                try w.writeInt(i128, @bitCast(data.value), .little);
            },
            .Pointer => |data| {
                try w.writeString(data.name);
                try w.writeString(data.value);
            },
        }
    }

    fn serializeOperation(w: Buffer.Writer, op: Operation) !void {
        const tag = @intFromEnum(op);
        try w.writeInt(u8, tag, .little);
        switch (op) {
            .Authenticate => |data| {
                try w.writeString(data.uid);
                try w.writeString(data.key);
            },
            .Logout => {},
            .Insert => |data| {
                try w.writeString(data.store_ns);
                try w.writeString(data.payload);
                try w.writeInt(u8, if (data.auto_create) 1 else 0, .little);
            },
            .BatchInsert => |data| {
                try w.writeString(data.store_ns);
                const count = @as(u32, @intCast(data.values.len));
                try w.writeInt(u32, count, .little);
                for (data.values) |value| {
                    try w.writeString(value);
                }
            },
            .Read => |data| {
                try w.writeString(data.store_ns);
                try w.writeInt(u128, data.id, .little);
            },
            .Update => |data| {
                try w.writeString(data.store_ns);
                try w.writeInt(u128, data.id, .little);
                try w.writeString(data.payload);
            },
            .Delete => |data| {
                try w.writeString(data.store_ns);
                if (data.id) |id| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeInt(u128, id, .little);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
                if (data.query_json) |qj| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeString(qj);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
            },
            .Query => |data| {
                try w.writeString(data.store_ns);
                try w.writeString(data.query_json);
            },
            .Aggregate => |data| {
                try w.writeString(data.store_ns);
                try w.writeString(data.aggregate_json);
            },
            .Scan => |data| {
                try w.writeString(data.store_ns);
                if (data.start_key) |key| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeInt(u128, key, .little);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
                try w.writeInt(u32, data.limit, .little);
                try w.writeInt(u32, data.skip, .little);
            },
            .Range => |data| {
                try w.writeString(data.store_ns);
                try w.writeInt(u128, data.start_key, .little);
                try w.writeInt(u128, data.end_key, .little);
            },
            .List => |data| {
                try w.writeInt(u8, @intFromEnum(data.doc_type), .little);
                if (data.ns) |ns| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeString(ns);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
                if (data.limit) |lim| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeInt(u32, lim, .little);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
                if (data.offset) |off| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeInt(u32, off, .little);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
            },
            .NextSequence => |data| {
                try w.writeString(data.name);
            },
            .Watch => |data| {
                const stores_count = @as(u32, @intCast(data.stores.len));
                try w.writeInt(u32, stores_count, .little);
                for (data.stores) |s| {
                    try w.writeString(s);
                }
                try w.writeInt(u64, data.since_lsn, .little);
                try w.writeInt(u32, data.max_wait_ms, .little);
                try w.writeInt(u32, data.max_records, .little);
            },
            .WatchReply => |data| {
                try w.writeInt(u8, @intFromEnum(data.status), .little);
                try w.writeInt(u64, data.high_lsn, .little);
                const records_count = @as(u32, @intCast(data.records.len));
                try w.writeInt(u32, records_count, .little);
                for (data.records) |r| {
                    try w.writeString(r);
                }
            },
            .Reply => |data| {
                try w.writeInt(u8, @intFromEnum(data.status), .little);
                if (data.data) |d| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeString(d);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
            },
            .BatchReply => |data| {
                try w.writeInt(u8, @intFromEnum(data.status), .little);
                const count = @as(u32, @intCast(data.results.len));
                try w.writeInt(u32, count, .little);
                for (data.results) |result| {
                    try w.writeString(result);
                }
            },
            .Create => |data| {
                try w.writeInt(u8, @intFromEnum(data.doc_type), .little);
                try w.writeString(data.ns);
                try w.writeString(data.payload);
                try w.writeInt(u8, if (data.auto_create) 1 else 0, .little);
                if (data.metadata) |meta| {
                    try w.writeInt(u8, 1, .little);
                    try w.writeString(meta);
                } else {
                    try w.writeInt(u8, 0, .little);
                }
            },
            .Drop => |data| {
                try w.writeInt(u8, @intFromEnum(data.doc_type), .little);
                try w.writeString(data.name);
            },
            .Flush => {},
        }
    }

    fn readBytes(data: []const u8, offset: *usize, comptime T: type) !T {
        if (offset.* + @sizeOf(T) > data.len) {
            return SerializationError.InvalidData;
        }
        const result = std.mem.bytesToValue(T, data[offset.* .. offset.* + @sizeOf(T)]);
        offset.* += @sizeOf(T);
        return result;
    }

    fn readString(allocator: Allocator, data: []const u8, offset: *usize) ![]const u8 {
        const len = try Packet.readBytes(data, offset, u32);
        if (offset.* + len > data.len) {
            return SerializationError.InvalidData;
        }
        _ = allocator;
        const result = data[offset.* .. offset.* + len][0..];
        offset.* += len;
        return result;
    }

    fn deserializeAttribute(allocator: Allocator, data: []const u8, offset: *usize) !Attribute {
        const tag = try Packet.readBytes(data, offset, u8);
        return switch (tag) {
            0 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, i8);
                return Attribute{ .I8 = .{ .name = name, .value = value } };
            },
            1 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, i16);
                return Attribute{ .I16 = .{ .name = name, .value = value } };
            },
            2 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, i32);
                return Attribute{ .I32 = .{ .name = name, .value = value } };
            },
            3 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, i64);
                return Attribute{ .I64 = .{ .name = name, .value = value } };
            },
            4 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, i128);
                return Attribute{ .I128 = .{ .name = name, .value = value } };
            },
            5 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, u8);
                return Attribute{ .U8 = .{ .name = name, .value = value } };
            },
            6 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, u16);
                return Attribute{ .U16 = .{ .name = name, .value = value } };
            },
            7 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, u32);
                return Attribute{ .U32 = .{ .name = name, .value = value } };
            },
            8 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, u64);
                return Attribute{ .U64 = .{ .name = name, .value = value } };
            },
            9 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, u128);
                return Attribute{ .U128 = .{ .name = name, .value = value } };
            },
            10 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, f32);
                return Attribute{ .F32 = .{ .name = name, .value = value } };
            },
            11 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, f64);
                return Attribute{ .F64 = .{ .name = name, .value = value } };
            },
            12 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readBytes(data, offset, f128);
                return Attribute{ .F128 = .{ .name = name, .value = value } };
            },
            13 => {
                const name = try Packet.readString(allocator, data, offset);
                const value = try Packet.readString(allocator, data, offset);
                return Attribute{ .Pointer = .{ .name = name, .value = value } };
            },
            else => SerializationError.InvalidData,
        };
    }

    fn deserializeOperation(allocator: Allocator, data: []const u8, offset: *usize) !Operation {
        const tag = try Packet.readBytes(data, offset, u8);
        return switch (tag) {
            1 => {
                const uid = try Packet.readString(allocator, data, offset);
                const key = try Packet.readString(allocator, data, offset);
                return Operation{ .Authenticate = .{ .uid = uid, .key = key } };
            },
            2 => Operation.Logout,
            3 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const payload = try Packet.readString(allocator, data, offset);
                const auto_create = (try Packet.readBytes(data, offset, u8)) == 1;
                return Operation{ .Insert = .{
                    .store_ns = store_ns,
                    .payload = payload,
                    .auto_create = auto_create,
                } };
            },
            4 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const count = try Packet.readBytes(data, offset, u32);
                const values = try allocator.alloc([]const u8, count);
                for (values) |*value| {
                    value.* = try Packet.readString(allocator, data, offset);
                }
                return Operation{ .BatchInsert = .{
                    .store_ns = store_ns,
                    .values = values,
                } };
            },
            5 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const id = try Packet.readBytes(data, offset, u128);
                return Operation{ .Read = .{ .store_ns = store_ns, .id = id } };
            },
            6 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const id = try Packet.readBytes(data, offset, u128);
                const payload = try Packet.readString(allocator, data, offset);
                return Operation{ .Update = .{
                    .store_ns = store_ns,
                    .id = id,
                    .payload = payload,
                } };
            },
            7 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const has_id = try Packet.readBytes(data, offset, u8);
                const id = if (has_id == 1) try Packet.readBytes(data, offset, u128) else null;
                const has_query_json = try Packet.readBytes(data, offset, u8);
                const query_json = if (has_query_json == 1) try Packet.readString(allocator, data, offset) else null;
                return Operation{ .Delete = .{
                    .store_ns = store_ns,
                    .id = id,
                    .query_json = query_json,
                } };
            },
            8 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const query_json = try Packet.readString(allocator, data, offset);
                return Operation{ .Query = .{ .store_ns = store_ns, .query_json = query_json } };
            },
            9 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const aggregate_json = try Packet.readString(allocator, data, offset);
                return Operation{ .Aggregate = .{ .store_ns = store_ns, .aggregate_json = aggregate_json } };
            },
            10 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const has_start_key = try Packet.readBytes(data, offset, u8);
                const start_key = if (has_start_key == 1) try Packet.readBytes(data, offset, u128) else null;
                const limit = try Packet.readBytes(data, offset, u32);
                const skip = try Packet.readBytes(data, offset, u32);
                return Operation{ .Scan = .{
                    .store_ns = store_ns,
                    .start_key = start_key,
                    .limit = limit,
                    .skip = skip,
                } };
            },
            11 => {
                const store_ns = try Packet.readString(allocator, data, offset);
                const start_key = try Packet.readBytes(data, offset, u128);
                const end_key = try Packet.readBytes(data, offset, u128);
                return Operation{ .Range = .{
                    .store_ns = store_ns,
                    .start_key = start_key,
                    .end_key = end_key,
                } };
            },
            12 => {
                const doc_type_byte = try Packet.readBytes(data, offset, u8);
                const doc_type = @as(DocType, @enumFromInt(doc_type_byte));
                const has_ns = try Packet.readBytes(data, offset, u8);
                const ns = if (has_ns == 1) try Packet.readString(allocator, data, offset) else null;
                const has_limit = try Packet.readBytes(data, offset, u8);
                const limit = if (has_limit == 1) try Packet.readBytes(data, offset, u32) else null;
                const has_offset = try Packet.readBytes(data, offset, u8);
                const offset_val = if (has_offset == 1) try Packet.readBytes(data, offset, u32) else null;
                return Operation{ .List = .{
                    .doc_type = doc_type,
                    .ns = ns,
                    .limit = limit,
                    .offset = offset_val,
                } };
            },
            13 => {
                const name = try Packet.readString(allocator, data, offset);
                return Operation{ .NextSequence = .{ .name = name } };
            },
            14 => {
                const stores_count = try Packet.readBytes(data, offset, u32);
                const stores = try allocator.alloc([]const u8, stores_count);
                for (stores) |*s| {
                    s.* = try Packet.readString(allocator, data, offset);
                }
                const since_lsn = try Packet.readBytes(data, offset, u64);
                const max_wait_ms = try Packet.readBytes(data, offset, u32);
                const max_records = try Packet.readBytes(data, offset, u32);
                return Operation{ .Watch = .{
                    .stores = stores,
                    .since_lsn = since_lsn,
                    .max_wait_ms = max_wait_ms,
                    .max_records = max_records,
                } };
            },
            50 => {
                const status_byte = try Packet.readBytes(data, offset, u8);
                const status = @as(Status, @enumFromInt(status_byte));
                const has_data = try Packet.readBytes(data, offset, u8);
                const reply_data = if (has_data == 1) try Packet.readString(allocator, data, offset) else null;
                return Operation{ .Reply = .{ .status = status, .data = reply_data } };
            },
            51 => {
                const status_byte = try Packet.readBytes(data, offset, u8);
                const status = @as(Status, @enumFromInt(status_byte));
                const count = try Packet.readBytes(data, offset, u32);
                const results = try allocator.alloc([]const u8, count);
                for (results) |*result| {
                    result.* = try Packet.readString(allocator, data, offset);
                }
                return Operation{ .BatchReply = .{ .status = status, .results = results } };
            },
            52 => {
                const status_byte = try Packet.readBytes(data, offset, u8);
                const status = @as(Status, @enumFromInt(status_byte));
                const high_lsn = try Packet.readBytes(data, offset, u64);
                const count = try Packet.readBytes(data, offset, u32);
                const records = try allocator.alloc([]const u8, count);
                for (records) |*r| {
                    r.* = try Packet.readString(allocator, data, offset);
                }
                return Operation{ .WatchReply = .{
                    .status = status,
                    .high_lsn = high_lsn,
                    .records = records,
                } };
            },

            100 => {
                const doc_type_byte = try Packet.readBytes(data, offset, u8);
                const doc_type = @as(DocType, @enumFromInt(doc_type_byte));
                const ns = try Packet.readString(allocator, data, offset);
                const payload = try Packet.readString(allocator, data, offset);
                const auto_create = (try Packet.readBytes(data, offset, u8)) == 1;
                const has_metadata = try Packet.readBytes(data, offset, u8);
                const metadata = if (has_metadata == 1) try Packet.readString(allocator, data, offset) else null;
                return Operation{ .Create = .{
                    .doc_type = doc_type,
                    .ns = ns,
                    .payload = payload,
                    .auto_create = auto_create,
                    .metadata = metadata,
                } };
            },
            101 => {
                const doc_type_byte = try Packet.readBytes(data, offset, u8);
                const doc_type = @as(DocType, @enumFromInt(doc_type_byte));
                const name = try Packet.readString(allocator, data, offset);
                return Operation{ .Drop = .{
                    .doc_type = doc_type,
                    .name = name,
                } };
            },
            102 => Operation.Flush,

            else => SerializationError.InvalidData,
        };
    }

    fn freeAttribute(allocator: Allocator, attr: Attribute) void {
        switch (attr) {
            .Pointer => |data| {
                allocator.free(data.name);
                allocator.free(data.value);
            },
            .I8 => |data| allocator.free(data.name),
            .I16 => |data| allocator.free(data.name),
            .I32 => |data| allocator.free(data.name),
            .I64 => |data| allocator.free(data.name),
            .I128 => |data| allocator.free(data.name),
            .U8 => |data| allocator.free(data.name),
            .U16 => |data| allocator.free(data.name),
            .U32 => |data| allocator.free(data.name),
            .U64 => |data| allocator.free(data.name),
            .U128 => |data| allocator.free(data.name),
            .F32 => |data| allocator.free(data.name),
            .F64 => |data| allocator.free(data.name),
            .F128 => |data| allocator.free(data.name),
        }
    }
};

pub const SerializationError = error{
    BufferTooSmall,
    InvalidData,
    OutOfMemory,
};

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

fn roundTrip(original: Packet) !void {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, original.calcMsgSize());
    defer buf.deinit();
    const serialized = try original.serialize(&buf);
    const deserialized = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, deserialized);
    try expectEqual(original.checksum, deserialized.checksum);
    try expectEqual(original.packet_id, deserialized.packet_id);
    try expectEqual(original.timestamp, deserialized.timestamp);
    try expectEqual(@intFromEnum(original.op), @intFromEnum(deserialized.op));
}

test " Authenticate" {
    const pkt = Packet{
        .checksum = 17,
        .packet_length = 0,
        .packet_id = 26,
        .timestamp = 17000,
        .op = Operation{ .Authenticate = .{ .uid = "admin", .key = "secret_key_123" } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqualStrings("admin", d.op.Authenticate.uid);
    try expectEqualStrings("secret_key_123", d.op.Authenticate.key);
}

test " Logout" {
    try roundTrip(Packet{
        .checksum = 19,
        .packet_length = 0,
        .packet_id = 28,
        .timestamp = 19000,
        .op = Operation.Logout,
    });
}

test " Insert" {
    const pkt = Packet{
        .checksum = 6,
        .packet_length = 0,
        .packet_id = 15,
        .timestamp = 6000,
        .op = Operation{ .Insert = .{ .store_ns = "users", .payload = "\x10\x00\x00\x00", .auto_create = true } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqualStrings("users", d.op.Insert.store_ns);
    try expect(d.op.Insert.auto_create);
}

test " BatchInsert" {
    const allocator = testing.allocator;
    const values = try allocator.alloc([]const u8, 3);
    defer allocator.free(values);
    values[0] = "doc1";
    values[1] = "doc2";
    values[2] = "doc3";
    const pkt = Packet{
        .checksum = 7,
        .packet_length = 0,
        .packet_id = 16,
        .timestamp = 7000,
        .op = Operation{ .BatchInsert = .{ .store_ns = "orders", .values = values } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(usize, 3), d.op.BatchInsert.values.len);
    try expectEqualStrings("doc1", d.op.BatchInsert.values[0]);
}

test " Read" {
    const pkt = Packet{
        .checksum = 8,
        .packet_length = 0,
        .packet_id = 17,
        .timestamp = 8000,
        .op = Operation{ .Read = .{ .store_ns = "users", .id = 0xDEADBEEF_CAFEBABE_12345678_9ABCDEF0 } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(u128, 0xDEADBEEF_CAFEBABE_12345678_9ABCDEF0), d.op.Read.id);
}

test " Update" {
    const pkt = Packet{
        .checksum = 9,
        .packet_length = 0,
        .packet_id = 18,
        .timestamp = 9000,
        .op = Operation{ .Update = .{ .store_ns = "users", .id = 42, .payload = "updated_data" } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(u128, 42), d.op.Update.id);
    try expectEqualStrings("updated_data", d.op.Update.payload);
}

test " Delete with id" {
    const pkt = Packet{
        .checksum = 10,
        .packet_length = 0,
        .packet_id = 19,
        .timestamp = 10000,
        .op = Operation{ .Delete = .{ .store_ns = "users", .id = 99, .query_json = null } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(u128, 99), d.op.Delete.id.?);
    try expect(d.op.Delete.query_json == null);
}

test " Delete with query_json" {
    const pkt = Packet{
        .checksum = 11,
        .packet_length = 0,
        .packet_id = 20,
        .timestamp = 11000,
        .op = Operation{ .Delete = .{ .store_ns = "orders", .id = null, .query_json = "{\"status\":\"cancelled\"}" } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expect(d.op.Delete.id == null);
    try expectEqualStrings("{\"status\":\"cancelled\"}", d.op.Delete.query_json.?);
}

test " Query" {
    const pkt = Packet{
        .checksum = 13,
        .packet_length = 0,
        .packet_id = 22,
        .timestamp = 13000,
        .op = Operation{ .Query = .{ .store_ns = "users", .query_json = "{\"age\":{\"$gt\":18}}" } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqualStrings("{\"age\":{\"$gt\":18}}", d.op.Query.query_json);
}

test " Aggregate" {
    const pkt = Packet{
        .checksum = 14,
        .packet_length = 0,
        .packet_id = 23,
        .timestamp = 14000,
        .op = Operation{ .Aggregate = .{ .store_ns = "sales", .aggregate_json = "[{\"$sum\":\"amount\"}]" } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqualStrings("[{\"$sum\":\"amount\"}]", d.op.Aggregate.aggregate_json);
}

test " Scan with start_key" {
    const pkt = Packet{
        .checksum = 15,
        .packet_length = 0,
        .packet_id = 24,
        .timestamp = 15000,
        .op = Operation{ .Scan = .{ .store_ns = "logs", .start_key = 500, .limit = 100, .skip = 10 } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(u128, 500), d.op.Scan.start_key.?);
    try expectEqual(@as(u32, 100), d.op.Scan.limit);
    try expectEqual(@as(u32, 10), d.op.Scan.skip);
}

test " Scan without start_key" {
    const pkt = Packet{
        .checksum = 16,
        .packet_length = 0,
        .packet_id = 25,
        .timestamp = 16000,
        .op = Operation{ .Scan = .{ .store_ns = "logs", .start_key = null, .limit = 50, .skip = 0 } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expect(d.op.Scan.start_key == null);
}

test " Range with u128 keys" {
    const pkt = Packet{
        .checksum = 12,
        .packet_length = 0,
        .packet_id = 21,
        .timestamp = 12000,
        .op = Operation{ .Range = .{
            .store_ns = "events",
            .start_key = 1000,
            .end_key = 9999,
        } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(u128, 1000), d.op.Range.start_key);
    try expectEqual(@as(u128, 9999), d.op.Range.end_key);
}

test " List with optional fields" {
    const pkt = Packet{
        .checksum = 4,
        .packet_length = 0,
        .packet_id = 13,
        .timestamp = 4000,
        .op = Operation{ .List = .{ .doc_type = DocType.Store, .ns = null, .limit = 50, .offset = 10 } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(@as(u32, 50), d.op.List.limit.?);
    try expectEqual(@as(u32, 10), d.op.List.offset.?);
    try expect(d.op.List.ns == null);
}

test " Reply with data" {
    const pkt = Packet{
        .checksum = 22222,
        .packet_length = 75,
        .packet_id = 4,
        .timestamp = 2222222222,
        .op = Operation{ .Reply = .{ .status = Status.ok, .data = "response data" } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expectEqual(pkt.op.Reply.status, d.op.Reply.status);
    try expectEqualStrings("response data", d.op.Reply.data.?);
}

test " Reply without data" {
    const pkt = Packet{
        .checksum = 33333,
        .packet_length = 50,
        .packet_id = 5,
        .timestamp = 3333333333,
        .op = Operation{ .Reply = .{ .status = Status.not_found, .data = null } },
    };
    try roundTrip(pkt);
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer Packet.free(allocator, d);
    try expect(d.op.Reply.data == null);
}

test " BatchReply" {
    const allocator = testing.allocator;
    const results = try allocator.alloc([]const u8, 2);
    defer allocator.free(results);
    results[0] = "key_abc";
    results[1] = "key_def";
    const pkt = Packet{
        .checksum = 23,
        .packet_length = 0,
        .packet_id = 32,
        .timestamp = 23000,
        .op = Operation{ .BatchReply = .{ .status = Status.ok, .results = results } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.BatchReply.results);
    try expectEqual(Status.ok, d.op.BatchReply.status);
    try expectEqual(@as(usize, 2), d.op.BatchReply.results.len);
    try expectEqualStrings("key_abc", d.op.BatchReply.results[0]);
}

test " Range boundary u128 values" {
    const allocator = testing.allocator;
    const test_cases = [_][2]u128{
        .{ 0, 0 },
        .{ 0, 1 },
        .{ 0, std.math.maxInt(u128) },
        .{ 1000, 9999 },
        .{ std.math.maxInt(u128) - 1, std.math.maxInt(u128) },
    };
    for (test_cases) |tc| {
        const pkt = Packet{
            .checksum = 0,
            .packet_length = 0,
            .packet_id = 0,
            .timestamp = 0,
            .op = Operation{ .Range = .{ .store_ns = "a.b", .start_key = tc[0], .end_key = tc[1] } },
        };
        var buf = try Buffer.init(allocator, pkt.calcMsgSize());
        defer buf.deinit();
        const serialized = try pkt.serialize(&buf);
        const d = try Packet.deserialize(allocator, serialized);
        defer Packet.free(allocator, d);
        try expectEqual(tc[0], d.op.Range.start_key);
        try expectEqual(tc[1], d.op.Range.end_key);
    }
}

// NOTE on free pattern: existing tests (e.g. BatchReply) only free the
// OUTER slice on the deserialized side, NOT each inner string. That's
// because readString returns slices that view the original buffer (it
// takes an allocator but doesn't use it). Calling Packet.free on a
// deserialized packet would attempt to free non-owned slices and panic.
// Pre-existing quirk; we match the established pattern here.

test " Watch empty stores" {
    const allocator = testing.allocator;
    const stores = try allocator.alloc([]const u8, 0);
    defer allocator.free(stores);
    const pkt = Packet{
        .checksum = 100,
        .packet_length = 0,
        .packet_id = 40,
        .timestamp = 100000,
        .op = Operation{ .Watch = .{
            .stores = stores,
            .since_lsn = 0,
            .max_wait_ms = 30_000,
            .max_records = 256,
        } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.Watch.stores);
    try expectEqual(@as(usize, 0), d.op.Watch.stores.len);
    try expectEqual(@as(u64, 0), d.op.Watch.since_lsn);
    try expectEqual(@as(u32, 30_000), d.op.Watch.max_wait_ms);
    try expectEqual(@as(u32, 256), d.op.Watch.max_records);
}

test " Watch single store" {
    const allocator = testing.allocator;
    const stores = try allocator.alloc([]const u8, 1);
    defer allocator.free(stores);
    stores[0] = "orders";
    const pkt = Packet{
        .checksum = 101,
        .packet_length = 0,
        .packet_id = 41,
        .timestamp = 101000,
        .op = Operation{ .Watch = .{
            .stores = stores,
            .since_lsn = 42,
            .max_wait_ms = 5_000,
            .max_records = 100,
        } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.Watch.stores);
    try expectEqual(@as(usize, 1), d.op.Watch.stores.len);
    try expectEqualStrings("orders", d.op.Watch.stores[0]);
    try expectEqual(@as(u64, 42), d.op.Watch.since_lsn);
    try expectEqual(@as(u32, 5_000), d.op.Watch.max_wait_ms);
    try expectEqual(@as(u32, 100), d.op.Watch.max_records);
}

test " Watch multiple stores" {
    const allocator = testing.allocator;
    const stores = try allocator.alloc([]const u8, 3);
    defer allocator.free(stores);
    stores[0] = "orders";
    stores[1] = "payments";
    stores[2] = "deliveries";
    const pkt = Packet{
        .checksum = 102,
        .packet_length = 0,
        .packet_id = 42,
        .timestamp = 102000,
        .op = Operation{
            .Watch = .{
                .stores = stores,
                .since_lsn = 12345,
                .max_wait_ms = 0, // server default
                .max_records = 0, // server default
            },
        },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.Watch.stores);
    try expectEqual(@as(usize, 3), d.op.Watch.stores.len);
    try expectEqualStrings("orders", d.op.Watch.stores[0]);
    try expectEqualStrings("payments", d.op.Watch.stores[1]);
    try expectEqualStrings("deliveries", d.op.Watch.stores[2]);
    try expectEqual(@as(u64, 12345), d.op.Watch.since_lsn);
}

test " WatchReply empty (timeout case)" {
    const allocator = testing.allocator;
    const records = try allocator.alloc([]const u8, 0);
    defer allocator.free(records);
    const pkt = Packet{
        .checksum = 103,
        .packet_length = 0,
        .packet_id = 43,
        .timestamp = 103000,
        .op = Operation{ .WatchReply = .{
            .status = Status.ok,
            .high_lsn = 99,
            .records = records,
        } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.WatchReply.records);
    try expectEqual(Status.ok, d.op.WatchReply.status);
    try expectEqual(@as(u64, 99), d.op.WatchReply.high_lsn);
    try expectEqual(@as(usize, 0), d.op.WatchReply.records.len);
}

test " WatchReply with records" {
    const allocator = testing.allocator;
    const records = try allocator.alloc([]const u8, 2);
    defer allocator.free(records);
    records[0] = "frame_one_bytes\x00\x01\x02";
    records[1] = "frame_two_longer_payload_bytes\xff\xfe";
    const pkt = Packet{
        .checksum = 104,
        .packet_length = 0,
        .packet_id = 44,
        .timestamp = 104000,
        .op = Operation{ .WatchReply = .{
            .status = Status.ok,
            .high_lsn = 200,
            .records = records,
        } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.WatchReply.records);
    try expectEqual(Status.ok, d.op.WatchReply.status);
    try expectEqual(@as(u64, 200), d.op.WatchReply.high_lsn);
    try expectEqual(@as(usize, 2), d.op.WatchReply.records.len);
    try expectEqualStrings("frame_one_bytes\x00\x01\x02", d.op.WatchReply.records[0]);
    try expectEqualStrings("frame_two_longer_payload_bytes\xff\xfe", d.op.WatchReply.records[1]);
}

test " WatchReply not_found (rebootstrap signal)" {
    const allocator = testing.allocator;
    const records = try allocator.alloc([]const u8, 0);
    defer allocator.free(records);
    const pkt = Packet{
        .checksum = 105,
        .packet_length = 0,
        .packet_id = 45,
        .timestamp = 105000,
        .op = Operation{ .WatchReply = .{
            .status = Status.not_found,
            .high_lsn = 1000,
            .records = records,
        } },
    };
    var buf = try Buffer.init(allocator, pkt.calcMsgSize());
    defer buf.deinit();
    const serialized = try pkt.serialize(&buf);
    const d = try Packet.deserialize(allocator, serialized);
    defer allocator.free(d.op.WatchReply.records);
    try expectEqual(Status.not_found, d.op.WatchReply.status);
    try expectEqual(@as(u64, 1000), d.op.WatchReply.high_lsn);
    try expectEqual(@as(usize, 0), d.op.WatchReply.records.len);
}

test "error handling for invalid data" {
    const allocator = testing.allocator;
    const empty_data = [_]u8{};
    try testing.expectError(SerializationError.InvalidData, Packet.deserialize(allocator, &empty_data));
    const partial_data = [_]u8{ 1, 2, 3, 4 };
    try testing.expectError(SerializationError.InvalidData, Packet.deserialize(allocator, &partial_data));
    var invalid_op_data = [_]u8{0} ** 25;
    invalid_op_data[24] = 255;
    try testing.expectError(SerializationError.InvalidData, Packet.deserialize(allocator, &invalid_op_data));
}

test "deserialize truncated header" {
    const allocator = testing.allocator;
    var short = [_]u8{0} ** 20;
    try testing.expectError(SerializationError.InvalidData, Packet.deserialize(allocator, &short));
}
