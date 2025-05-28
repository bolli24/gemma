const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Entity = struct {
    id: u32,
    generation: u32,
};

pub const World = struct {
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

    pub fn deinit(self: *Self) void {
        self.flags.deinit();
        self.unused_ids.deinit();
        self.generations.deinit();

        var set_iter = self.sets.valueIterator();
        while (set_iter.next()) |set| {
            set.deinit();
        }

        self.sets.deinit();
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

        var iter = self.sets.valueIterator();
        while (iter.next()) |*set| {
            set.*.remove(entity);
        }

        self.flags.items[entity.id] = false;
        try self.unused_ids.append(entity.id);
    }

    pub fn add_component(self: *Self, entity: Entity, value: anytype) !void {
        const comps = try self.components(@TypeOf(value));
        try comps.insert(entity, value);
    }

    // TODO: get_component, delete_component

    pub fn isValid(self: *Self, entity: Entity) bool {
        return self.flags.items[entity.id] and entity.generation == self.generations.items[entity.id];
    }

    const SetInfo = struct { *SparseSet(anyopaque), type };

    pub fn query(self: *Self, comptime query_type: type) !query_type {
        comptime var Values: type = undefined;

        comptime switch (@typeInfo(query_type)) {
            .@"struct" => |info| {
                if (std.mem.indexOf(u8, @typeName(query_type), "Query") != null) {
                    for (info.fields) |field| {
                        if (std.mem.eql(u8, field.name, "type")) {
                            Values = get_query_tuple(@typeInfo(field.type).@"struct");
                        }
                    }
                } else {
                    @compileError("Invalid system parameter.");
                }
            },
            else => @compileError("Invalid system parameter."),
        };

        var new_query: query_type = .{
            .world = self,
            .current = 0,
            .comps = undefined,
        };

        inline for (0..new_query.comps.len) |i| {
            const value_type = @typeInfo(Values).@"struct".fields[i].type;
            if (value_type != Entity) {
                const set_type = std.meta.Child();
                const set = try self.components(set_type);
                new_query.comps[i] = @ptrCast(set);
            } else {
                new_query.comps[i] = null;
            }
        }
        return new_query;
    }

    const SystemArg = union(enum) {
        query: type,
        commands: void,
        world: void,
    };

    pub fn runSystem(self: *Self, comptime system: anytype) !void {
        const fn_info = switch (@typeInfo(@TypeOf(system))) {
            .@"fn" => |info| info,
            else => @compileError("System must be function."),
        };

        // TODO: support errors
        const return_type_info = @typeInfo(fn_info.return_type orelse void);

        const void_return = switch (return_type_info) {
            .void => true,
            .error_union => |error_union| error_union.payload == void,
            else => false,
        };

        if (!void_return) {
            @compileError("System must not return any value.");
        }

        comptime var input_args = [_]SystemArg{undefined} ** fn_info.params.len;

        comptime outer: for (fn_info.params, 0..) |*param, i| {
            const param_type = std.meta.Child(param.type orelse @compileError("Parameter type must be defined."));
            if (param_type == Commands) {
                input_args[i] = .{ .commands = {} };
                continue :outer;
            }
            switch (@typeInfo(param_type)) {
                .@"struct" => |info| {
                    if (std.mem.indexOf(u8, @typeName(param_type), "Query") != null) {
                        for (info.fields) |field| {
                            if (std.mem.eql(u8, field.name, "type")) {
                                input_args[i] = SystemArg{ .query = field.type };
                                // Values = get_pointed_tuple(@typeInfo(field.type).@"struct");
                                continue :outer;
                            }
                        }
                        @compileError("Invald query type");
                    }
                },
                else => {
                    @compileError("Invalid system parameter.");
                },
            }
        };

        var output_args_array = [_]*anyopaque{undefined} ** fn_info.params.len;
        comptime var OutPutArgs = [_]type{undefined} ** fn_info.params.len;

        inline for (input_args, 0..) |arg, i| {
            switch (arg) {
                .query => |query_type| {
                    // TODO: make sure query arguments are unique
                    const struct_info: std.builtin.Type.Struct = switch (@typeInfo(query_type)) {
                        .@"struct" => |info| info,
                        else => @compileError("Query argument must be tuple struct."),
                    };

                    if (!struct_info.is_tuple) {
                        @compileError("Query argument must be tuple struct.");
                    }

                    var new_query: Query(query_type) = .{
                        .world = self,
                        .current = 0,
                        .comps = undefined,
                    };

                    inline for (0..new_query.comps.len) |j| {
                        const set_type = struct_info.fields[j].type;
                        const set = try self.components(set_type);
                        new_query.comps[j] = @ptrCast(set);
                    }

                    OutPutArgs[i] = *Query(query_type);
                    output_args_array[i] = &new_query;
                },
                .commands => {
                    OutPutArgs[i] = *Commands;
                    var commands = Commands.init(self.allocator);
                    output_args_array[i] = @ptrCast(&commands);
                },
                else => @compileError("System arg not implemented yet."),
            }
        }

        const ArgsTuple = std.meta.Tuple(&OutPutArgs);
        var args_tuple: ArgsTuple = undefined;

        inline for (0..output_args_array.len) |i| {
            args_tuple[i] = @as(OutPutArgs[i], @ptrCast(@alignCast(output_args_array[i])));
        }

        if (fn_info.return_type == void) {
            @call(.auto, system, args_tuple);
        } else {
            try @call(.auto, system, args_tuple);
        }

        inline for (input_args, 0..) |arg, i| {
            switch (arg) {
                .commands => {
                    const commands: *Commands = @ptrCast(args_tuple[i]);
                    for (commands.list.items) |cmd| {
                        switch (cmd) {
                            .delete => |entity| {
                                try self.delete(entity);
                            },
                        }
                    }
                    commands.deinit();
                },
                else => {},
            }
        }
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

    if (struct_info.fields.len == 0) {
        @compileLog("Query parameter must contain at least one field.");
    }

    const Values = get_query_tuple(struct_info);
    comptime var comp_types = [_]type{undefined} ** struct_info.fields.len;

    for (struct_info.fields, 0..) |*field, i| {
        comp_types[i] = *SparseSet(field.type);
    }

    const Comps = std.meta.Tuple(&comp_types);

    const QueryIter = struct {
        query: *Query(T),
        current: usize,

        pub fn next(self: *@This()) ?Values {
            var values: Values = undefined;

            comptime var ref_index: usize = undefined;
            inline for (@typeInfo(Values).@"struct".fields, 0..) |field, i| {
                if (field.type == Entity) {
                    if (@typeInfo(Values).@"struct".fields.len == 1) {
                        // TODO:
                        @compileError("Query must contain at least one none Entity field");
                    }
                } else {
                    ref_index = i;
                }
            }

            const entities = self.query.comps[ref_index].entities.items;

            if (self.current == std.math.maxInt(usize) or entities.len == 0) return null;

            outer: for (entities[self.current..], self.current..) |*entity, current| {
                inline for (self.query.comps, 0..) |set, i| {
                    if (struct_info.fields[i].type == Entity) {
                        values[i] = entity.*;
                    } else {
                        const typed_set = @as(*SparseSet(struct_info.fields[i].type), @ptrCast(set));
                        const ptr = typed_set.get(entity.*) orelse continue :outer;
                        values[i] = @ptrCast(ptr);
                    }
                }
                self.current = current + 1;
                if (current >= entities.len) {
                    self.current = std.math.maxInt(usize);
                }

                return values;
            }
            self.current = std.math.maxInt(usize);

            return null;
        }
    };

    return struct {
        world: *World,
        comps: Comps,
        current: usize,
        comptime type: T = undefined,

        const Self = @This();

        pub fn iter(self: *Self) QueryIter {
            return QueryIter{
                .query = self,
                .current = 0,
            };
        }

        pub fn single(self: *Self) ?Values {
            var iter_ = self.iter();
            const value = iter_.next();
            if (iter_.next() != null) {
                return null;
            } else {
                return value;
            }
        }
    };
}

fn get_query_tuple(comptime struct_info: std.builtin.Type.Struct) type {
    comptime var types = [_]type{undefined} ** struct_info.fields.len;

    for (struct_info.fields, 0..) |*field, i| {
        if (field.type == Entity) {
            types[i] = Entity;
        } else {
            types[i] = *field.type;
        }
    }

    return std.meta.Tuple(&types);
}

fn makeSwapRemoveFn(comptime T: type) fn (*anyopaque, usize) void {
    return struct {
        fn swapRemove(ptr: *anyopaque, index: usize) void {
            const list: *std.ArrayList(T) = @ptrCast(@alignCast(ptr));
            _ = list.swapRemove(index);
        }
    }.swapRemove;
}

fn makeDeinitFn(comptime T: type) fn (*anyopaque) void {
    return struct {
        fn deinit(ptr: *anyopaque) void {
            const list: *std.ArrayList(T) = @ptrCast(@alignCast(ptr));
            list.deinit();
        }
    }.deinit;
}

pub fn SparseSet(comptime T: type) type {
    return struct {
        entities: std.ArrayList(Entity),
        sparse: std.ArrayList(usize),
        data: std.ArrayList(T),
        swap_remove: *const fn (*anyopaque, usize) void,
        data_deinit: *const fn (*anyopaque) void,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .entities = .init(allocator),
                .sparse = .init(allocator),
                .data = .init(allocator),
                .swap_remove = makeSwapRemoveFn(T),
                .data_deinit = makeDeinitFn(T),
            };
        }
        pub fn deinit(self: *Self) void {
            self.entities.deinit();
            self.sparse.deinit();
            self.data_deinit(@ptrCast(&self.data));
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
            if (self.sparse.items.len <= entity.id) return;
            const index = &self.sparse.items[entity.id];
            if (index.* == std.math.maxInt(usize)) return;

            const removed_index = index.*;

            _ = self.swap_remove(&self.data, removed_index);
            _ = self.entities.swapRemove(removed_index);

            if (self.entities.items.len > removed_index)
                self.sparse.items[self.entities.items[removed_index].id] = removed_index;

            index.* = std.math.maxInt(usize);
        }
    };
}

pub const Commands = struct {
    const Self = @This();
    list: std.ArrayList(Command),

    const Command = union(enum) {
        delete: Entity,
    };

    pub fn init(allocator: Allocator) @This() {
        return Self{
            .list = .init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.list.deinit();
    }

    pub fn delete(self: *Self, entity: Entity) !void {
        try self.list.append(.{ .delete = entity });
    }
};

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

pub fn component(comptime T: type, comptime u: []const u8) type {
    const Type = std.builtin.Type;

    const id_field = Type.EnumField{
        .name = "id_" ++ u,
        .value = 0,
    };

    const extra = std.builtin.Type{ .@"enum" = .{
        .tag_type = u8,
        .fields = &[1]Type.EnumField{id_field},
        .decls = &[0]Type.Declaration{},
        .is_exhaustive = false,
    } };

    const extra_type = @Type(extra);

    return struct {
        T,
        comptime extra_type = @enumFromInt(0),
    };
}

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

fn printNumber(query: *Query(struct { i32 })) void {
    while (query.next()) |item| {
        std.debug.print("Number: {d}.\n", .{item[0].*});
    }
}

fn printCharNTimes(query: *Query(struct { i32, u8 })) void {
    while (query.next()) |item| {
        const number, const char = item;
        for (0..@intCast(number.*)) |_| {
            std.debug.print("{c}", .{char.*});
        }
        std.debug.print("\n", .{});
    }
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
    try world.runSystem(printCharNTimes);

    var query = try world.query(Query(struct { i32 }));

    while (query.next()) |item| {
        std.debug.print("Number: {d}.\n", .{item[0].*});
    }
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
