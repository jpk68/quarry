const builtin = @import("builtin");

pub const CodeBlock = struct {
    instructions: []const u8,
    constants: []const i64,
};
