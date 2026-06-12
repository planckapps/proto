const std = @import("std");

pub const ValueType = enum {
    I8,
    I16,
    I32,
    I64,
    I128,
    U8,
    U16,
    U32,
    U64,
    U128,
    F32,
    F64,
    F128,
    Pointer,
};

pub const Status = enum(u8) {
    ok = 0,
    err = 1,
    not_found = 2,
    invalid_request = 3,
    server_error = 4,
    no_index_on_field = 5,
    document_too_large = 6,
    not_leader = 7,
    /// Returned by idempotent ops (today: `Create` on `Store`/`Index`)
    /// when the target already exists. Distinguishes "we did the work"
    /// from "no-op, was already there" without surfacing an error.
    already_exists = 8,

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            .ok => "Success",
            .err => "General error occurred",
            .not_found => "Resource not found",
            .invalid_request => "Invalid request format",
            .server_error => "Internal server error",
            .no_index_on_field => "No index on field",
            .document_too_large => "Document exceeds size limit",
            .not_leader => "Not the leader node",
            .already_exists => "Resource already exists",
        };
    }
};

pub const ErrorCode = enum(u16) {
    success = 1000,

    not_found = 1100,
    store_not_found = 1101,
    user_not_found = 1103,
    index_not_found = 1104,
    key_not_found = 1105,

    unauthorized = 1200,
    invalid_credentials = 1201,
    session_expired = 1202,
    permission_denied = 1203,
    account_locked = 1204,
    user_disabled = 1205,
    user_already_exists = 1206,

    invalid_request = 1300,
    invalid_namespace = 1301,
    invalid_query = 1302,
    key_too_large = 1303,
    document_too_large = 1304,
    batch_too_large = 1305,
    no_index_on_field = 1306,
    invalid_field_type = 1307,
    missing_required_field = 1308,
    duplicate_index = 1309,

    server_offline = 1400,
    not_leader = 1401,
    read_only = 1402,
    store_already_exists = 1403,
    store_delete_in_progress = 1405,

    internal_error = 1500,
    io_error = 1501,
    wal_error = 1502,
    replication_error = 1503,

    pub fn toName(self: ErrorCode) []const u8 {
        return switch (self) {
            .success => "success",
            .not_found => "not_found",
            .store_not_found => "store_not_found",
            .user_not_found => "user_not_found",
            .index_not_found => "index_not_found",
            .key_not_found => "key_not_found",
            .unauthorized => "unauthorized",
            .invalid_credentials => "invalid_credentials",
            .session_expired => "session_expired",
            .permission_denied => "permission_denied",
            .account_locked => "account_locked",
            .user_disabled => "user_disabled",
            .user_already_exists => "user_already_exists",
            .invalid_request => "invalid_request",
            .invalid_namespace => "invalid_namespace",
            .invalid_query => "invalid_query",
            .key_too_large => "key_too_large",
            .document_too_large => "document_too_large",
            .batch_too_large => "batch_too_large",
            .no_index_on_field => "no_index_on_field",
            .invalid_field_type => "invalid_field_type",
            .missing_required_field => "missing_required_field",
            .duplicate_index => "duplicate_index",
            .server_offline => "server_offline",
            .not_leader => "not_leader",
            .read_only => "read_only",
            .store_already_exists => "store_already_exists",
            .store_delete_in_progress => "store_delete_in_progress",
            .internal_error => "internal_error",
            .io_error => "io_error",
            .wal_error => "wal_error",
            .replication_error => "replication_error",
        };
    }

    pub fn toStatus(self: ErrorCode) Status {
        return switch (self) {
            .success => .ok,
            .not_found, .store_not_found, .user_not_found, .index_not_found, .key_not_found => .not_found,
            .unauthorized, .invalid_credentials, .session_expired, .permission_denied, .account_locked, .user_disabled, .user_already_exists => .err,
            .invalid_request, .invalid_namespace, .invalid_query, .key_too_large, .missing_required_field, .invalid_field_type, .duplicate_index => .invalid_request,
            .document_too_large, .batch_too_large => .document_too_large,
            .no_index_on_field => .no_index_on_field,
            .server_offline, .read_only, .store_already_exists, .store_delete_in_progress => .invalid_request,
            .not_leader => .not_leader,
            .internal_error, .io_error, .wal_error, .replication_error => .server_error,
        };
    }

    pub fn formatError(self: ErrorCode, allocator: std.mem.Allocator, message: []const u8) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);
        try buf.print(allocator,
            \\{{"code":{d},"error":"{s}","message":"{s}"}}
        , .{ @intFromEnum(self), self.toName(), message });
        return try buf.toOwnedSlice(allocator);
    }
};

pub const Attribute = union(enum) {
    I8: struct {
        name: []const u8,
        value: i8,
    },
    I16: struct {
        name: []const u8,
        value: i16,
    },
    I32: struct {
        name: []const u8,
        value: i32,
    },
    I64: struct {
        name: []const u8,
        value: i64,
    },
    I128: struct {
        name: []const u8,
        value: i128,
    },
    U8: struct {
        name: []const u8,
        value: u8,
    },
    U16: struct {
        name: []const u8,
        value: u16,
    },
    U32: struct {
        name: []const u8,
        value: u32,
    },
    U64: struct {
        name: []const u8,
        value: u64,
    },
    U128: struct {
        name: []const u8,
        value: u128,
    },
    F32: struct {
        name: []const u8,
        value: f32,
    },
    F64: struct {
        name: []const u8,
        value: f64,
    },
    F128: struct {
        name: []const u8,
        value: f128,
    },
    Pointer: struct {
        name: []const u8,
        value: []const u8,
    },

    pub fn calcAttributeSize(attr: *const Attribute) usize {
        var size: usize = 1; // type tag

        switch (attr.*) {
            .I8 => |data| size += 4 + data.name.len + 1,
            .I16 => |data| size += 4 + data.name.len + 2,
            .I32 => |data| size += 4 + data.name.len + 4,
            .I64 => |data| size += 4 + data.name.len + 8,
            .I128 => |data| size += 4 + data.name.len + 16,
            .U8 => |data| size += 4 + data.name.len + 1,
            .U16 => |data| size += 4 + data.name.len + 2,
            .U32 => |data| size += 4 + data.name.len + 4,
            .U64 => |data| size += 4 + data.name.len + 8,
            .U128 => |data| size += 4 + data.name.len + 16,
            .F32 => |data| size += 4 + data.name.len + 4,
            .F64 => |data| size += 4 + data.name.len + 8,
            .F128 => |data| size += 4 + data.name.len + 16,
            .Pointer => |data| size += 4 + data.name.len + 4 + data.value.len,
        }

        return size;
    }
};

pub const StatsTag = enum(u8) {
    WalStats = 1,
    DbStats = 2,
    IndexStats = 3,
    VLogStats = 4,
    GcStats = 5,
    HistoryStats = 6,
    AllStats = 255,
};

pub const OperationTag = enum(u8) {
    // ---- Auth + data operations (1-14) ----
    Authenticate = 1,
    Logout = 2,
    Insert = 3,
    BatchInsert = 4,
    Read = 5,
    Update = 6,
    Delete = 7,
    Query = 8,
    Aggregate = 9,
    Scan = 10,
    Range = 11,
    List = 12,
    NextSequence = 13,
    Watch = 14,

    // ---- Response operations (50-52) ----
    Reply = 50,
    BatchReply = 51,
    WatchReply = 52,

    // ---- DDL + admin operations (100-118) ----
    Create = 100,
    Drop = 101,
    Flush = 102,
    Shutdown = 103,
    SetMode = 104,
    RegenerateKey = 105,
    UpdateUser = 106,
    Backup = 107,
    Restore = 108,
    Export = 109,
    Import = 110,
    Stats = 111,
    GetConfig = 112,
    SetConfig = 113,
    Collect = 114,
    Vlogs = 115,
    Ping = 116,
    Truncate = 117,
    SaveStats = 118,

    // ---- Auth token operations (119-122) ----
    SaveToken = 119,
    RevokeToken = 120,
    RefreshToken = 121,
    AuditLog = 122,

    // ---- Replication (200) ----
    ShipWal = 200,

    // ---- Role management (201-202) ----
    Demote = 201,
    Promote = 202,
};

pub const Operation = union(OperationTag) {
    Authenticate: struct {
        uid: []const u8,
        key: []const u8,
    },

    Logout: void,

    Insert: struct {
        store_ns: []const u8,
        payload: []const u8,
        auto_create: bool,
    },

    BatchInsert: struct {
        store_ns: []const u8,
        values: [][]const u8,
    },

    Read: struct {
        store_ns: []const u8,
        // Primary key of the target document (u128). Named `key` to
        // match the on-the-wire BSON field engine queries return
        // (`"key": "<32-char hex>"`). Same value, no encoding change.
        key: u128,
    },

    Update: struct {
        store_ns: []const u8,
        key: u128,
        payload: []const u8,
    },

    Delete: struct {
        store_ns: []const u8,
        // Either `key` (delete that one doc) or `query_json` (delete
        // every doc matching the filter) is non-null. The engine
        // dispatches on which one is set.
        key: ?u128,
        query_json: ?[]const u8,
    },

    Query: struct {
        store_ns: []const u8,
        query_json: []const u8,
    },

    Aggregate: struct {
        store_ns: []const u8,
        aggregate_json: []const u8,
    },

    Scan: struct {
        store_ns: []const u8,
        start_key: ?u128,
        limit: u32,
        skip: u32,
    },

    Range: struct {
        store_ns: []const u8,
        start_key: u128,
        end_key: u128,
    },

    List: struct {
        doc_type: DocType,
        ns: ?[]const u8,
        limit: ?u32,
        offset: ?u32,
    },

    NextSequence: struct {
        name: []const u8,
    },

    Watch: struct {
        stores: [][]const u8,
        since_lsn: u64,
        max_wait_ms: u32,
        max_records: u32,
    },

    Reply: struct {
        status: Status,
        data: ?[]const u8,
    },

    BatchReply: struct {
        status: Status,
        results: [][]const u8,
    },

    WatchReply: struct {
        status: Status,
        high_lsn: u64,
        records: [][]const u8,
    },

    Create: struct {
        doc_type: DocType,
        ns: []const u8,
        payload: []const u8,
        auto_create: bool,
        metadata: ?[]const u8,
    },

    Drop: struct {
        doc_type: DocType,
        name: []const u8,
    },

    Flush: void,

    // ========== ADMIN OPERATIONS (103-118) ==========

    Shutdown: void,

    SetMode: struct {
        online: bool,
    },

    RegenerateKey: struct {
        uid: []const u8,
    },

    UpdateUser: struct {
        uid: []const u8,
        role: u8,
    },

    Backup: struct {
        path: []const u8,
    },

    Restore: struct {
        backup_path: []const u8,
        target_path: []const u8,
    },

    Export: struct {
        data: []const u8, // manifest YAML
    },

    Import: struct {
        data: []const u8, // manifest YAML
    },

    Stats: struct { stat: StatsTag },

    GetConfig: void,

    SetConfig: struct {
        data: []const u8,
    },

    Collect: struct { vlogs: []const u8 },

    Vlogs: void,

    Ping: void,

    Truncate: void,

    SaveStats: struct {
        store_ns: []const u8,
        data: []const u8,
    },

    // ========== AUTH TOKEN OPERATIONS (119-122) ==========

    SaveToken: struct {
        app: []const u8,
        uid: []const u8,
        provider: []const u8,
        token: []const u8,
        expires_at: i64,
        claims: ?[]const u8,
        role: []const u8,
        client_ip: ?[]const u8,
    },

    RevokeToken: struct {
        app: []const u8,
        token: []const u8,
    },

    RefreshToken: struct {
        app: []const u8,
        old_token: []const u8,
        refresh_token: []const u8,
        provider: []const u8,
    },

    AuditLog: struct {
        event: []const u8,
        uid: ?[]const u8,
        provider: ?[]const u8,
        client_ip: ?[]const u8,
        reason: ?[]const u8,
        timestamp: i64,
        app: []const u8,
    },

    // ========== REPLICATION (200) ==========

    ShipWal: struct {
        op_kind: u8,
        store_ns: []const u8,
        lsn: u64,
        doc_id: u128,
        timestamp: i64,
        data: []const u8,
    },

    // ========== ROLE MANAGEMENT (201-202) ==========

    Demote: void,
    Promote: void,
};

pub const DocType = enum(u8) {
    Store = 2,
    Index = 3,
    Document = 4,
    User = 5,
    Backup = 6,
    Schedule = 7,
    Service = 8,
    Sequence = 9,
};

pub const FieldType = enum(u8) {
    String = 1,
    U32 = 2,
    U64 = 3,
    I32 = 4,
    I64 = 5,
    F32 = 6,
    F64 = 7,
    Boolean = 8,
};

 pub const StoreStatus = enum(u8) {
    active = 0,
    deleting = 1,
};

 pub const Store = struct {
    id: u16,
    store_id: u16,
    ns: []const u8,
    description: ?[]const u8 = null,
    created_at: i64 = 0,
    status: StoreStatus = .active,
};

 
pub const Index = struct {
    id: u16,
    store_id: u16,
    ns: []const u8,
    field: []const u8,
    field_type: FieldType,
    unique: bool = true,
    description: ?[]const u8 = null,
    created_at: i64 = 0,
    index_path: []const u8 = "",
};

 
pub const StoreInfo = struct {
    store: Store,
    indexes: []Index,
};

const VLog = struct {
    id: u16,
    file_name: []u8,
    created_at: i64,
};

 
pub const User = struct {
    id: u16,
    username: []const u8,
    password_hash: []const u8,
    role: u8,
    created_at: i64 = 0,
};

 
pub const Backup = struct {
    id: u16,
    name: []const u8,
    backup_path: []const u8,
    size_bytes: u64 = 0,
    created_at: i64 = 0,
    description: ?[]const u8 = null,
};

 
pub const Schedule = struct {
    name: []const u8,
    task_type: []const u8,
    cron_expr: []const u8,
    enabled: bool,
    backup_path: []const u8 = "",
    description: ?[]const u8 = null,
    created_at: i64 = 0,
    updated_at: i64 = 0,
    last_run_at: i64 = 0,
    next_run_at: i64 = 0,
};

 
pub const NamespaceParts = struct {
    store: ?[]const u8,
    index: ?[]const u8,

     pub fn deinit(self: *NamespaceParts, allocator: std.mem.Allocator) void {
        if (self.store) |s| allocator.free(s);
        if (self.index) |s| allocator.free(s);
    }
};

 
pub fn parseNamespace(allocator: std.mem.Allocator, ns: []const u8) !NamespaceParts {
    var parts = NamespaceParts{
        .store = null,
        .index = null,
    };

    var iter = std.mem.splitScalar(u8, ns, '.');
    var count: u8 = 0;

    while (iter.next()) |part| : (count += 1) {
        const part_copy = try allocator.dupe(u8, part);
        switch (count) {
            0 => parts.store = part_copy,
            1 => parts.index = part_copy,
            else => {
                allocator.free(part_copy);
                parts.deinit(allocator);
                return error.InvalidNamespace;
            },
        }
    }

    return parts;
}

 
pub fn validateNamespace(ns: []const u8, expected_type: DocType) !void {
    const part_count = std.mem.count(u8, ns, ".") + 1;

    switch (expected_type) {
        .Store => if (part_count != 1) return error.InvalidStoreNamespace,
        .Index => if (part_count != 2) return error.InvalidIndexNamespace,
        .Document => if (part_count != 1) return error.InvalidDocumentNamespace,
        .User => if (part_count != 1) return error.InvalidUserNamespace,
        .Backup => if (part_count != 1) return error.InvalidBackupNamespace,
        .Schedule => if (part_count != 1) return error.InvalidScheduleNamespace,
        .Service => if (part_count != 1) return error.InvalidServiceNamespace,
        .Sequence => if (part_count != 1) return error.InvalidSequenceNamespace,
    }
}

const testing = std.testing;

test "parseNamespace - single part (store)" {
    const allocator = testing.allocator;
    var parts = try parseNamespace(allocator, "orders");
    defer parts.deinit(allocator);
    try testing.expectEqualStrings("orders", parts.store.?);
    try testing.expect(parts.index == null);
}

test "parseNamespace - two parts (store.index)" {
    const allocator = testing.allocator;
    var parts = try parseNamespace(allocator, "orders.user_id_idx");
    defer parts.deinit(allocator);
    try testing.expectEqualStrings("orders", parts.store.?);
    try testing.expectEqualStrings("user_id_idx", parts.index.?);
}

test "parseNamespace - too many parts returns error" {
    const allocator = testing.allocator;
    try testing.expectError(error.InvalidNamespace, parseNamespace(allocator, "a.b.c"));
}

test "validateNamespace - correct part counts" {
    try validateNamespace("orders", .Store);
    try validateNamespace("orders.idx", .Index);
    try validateNamespace("orders", .Document);
    try validateNamespace("admin", .User);
    try validateNamespace("snap1", .Backup);
}

test "validateNamespace - wrong part counts" {
    try testing.expectError(error.InvalidStoreNamespace, validateNamespace("a.b", .Store));
    try testing.expectError(error.InvalidIndexNamespace, validateNamespace("a", .Index));
    try testing.expectError(error.InvalidIndexNamespace, validateNamespace("a.b.c", .Index));
    try testing.expectError(error.InvalidDocumentNamespace, validateNamespace("a.b", .Document));
    try testing.expectError(error.InvalidUserNamespace, validateNamespace("a.b", .User));
    try testing.expectError(error.InvalidBackupNamespace, validateNamespace("a.b", .Backup));
}

test "ValueType has all expected variants" {
    try testing.expectEqual(@as(usize, 14), @typeInfo(ValueType).@"enum".fields.len);
}

test "OperationTag wire values" {
    try testing.expectEqual(@as(u8, 1), @intFromEnum(OperationTag.Authenticate));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(OperationTag.Logout));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(OperationTag.Insert));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(OperationTag.Query));
    try testing.expectEqual(@as(u8, 12), @intFromEnum(OperationTag.List));
    try testing.expectEqual(@as(u8, 14), @intFromEnum(OperationTag.Watch));
    try testing.expectEqual(@as(u8, 50), @intFromEnum(OperationTag.Reply));
    try testing.expectEqual(@as(u8, 51), @intFromEnum(OperationTag.BatchReply));
    try testing.expectEqual(@as(u8, 52), @intFromEnum(OperationTag.WatchReply));
    try testing.expectEqual(@as(u8, 100), @intFromEnum(OperationTag.Create));
    try testing.expectEqual(@as(u8, 102), @intFromEnum(OperationTag.Flush));
}

test "Status toString" {
    try testing.expectEqualStrings("Success", Status.ok.toString());
    try testing.expectEqualStrings("Resource not found", Status.not_found.toString());
    try testing.expectEqualStrings("Internal server error", Status.server_error.toString());
}

test "ErrorCode toName" {
    try testing.expectEqualStrings("success", ErrorCode.success.toName());
    try testing.expectEqualStrings("store_not_found", ErrorCode.store_not_found.toName());
    try testing.expectEqualStrings("invalid_credentials", ErrorCode.invalid_credentials.toName());
    try testing.expectEqualStrings("batch_too_large", ErrorCode.batch_too_large.toName());
    try testing.expectEqualStrings("not_leader", ErrorCode.not_leader.toName());
    try testing.expectEqualStrings("internal_error", ErrorCode.internal_error.toName());
}

test "ErrorCode toStatus mapping" {
    try testing.expectEqual(Status.ok, ErrorCode.success.toStatus());
    try testing.expectEqual(Status.not_found, ErrorCode.store_not_found.toStatus());
    try testing.expectEqual(Status.not_found, ErrorCode.key_not_found.toStatus());
    try testing.expectEqual(Status.invalid_request, ErrorCode.invalid_request.toStatus());
    try testing.expectEqual(Status.document_too_large, ErrorCode.document_too_large.toStatus());
    try testing.expectEqual(Status.no_index_on_field, ErrorCode.no_index_on_field.toStatus());
    try testing.expectEqual(Status.not_leader, ErrorCode.not_leader.toStatus());
    try testing.expectEqual(Status.server_error, ErrorCode.internal_error.toStatus());
    try testing.expectEqual(Status.err, ErrorCode.invalid_credentials.toStatus());
}

test "ErrorCode numeric values" {
    try testing.expectEqual(@as(u16, 1000), @intFromEnum(ErrorCode.success));
    try testing.expectEqual(@as(u16, 1101), @intFromEnum(ErrorCode.store_not_found));
    try testing.expectEqual(@as(u16, 1201), @intFromEnum(ErrorCode.invalid_credentials));
    try testing.expectEqual(@as(u16, 1304), @intFromEnum(ErrorCode.document_too_large));
    try testing.expectEqual(@as(u16, 1401), @intFromEnum(ErrorCode.not_leader));
    try testing.expectEqual(@as(u16, 1500), @intFromEnum(ErrorCode.internal_error));
}

test "ErrorCode formatError" {
    const allocator = testing.allocator;
    const json = try ErrorCode.store_not_found.formatError(allocator, "store 'mydb' does not exist");
    defer allocator.free(json);
    try testing.expectEqualStrings(
        \\{"code":1101,"error":"store_not_found","message":"store 'mydb' does not exist"}
    , json);
}

test "Attribute calcAttributeSize" {
    const attr_i8 = Attribute{ .I8 = .{ .name = "age", .value = 25 } };
    try testing.expectEqual(@as(usize, 1 + 4 + 3 + 1), attr_i8.calcAttributeSize()); // tag + len + "age" + i8

    const attr_ptr = Attribute{ .Pointer = .{ .name = "name", .value = "hello" } };
    try testing.expectEqual(@as(usize, 1 + 4 + 4 + 4 + 5), attr_ptr.calcAttributeSize()); // tag + len + "name" + len + "hello"
}
