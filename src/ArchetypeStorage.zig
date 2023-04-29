//! Represents a single archetype, that is, entities which have the same exact set of component
//! types. When a component is added or removed from an entity, it's archetype changes.
//!
//! Database equivalent: a table where rows are entities and columns are components (dense storage).
//! The hash of every component name in this archetype, i.e. the name of this archetype.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const assert = std.debug.assert;
const builtin = @import("builtin");

const ArchetypeStorage = @This();

pub const TypeId = enum(usize) { _ };

const is_debug = builtin.mode == .Debug;

// typeId implementation by Felix "xq" Queißner
pub fn typeId(comptime T: type) TypeId {
    _ = T;
    return @intToEnum(TypeId, @ptrToInt(&struct {
        var x: u8 = 0;
    }.x));
}

pub const Column = struct {
    name: []const u8,
    type_id: TypeId,
    size: u32,
    alignment: u16,
    values: []u8,
};

hash: u64,

/// The length of the table (used number of rows.)
len: u32,

/// The capacity of the table (allocated number of rows.)
capacity: u32,

/// Describes the columns in this table. Each column stores its row values.
columns: []Column,

/// Calculates the storage.hash value. This is a hash of all the component names, and can
/// effectively be used to uniquely identify this table within the database.
pub fn calculateHash(storage: *ArchetypeStorage) void {
    storage.hash = 0;
    for (storage.columns) |column| {
        storage.hash ^= std.hash_map.hashString(column.name);
    }
}

pub fn deinit(storage: *ArchetypeStorage, gpa: Allocator) void {
    if (storage.capacity > 0) {
        for (storage.columns) |column| gpa.free(column.values);
    }
    gpa.free(storage.columns);
}

fn debugValidateRow(storage: *ArchetypeStorage, gpa: Allocator, row: anytype) void {
    inline for (std.meta.fields(@TypeOf(row)), 0..) |field, index| {
        const column = storage.columns[index];
        if (typeId(field.type) != column.type_id) {
            const msg = std.mem.concat(gpa, u8, &.{
                "unexpected type: ",
                @typeName(field.type),
                " expected: ",
                column.name,
            }) catch |err| @panic(@errorName(err));
            @panic(msg);
        }
    }
}

/// appends a new row to this table, with all undefined values.
pub fn appendUndefined(storage: *ArchetypeStorage, gpa: Allocator) !u32 {
    try storage.ensureUnusedCapacity(gpa, 1);
    assert(storage.len < storage.capacity);
    const row_index = storage.len;
    storage.len += 1;
    return row_index;
}

pub fn append(storage: *ArchetypeStorage, gpa: Allocator, row: anytype) !u32 {
    if (is_debug) storage.debugValidateRow(gpa, row);

    try storage.ensureUnusedCapacity(gpa, 1);
    assert(storage.len < storage.capacity);
    storage.len += 1;

    storage.setRow(gpa, storage.len - 1, row);
    return storage.len;
}

pub fn undoAppend(storage: *ArchetypeStorage) void {
    storage.len -= 1;
}

/// Ensures there is enough unused capacity to store `num_rows`.
pub fn ensureUnusedCapacity(storage: *ArchetypeStorage, gpa: Allocator, num_rows: usize) !void {
    return storage.ensureTotalCapacity(gpa, storage.len + num_rows);
}

/// Ensures the total capacity is enough to store `new_capacity` rows total.
pub fn ensureTotalCapacity(storage: *ArchetypeStorage, gpa: Allocator, new_capacity: usize) !void {
    var better_capacity = storage.capacity;
    if (better_capacity >= new_capacity) return;

    while (true) {
        better_capacity +|= better_capacity / 2 + 8;
        if (better_capacity >= new_capacity) break;
    }

    return storage.setCapacity(gpa, better_capacity);
}

/// Sets the capacity to exactly `new_capacity` rows total
///
/// Asserts `new_capacity >= storage.len`, if you want to shrink capacity then change the len
/// yourself first.
pub fn setCapacity(storage: *ArchetypeStorage, gpa: Allocator, new_capacity: usize) !void {
    assert(new_capacity >= storage.len);

    // TODO: ensure columns are sorted by type_id
    for (storage.columns) |*column| {
        const old_values = column.values;
        const new_values = try gpa.alloc(u8, new_capacity * column.size);
        if (storage.capacity > 0) {
            std.mem.copy(u8, new_values[0..], old_values);
            gpa.free(old_values);
        }
        column.values = new_values;
    }
    storage.capacity = @intCast(u32, new_capacity);
}

/// Sets the entire row's values in the table.
pub fn setRow(storage: *ArchetypeStorage, gpa: Allocator, row_index: u32, row: anytype) void {
    if (is_debug) storage.debugValidateRow(gpa, row);

    const fields = std.meta.fields(@TypeOf(row));
    inline for (fields, 0..) |field, index| {
        const ColumnType = field.type;
        if (@sizeOf(ColumnType) == 0) continue;

        var column = storage.columns[index];
        const column_values = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), column.values.ptr));
        column_values[row_index] = @field(row, field.name);
    }
}

/// Sets the value of the named components (columns) for the given row in the table.
pub fn set(storage: *ArchetypeStorage, gpa: Allocator, row_index: u32, name: []const u8, component: anytype) void {
    assert(storage.len != 0 and storage.len >= row_index);

    const ColumnType = @TypeOf(component);
    if (@sizeOf(ColumnType) == 0) return;

    const values = storage.getColumnValues(gpa, name, ColumnType) orelse @panic("no such component");
    values[row_index] = component;
}

pub fn get(storage: *ArchetypeStorage, gpa: Allocator, row_index: u32, name: []const u8, comptime ColumnType: type) ?ColumnType {
    if (@sizeOf(ColumnType) == 0) return {};

    const values = storage.getColumnValues(gpa, name, ColumnType) orelse return null;
    return values[row_index];
}

pub fn getRaw(storage: *ArchetypeStorage, row_index: u32, column: Column) []u8 {
    const values = storage.getRawColumnValues(column.name) orelse @panic("getRaw(): no such component");
    const start = column.size * row_index;
    const end = start + column.size;
    return values[start..end];
}

pub fn setRaw(storage: *ArchetypeStorage, row_index: u32, column: Column, component: []u8) !void {
    const values = storage.getRawColumnValues(column.name) orelse @panic("setRaw(): no such component");
    const start = column.size * row_index;
    assert(component.len == column.size);
    std.mem.copy(u8, values[start..], component);
}

/// Swap-removes the specified row with the last row in the table.
pub fn remove(storage: *ArchetypeStorage, row_index: u32) void {
    if (storage.len > 1) {
        for (storage.columns) |column| {
            const dstStart = column.size * row_index;
            const dst = column.values[dstStart .. dstStart + column.size];
            const srcStart = column.size * (storage.len - 1);
            const src = column.values[srcStart .. srcStart + column.size];
            std.mem.copy(u8, dst, src);
        }
    }
    storage.len -= 1;
}

/// Tells if this archetype has every one of the given components.
pub fn hasComponents(storage: *ArchetypeStorage, components: []const []const u8) bool {
    for (components) |component_name| {
        if (!storage.hasComponent(component_name)) return false;
    }
    return true;
}

/// Tells if this archetype has a component with the specified name.
pub fn hasComponent(storage: *ArchetypeStorage, component: []const u8) bool {
    for (storage.columns) |column| {
        if (std.mem.eql(u8, column.name, component)) return true;
    }
    return false;
}

pub fn getColumnValues(storage: *ArchetypeStorage, gpa: Allocator, name: []const u8, comptime ColumnType: type) ?[]ColumnType {
    for (storage.columns) |*column| {
        if (!std.mem.eql(u8, column.name, name)) continue;
        if (is_debug) {
            if (typeId(ColumnType) != column.type_id) {
                const msg = std.mem.concat(gpa, u8, &.{
                    "unexpected type: ",
                    @typeName(ColumnType),
                    " expected: ",
                    column.name,
                }) catch |err| @panic(@errorName(err));
                @panic(msg);
            }
        }
        var ptr = @ptrCast([*]ColumnType, @alignCast(@alignOf(ColumnType), column.values.ptr));
        const column_values = ptr[0..storage.capacity];
        return column_values;
    }
    return null;
}

pub fn getRawColumnValues(storage: *ArchetypeStorage, name: []const u8) ?[]u8 {
    for (storage.columns) |column| {
        if (!std.mem.eql(u8, column.name, name)) continue;
        return column.values;
    }
    return null;
}
