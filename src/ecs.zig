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
};

pub fn SparseSet(comptime T: type) type {
    return struct {
        map: std.AutoHashMap(Entity, usize),
        data: std.ArrayList(T),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .map = .init(allocator),
                .data = .init(allocator),
            };
        }

        pub fn insert(self: *Self, entity: Entity, value: T) !void {
            if (self.map.get(entity)) |index| {
                const ptr = &self.data.items[index];
                ptr.* = value;
                return;
            }

            const index = self.data.items.len;
            try self.map.put(entity, index);
            try self.data.append(value);
            return;
        }

        pub fn get(self: *Self, entity: Entity) ?*T {
            const index = self.map.get(entity) orelse return null;
            return &self.data.items[index];
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

    try integers.insert(entity1, 69);
    try integers.insert(entity2, 420);

    const value1 = integers.get(entity1);
    const value2 = integers.get(entity2);

    try expect(value1.?.* == 69);
    try expect(value2.?.* == 420);
}
