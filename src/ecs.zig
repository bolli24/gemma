const std = @import("std");
const Allocator = std.mem.Allocator;

const Entity = struct {
    id: u32,
    generation: u32,
};

const World = struct {
    const Self = @This();

    flags: std.ArrayList(bool),
    unused_ids: std.ArrayList(u32),
    generations: std.ArrayList(u32),
    sets: std.AutoHashMap(TypeId, SparseSet(anyopaque)),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{
            .flags = .init(allocator),
            .unused_ids = .init(allocator),
            .generations = .init(allocator),
            .sets = .init(allocator),
            .allocator = allocator,
        };
    }

    pub fn components(self: *Self, comptime T: type) !*SparseSet(T) {
        const entry = try self.sets.getOrPut(typeId(T));
        if (!entry.found_existing) {
            const ptr: *SparseSet(T) = @ptrCast(entry.value_ptr);
            ptr.* = SparseSet(T).init(self.allocator);
        }

        return @ptrCast(entry.value_ptr);
    }

    pub fn create(self: *Self) !Entity {
        if (self.unused_ids.pop()) |id| {
            self.flags.items[id] = true;
            self.generations.items[id] += 1;

            return Entity{ .id = id, .generation = self.generations.items[id] };
        } else {
            try self.flags.append(true);
            try self.generations.append(0);

            return Entity{ .id = @intCast(self.flags.items.len - 1), .generation = 0 };
        }
    }

    pub fn delete(self: *Self, entity: Entity) !void {
        if (self.flags.items[entity.id] == false) {
            return;
        }
        self.flags.items[entity.id] = false;
        try self.unused_ids.append(entity.id);
    }

    pub fn isValid(self: *Self, entity: Entity) bool {
        return self.flags.items[entity.id] and entity.generation == self.generations.items[entity.id];
    }

    const SetInfo = struct { *SparseSet(anyopaque), type };

    pub fn runSystem(self: *Self, comptime system: anytype) !void {
        const fn_info = switch (@typeInfo(@TypeOf(system))) {
            .@"fn" => |info| info,
            else => @compileError("System must be function."),
        };

        // TODO: support errors
        if (fn_info.return_type != void) {
            @compileError("System must not return any value.");
        }

        comptime var Values: type = undefined;
        comptime var found_query = false;

        comptime for (fn_info.params, 0..) |*param, i| {
            _ = i;
            const param_type = std.meta.Child(param.type orelse @compileError("Parameter type must be defined."));
            switch (@typeInfo(param_type)) {
                .@"struct" => |info| {
                    if (std.mem.indexOf(u8, @typeName(param_type), "Query") != null) {
                        if (found_query) {
                            // TODO: support multiple queries
                            @compileError("System parameters must not include more than one query.");
                        }
                        for (info.fields) |field| {
                            if (std.mem.eql(u8, field.name, "type")) {
                                found_query = true;
                                Values = get_pointed_tuple(@typeInfo(field.type).@"struct");
                            }
                        }
                    }
                },
                else => @compileError("Invalid system parameter.")
            }
        };

        if (!found_query) @compileError("System parameters must include Query.");

        // const comps = [_]*SparseSet(anyopaque){undefined} ** @typeInfo(Values).@"struct".fields.len;
        const query_type = get_query_type(@typeInfo(Values).@"struct");

        var query: Query(query_type) = .{
            .world = self,
            .current = 0,
            .comps = undefined,
        };

        inline for (0..query.comps.len) |i| {
            const set_type = comptime @TypeOf(query.comps[i]);
            const set = try self.components(set_type);
            query.comps[i] = @ptrCast(set);
        }

        // std.debug.print("{p}\n", .{query.next().?[0]});

        system(&query);
    }
};

pub fn Query(comptime T: type) type {
    const struct_info: std.builtin.Type.Struct = switch (@typeInfo(T)) {
        .@"struct" => |info| info,
        else => @compileError(
            "Query parameter must be a tuple struct.",
        ),
    };

    if (!struct_info.is_tuple) @compileError("Query parameter must be a tuple struct.");

    const Values = get_pointed_tuple(struct_info);
    comptime var comp_types = [_]type{undefined} ** struct_info.fields.len;

    for (struct_info.fields, 0..) |*field, i| {
        comp_types[i] = *SparseSet(field.type);
    }

    const Comps = std.meta.Tuple(&comp_types);

    return struct {
        world: *World,
        comps: Comps,
        current: usize,
        comptime type: T = undefined,

        const Self = @This();

        pub fn next(self: *Self) ?Values {
            var values: Values = undefined;
            if (self.current == std.math.maxInt(usize)) return null;

            outer: for (self.comps[0].entities.items[self.current..], self.current..) |*entity, current| {
                std.debug.print("hello: {d}", .{current});
                inline for (self.comps, 0..) |set, i| {
                    const typed_set = @as(*SparseSet(struct_info.fields[i].type), @ptrCast(set));
                    const ptr = typed_set.get(entity.*) orelse continue :outer;
                    values[i] = @ptrCast(ptr);
                }
                self.current = current;
                if (current == self.comps[0].entities.items.len) {
                    self.current = std.math.maxInt(usize);
                }
                break;
            }

            return values;
        }
    };
}

fn get_pointed_tuple(comptime struct_info: std.builtin.Type.Struct) type {
    comptime var types = [_]type{undefined} ** struct_info.fields.len;

    for (struct_info.fields, 0..) |*field, i| {
        types[i] = *field.type;
    }

    return std.meta.Tuple(&types);
}

fn get_query_type(comptime struct_info: std.builtin.Type.Struct) type {
    comptime var types = [_]type{undefined} ** struct_info.fields.len;

    for (struct_info.fields, 0..) |*field, i| {
        types[i] = std.meta.Child(field.type);
    }

    return std.meta.Tuple(&types);
}

pub fn SparseSet(comptime T: type) type {
    return struct {
        entities: std.ArrayList(Entity),
        sparse: std.ArrayList(usize),
        data: std.ArrayList(T),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .entities = .init(allocator),
                .sparse = .init(allocator),
                .data = .init(allocator),
            };
        }

        pub fn contains(self: *Self, entity: Entity) bool {
            return (self.sparse.items.len > entity.id and self.sparse.items[entity.id] != std.math.maxInt(usize));
        }

        pub fn insert(self: *Self, entity: Entity, value: T) !void {
            if (self.sparse.items.len > entity.id) {
                const index = self.sparse.items[entity.id];
                if (index != std.math.maxInt(usize)) {
                    self.data.items[index] = value;
                    return;
                }
            } else {
                try self.sparse.appendNTimes(std.math.maxInt(usize), entity.id - self.sparse.items.len + 1);
            }

            try self.data.append(value);
            try self.entities.append(entity);
            self.sparse.items[entity.id] = self.data.items.len - 1;
        }

        pub fn get(self: *Self, entity: Entity) ?*T {
            if (self.sparse.items.len <= entity.id) return null;
            const index = self.sparse.items[entity.id];
            if (index == std.math.maxInt(usize)) return null;
            return &self.data.items[index];
        }

        pub fn remove(self: *Self, entity: Entity) void {
            if (self.sparse.items.len < entity.id) return;
            const index = &self.sparse.items[entity.id];
            if (index.* == std.math.maxInt(usize)) return;

            _ = self.data.swapRemove(index.*);
            _ = self.entities.swapRemove(index.*);

            if (self.entities.items.len > 0)
                self.sparse.items[self.entities.items[index.*].id] = index.*;

            index.* = std.math.maxInt(usize);
        }
    };
}

const TypeId = *const struct {
    _: u8,
};

pub inline fn typeId(comptime T: type) TypeId {
    return &struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(TypeId).pointer.child = undefined;
    }.id;
}

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

fn printNumber(query: *Query(struct { i32 })) void {
    while (query.next()) |item| {
        std.debug.print("Number: {d}.\n", .{item[0].*});
    }
}

fn printCharNTimes(char: *u8, number: *i32) void {
    for (0..@intCast(number.*)) |_| {
        std.debug.print("{c}", .{char.*});
    }
    std.debug.print("\n", .{});
}

test "system" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var world = World.init(gpa.allocator());

    const entity1 = try world.create();
    const entity2 = try world.create();
    const entity3 = try world.create();

    const integers = try world.components(i32);

    _ = try integers.insert(entity1, 69);
    _ = try integers.insert(entity2, 420);
    _ = try integers.insert(entity3, 12);

    const chars = try world.components(u8);

    _ = try chars.insert(entity3, 'a');

    try world.runSystem(printNumber);
    // try world.runSystem(printCharNTimes);
}

test "create entity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var world = World.init(gpa.allocator());

    const entity1 = try world.create();
    const entity2 = try world.create();
    try expect(world.isValid(entity1));
    try expect(world.isValid(entity2));
    try world.delete(entity1);
    try expect(!world.isValid(entity1));
    try expect(world.isValid(entity2));
    const entity3 = try world.create();
    try expect(world.isValid(entity3));

    try expectEqual(entity1, Entity{ .id = 0, .generation = 0 });
    try expectEqual(entity2, Entity{ .id = 1, .generation = 0 });
    try expectEqual(entity3, Entity{ .id = 0, .generation = 1 });
}

test "components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var world = World.init(gpa.allocator());

    const entity1 = try world.create();
    const entity2 = try world.create();

    const integers = try world.components(i32);

    _ = try integers.insert(entity1, 69);
    _ = try integers.insert(entity2, 420);

    const value1 = integers.get(entity1);
    const value2 = integers.get(entity2);

    try expectEqual(69, value1.?.*);
    try expectEqual(420, value2.?.*);

    integers.remove(entity1);

    try expectEqual(420, integers.get(entity2).?.*);
    try expectEqual(null, integers.get(entity1));
    try expect(integers.contains(entity2));
    try expect(!integers.contains(entity1));
}
