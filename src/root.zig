pub const Operation = @import("operation.zig").Operation;
pub const OperationTag = @import("operation.zig").OperationTag;
pub const Attribute = @import("operation.zig").Attribute;
pub const Status = @import("operation.zig").Status;
pub const ErrorCode = @import("operation.zig").ErrorCode;
pub const Store = @import("operation.zig").Store;
pub const StoreStatus = @import("operation.zig").StoreStatus;
pub const StoreInfo = @import("operation.zig").StoreInfo;
pub const Index = @import("operation.zig").Index;
pub const User = @import("operation.zig").User;
pub const Backup = @import("operation.zig").Backup;
pub const Schedule = @import("operation.zig").Schedule;
pub const DocType = @import("operation.zig").DocType;
pub const FieldType = @import("operation.zig").FieldType;
pub const ValueType = @import("operation.zig").ValueType;
pub const parseNamespace = @import("operation.zig").parseNamespace;
pub const NamespaceParts = @import("operation.zig").NamespaceParts;
pub const Packet = @import("packet.zig").Packet;
pub const SerializationError = @import("packet.zig").SerializationError;

test {
    _ = @import("packet.zig");
    _ = @import("operation.zig");
}
